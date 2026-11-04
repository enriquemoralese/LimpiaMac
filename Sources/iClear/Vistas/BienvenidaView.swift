import iClearNucleo
import SwiftUI

/// Primera vez que se abre la app: explica cómo trabaja y pide las carpetas a proteger
/// antes del primer escaneo.
@MainActor struct BienvenidaView: View {
    @AppStorage(Ajustes.claveBienvenida) private var vista = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to iClear").font(.title2.weight(.semibold))
                    Text("Find what takes up space for nothing.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Punto(simbolo: "eye", texto: "Scanning only looks. It never moves or deletes anything.")
                Punto(simbolo: "hand.tap", texto: "You choose what goes to the Trash, and you can restore it.")
                Punto(simbolo: "lock", texto: "Anything that looks sensitive (IDs, bank statements, passwords) gets a lock and is never checked for you.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What should it never touch?").font(.headline)
                Text("Add your important documents, projects, or any folder you want to protect. You can change this later in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                Form { CarpetasPropias() }
                    .formStyle(.grouped)
                    .frame(height: 150)
                Text("iClear already protects your keys (.ssh, .gnupg) and your app settings out of the box.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Get Started") { vista = true }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

private struct Punto: View {
    let simbolo: String
    let texto: String

    var body: some View {
        Label {
            Text(texto)
        } icon: {
            Image(systemName: simbolo).foregroundStyle(Color.accentColor).frame(width: 22)
        }
    }
}
