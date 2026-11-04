import SwiftUI

@main
@MainActor struct IClearApp: App {
    @State private var estado = Estado()

    init() { PruebasUI.preparar() }

    var body: some Scene {
        WindowGroup("iClear") {
            Principal()
                .environment(estado)
                // Fechas y meses en inglés aunque la Mac esté en español.
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            AjustesView()
                .environment(estado)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
    }
}
