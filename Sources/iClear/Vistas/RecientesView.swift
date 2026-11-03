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
                ContentUnavailableView("Nada por restaurar", systemImage: "arrow.uturn.backward.circle",
                                       description: Text(estado.accesoCompleto == false
                                           ? "Para ver lo que se puede restaurar, iClear necesita acceso total al disco."
                                           : "Aquí aparece lo que iClear mueva a la Papelera, mientras siga ahí."))
            } else {
                List(estado.recientes) { m in
                    Fila(movimiento: m) { restaurar([m]) }
                }
            }
        }
        .navigationTitle("Movido recientemente")
        .navigationSubtitle("Lo que iClear movió y sigue en la Papelera")
        .toolbar {
            Button {
                restaurar(estado.recientes)
            } label: {
                Label("Restaurar todo", systemImage: "arrow.uturn.backward")
            }
            .disabled(estado.recientes.isEmpty || restaurando)
        }
        .onAppear { estado.cargarRecientes() }
        .alert("No se pudo restaurar todo", isPresented: Binding(get: { !errores.isEmpty }, set: { if !$0 { errores = [] } })) {
            Button("Aceptar") { errores = [] }
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
            Button("Restaurar", action: restaurar)
        }
        .padding(.vertical, 4)
    }
}
