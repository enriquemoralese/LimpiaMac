import SwiftUI

@main
@MainActor struct IClearApp: App {
    @State private var estado = Estado()

    init() { PruebasUI.preparar() }

    var body: some Scene {
        WindowGroup("iClear") {
            Principal()
                .environment(estado)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            AjustesView()
                .environment(estado)
        }
    }
}
