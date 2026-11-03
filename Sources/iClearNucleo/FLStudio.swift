import Foundation

/// Detecta qué carpetas de samples usa FL Studio, para protegerlas aunque estén en Descargas.
/// Fuentes: los archivos recientes y la caché del navegador de FL, y las rutas guardadas dentro de cada .flp.
public enum FLStudio {
    public static func carpetasEnUso(inicio: URL) -> Set<URL> {
        let base = Reglas.canonica(inicio)
        let navegador = base.appendingPathComponent("Documents/Image-Line/FL Studio/Settings/Browser")
        var rutas: [String] = []
        rutas += lineas(navegador.appendingPathComponent("Recent files.scr"))
        // En SearchCache, las carpetas van como '/ruta/completa/|0'.
        rutas += lineas(navegador.appendingPathComponent("SearchCache"))
            .filter { $0.hasPrefix("'/") }
            .map { String($0.dropFirst().prefix { $0 != "|" }) }
        for flp in proyectos(base) {
            rutas += rutasEnProyecto(flp, prefijo: base.path + "/")
        }
        return Set(rutas.compactMap { raizDeKit($0, inicio: base) })
    }

    /// De "~/Downloads/KIT/Kicks/kick.wav" devuelve "~/Downloads/KIT": se protege el kit completo.
    /// Si el sample está suelto en Descargas, solo ese archivo.
    static func raizDeKit(_ ruta: String, inicio: URL) -> URL? {
        let prefijo = inicio.path + "/"
        guard ruta.hasPrefix(prefijo) else { return nil }
        let partes = ruta.dropFirst(prefijo.count).split(separator: "/", omittingEmptySubsequences: true)
        guard let raiz = partes.first, raiz != "Library" else { return nil }
        let componentes = partes.count >= 2 ? Array(partes.prefix(2)) : Array(partes)
        return componentes.reduce(inicio) { $0.appendingPathComponent(String($1)) }
    }

    static func lineas(_ url: URL) -> [String] {
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return texto.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespaces)) }
    }

    /// Todos los .flp de la carpeta de inicio, según Spotlight, más los de la carpeta de FL por si Spotlight no los indexó.
    static func proyectos(_ inicio: URL) -> [URL] {
        var urls = Set<URL>()
        let consulta = Process()
        consulta.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        consulta.arguments = ["-onlyin", inicio.path, "kMDItemFSName == '*.flp'"]
        let salida = Pipe()
        consulta.standardOutput = salida
        if (try? consulta.run()) != nil {
            let datos = salida.fileHandleForReading.readDataToEndOfFile()
            consulta.waitUntilExit()
            for linea in String(decoding: datos, as: UTF8.self).split(separator: "\n") {
                urls.insert(URL(fileURLWithPath: String(linea)))
            }
        }
        let fl = inicio.appendingPathComponent("Documents/Image-Line")
        if let e = FileManager.default.enumerator(at: fl, includingPropertiesForKeys: nil) {
            while let url = e.nextObject() as? URL {
                if url.pathExtension.lowercased() == "flp" { urls.insert(url) }
            }
        }
        return Array(urls)
    }

    /// Los .flp guardan las rutas de los samples en UTF-16LE (y en versiones viejas, en UTF-8).
    static func rutasEnProyecto(_ url: URL, prefijo: String) -> [String] {
        guard let datos = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let bytes = [UInt8](datos)
        var rutas: [String] = []

        let utf16 = Array(prefijo.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        for inicio in posiciones(de: utf16, en: bytes) {
            var unidades: [UInt16] = []
            var i = inicio
            while i + 1 < bytes.count {
                let u = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
                if u < 0x20 { break }
                unidades.append(u)
                i += 2
            }
            rutas.append(String(decoding: unidades, as: UTF16.self))
        }

        let utf8 = Array(prefijo.utf8)
        for inicio in posiciones(de: utf8, en: bytes) {
            let fin: Int = bytes[inicio...].firstIndex(where: { $0 < 0x20 }) ?? bytes.count
            rutas.append(String(decoding: bytes[inicio..<fin], as: UTF8.self))
        }
        return rutas
    }

    static func posiciones(de patron: [UInt8], en bytes: [UInt8]) -> [Int] {
        guard let primero = patron.first, patron.count <= bytes.count else { return [] }
        var encontradas: [Int] = []
        var i = 0
        while i <= bytes.count - patron.count {
            if bytes[i] == primero && bytes[i..<i + patron.count].elementsEqual(patron) {
                encontradas.append(i)
                i += patron.count
            } else {
                i += 1
            }
        }
        return encontradas
    }
}
