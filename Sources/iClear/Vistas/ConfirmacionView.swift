import iClearNucleo
import SwiftUI

@MainActor struct ConfirmacionView: View {
    @Environment(Estado.self) private var estado
    @Environment(\.dismiss) private var cerrar
    @State private var revisados = false
    @State private var revisarDeNuevo = 0

    var body: some View {
        let elegidos = estado.seleccionados
        let sensibles = elegidos.filter(\.sensible)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "trash.circle.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("¿Mover \(elegidos.count) elementos a la Papelera?").font(.title3.weight(.semibold))
                    Text("Liberarás \(tamano(estado.bytesSeleccionados)) al vaciar la Papelera. Hasta entonces puedes recuperarlos.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            let porCategoria = Dictionary(grouping: elegidos, by: \.categoria)
            VStack(spacing: 6) {
                ForEach(Categoria.allCases.filter { porCategoria[$0] != nil }) { c in
                    let grupo = porCategoria[c]!
                    HStack {
                        Label(c.titulo, systemImage: c.simbolo)
                        Spacer()
                        Text("\(grupo.count) · \(tamano(grupo.reduce(0) { $0 + $1.bytes }))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

            let _ = revisarDeNuevo
            let abiertas = estado.abiertas(elegidos)
            if !abiertas.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Label("Abiertas ahora: \(abiertas.compactMap(\.localizedName).joined(separator: ", ")). Ciérralas antes de moverlas.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                    Spacer()
                    Button("Cerrar apps") {
                        abiertas.forEach { $0.terminate() }
                        // macOS no avisa a la vista cuando una app se cierra: se vuelve a revisar al momento.
                        Task { try? await Task.sleep(for: .seconds(1.5)); revisarDeNuevo += 1 }
                    }
                }
            }

            let restos = elegidos.reduce(0) { $0 + $1.extras.count }
            if restos > 0 {
                Label("Incluye \(restos) restos de apps en la Librería (cachés, preferencias, datos).", systemImage: "app.dashed")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if !sensibles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(sensibles.count) con nombre sensible", systemImage: "lock.fill")
                        .font(.headline).foregroundStyle(.orange)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(sensibles) { h in
                                Text(h.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    Toggle("Revisé estos archivos y sí quiero moverlos", isOn: $revisados)
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { cerrar() }
                    .keyboardShortcut(.cancelAction)
                Button("Mover a la Papelera") {
                    estado.limpiar()
                    cerrar()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(elegidos.isEmpty || (!sensibles.isEmpty && !revisados))
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
