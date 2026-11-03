import SwiftUI

@main
@MainActor struct LimpiaMacApp: App {
    @State private var estado = Estado()

    var body: some Scene {
        WindowGroup("LimpiaMac") {
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
