import iClearNucleo
import SwiftUI

/// Lo que iClear mandó a la Papelera y todavía se puede regresar a su lugar.
@MainActor struct RecientesView: View {
    @Environment(Estado.self) private var estado
    @State private var restaurando = false
    @State private var errores: [String] = []

    var body: some View {
        Group {
            if estado.recientes.isEmpty {
                ContentUnavailableView("Nothing to Restore", systemImage: "arrow.uturn.backward.circle",
                                       description: Text(estado.accesoCompleto == false
                                           ? "To see what can be restored, iClear needs Full Disk Access."
                                           : "Items iClear moves to the Trash show up here while they are still there."))
            } else {
                List(estado.recientes) { m in
                    Fila(movimiento: m) { restaurar([m]) }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Recently Moved")
        .navigationSubtitle("What iClear moved that is still in the Trash")
        .toolbar {
            Button {
                restaurar(estado.recientes)
            } label: {
                Label("Restore All", systemImage: "arrow.uturn.backward")
            }
            .disabled(estado.recientes.isEmpty || restaurando)
        }
        .onAppear { estado.cargarRecientes() }
        .alert("Some Items Couldn't Be Restored", isPresented: Binding(get: { !errores.isEmpty }, set: { if !$0 { errores = [] } })) {
            Button("OK") { errores = [] }
        } message: {
            Text(errores.prefix(8).joined(separator: "\n"))
        }
    }

    private func restaurar(_ lista: [Movimiento]) {
        restaurando = true
        Task {
            errores = await estado.restaurar(lista)
            restaurando = false
        }
    }
}

private struct Fila: View {
    let movimiento: Movimiento
    let restaurar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Miniatura(url: URL(fileURLWithPath: movimiento.enPapelera), lado: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(movimiento.nombre).lineLimit(1).truncationMode(.middle)
                Text(((movimiento.original as NSString).deletingLastPathComponent).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if movimiento.bytes > 0 { Text(tamano(movimiento.bytes)).monospacedDigit() }
                Text(movimiento.fecha, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Button("Restore", action: restaurar)
        }
        .padding(.vertical, 4)
    }
}
