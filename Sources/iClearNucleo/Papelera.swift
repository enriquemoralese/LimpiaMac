import Foundation

public struct Movimiento: Codable, Sendable, Hashable, Identifiable {
    public let original: String
    public let enPapelera: String
    public let bytes: Int64
    public let fecha: Date

    public init(original: String, enPapelera: String, bytes: Int64, fecha: Date) {
        self.original = original
        self.enPapelera = enPapelera
        self.bytes = bytes
        self.fecha = fecha
    }

    public var id: String { enPapelera + "|" + original }
    public var nombre: String { (original as NSString).lastPathComponent }
}

public struct ResultadoLimpieza: Sendable {
    public var movidos: [Movimiento] = []
    public var errores: [String] = []
    /// Lo que macOS no dejó mover por falta de permiso (apps del sistema). Finder sí puede, pidiendo la contraseña.
    public var sinPermiso: [Pendiente] = []
    public var bytes: Int64 { movidos.reduce(0) { $0 + $1.bytes } }

    public init() {}
}

public struct Pendiente: Sendable, Hashable {
    public let url: URL
    public let bytes: Int64
}

/// Lo único que modifica el disco. Siempre manda a la Papelera, nunca borra de forma definitiva.
public enum Papelera {
    public static var historialPorDefecto: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iClear/historial.json")
    }

    /// Quita rutas repetidas y las que ya van dentro de una carpeta seleccionada,
    /// para no mover dos veces ni contar doble el espacio.
    public static func unicos(_ hallazgos: [Hallazgo]) -> [Hallazgo] {
        var porRuta: [String: Hallazgo] = [:]
        for h in hallazgos where (porRuta[h.url.path]?.bytes ?? -1) < h.bytes { porRuta[h.url.path] = h }
        let rutas = Set(porRuta.keys)
        return porRuta.values
            .filter { h in
                var padre = (h.url.path as NSString).deletingLastPathComponent
                while padre.count > 1 {
                    if rutas.contains(padre) { return false }
                    padre = (padre as NSString).deletingLastPathComponent
                }
                return true
            }
            .sorted { $0.url.path < $1.url.path }
    }

    /// `aPapelera` existe para que las pruebas no toquen la Papelera real.
    public static func mover(_ hallazgos: [Hallazgo], reglas: Reglas, historial: URL = historialPorDefecto,
                             aPapelera: (URL) throws -> URL? = alaPapelera) -> ResultadoLimpieza {
        var resultado = ResultadoLimpieza()
        var movidas = Set<String>()
        for h in unicos(hallazgos) {
            // Primero la app (o el archivo); sus restos solo si ella sí se movió.
            for (i, url) in ([h.url] + h.extras).enumerated() {
                // Un resto pudo moverse ya en otra categoría (por ejemplo en Basura del sistema).
                if movidas.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) { continue }
                if i > 0 && !FileManager.default.fileExists(atPath: url.path) { continue }
                // Segunda revisión por si las reglas cambiaron entre el escaneo y la limpieza.
                if reglas.esIntocable(url) {
                    resultado.errores.append("\(url.path): está protegida, no se movió")
                    if i == 0 { break } else { continue }
                }
                do {
                    let destino = try aPapelera(url)
                    movidas.insert(url.path)
                    // El tamaño del hallazgo ya incluye sus restos: se anota completo en el primero.
                    resultado.movidos.append(Movimiento(original: url.path, enPapelera: destino?.path ?? "",
                                                        bytes: i == 0 ? h.bytes : 0, fecha: Date()))
                } catch {
                    resultado.errores.append("\(url.path): \(error.localizedDescription)")
                    if esFaltaDePermiso(error) { resultado.sinPermiso.append(Pendiente(url: url, bytes: i == 0 ? h.bytes : 0)) }
                    if i == 0 { break }
                }
            }
        }
        if !resultado.movidos.isEmpty {
            do { try anotar(resultado.movidos, en: historial) } catch {
                resultado.errores.append("No se pudo guardar el historial: \(error.localizedDescription)")
            }
        }
        return resultado
    }

    public static func alaPapelera(_ url: URL) throws -> URL? {
        var destino: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destino)
        return destino as URL?
    }

    static func esFaltaDePermiso(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteNoPermissionError { return true }
        let posix = (ns.domain == NSPOSIXErrorDomain ? ns : ns.userInfo[NSUnderlyingErrorKey] as? NSError)
        return posix?.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(posix?.code ?? 0)
    }

    /// Para anotar lo que movió Finder (por ejemplo, apps del sistema con contraseña).
    public static func anotarMovidos(_ movidos: [Movimiento], historial: URL = historialPorDefecto) throws {
        try anotar(movidos, en: historial)
    }

    static func anotar(_ movidos: [Movimiento], en historial: URL) throws {
        try guardar(try leerHistorial(historial) + movidos, en: historial)
    }

    public static func leerHistorial(_ historial: URL = historialPorDefecto) throws -> [Movimiento] {
        guard FileManager.default.fileExists(atPath: historial.path) else { return [] }
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return try decodificador.decode([Movimiento].self, from: Data(contentsOf: historial))
    }

    static func guardar(_ movimientos: [Movimiento], en historial: URL) throws {
        try FileManager.default.createDirectory(at: historial.deletingLastPathComponent(), withIntermediateDirectories: true)
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try codificador.encode(movimientos).write(to: historial, options: .atomic)
    }

    /// Lo que iClear movió y todavía está en la Papelera, lo más reciente primero.
    public static func restaurables(_ historial: URL = historialPorDefecto) throws -> [Movimiento] {
        try leerHistorial(historial)
            .filter { !$0.enPapelera.isEmpty && FileManager.default.fileExists(atPath: $0.enPapelera) }
            .sorted { $0.fecha > $1.fecha }
    }

    public enum ErrorRestaurar: LocalizedError {
        case yaNoEstaEnLaPapelera, yaExisteElOriginal(String)
        public var errorDescription: String? {
            switch self {
            case .yaNoEstaEnLaPapelera: "Ya no está en la Papelera."
            case .yaExisteElOriginal(let ruta): "Ya hay algo con ese nombre en \(ruta)."
            }
        }
    }

    /// Regresa un elemento a su lugar original y lo quita del historial. Nunca sobrescribe.
    public static func restaurar(_ m: Movimiento, historial: URL = historialPorDefecto) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: m.enPapelera) else { throw ErrorRestaurar.yaNoEstaEnLaPapelera }
        guard !fm.fileExists(atPath: m.original) else {
            throw ErrorRestaurar.yaExisteElOriginal((m.original as NSString).deletingLastPathComponent)
        }
        let destino = URL(fileURLWithPath: m.original)
        try fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: URL(fileURLWithPath: m.enPapelera), to: destino)
        try guardar(try leerHistorial(historial).filter { $0 != m }, en: historial)
    }

    /// `nil` si no se puede saber (la carpeta de prueba no existe). `false` si macOS niega la lectura.
    public static func tieneAccesoCompleto(inicio: URL) -> Bool? {
        let protegida = inicio.appendingPathComponent("Library/Safari")
        guard FileManager.default.fileExists(atPath: protegida.path) else { return nil }
        return (try? FileManager.default.contentsOfDirectory(atPath: protegida.path)) != nil
    }
}

public struct ResultadoVaciado: Sendable {
    public var borrados = 0
    public var bytes: Int64 = 0
    public var errores: [String] = []
}

extension Papelera {
    /// Borra de forma definitiva cada elemento de la Papelera. Va uno por uno para que, si algo
    /// falla (en uso, bloqueado, de otro usuario), lo demás sí se borre y se sepa cuál falló.
    public static func vaciar(_ papelera: URL) -> ResultadoVaciado {
        var r = ResultadoVaciado()
        let elementos: [URL]
        do {
            elementos = try FileManager.default.contentsOfDirectory(at: papelera, includingPropertiesForKeys: nil)
        } catch {
            r.errores.append("No se pudo leer la Papelera: \(error.localizedDescription)")
            return r
        }
        for url in elementos where url.lastPathComponent != ".DS_Store" {
            var ignorados: [String] = []
            let bytes = Escaner.ocupado(url, errores: &ignorados)
            do {
                try FileManager.default.removeItem(at: url)
                r.borrados += 1
                r.bytes += bytes
            } catch {
                r.errores.append("\(url.lastPathComponent): \(motivo(error))")
            }
        }
        return r
    }

    /// El error de Foundation trae el motivo real (permiso, bloqueado) en el error interno.
    static func motivo(_ error: Error) -> String {
        let ns = error as NSError
        if let interno = ns.userInfo[NSUnderlyingErrorKey] as? NSError, interno.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(interno.code)))
        }
        return ns.localizedDescription
    }
}
