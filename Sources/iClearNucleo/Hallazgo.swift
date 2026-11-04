import Foundation

public enum Categoria: String, CaseIterable, Identifiable, Hashable, Sendable {
    case basura, instaladores, grandes, viejos, duplicados, aplicaciones

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .basura: "System Junk"
        case .instaladores: "Installers"
        case .grandes: "Large Files"
        case .viejos: "Old or Unopened"
        case .duplicados: "Duplicates"
        case .aplicaciones: "Applications"
        }
    }

    public var descripcion: String {
        switch self {
        case .basura: "Caches and logs that apps recreate when they need them."
        case .instaladores: ".dmg and .pkg files in Downloads that have done their job."
        case .grandes: "The files that take up the most space, starting with videos."
        case .viejos: "Files you haven't opened in a while and whole folders left unchanged, like past semesters or finished projects."
        case .duplicados: "Copies with identical content. The oldest one is kept."
        case .aplicaciones: "Installed apps with their leftovers in Library. They go to the Trash together."
        }
    }

    public var simbolo: String {
        switch self {
        case .basura: "trash.circle"
        case .instaladores: "shippingbox"
        case .grandes: "film.stack"
        case .viejos: "clock.arrow.circlepath"
        case .duplicados: "doc.on.doc"
        case .aplicaciones: "app.dashed"
        }
    }

    /// Solo la basura técnica llega marcada; lo demás lo decide Enrique.
    public var preseleccion: Bool { self == .basura || self == .instaladores }
}

public enum TipoFecha: Sendable, Hashable {
    /// Fecha real de última apertura según Spotlight.
    case apertura
    /// Spotlight no la tiene; se usa la más reciente entre modificación y creación.
    case estimada
    case modificacion

    public var etiqueta: String {
        switch self {
        case .apertura: "Last opened"
        case .estimada: "No open record"
        case .modificacion: "Last modified"
        }
    }
}

public struct Hallazgo: Identifiable, Hashable, Sendable {
    public let url: URL
    public let categoria: Categoria
    public let bytes: Int64
    public let fecha: Date
    public let tipoFecha: TipoFecha
    public let sensible: Bool
    public let nota: String?
    /// Archivos que se mueven junto con `url`, como los restos de una app en la Librería.
    public let extras: [URL]

    public init(url: URL, categoria: Categoria, bytes: Int64, fecha: Date, tipoFecha: TipoFecha, sensible: Bool,
                nota: String? = nil, extras: [URL] = []) {
        self.url = url
        self.categoria = categoria
        self.bytes = bytes
        self.fecha = fecha
        self.tipoFecha = tipoFecha
        self.sensible = sensible
        self.nota = nota
        self.extras = extras
    }

    /// Un archivo puede salir en dos categorías (grande y viejo), así que el id combina ambas.
    public var id: String { categoria.rawValue + ":" + url.path }
    public var nombre: String { url.lastPathComponent }
}

public struct ResultadoEscaneo: Sendable {
    public var hallazgos: [Hallazgo]
    /// Rutas que no se pudieron leer, con el motivo. Se muestran en la interfaz.
    public var errores: [String]
}
