import LimpiaNucleo
import QuickLook
import SwiftUI

@MainActor struct TablaView: View {
    let categoria: Categoria
    @Environment(Estado.self) private var estado
    @State private var orden = [KeyPathComparator(\Hallazgo.bytes, order: .reverse)]
    @State private var filas: Set<Hallazgo.ID> = []
    @State private var soloSensibles = false
    @State private var vistaPrevia: URL?

    private var lista: [Hallazgo] {
        estado.hallazgos(en: categoria)
            .filter { !soloSensibles || $0.sensible }
            .sorted(using: orden)
    }

    var body: some View {
        let lista = lista
        Group {
            if !estado.escaneado {
                ContentUnavailableView("Sin escanear", systemImage: categoria.simbolo,
                                       description: Text("Ve a Resumen y presiona Escanear."))
            } else if lista.isEmpty {
                ContentUnavailableView("Nada por aquí", systemImage: "checkmark.circle",
                                       description: Text(categoria.descripcion))
            } else {
                tabla(lista)
            }
        }
        .navigationTitle(categoria.titulo)
        .navigationSubtitle(categoria.descripcion)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $soloSensibles) {
                    Label("Solo sensibles", systemImage: "lock")
                }
                .help("Mostrar solo archivos con nombre sensible")
                Menu {
                    Button("Marcar todo (sin sensibles)") { estado.marcar(lista.filter { !$0.sensible }.map(\.id), true) }
                    Button("Desmarcar todo") { estado.marcar(lista.map(\.id), false) }
                } label: {
                    Label("Selección", systemImage: "checklist")
                }
            }
        }
        .quickLookPreview($vistaPrevia)
    }

    private func tabla(_ lista: [Hallazgo]) -> some View {
        Table(lista, selection: $filas, sortOrder: $orden) {
            TableColumn("") { h in Casilla(id: h.id, estado: estado) }
                .width(22)

            TableColumn("Nombre", value: \.nombre) { h in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: h.url.path))
                        .resizable().frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(h.nombre).lineLimit(1).truncationMode(.middle)
                            if h.sensible {
                                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                                    .help("El nombre parece de un documento sensible. Revísalo antes de moverlo.")
                            }
                        }
                        if let nota = h.nota {
                            Text(nota).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Tamaño", value: \.bytes) { h in
                Text(tamano(h.bytes)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn("Fecha", value: \.fecha) { h in
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.fecha, format: .dateTime.day().month(.abbreviated).year())
                    Text(h.tipoFecha.etiqueta).font(.caption).foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 150)

            TableColumn("Ubicación") { h in
                Text(h.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        .contextMenu(forSelectionType: Hallazgo.ID.self) { ids in
            let elegidos = lista.filter { ids.contains($0.id) }
            Button("Vista rápida") { vistaPrevia = elegidos.first?.url }
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting(elegidos.map(\.url)) }
            Divider()
            Button("Marcar") { estado.marcar(ids, true) }
            Button("Desmarcar") { estado.marcar(ids, false) }
        } primaryAction: { ids in
            NSWorkspace.shared.activateFileViewerSelecting(lista.filter { ids.contains($0.id) }.map(\.url))
        }
        .onKeyPress(.space) {
            guard let id = filas.first, let h = lista.first(where: { $0.id == id }) else { return .ignored }
            vistaPrevia = vistaPrevia == nil ? h.url : nil
            return .handled
        }
    }
}

/// Vista aparte para que la celda lea la selección en su `body`: si solo se lee dentro del
/// Binding, SwiftUI no se entera del cambio y la casilla no se redibuja hasta salir y volver.
/// El estado llega como parámetro: en macOS 14, las celdas que la tabla reutiliza a veces
/// pierden el entorno y `@Environment(Estado.self)` truena.
@MainActor private struct Casilla: View {
    let id: String
    let estado: Estado

    var body: some View {
        let marcado = estado.seleccion.contains(id)
        Toggle("", isOn: Binding(get: { marcado }, set: { estado.marcar([id], $0) }))
            .labelsHidden()
            .toggleStyle(.checkbox)
    }
}
