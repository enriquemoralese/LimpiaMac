import Charts
import iClearNucleo
import SwiftUI

@MainActor struct ResumenView: View {
    @Environment(Estado.self) private var estado

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                anillo
                    .frame(width: 220, height: 220)
                    .padding(.top, 24)

                if estado.escaneando {
                    VStack(spacing: 8) {
                        Text(estado.progreso).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Button("Stop") { estado.cancelar() }.buttonStyle(.link)
                    }
                    .frame(height: 80)
                } else {
                    Button {
                        estado.escanear()
                    } label: {
                        Text(estado.escaneado ? "Scan Again" : "Scan")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .frame(height: 80)
                }

                if estado.accesoCompleto == false { avisoAcceso }

                // Las tarjetas siempre están; mientras escanea muestran su forma y se llenan al terminar.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(Categoria.allCases) { c in
                        Tarjeta(categoria: c, bytes: estado.total(c), cantidad: estado.hallazgos(en: c).count,
                                fase: estado.escaneando ? .cargando : (estado.escaneado ? .lista : .vacia))
                            .onTapGesture { if !estado.escaneando { estado.seccion = .categoria(c) } }
                    }
                }
                .frame(maxWidth: 680)

                if !estado.errores.isEmpty {
                    DisclosureGroup("\(estado.errores.count) paths couldn't be read") {
                        Text(estado.errores.prefix(200).joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 680)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }

    // MARK: - Anillo del disco

    private var disco: (total: Int64, libre: Int64)? {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = v?.volumeTotalCapacity, let libre = v?.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total), libre)
    }

    @ViewBuilder private var anillo: some View {
        if let disco {
            let seleccionado = min(estado.bytesSeleccionados, disco.total - disco.libre)
            let partes: [(String, Int64, Color)] = [
                ("Used", disco.total - disco.libre - seleccionado, .accentColor),
                ("To free", seleccionado, .orange),
                ("Available", disco.libre, Color.secondary.opacity(0.18)),
            ]
            Chart(partes, id: \.0) { parte in
                SectorMark(angle: .value("Bytes", parte.1), innerRadius: .ratio(0.78), angularInset: 1.2)
                    .cornerRadius(3)
                    .foregroundStyle(parte.2)
            }
            .chartLegend(.hidden)
            .overlay {
                VStack(spacing: 2) {
                    Text(tamano(disco.libre)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("available").font(.callout).foregroundStyle(.secondary)
                    // El total del disco, para dar contexto: "47 GB available of 245 GB".
                    Text("of \(tamano(disco.total))").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    if seleccionado > 0 {
                        Text("+\(tamano(seleccionado))").font(.callout.weight(.medium)).foregroundStyle(.orange)
                    }
                }
            }
            .animation(.smooth, value: seleccionado)
        } else {
            Image(systemName: "internaldrive").font(.system(size: 80, weight: .thin)).foregroundStyle(.secondary)
        }
    }

    private var avisoAcceso: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Full Disk Access is missing").font(.headline)
                Text("Without it, macOS hides some folders and the scan is incomplete. Add iClear in Privacy & Security › Full Disk Access and reopen the app.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .frame(maxWidth: 680, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor private struct Tarjeta: View {
    let categoria: Categoria
    let bytes: Int64
    let cantidad: Int
    let fase: Fase
    @State private var encima = false
    @State private var pulso = false

    enum Fase { case vacia, cargando, lista }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: categoria.simbolo).font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(categoria.titulo).font(.headline)
                Group {
                    switch fase {
                    case .vacia: Text("Not scanned")
                    case .cargando: Text("00 items").redacted(reason: .placeholder)
                    case .lista: Text(cantidad == 0 ? "Nothing to review" : "\(cantidad) items")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Group {
                switch fase {
                case .vacia: Text("—").foregroundStyle(.tertiary)
                case .cargando: Text("00.00 GB").redacted(reason: .placeholder)
                case .lista: Text(tamano(bytes))
                }
            }
            .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .opacity(fase == .cargando && pulso ? 0.55 : 1)
        .animation(fase == .cargando ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .smooth(duration: 0.3), value: pulso)
        .onAppear { pulso = fase == .cargando }
        .onChange(of: fase) { pulso = fase == .cargando }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjetaDeVidrio(radio: 14, resaltada: encima)
        .scaleEffect(encima ? 1.015 : 1)
        .animation(.smooth(duration: 0.15), value: encima)
        .onHover { encima = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
