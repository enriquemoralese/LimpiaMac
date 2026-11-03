import iClearNucleo
import SwiftUI

@MainActor struct Principal: View {
    @Environment(Estado.self) private var estado

    var body: some View {
        @Bindable var estado = estado
        NavigationSplitView {
            List(selection: $estado.seccion) {
                Label("Resumen", systemImage: "internaldrive").tag(Seccion.resumen)
                Section("Hallazgos") {
                    ForEach(Categoria.allCases) { c in
                        FilaLateral(titulo: c.titulo, simbolo: c.simbolo,
                                    valor: estado.escaneado ? tamano(estado.total(c)) : nil)
                            .tag(Seccion.categoria(c))
                    }
                }
                Section {
                    FilaLateral(titulo: "Papelera", simbolo: "trash",
                                valor: estado.papeleraBytes.map(tamano))
                        .tag(Seccion.papelera)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            Group {
                switch estado.seccion ?? .resumen {
                case .resumen: ResumenView()
                case .categoria(let c): TablaView(categoria: c)
                case .papelera: PapeleraView()
                }
            }
            // En las categorías la barra la pone TablaView solo bajo la tabla, para que no tape el panel de vista previa.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if estado.escaneado && !enCategoria { BarraInferior(estado: estado) }
            }
        }
        .sheet(isPresented: $estado.confirmando) { ConfirmacionView() }
        .alert("Listo", isPresented: Binding(get: { estado.ultimaLimpieza != nil }, set: { if !$0 { estado.ultimaLimpieza = nil } })) {
            Button("Aceptar") { estado.ultimaLimpieza = nil }
        } message: {
            if let r = estado.ultimaLimpieza {
                Text(mensaje(r))
            }
        }
    }

    private var enCategoria: Bool {
        if case .categoria = estado.seccion { return true }
        return false
    }

    private func mensaje(_ r: ResultadoLimpieza) -> String {
        var texto = "Se movieron \(r.movidos.count) elementos a la Papelera (\(tamano(r.bytes))). Puedes recuperarlos desde ahí."
        if !r.errores.isEmpty {
            texto += "\n\n\(r.errores.count) no se pudieron mover:\n" + r.errores.prefix(5).joined(separator: "\n")
        }
        return texto
    }
}

/// Total seleccionado y botón para mover a la Papelera.
@MainActor struct BarraInferior: View {
    let estado: Estado

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tamano(estado.bytesSeleccionados)).font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(estado.seleccionados.count) elementos seleccionados").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                estado.confirmando = true
            } label: {
                Label("Mover a la Papelera", systemImage: "trash")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(estado.seleccionados.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

@MainActor private struct FilaLateral: View {
    let titulo: String
    let simbolo: String
    let valor: String?

    var body: some View {
        HStack {
            Label(titulo, systemImage: simbolo)
            Spacer()
            if let valor {
                Text(valor).font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
