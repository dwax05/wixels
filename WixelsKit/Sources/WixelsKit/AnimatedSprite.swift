import AppKit
import SwiftUI

public struct AnimatedSprite: View {
    let frames: [Sprite]; let px: CGFloat; let palette: [Character: Color]
    let frameMS: Double; let motion: [LoopTrack]; let anchor: UnitPoint
    public init(frames: [Sprite], px: CGFloat, palette: [Character: Color], frameMS: Double = 0,
                motion: [LoopTrack] = [], anchor: UnitPoint = .center) {
        self.frames = frames; self.px = px; self.palette = palette; self.frameMS = frameMS; self.motion = motion; self.anchor = anchor
    }
    public var body: some View {
        let sprite = frames.first ?? []
        SpriteLayerRepresentable(images: frames.compactMap { SpriteImages.image(for: $0, palette: palette) },
                                 frameMS: frameMS, tracks: motion, anchor: anchor)
            .frame(width: CGFloat(sprite.first?.count ?? 0) * px, height: CGFloat(sprite.count) * px)
    }
}

private struct SpriteLayerRepresentable: NSViewRepresentable {
    let images: [CGImage]; let frameMS: Double; let tracks: [LoopTrack]; let anchor: UnitPoint
    func makeNSView(context: Context) -> LoopLayerView { LoopLayerView(frame: .zero) }
    func updateNSView(_ view: LoopLayerView, context: Context) { view.applyContents(images, frameMS: frameMS); view.apply(tracks: tracks, anchor: anchor) }
}
