import AppKit
import SwiftUI
import WixelsKit

/// Deliberately command-line-only developer gallery. It is never attached to the
/// status menu or production host lifecycle.
@MainActor
final class PreviewGalleryController: NSObject, NSWindowDelegate {
    private let registrar: Registrar
    private let services = Services()
    private var window: NSWindow?
    init(registrar: Registrar) { self.registrar = registrar }
    func show() {
        let view = PreviewGallery(registrar: registrar, services: services)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Wixels Widget Gallery"
        window.contentView = NSHostingView(rootView: view)
        window.center(); window.delegate = self; window.makeKeyAndOrderFront(nil)
        self.window = window
    }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

@MainActor
private struct PreviewGallery: View {
    let registrar: Registrar; let services: Services
    @State private var themeID = "macos"
    private var themes: [ThemeDefinition] { registrar.themes.values.sorted { $0.manifest.name < $1.manifest.name } }
    var previews: [RegisteredWidgetPreview] { registrar.registeredPreviews(services: services, themeID: themeID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Theme", selection: $themeID) {
                ForEach(themes, id: \.manifest.id) { theme in
                    Text(theme.manifest.name).tag(theme.manifest.id)
                }
            }.pickerStyle(.segmented).frame(width: 220)
            ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 22)], spacing: 22) {
                ForEach(Array(previews.enumerated()), id: \.offset) { _, preview in
                    VStack(alignment: .leading, spacing: 7) {
                        preview.view.frame(width: preview.placement.size.width, height: preview.placement.size.height, alignment: .topLeading)
                        Text("\(preview.kind) · \(preview.name) · \(Int(preview.placement.size.width))×\(Int(preview.placement.size.height))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.vertical, 4) }
        }.padding(24).frame(minWidth: 700, minHeight: 500)
    }
}
