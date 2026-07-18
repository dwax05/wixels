import Foundation
import SwiftUI
import WixelsKit

@MainActor
final class DeclarativeWidget: ObservableObject, MountableWidget, WidgetTicker {
    let kind: String
    let refresh: RefreshPolicy = .interval(1)
    let interactive: Bool
    var active = true
    var hasSample = false
    private let definition: DeclarativeWidgetDefinition
    private let variables: CommandVariableStore
    private var contentUpdate: (() -> Void)?
    @Published fileprivate var values: [String: String] = [:]

    init(definition: DeclarativeWidgetDefinition, variables: CommandVariableStore) {
        kind = definition.id; self.definition = definition; self.variables = variables
        interactive = definition.root.containsAction
    }

    func setContentUpdateHandler(_ handler: @escaping () -> Void) { contentUpdate = handler }
    func makeTicker() -> any WidgetTicker { self }
    func makeView(_ palette: PaletteStore) -> AnyView {
        AnyView(DeclarativeWidgetView(model: self, palette: palette, definition: definition))
    }

    func tick() async {
        let next = await variables.snapshot()
        if next != values { values = next; contentUpdate?() }
        hasSample = true
    }
}

private struct DeclarativeWidgetView: View {
    @ObservedObject var model: DeclarativeWidget
    @ObservedObject var palette: PaletteStore
    let definition: DeclarativeWidgetDefinition

    var body: some View {
        if definition.visible.isVisible(in: model.values) {
            DeclarativeNodeView(node: definition.root, values: model.values, palette: palette.palette)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(declarativeAccessibilityLabel(definition.root, values: model.values))
        }
    }
}
