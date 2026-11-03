import LimpiaNucleo
import SwiftUI

@MainActor struct PapeleraView: View {
    @Environment(Estado.self) private var estado
    @State private var confirmando = false
    @State private var vaciando = false
    @State private var resultado: ResultadoVaciado?

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
                Button(vaciando ? "Vaciando…" : "Vaciar Papelera…", role: .destructive) { confirmando = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(vaciando)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Papelera")
        .onAppear { estado.medirPapelera() }
        .confirmationDialog("¿Vaciar la Papelera?", isPresented: $confirmando) {
            Button("Vaciar Papelera", role: .destructive) {
                vaciando = true
                Task {
                    resultado = await estado.vaciarPapelera()
                    vaciando = false
                }
            }
        } message: {
            Text("Esto borra de forma definitiva todo lo que hay en la Papelera, incluido lo que no movió LimpiaMac. No se puede deshacer.")
        }
        .alert(titulo, isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
            Button("Aceptar") { resultado = nil }
        } message: {
            Text(mensaje)
        }
    }

    private var titulo: String {
        guard let r = resultado else { return "" }
        return r.errores.isEmpty ? "Papelera vacía" : (r.borrados == 0 ? "No se vació la Papelera" : "Se vació casi todo")
    }

    private var mensaje: String {
        guard let r = resultado else { return "" }
        var texto = "Se borraron \(r.borrados) elementos y se liberaron \(tamano(r.bytes))."
        if !r.errores.isEmpty {
            texto += "\n\n\(r.errores.count) no se pudieron borrar:\n" + r.errores.prefix(8).joined(separator: "\n")
            if r.errores.count > 8 { texto += "\n…y \(r.errores.count - 8) más." }
        }
        return texto
    }
}
