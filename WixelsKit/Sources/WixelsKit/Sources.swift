// Native data sources — replace Übersicht's per-tick shell/python spawns with
// direct syscalls. Two adapters here (disk, cpu) is what makes DataSource a real
// seam rather than a hypothetical one.

import Foundation
import IOKit
import IOKit.ps
import CoreWLAN

// MARK: - Interfaces

/// Walk active BSD network interfaces, handing each `ifaddrs` to `body` — the
/// shared getifaddrs loop behind net-throughput and wifi-IP checks.
func forEachInterface(_ body: (ifaddrs) -> Void) {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0 else { return }
    defer { freeifaddrs(ifap) }
    var p = ifap
    while let cur = p { body(cur.pointee); p = cur.pointee.ifa_next }
}

// MARK: - Power (battery + AC state) — one reading shared by pet + stats.

struct PowerReading: Sendable {
    var pct: Double            // 0…100
    var charging: Bool
    var plugged: Bool          // on AC (a full battery on the charger still counts)
    var onPower: Bool { charging || plugged }
    static let none = PowerReading(pct: 0, charging: false, plugged: false)
}

enum Power {
    /// First power source via IOKit IOPS — no `pmset` spawn. Feeds the pet's blush
    /// (`charging || plugged`) and the stats battery gauge from one place.
    static func read() -> PowerReading {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .none }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return PowerReading(pct: max > 0 ? Double(cur) / Double(max) * 100 : 0,
                                charging: charging, plugged: plugged)
        }
        return .none
    }
}

// MARK: - Disk

public struct DiskInfo: Equatable, Sendable {
    public var usedFraction: Double      // 0…1
    public var freeBytes: Int64
    public init(usedFraction: Double, freeBytes: Int64) {
        self.usedFraction = usedFraction; self.freeBytes = freeBytes
    }
}

public struct DiskSource: DataSource {
    public let path: String
    public init(path: String = "/") { self.path = path }

    public func read() async -> DiskInfo {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let v = try? url.resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, total > 0 else {
            return DiskInfo(usedFraction: 0, freeBytes: 0)
        }
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0
        let used = max(0, Int64(total) - free)
        return DiskInfo(usedFraction: Double(used) / Double(total), freeBytes: free)
    }
}

// MARK: - CPU

/// Whole-system CPU utilisation (0…1) via mach `host_statistics(HOST_CPU_LOAD_INFO)`,
/// differencing tick counters between reads. No `top -l 1`, no process spawn.
///
/// One shared instance feeds every subscriber (pet + stats), per the design's
/// single-sampler rule. An `actor` so concurrent readers can't race the tick
/// counters; two reads closer together than `minInterval` return the last
/// computed value instead of a near-zero micro-window, so a slow poller sharing
/// the sampler with a fast one still sees a meaningful load.
public actor CPUSource: DataSource {
    private var prev: host_cpu_load_info?
    private var cached: Double = 0
    private var lastRead = Date.distantPast
    private let minInterval: TimeInterval

    public init(minInterval: TimeInterval = 1.0) { self.minInterval = minInterval }

    public func read() async -> Double {
        let now = Date()
        if now.timeIntervalSince(lastRead) < minInterval { return cached }
        lastRead = now

        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return cached }
        defer { prev = info }
        guard let p = prev else { return cached }   // first read has no delta

        // cpu_ticks = (USER, SYSTEM, IDLE, NICE)
        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let sys  = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + sys + idle + nice
        cached = total > 0 ? (user + sys + nice) / total : cached
        return cached
    }
}

// MARK: - Pet composite source (cpu + net + battery + music -> a mood)

public enum PetMood: Sendable { case idle, sleep, run, eat }

public struct PetState: Equatable, Sendable {
    public var mood: PetMood
    public var charging: Bool
    public var music: Bool
    public var cpu: Double        // 0…1
    public init(mood: PetMood, charging: Bool, music: Bool, cpu: Double) {
        self.mood = mood; self.charging = charging; self.music = music; self.cpu = cpu
    }
}

/// Composes several native readings into the pet's mood, mirroring pet.py's
/// state machine — but with syscalls instead of `top`/`netstat`/`pmset` spawns.
/// An actor because lifecycle-triggered refreshes can overlap the scheduler loop;
/// serial isolation protects the network-delta state across suspended reads.
public actor PetSource: DataSource {
    private let cpu: CPUSource
    private let music: MusicMonitor
    private var prevNet: (t: Date, bytes: UInt64)?

    public init(cpu: CPUSource, music: MusicMonitor) { self.cpu = cpu; self.music = music }

    static let eatKBps = 150.0
    static let runPct = 70.0
    static let sleepPct = 8.0

    public func read() async -> PetState {
        let load = await cpu.read()               // 0…1
        let kbps = netKBps()
        let onPower = Power.read().onPower
        let pct = load * 100

        let mood: PetMood
        if kbps > Self.eatKBps { mood = .eat }
        else if pct > Self.runPct { mood = .run }
        else if pct < Self.sleepPct { mood = .sleep }
        else { mood = .idle }

        let playing = await music.isPlayingNow()
        return PetState(mood: mood, charging: onPower, music: playing, cpu: load)
    }

    /// Sum in+out bytes across real link interfaces (skip lo0) via getifaddrs,
    /// diffed against the previous read — the native form of pet.py's netstat.
    private func netKBps() -> Double {
        let now = Date()
        let bytes = Self.netTotalBytes()
        defer { prevNet = (now, bytes) }
        guard let prev = prevNet else { return 0 }
        let dt = now.timeIntervalSince(prev.t)
        guard dt > 0, bytes >= prev.bytes else { return 0 }
        return Double(bytes - prev.bytes) / dt / 1024
    }

    private static func netTotalBytes() -> UInt64 {
        var total: UInt64 = 0
        forEachInterface { ifa in
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: ifa.ifa_name) != "lo0", let raw = ifa.ifa_data {
                let d = raw.assumingMemoryBound(to: if_data.self).pointee
                total += UInt64(d.ifi_ibytes) + UInt64(d.ifi_obytes)
            }
        }
        return total
    }
}

// MARK: - Stats composite source (cpu wilt + memory + battery -> soft-stats card)

public struct StatsInfo: Equatable, Sendable {
    public var cpu: Int          // %
    public var mem: Int          // %
    public var battery: Int      // %
    public var charging: Bool
    public var plugged: Bool
    public var wilt: Int         // 0 (perky) … 3 (droopy), from CPU load
    public init(cpu: Int, mem: Int, battery: Int, charging: Bool, plugged: Bool, wilt: Int) {
        self.cpu = cpu; self.mem = mem; self.battery = battery
        self.charging = charging; self.plugged = plugged; self.wilt = wilt
    }
}

/// cpu (shared host-tick sampler) + memory (host_statistics64) + battery (IOPS),
/// all native — the stock-tool spawns in stats.py (top/vm_stat/pmset) become syscalls.
public final class StatsSource: DataSource, @unchecked Sendable {
    private let cpu: CPUSource

    public init(cpu: CPUSource) { self.cpu = cpu }

    public func read() async -> StatsInfo {
        let load = await cpu.read() * 100                 // 0…100
        let power = Power.read()
        let wilt = load < 25 ? 0 : load < 50 ? 1 : load < 75 ? 2 : 3
        return StatsInfo(cpu: Int(load.rounded()), mem: Int(Self.memPct().rounded()),
                         battery: Int(power.pct.rounded()), charging: power.charging,
                         plugged: power.plugged, wilt: wilt)
    }

    /// Used memory %: (active + wired + compressed) / physical, via host_statistics64.
    private static func memPct() -> Double {
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(total) * 100))
    }
}

// MARK: - Owl presence source (HID idle time -> awake/drowsy/asleep)

public enum OwlState: Sendable { case awake, drowsy, asleep }

/// Presence gauge from HID idle seconds (HIDIdleTime on IOHIDSystem), read straight
/// from the IO registry — no `ioreg` spawn. drowsy ≥10s idle, asleep ≥30s.
public struct OwlSource: DataSource {
    static let drowsyS = 10.0, asleepS = 30.0
    public init() {}

    public func read() async -> OwlState {
        let idle = Self.idleSeconds()
        return idle >= Self.asleepS ? .asleep : idle >= Self.drowsyS ? .drowsy : .awake
    }

    private static func idleSeconds() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(
            service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
            let num = prop as? NSNumber
        else { return 0 }
        return Double(num.uint64Value) / 1_000_000_000   // HIDIdleTime is nanoseconds
    }
}

// MARK: - Frog thermal source

/// The frog warms cool→hot with system thermal pressure. Native — no `swift -e`
/// spawn like frog.py: NSProcessInfo.thermalState needs no privileges.
public enum FrogState: Int, Sendable { case nominal = 0, fair, serious, critical }

public struct FrogSource: DataSource {
    public init() {}
    public func read() async -> FrogState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .nominal
        case .fair:     return .fair
        case .serious:  return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}

// MARK: - Sys composite source (wifi + disk -> the cynaberii-sys box)

public struct SysInfo: Equatable, Sendable {
    public var connected: Bool
    public var ssid: String
    public var diskPct: Double        // 0…100, of the Data volume (matches sys.py)
    public init(connected: Bool, ssid: String, diskPct: Double) {
        self.connected = connected; self.ssid = ssid; self.diskPct = diskPct
    }
}

/// Ports cynaberii-sys/sys.py: wifi connection + Data-volume disk %. Wifi state is
/// read natively (CoreWLAN for the interface, getifaddrs for an assigned IPv4 —
/// which needs no Location Services permission, unlike SSID). Disk reuses DiskSource.
public struct SysSource: DataSource {
    private let dataVolume = DiskSource(path: "/System/Volumes/Data")
    public init() {}

    public func read() async -> SysInfo {
        let (connected, ssid) = Self.wifi()
        let disk = await dataVolume.read().usedFraction * 100
        return SysInfo(connected: connected, ssid: ssid, diskPct: disk)
    }

    private static func wifi() -> (Bool, String) {
        let iface = CWWiFiClient.shared().interface()
        let name = iface?.interfaceName ?? "en0"
        let connected = interfaceHasIPv4(name)     // assigned IPv4 == associated + up
        guard connected else { return (false, "offline") }
        let ssid = iface?.ssid()                   // nil/redacted without Location perms
        return (true, (ssid?.isEmpty == false) ? ssid! : "wi-fi")
    }

    /// True if the named BSD interface has an assigned IPv4 address.
    private static func interfaceHasIPv4(_ name: String) -> Bool {
        var found = false
        forEachInterface { ifa in
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == name {
                found = true
            }
        }
        return found
    }
}
