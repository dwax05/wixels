// Registry — the plugin ABI's registration surface.
//
//   WidgetSpec : what a widget IS — kind, default placement, and a `build` closure
//                that constructs+erases it from shared Services and its Options.
//                A plugin's @_cdecl entry hands one of these to the Registrar.
//   Registrar  : the table the host passes (as an opaque pointer) into each loaded
//                plugin; the plugin calls `add(_:)` to register its kind(s).
//   Options    : a read-only, TOML-agnostic view of a widget's `[widget.options]`
//                table. Lives here so plugins never depend on a TOML library — the
//                host decodes TOML into this.
//
// `build` returns `any MountableWidget` (see Widget.swift), so a plugin never needs
// to see the host's `WidgetHost` type.

import Foundation

public struct WidgetSpec: Sendable {
    public let kind: String
    public let defaultPlacement: Placement
    public let build: @MainActor @Sendable (Services, Options) -> any MountableWidget

    public init(kind: String, defaultPlacement: Placement,
                build: @escaping @MainActor @Sendable (Services, Options) -> any MountableWidget) {
        self.kind = kind
        self.defaultPlacement = defaultPlacement
        self.build = build
    }
}

/// Collects the specs a plugin registers. The host makes one, passes it into every
/// plugin's `wixels_register`, then resolves the config against `specs`.
public final class Registrar: @unchecked Sendable {
    public private(set) var specs: [String: WidgetSpec] = [:]
    public init() {}

    public func add(_ spec: WidgetSpec) {
        if specs[spec.kind] != nil {
            Log.note("duplicate widget kind '\(spec.kind)' — keeping the first")
            return
        }
        specs[spec.kind] = spec
    }
}

/// Typed, read-only options passed to a widget's `build`. Getters coerce leniently
/// (int↔double) and return nil when absent or the wrong shape, so widgets fall back
/// to their own defaults.
public struct Options: Sendable {
    public enum Value: Sendable, Equatable {
        case string(String), int(Int), double(Double), bool(Bool), array([Value])
    }

    private let dict: [String: Value]
    public init(_ dict: [String: Value] = [:]) { self.dict = dict }
    public static let empty = Options()

    public func string(_ key: String) -> String? {
        if case .string(let s)? = dict[key] { return s }
        return nil
    }
    public func double(_ key: String) -> Double? {
        switch dict[key] {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }
    public func int(_ key: String) -> Int? {
        switch dict[key] {
        case .int(let i):    return i
        case .double(let d): return Int(d)
        default:             return nil
        }
    }
    public func bool(_ key: String) -> Bool? {
        if case .bool(let b)? = dict[key] { return b }
        return nil
    }
}
