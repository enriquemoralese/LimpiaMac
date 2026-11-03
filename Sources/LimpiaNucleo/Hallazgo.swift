import Foundation

public enum Categoria: String, CaseIterable, Identifiable, Hashable, Sendable {
    case basura, instaladores, grandes, viejos, dormidos, duplicados

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .basura: "Basura del sistema"
        case .instaladores: "Instaladores"
        case .grandes: "Archivos grandes"
        case .viejos: "Viejos o sin abrir"
        case .dormidos: "Proyectos dormidos"
        case .duplicados: "Duplicados"
        }
    }

    public var descripcion: String {
        switch self {
        case .basura: "Cachés y registros que las apps vuelven a crear cuando los necesitan."
        case .instaladores: "Archivos .dmg y .pkg en Descargas que ya cumplieron su función."
        case .grandes: "Los archivos que más espacio ocupan, empezando por los videos."
        case .viejos: "Archivos que no se abren desde hace tiempo."
        case .dormidos: "Carpetas completas sin cambios desde hace mucho, como semestres o proyectos cerrados."
        case .duplicados: "Copias idénticas por contenido. Se conserva la más antigua."
        }
    }

    public var simbolo: String {
        switch self {
        case .basura: "trash.circle"
        case .instaladores: "shippingbox"
        case .grandes: "film.stack"
        case .viejos: "clock.arrow.circlepath"
        case .dormidos: "moon.zzz"
        case .duplicados: "doc.on.doc"
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
        case .apertura: "Última apertura"
        case .estimada: "Sin registro de apertura"
        case .modificacion: "Última modificación"
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

    public init(url: URL, categoria: Categoria, bytes: Int64, fecha: Date, tipoFecha: TipoFecha, sensible: Bool, nota: String? = nil) {
        self.url = url
        self.categoria = categoria
        self.bytes = bytes
        self.fecha = fecha
        self.tipoFecha = tipoFecha
        self.sensible = sensible
        self.nota = nota
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
