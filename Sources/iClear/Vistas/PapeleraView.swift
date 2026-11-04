import iClearNucleo
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
                Text("in the Trash. That space is freed when you empty it.").foregroundStyle(.secondary)
            } else {
                Text("Couldn't measure the Trash").font(.title3.weight(.semibold))
                Text("macOS requires Full Disk Access to read it.").foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Open Trash") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                Button(vaciando ? "Emptying…" : "Empty Trash…", role: .destructive) { confirmando = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(vaciando)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Trash")
        .onAppear { estado.medirPapelera() }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmando) {
            Button("Empty Trash", role: .destructive) {
                vaciando = true
                Task {
                    resultado = await estado.vaciarPapelera()
                    vaciando = false
                }
            }
        } message: {
            Text("This permanently deletes everything in the Trash, including items iClear didn't move. This can't be undone.")
        }
        .alert(titulo, isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
            Button("OK") { resultado = nil }
        } message: {
            Text(mensaje)
        }
    }

    private var titulo: String {
        guard let r = resultado else { return "" }
        return r.errores.isEmpty ? "Trash Emptied" : (r.borrados == 0 ? "The Trash Wasn't Emptied" : "Almost Everything Was Deleted")
    }

    private var mensaje: String {
        guard let r = resultado else { return "" }
        var texto = "Deleted \(r.borrados) items and freed \(tamano(r.bytes))."
        if !r.errores.isEmpty {
            texto += "\n\n\(r.errores.count) couldn't be deleted:\n" + r.errores.prefix(8).joined(separator: "\n")
            if r.errores.count > 8 { texto += "\n…and \(r.errores.count - 8) more." }
        }
        return texto
    }
}
