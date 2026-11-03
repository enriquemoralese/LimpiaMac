import AppKit
import AVKit
import iClearNucleo
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Miniaturas del contenido real (cuadro de video, foto, primera página) con caché en memoria.
@MainActor final class Miniaturas {
    static let compartidas = Miniaturas()
    private let cache = NSCache<NSString, NSImage>()

    func enCache(_ url: URL, lado: CGFloat) -> NSImage? {
        cache.object(forKey: "\(url.path)#\(Int(lado))" as NSString)
    }

    /// `nil` cuando Quick Look no sabe dibujar ese tipo (carpetas, instaladores): se usa el ícono de Finder.
    func imagen(_ url: URL, lado: CGFloat) async -> NSImage? {
        let clave = "\(url.path)#\(Int(lado))" as NSString
        if let guardada = cache.object(forKey: clave) { return guardada }
        let pedido = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: lado, height: lado),
                                                  scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                  representationTypes: .thumbnail)
        guard let r = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: pedido) else { return nil }
        cache.setObject(r.nsImage, forKey: clave)
        return r.nsImage
    }
}

/// Sin `@Environment`: también se usa dentro de celdas de la tabla (ver `Casilla`).
@MainActor struct Miniatura: View {
    let url: URL
    let lado: CGFloat
    /// En la tabla es un cuadro fijo de `lado`; en el panel ocupa todo el espacio libre
    /// y `lado` solo fija la resolución que se pide a Quick Look.
    var flexible = false
    @State private var imagen: NSImage?

    var body: some View {
        Group {
            if flexible {
                // Color.clear no pide tamaño propio: la imagen se ajusta al espacio que haya.
                // Sin esto, la imagen de 1000 pt pedía más alto que la ventana y descuadraba
                // toda la ventana (barra lateral vacía, datos fuera de pantalla).
                Color.clear.overlay { contenido }
            } else {
                contenido.frame(width: lado, height: lado)
            }
        }
        .task(id: url) {
            imagen = nil
            imagen = await Miniaturas.compartidas.imagen(url, lado: lado)
        }
    }

    @ViewBuilder private var contenido: some View {
        if let imagen = imagen ?? Miniaturas.compartidas.enCache(url, lado: lado) {
            Image(nsImage: imagen).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: lado > 80 ? 10 : 4))
                .shadow(color: .black.opacity(0.25), radius: lado > 80 ? 6 : 1, y: 1)
        } else {
            Image(nsImage: icono).resizable().scaledToFit()
                .frame(maxWidth: flexible ? 160 : nil, maxHeight: flexible ? 160 : nil)
        }
    }

    /// El ícono de Finder viene a 32 px por omisión; pedirlo al tamaño final evita que se vea borroso.
    private var icono: NSImage {
        let i = NSWorkspace.shared.icon(forFile: url.path)
        i.size = NSSize(width: lado, height: lado)
        return i
    }
}

/// Panel derecho con la vista previa grande del archivo seleccionado.
@MainActor struct DetalleView: View {
    let estado: Estado
    let vistaRapida: (URL) -> Void
    @State private var revisarDeNuevo = 0

    var body: some View {
        // Se lee del estado dentro del body para que el panel se redibuje con cada clic.
        let ids = estado.filas
        let elegido = ids.count == 1 ? estado.hallazgos.first { ids.contains($0.id) } : nil
        if let h = elegido {
            // GeometryReader toma exactamente el espacio que le dan y no le pide altura a la ventana.
            // Sin él, el panel le pasaba su alto ideal a la ventana y la barra lateral quedaba
            // dibujada fuera de la pantalla, vacía.
            GeometryReader { geo in
            // La vista previa toma todo el alto libre; los datos quedan fijos abajo.
            VStack(alignment: .leading, spacing: 16) {
                // Se pide a Quick Look a 1000 pt para que se vea nítida aunque el panel se agrande.
                Group {
                    if Reproductor.puedeReproducir(h.url) {
                        // .id: al cambiar de archivo se crea uno nuevo y el anterior deja de sonar.
                        Reproductor(url: h.url).id(h.url)
                    } else {
                        Miniatura(url: h.url, lado: 1000, flexible: true)
                    }
                }
                    .frame(minHeight: 200)
                    .padding(.top, 8)
                    .onTapGesture(count: 2) { vistaRapida(h.url) }
                    .help("Doble clic para abrir la vista rápida")

                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(h.nombre).font(.headline).textSelection(.enabled)
                            if h.sensible { Image(systemName: "lock.fill").foregroundStyle(.orange) }
                        }
                        Text(tamano(h.bytes)).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                    }

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        GridRow {
                            Text(h.tipoFecha.etiqueta).foregroundStyle(.secondary)
                            Text(h.fecha, format: .dateTime.day().month(.wide).year())
                        }
                        if let nota = h.nota {
                            GridRow {
                                Text("Nota").foregroundStyle(.secondary)
                                Text(nota)
                            }
                        }
                        GridRow {
                            Text("Ubicación").foregroundStyle(.secondary)
                            Text(h.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .textSelection(.enabled)
                        }
                    }
                    .font(.callout)

                    let _ = revisarDeNuevo
                    if let app = estado.abiertas([h]).first {
                        HStack {
                            Label("Está abierta. Ciérrala antes de moverla.", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange)
                            Spacer()
                            Button("Cerrar") {
                                app.terminate()
                                Task { try? await Task.sleep(for: .seconds(1.5)); revisarDeNuevo += 1 }
                            }
                        }
                    }

                    if !h.extras.isEmpty {
                        DisclosureGroup("También se moverán \(h.extras.count) restos") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(h.extras, id: \.self) { url in
                                    Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.callout)
                    }

                    if h.sensible {
                        Label("El nombre parece de un documento sensible. Revísalo antes de moverlo.", systemImage: "lock")
                            .font(.callout).foregroundStyle(.orange)
                    }

                    let marcado = estado.seleccion.contains(h.id)
                    Toggle("Mover a la Papelera", isOn: Binding(get: { marcado }, set: { estado.marcar([h.id], $0) }))

                    HStack {
                        Button("Vista rápida") { vistaRapida(h.url) }
                        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([h.url]) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        } else {
            ContentUnavailableView("Sin selección", systemImage: "eye",
                                   description: Text("Haz clic en una fila para ver su vista previa."))
        }
    }
}

/// Videos y audios: muestra la miniatura con un botón de play y, al tocarlo, los reproduce ahí mismo.
/// El reproductor se crea solo al dar play, para no cargar cada archivo que se selecciona.
@MainActor struct Reproductor: View {
    let url: URL
    @State private var reproductor: AVPlayer?

    static func puedeReproducir(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) ?? false
    }

    var body: some View {
        if let reproductor {
            VistaReproductor(reproductor: reproductor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onAppear { reproductor.play() }
                .onDisappear { reproductor.pause() }
        } else {
            Miniatura(url: url, lado: 1000, flexible: true)
                .overlay {
                    Button {
                        reproductor = AVPlayer(url: url)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 68, height: 68)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    .buttonStyle(.plain)
                    .help("Reproducir aquí")
                }
        }
    }
}

/// Reproductor nativo de macOS. Se usa en lugar de `VideoPlayer` de SwiftUI, que en macOS 14
/// tronó al abrirse en la app empaquetada (_AVKit_SwiftUI no encontraba su clase base).
private struct VistaReproductor: NSViewRepresentable {
    let reproductor: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let vista = AVPlayerView()
        vista.controlsStyle = .floating
        vista.player = reproductor
        return vista
    }

    func updateNSView(_ vista: AVPlayerView, context: Context) {
        if vista.player !== reproductor { vista.player = reproductor }
    }
}
