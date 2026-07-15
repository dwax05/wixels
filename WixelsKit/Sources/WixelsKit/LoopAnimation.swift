import AppKit
import QuartzCore
import SwiftUI

public struct LoopTrack: Equatable, Sendable {
    public enum Property: Equatable, Sendable { case offsetX, offsetY, opacity, rotationDegrees, scale, scaleX, scaleY }
    public var property: Property
    public var values: [Double]
    public var keyTimes: [Double]?
    public var duration: Double
    public var delay: Double
    public var discrete: Bool

    public init(_ property: Property, values: [Double], keyTimes: [Double]? = nil,
                duration: Double, delay: Double = 0, discrete: Bool = false) {
        self.property = property; self.values = values; self.keyTimes = keyTimes
        self.duration = duration; self.delay = delay; self.discrete = discrete
    }

    public static func sampled(_ property: Property, duration: Double, fps: Double,
                               delay: Double = 0, discrete: Bool = false,
                               _ value: (Double) -> Double) -> LoopTrack {
        let count = max(2, Int((duration * fps).rounded(.up)))
        let times = (0...count).map { Double($0) / Double(count) }
        return LoopTrack(property, values: times.map(value), keyTimes: times,
                         duration: duration, delay: delay, discrete: discrete)
    }
}

@MainActor
class LoopLayerView: NSView {
    private var specs: [LoopTrack] = []
    private var anchor = CGPoint(x: 0.5, y: 0.5)
    private var occlusionObserver: NSObjectProtocol?
    private var paused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
    }
    required init?(coder: NSCoder) { nil }

    func apply(tracks: [LoopTrack], anchor: UnitPoint) {
        let point = CGPoint(x: anchor.x, y: anchor.y)
        guard specs != tracks || self.anchor != point else { return }
        specs = tracks; self.anchor = point
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.anchorPoint = point
        layer.removeAllAnimations()
        let now = Date.timeIntervalSinceReferenceDate
        for (index, track) in tracks.enumerated() where track.duration > 0 && !track.values.isEmpty {
            let animation = CAKeyframeAnimation(keyPath: keyPath(for: track.property))
            animation.values = track.values.map { caTrackValue($0, property: track.property) }
            animation.keyTimes = (track.keyTimes ?? evenTimes(track.values.count)).map(NSNumber.init(value:))
            animation.duration = track.duration
            animation.repeatCount = .infinity
            animation.calculationMode = track.discrete ? .discrete : .linear
            let phase = positiveModulo(now - track.delay, track.duration) / track.duration
            animation.beginTime = CACurrentMediaTime() - phase * track.duration
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "wixels.loop.\(index).\(keyPath(for: track.property))")
        }
        CATransaction.commit()
    }

    func applyContents(_ images: [CGImage], frameMS: Double) {
        guard let layer else { return }
        layer.removeAnimation(forKey: "wixels.contents")
        layer.contents = images.first
        guard images.count > 1, frameMS > 0 else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images
        animation.duration = frameMS / 1000 * Double(images.count)
        animation.repeatCount = .infinity
        animation.calculationMode = .discrete
        let now = Date.timeIntervalSinceReferenceDate
        animation.beginTime = CACurrentMediaTime() - positiveModulo(now, animation.duration)
        layer.add(animation, forKey: "wixels.contents")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(!(window.occlusionState.contains(.visible))) }
        }
        setPaused(!window.occlusionState.contains(.visible))
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func setPaused(_ shouldPause: Bool) {
        guard let layer, paused != shouldPause else { return }
        paused = shouldPause
        if shouldPause {
            layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
        } else {
            let pausedAt = layer.timeOffset
            layer.speed = 1; layer.timeOffset = 0; layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }
}

private func keyPath(for property: LoopTrack.Property) -> String {
    switch property { case .offsetX: "transform.translation.x"; case .offsetY: "transform.translation.y"; case .opacity: "opacity"; case .rotationDegrees: "transform.rotation.z"; case .scale: "transform.scale"; case .scaleX: "transform.scale.x"; case .scaleY: "transform.scale.y" }
}
/// Converts SwiftUI-space values to Core Animation's default, unflipped layer
/// coordinates. SwiftUI treats positive Y as down; CALayer treats it as up.
func caTrackValue(_ value: Double, property: LoopTrack.Property) -> NSNumber {
    switch property {
    case .rotationDegrees: NSNumber(value: value * .pi / 180)
    case .offsetY: NSNumber(value: -value)
    default: NSNumber(value: value)
    }
}
private func evenTimes(_ count: Int) -> [Double] { guard count > 1 else { return [0] }; return (0..<count).map { Double($0) / Double(count - 1) } }
private func positiveModulo(_ value: Double, _ modulus: Double) -> Double { let r = value.truncatingRemainder(dividingBy: modulus); return r < 0 ? r + modulus : r }
