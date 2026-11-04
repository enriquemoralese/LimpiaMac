import iClearNucleo
import SwiftUI

@MainActor struct Principal: View {
    @Environment(Estado.self) private var estado
    @AppStorage(Ajustes.claveBienvenida) private var bienvenidaVista = false

    var body: some View {
        @Bindable var estado = estado
        NavigationSplitView {
            List(selection: $estado.seccion) {
                Label("Overview", systemImage: "internaldrive").tag(Seccion.resumen)
                // Los dos títulos son filas con el mismo estilo, sin `Section`: con dos secciones, macOS 14 avisa
                // "reentrant operation in its NSTableView delegate" al abrir (medido con Scripts/pruebas_ui.sh),
                // y con una sola el título del sistema se ve distinto al otro.
                TituloLateral(texto: "Findings")
                ForEach(Categoria.allCases) { c in
                    FilaLateral(titulo: c.titulo, simbolo: c.simbolo,
                                valor: estado.escaneado ? tamano(estado.total(c)) : nil)
                        .tag(Seccion.categoria(c))
                }
                TituloLateral(texto: "Trash")
                FilaLateral(titulo: "Recently Moved", simbolo: "arrow.uturn.backward.circle",
                            valor: estado.recientes.isEmpty ? nil : "\(estado.recientes.count)")
                    .tag(Seccion.recientes)
                FilaLateral(titulo: "Trash", simbolo: "trash",
                            valor: estado.papeleraBytes.map(tamano))
                    .tag(Seccion.papelera)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            Group {
                switch estado.seccion ?? .resumen {
                case .resumen: ResumenView()
                case .categoria(let c): TablaView(categoria: c)
                case .recientes: RecientesView()
                case .papelera: PapeleraView()
                }
            }
            // Cada pantalla ocupa todo el alto, para que la barra de abajo quede pegada al borde.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Vidrio())
            // En las categorías la barra la pone TablaView solo bajo la tabla, para que no tape el panel de vista previa.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if estado.escaneado && !enCategoria { BarraInferior(estado: estado) }
            }
        }
        .task { await PruebasUI.correr(estado) }
        .sheet(isPresented: $estado.confirmando) { ConfirmacionView() }
        .sheet(isPresented: Binding(get: { !bienvenidaVista }, set: { if !$0 { bienvenidaVista = true } })) {
            BienvenidaView().interactiveDismissDisabled()
        }
        .alert("Kept", isPresented: Binding(get: { estado.ultimoGuardado != nil }, set: { if !$0 { estado.ultimoGuardado = nil } })) {
            Button("Show in Finder") {
                NSWorkspace.shared.open(estado.carpetaGuardar)
                estado.ultimoGuardado = nil
            }
            Button("OK", role: .cancel) { estado.ultimoGuardado = nil }
        } message: {
            if let r = estado.ultimoGuardado {
                Text(mensaje(r))
            }
        }
        .alert("Done", isPresented: Binding(get: { estado.ultimaLimpieza != nil }, set: { if !$0 { estado.ultimaLimpieza = nil } })) {
            if let pendientes = estado.ultimaLimpieza?.sinPermiso, !pendientes.isEmpty {
                Button("Move with Finder") { estado.moverConFinder(pendientes) }
                Button("Not Now", role: .cancel) { estado.ultimaLimpieza = nil }
            } else {
                Button("OK") { estado.ultimaLimpieza = nil }
            }
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

    private func mensaje(_ r: ResultadoGuardado) -> String {
        var texto = "Moved \(r.guardados.count) items (\(tamano(r.bytes))) to Documents/Keep. iClear won't scan that folder, so they won't show up again."
        if !r.errores.isEmpty {
            texto += "\n\n\(r.errores.count) couldn't be moved:\n" + r.errores.prefix(5).joined(separator: "\n")
        }
        return texto
    }

    private func mensaje(_ r: ResultadoLimpieza) -> String {
        var texto = "Moved \(r.movidos.count) items to the Trash (\(tamano(r.bytes))). You can get them back from there."
        if !r.errores.isEmpty {
            texto += "\n\n\(r.errores.count) couldn't be moved:\n" + r.errores.prefix(5).joined(separator: "\n")
        }
        if !r.sinPermiso.isEmpty {
            texto += "\n\n\(r.sinPermiso.count) belong to the system and need your password. Finder can move them."
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
                Text("\(estado.seleccionados.count) items selected").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                estado.guardar(estado.paraGuardar)
            } label: {
                Label("Keep", systemImage: "archivebox")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .disabled(estado.paraGuardar.isEmpty)
            .help("Move the checked files to Documents/Keep. iClear never scans that folder, so they stop showing up.")
            Button {
                estado.confirmando = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
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

/// Título de grupo en la barra lateral, con el aspecto de los encabezados de sección de macOS.
@MainActor private struct TituloLateral: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .selectionDisabled()
    }
}
