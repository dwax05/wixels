import Foundation
import WixelsKit

@MainActor
final class WidgetsSession {
    private let variables: CommandVariableStore
    private let definitions: [DeclarativeWidgetDefinition]
    init(_ config: LoadedWidgetsConfig) { variables = .init(definitions: config.variables); definitions = config.widgets }
    func mount(in host: WidgetHost) {
        Task { await variables.start() }
        for definition in definitions {
            let widget = DeclarativeWidget(definition: definition, variables: variables)
            host.mount(widget, placement: definition.placement, defaultPlacement: definition.placement,
                       configIndex: WidgetHost.unmanagedConfigIndex, group: "ScriptWidgets", layoutID: definition.id)
        }
    }
    func stop() { Task { await variables.stop() } }
}
