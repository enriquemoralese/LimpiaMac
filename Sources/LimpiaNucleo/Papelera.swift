import Foundation

public struct Movimiento: Codable, Sendable {
    public let original: String
    public let enPapelera: String
    public let bytes: Int64
    public let fecha: Date
}

public struct ResultadoLimpieza: Sendable {
    public var movidos: [Movimiento] = []
    public var errores: [String] = []
    public var bytes: Int64 { movidos.reduce(0) { $0 + $1.bytes } }
}

/// Lo único que modifica el disco. Siempre manda a la Papelera, nunca borra de forma definitiva.
public enum Papelera {
    public static var historialPorDefecto: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LimpiaMac/historial.json")
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

    static func anotar(_ movidos: [Movimiento], en historial: URL) throws {
        try FileManager.default.createDirectory(at: historial.deletingLastPathComponent(), withIntermediateDirectories: true)
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        var todos: [Movimiento] = []
        if FileManager.default.fileExists(atPath: historial.path) {
            todos = try decodificador.decode([Movimiento].self, from: Data(contentsOf: historial))
        }
        todos += movidos
        try codificador.encode(todos).write(to: historial, options: .atomic)
    }

    /// `nil` si no se puede saber (la carpeta de prueba no existe). `false` si macOS niega la lectura.
    public static func tieneAccesoCompleto(inicio: URL) -> Bool? {
        let protegida = inicio.appendingPathComponent("Library/Safari")
        guard FileManager.default.fileExists(atPath: protegida.path) else { return nil }
        return (try? FileManager.default.contentsOfDirectory(atPath: protegida.path)) != nil
    }
}
