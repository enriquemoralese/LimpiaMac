import SwiftUI

@MainActor struct PapeleraView: View {
    @Environment(Estado.self) private var estado
    @State private var confirmando = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash").font(.system(size: 64, weight: .thin)).foregroundStyle(.secondary)
            if let bytes = estado.papeleraBytes {
                Text(tamano(bytes)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("en la Papelera. Ese espacio se libera al vaciarla.").foregroundStyle(.secondary)
            } else {
                Text("No se pudo medir la Papelera").font(.title3.weight(.semibold))
                Text("macOS pide acceso completo al disco para leerla.").foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Abrir Papelera") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                Button("Vaciar Papelera…", role: .destructive) { confirmando = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Papelera")
        .onAppear { estado.medirPapelera() }
        .confirmationDialog("¿Vaciar la Papelera?", isPresented: $confirmando) {
            Button("Vaciar Papelera", role: .destructive) { error = estado.vaciarPapelera() }
        } message: {
            Text("Esto borra de forma definitiva todo lo que hay en la Papelera, incluido lo que no movió LimpiaMac. No se puede deshacer.")
        }
        .alert("No se vació la Papelera", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Aceptar") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }
}
