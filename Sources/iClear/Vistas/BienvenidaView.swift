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
                    Text("Bienvenido a iClear").font(.title2.weight(.semibold))
                    Text("Encuentra lo que ocupa espacio sin servir.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Punto(simbolo: "eye", texto: "El escaneo solo mira. No mueve ni borra nada.")
                Punto(simbolo: "hand.tap", texto: "Tú eliges qué mandar a la Papelera, y puedes restaurarlo.")
                Punto(simbolo: "lock", texto: "Lo que parece sensible (INE, estados de cuenta, contraseñas) lleva candado y nunca llega marcado.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("¿Qué no debe tocar nunca?").font(.headline)
                Text("Agrega tus documentos importantes, proyectos o cualquier carpeta que quieras proteger. Puedes cambiarlo después en Ajustes.")
                    .font(.callout).foregroundStyle(.secondary)
                Form { CarpetasPropias() }
                    .formStyle(.grouped)
                    .frame(height: 150)
                Text("iClear ya protege de fábrica tus llaves (.ssh, .gnupg) y las configuraciones de tus apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Empezar") { vista = true }
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
