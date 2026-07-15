import AppKit
import SwiftUI

public extension View {
    @ViewBuilder func loopEffect(_ tracks: [LoopTrack], anchor: UnitPoint = .center) -> some View {
        if tracks.isEmpty { self } else { LoopEffectRepresentable(content: self, tracks: tracks, anchor: anchor) }
    }
}

private struct LoopEffectRepresentable<Content: View>: NSViewRepresentable {
    let content: Content; let tracks: [LoopTrack]; let anchor: UnitPoint
    func makeNSView(context: Context) -> HostingLoopView<Content> { HostingLoopView(content: content) }
    func updateNSView(_ view: HostingLoopView<Content>, context: Context) { view.host.rootView = content; view.apply(tracks: tracks, anchor: anchor) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HostingLoopView<Content>, context: Context) -> CGSize? { nsView.fittingSize }
}

@MainActor private final class HostingLoopView<Content: View>: LoopLayerView {
    let host: NSHostingView<Content>
    init(content: Content) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor), host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { nil }
}
