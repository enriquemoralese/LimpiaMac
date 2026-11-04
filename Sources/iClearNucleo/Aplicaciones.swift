import CoreServices
import Foundation

/// Apps instaladas y sus restos en ~/Library, buscados por el identificador de la app.
extension Escaner {
    /// Safari viene con el sistema y macOS no deja borrarlo.
    static let appsIntocables: Set<String> = ["com.apple.Safari"]
    /// Apps de FL Studio, solo con la opción de FL Studio encendida.
    static let prefijosAppsFL = ["com.image-line."]

    func aplicaciones(errores: inout [String]) throws -> [Hallazgo] {
        let fm = FileManager.default
        var hallazgos: [Hallazgo] = []
        for carpeta in config.carpetasApps ?? [URL(fileURLWithPath: "/Applications"), reglas.inicio.appendingPathComponent("Applications")]
        where fm.fileExists(atPath: carpeta.path) {
            let apps: [URL]
            do {
                apps = try fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.isSymbolicLinkKey])
                    .filter { $0.pathExtension == "app" }
            } catch {
                errores.append("\(carpeta.path): \(error.localizedDescription)")
                continue
            }
            for app in apps {
                try Task.checkCancellation()
                if (try? app.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { continue }
                // Algunos accesos directos (como los juegos de Steam) no tienen identificador:
                // se listan, pero sin buscar restos.
                let id = Bundle(url: app)?.bundleIdentifier ?? ""
                if Self.appsIntocables.contains(id) || (reglas.protegerFL && Self.prefijosAppsFL.contains(where: id.hasPrefix)) || reglas.esIntocable(app) {
                    continue
                }
                // Las apps de Apple comparten archivos con el sistema en la Librería: solo se mueve la app.
                let restos = id.isEmpty || id.hasPrefix("com.apple.") ? [] : restosDe(app: app, id: id)
                let bytesApp = Self.ocupado(app, errores: &errores)
                let bytesRestos = restos.reduce(Int64(0)) { $0 + Self.ocupado($1, errores: &errores) }
                let (fecha, tipo) = ultimoUso(app)
                var nota = restos.isEmpty ? "No leftovers in Library" : "\(restos.count) leftovers in Library · \(Self.formato(bytesRestos))"
                if id.hasPrefix("com.apple.") { nota = "Apple app: only the app is moved" }
                if id.isEmpty { nota = "No bundle ID: only the app is moved" }
                hallazgos.append(Hallazgo(url: app, categoria: .aplicaciones, bytes: bytesApp + bytesRestos, fecha: fecha,
                                          tipoFecha: tipo, sensible: false, nota: nota, extras: restos))
            }
        }
        return hallazgos
    }

    /// Solo coincidencias exactas con el identificador, más el nombre de la app en tres carpetas
    /// donde se usa como nombre de carpeta. Nunca coincidencias parciales.
    func restosDe(app: URL, id: String) -> [URL] {
        let lib = reglas.inicio.appendingPathComponent("Library")
        let nombre = app.deletingPathExtension().lastPathComponent
        var candidatos: [URL] = [
            lib.appendingPathComponent("Application Support/\(id)"),
            lib.appendingPathComponent("Caches/\(id)"),
            lib.appendingPathComponent("Preferences/\(id).plist"),
            lib.appendingPathComponent("Containers/\(id)"),
            lib.appendingPathComponent("Saved Application State/\(id).savedState"),
            lib.appendingPathComponent("HTTPStorages/\(id)"),
            lib.appendingPathComponent("HTTPStorages/\(id).binarycookies"),
            lib.appendingPathComponent("WebKit/\(id)"),
            lib.appendingPathComponent("Cookies/\(id).binarycookies"),
        ]
        // Nombres muy cortos o genéricos podrían ser de otra app: se exige al menos 4 letras.
        if nombre.count >= 4 {
            candidatos += ["Application Support", "Caches", "Logs"].map { lib.appendingPathComponent("\($0)/\(nombre)") }
        }
        // Group Containers usan "<equipo>.<id>" o "group.<id>".
        if let grupos = try? FileManager.default.contentsOfDirectory(at: lib.appendingPathComponent("Group Containers"), includingPropertiesForKeys: nil) {
            candidatos += grupos.filter { g in
                let n = g.lastPathComponent
                return n == "group.\(id)" || n.hasSuffix(".\(id)")
            }
        }
        var vistos = Set<String>()
        return candidatos.filter { url in
            FileManager.default.fileExists(atPath: url.path) && !reglas.esIntocable(url) && vistos.insert(url.path.lowercased()).inserted
        }
    }

    /// En apps, Spotlight sí registra cada vez que se abren.
    func ultimoUso(_ app: URL) -> (Date, TipoFecha) {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, app as CFURL),
           let fecha = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return (fecha, .apertura)
        }
        let v = try? app.resourceValues(forKeys: [.contentModificationDateKey])
        return (v?.contentModificationDate ?? ahora, .estimada)
    }

    static func formato(_ bytes: Int64) -> String { textoTamano(bytes) }
}
