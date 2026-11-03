import XCTest
@testable import iClearNucleo

/// Apps ficticias en una carpeta temporal. Nunca toca /Applications ni la Papelera real.
final class AplicacionesTests: XCTestCase {
    var casa: URL!
    var apps: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("IClearApps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = Reglas.canonica(casa)
        apps = casa.appendingPathComponent("Aplicaciones")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: casa)
    }

    func crearApp(_ nombre: String, id: String, kb: Int = 200) throws {
        let contenido = apps.appendingPathComponent("\(nombre).app/Contents")
        try FileManager.default.createDirectory(at: contenido.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": nombre, "CFBundleExecutable": nombre]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contenido.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: kb * 1024).write(to: contenido.appendingPathComponent("MacOS/\(nombre)"))
    }

    func crear(_ ruta: String, kb: Int = 100) throws {
        let url = casa.appendingPathComponent(ruta)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 2, count: kb * 1024).write(to: url)
    }

    func escanearApps() throws -> [Hallazgo] {
        var c = Configuracion()
        c.carpetasApps = [apps]
        var errores: [String] = []
        let r = try Escaner(reglas: Reglas(inicio: casa), config: c).aplicaciones(errores: &errores)
        XCTAssertEqual(errores, [])
        return r
    }

    func testEncuentraAppConSusRestos() throws {
        try crearApp("Telegram", id: "ru.keepcoder.Telegram")
        try crear("Library/Caches/ru.keepcoder.Telegram/cache.db")
        try crear("Library/Application Support/Telegram/datos.sqlite")
        try crear("Library/Preferences/ru.keepcoder.Telegram.plist", kb: 4)
        try crear("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/x.db")
        try crear("Library/Containers/ru.keepcoder.TelegramShare/no-es-resto.db")
        try crear("Library/Caches/ru.keepcoder.Telegram.otro/no-es-resto.db")

        let r = try escanearApps()
        XCTAssertEqual(r.count, 1)
        let restos = Set(r[0].extras.map { $0.path.replacingOccurrences(of: casa.path + "/Library/", with: "") })
        XCTAssertEqual(restos, [
            "Caches/ru.keepcoder.Telegram",
            "Application Support/Telegram",
            "Preferences/ru.keepcoder.Telegram.plist",
            "Group Containers/6N38VWS5BX.ru.keepcoder.Telegram",
        ])
        XCTAssertGreaterThan(r[0].bytes, 500 * 1024, "El tamaño incluye la app y sus restos")
    }

    func testProtegeFLStudioSafariYNoBuscaRestosDeApple() throws {
        try crearApp("FL Studio 2025", id: "com.image-line.flstudio")
        try crearApp("FL Cloud Plugins", id: "com.image-line.fl-cloud-plugins")
        try crearApp("Safari", id: "com.apple.Safari")
        try crearApp("iMovie", id: "com.apple.iMovieApp")
        try crear("Library/Caches/com.apple.iMovieApp/cache.db")

        let r = try escanearApps()
        XCTAssertEqual(r.map(\.nombre), ["iMovie.app"])
        XCTAssertEqual(r[0].extras, [])
    }

    func testMoverLlevaLosRestosYNoRepite() throws {
        try crearApp("Telegram", id: "ru.keepcoder.Telegram")
        try crear("Library/Caches/ru.keepcoder.Telegram/cache.db")
        let app = try escanearApps()[0]
        // El mismo resto también salió en Basura del sistema.
        let cache = Hallazgo(url: casa.appendingPathComponent("Library/Caches/ru.keepcoder.Telegram"), categoria: .basura,
                             bytes: 100, fecha: Date(), tipoFecha: .modificacion, sensible: false)

        var llamadas: [String] = []
        let r = Papelera.mover([app, cache], reglas: Reglas(inicio: casa), historial: casa.appendingPathComponent("h.json")) {
            llamadas.append($0.lastPathComponent); return nil
        }
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(llamadas.sorted(), ["Telegram.app", "ru.keepcoder.Telegram"])
    }

    /// Solo lectura sobre las apps reales; se corre a mano con ICLEAR_REAL=1 para ver qué detecta.
    func testMostrarAppsReales() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ICLEAR_REAL"] == "1")
        var errores: [String] = []
        let r = try Escaner(reglas: Reglas(inicio: FileManager.default.homeDirectoryForCurrentUser)).aplicaciones(errores: &errores)
        for h in r.sorted(by: { $0.bytes > $1.bytes }) {
            print("APP \(h.nombre) | \(Escaner.formato(h.bytes)) | \(h.tipoFecha.etiqueta) \(h.fecha.formatted(date: .abbreviated, time: .omitted)) | \(h.nota ?? "")")
            for e in h.extras { print("    resto:", e.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) }
        }
        for e in errores { print("ERROR", e) }
    }
}
