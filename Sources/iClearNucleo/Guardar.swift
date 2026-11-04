import Foundation

public struct ResultadoGuardado: Sendable {
    /// Rutas originales que ya están en la carpeta para conservar.
    public var guardados: [String] = []
    public var bytes: Int64 = 0
    public var errores: [String] = []

    public init() {}
}

/// Mueve a una carpeta propia lo que se quiere conservar (videos, recuerdos), para que deje de salir en
/// cada escaneo. La carpeta se protege, así que iClear nunca vuelve a revisarla.
public enum Guardar {
    public static func carpetaPorDefecto(inicio: URL) -> URL {
        inicio.appendingPathComponent("Documents/Keep", isDirectory: true)
    }

    /// Las apps y la basura del sistema no se guardan: una app fuera de Aplicaciones o una caché suelta no sirven.
    public static func sePuedeGuardar(_ h: Hallazgo) -> Bool {
        h.categoria != .aplicaciones && h.categoria != .basura
    }

    /// Crea la carpeta si falta. Nunca sobrescribe: si el nombre ya existe, agrega " 2", " 3"...
    public static func mover(_ hallazgos: [Hallazgo], a carpeta: URL, reglas: Reglas) -> ResultadoGuardado {
        var r = ResultadoGuardado()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        } catch {
            r.errores.append("Couldn't create \(carpeta.path): \(error.localizedDescription)")
            return r
        }
        for h in Papelera.unicos(hallazgos.filter(sePuedeGuardar)) {
            if reglas.esIntocable(h.url) {
                r.errores.append("\(h.url.path): it's protected, not moved")
                continue
            }
            do {
                try fm.moveItem(at: h.url, to: libre(h.url.lastPathComponent, en: carpeta))
                r.guardados.append(h.url.path)
                r.bytes += h.bytes
            } catch {
                r.errores.append("\(h.url.path): \(error.localizedDescription)")
            }
        }
        return r
    }

    static func libre(_ nombre: String, en carpeta: URL) -> URL {
        let base = (nombre as NSString).deletingPathExtension
        let ext = (nombre as NSString).pathExtension
        var destino = carpeta.appendingPathComponent(nombre)
        var n = 2
        while FileManager.default.fileExists(atPath: destino.path) {
            destino = carpeta.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return destino
    }
}
