import XCTest
@testable import LimpiaNucleo

/// Escanea una carpeta de inicio ficticia en el directorio temporal. Nunca toca la carpeta real.
final class EscanerTests: XCTestCase {
    var casa: URL!
    let hace3Anios = Date().addingTimeInterval(-3 * 365 * 86_400)

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory
            .appendingPathComponent("LimpiaMacPrueba-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = Reglas.canonica(casa)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: casa)
    }

    @discardableResult
    func crear(_ ruta: String, kb: Int, fecha: Date? = nil, byte: UInt8 = 1) throws -> URL {
        let url = casa.appendingPathComponent(ruta)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: byte, count: kb * 1024).write(to: url)
        if let fecha {
            try FileManager.default.setAttributes([.modificationDate: fecha, .creationDate: fecha], ofItemAtPath: url.path)
        }
        return url
    }

    func escanear() throws -> ResultadoEscaneo {
        var c = Configuracion()
        c.umbralGrandes = 3_000_000
        c.minimoViejos = 1_000_000
        c.minimoDormidos = 1_000_000
        c.minimoDuplicados = 100_000
        c.minimoBasura = 100_000
        c.carpetasApps = []
        return try Escaner(reglas: Reglas(inicio: casa), config: c).escanear()
    }

    func rutas(_ r: ResultadoEscaneo, _ c: Categoria) -> Set<String> {
        Set(r.hallazgos.filter { $0.categoria == c }.map { $0.url.path.replacingOccurrences(of: casa.path + "/", with: "") })
    }

    func testClasificacionCompleta() throws {
        // Protegidos
        try crear("Downloads/Useful_docs/viejo.pdf", kb: 2000, fecha: hace3Anios)
        try crear("Downloads/beats/loop.wav", kb: 4000, fecha: hace3Anios)
        try crear("Documents/Cancion/proyecto.flp", kb: 10, fecha: hace3Anios)
        try crear("Documents/Cancion/samples/voz.wav", kb: 4000, fecha: hace3Anios)
        try crear("Quaio-Finance/datos.bin", kb: 4000, fecha: hace3Anios)
        try crear("Library/Caches/com.apple.algo/cache.db", kb: 2000)
        // Candidatos
        try crear("Library/Caches/com.app.ejemplo/cache.db", kb: 2000)
        try crear("Downloads/instalador.dmg", kb: 50)
        try crear("Movies/video.mov", kb: 4000)
        try crear("Desktop/INE frente.jpg", kb: 1500, fecha: hace3Anios)
        try crear("Documents/Escuela2021/tarea1.docx", kb: 1200, fecha: hace3Anios)
        try crear("Documents/Escuela2021/Parcial/tarea2.docx", kb: 1200, fecha: hace3Anios, byte: 2)
        try crear("Pictures/foto.jpg", kb: 300, byte: 7)
        try crear("Pictures/copia/foto.jpg", kb: 300, byte: 7)
        try crear("Pictures/distinta.jpg", kb: 300, byte: 8)

        let r = try escanear()
        XCTAssertEqual(r.errores, [])

        let todas = Set(r.hallazgos.map(\.url.path))
        for protegida in ["Useful_docs", "beats", "Cancion", "Quaio-Finance", "com.apple.algo"] {
            XCTAssertFalse(todas.contains { $0.contains(protegida) }, "No debe aparecer: \(protegida)")
        }

        XCTAssertEqual(rutas(r, .basura), ["Library/Caches/com.app.ejemplo"])
        XCTAssertEqual(rutas(r, .instaladores), ["Downloads/instalador.dmg"])
        XCTAssertEqual(rutas(r, .grandes), ["Movies/video.mov"])
        XCTAssertEqual(rutas(r, .viejos), ["Desktop/INE frente.jpg", "Documents/Escuela2021/tarea1.docx",
                                           "Documents/Escuela2021/Parcial/tarea2.docx"])
        XCTAssertEqual(rutas(r, .dormidos), ["Documents/Escuela2021"])
        XCTAssertEqual(rutas(r, .duplicados).count, 1)
        XCTAssertTrue(rutas(r, .duplicados).first!.hasSuffix("foto.jpg"))

        let ine = r.hallazgos.first { $0.nombre == "INE frente.jpg" }!
        XCTAssertTrue(ine.sensible)
        XCTAssertEqual(ine.tipoFecha, .estimada)
    }

    func testFlpSueltoSoloProtegeElArchivo() throws {
        try crear("Downloads/beat.flp", kb: 10)
        try crear("Downloads/instalador.pkg", kb: 50)
        let r = try escanear()
        XCTAssertEqual(rutas(r, .instaladores), ["Downloads/instalador.pkg"])
    }

    func testCancelacion() async throws {
        for i in 0..<3000 { try crear("Documents/muchos/\(i).txt", kb: 1) }
        let escaner = Escaner(reglas: Reglas(inicio: casa))
        let tarea = Task.detached { try escaner.escanear() }
        tarea.cancel()
        do {
            _ = try await tarea.value
            XCTFail("Debió cancelarse")
        } catch is CancellationError {}
    }

    func testUnicosQuitaRepetidosYAnidados() {
        let carpeta = Hallazgo(url: casa.appendingPathComponent("Documents/Escuela"), categoria: .dormidos,
                               bytes: 100, fecha: Date(), tipoFecha: .modificacion, sensible: false)
        let dentro = Hallazgo(url: casa.appendingPathComponent("Documents/Escuela/a.docx"), categoria: .viejos,
                              bytes: 10, fecha: Date(), tipoFecha: .estimada, sensible: false)
        let video = Hallazgo(url: casa.appendingPathComponent("Movies/v.mov"), categoria: .grandes,
                             bytes: 50, fecha: Date(), tipoFecha: .estimada, sensible: false)
        let videoViejo = Hallazgo(url: video.url, categoria: .viejos, bytes: 50, fecha: Date(), tipoFecha: .estimada, sensible: false)
        let unicos = Papelera.unicos([carpeta, dentro, video, videoViejo])
        XCTAssertEqual(unicos.map(\.url), [carpeta.url, video.url])
    }

    func testMoverRechazaProtegidos() throws {
        let url = try crear("Downloads/Useful_docs/importante.pdf", kb: 1)
        let h = Hallazgo(url: url, categoria: .viejos, bytes: 1024, fecha: Date(), tipoFecha: .estimada, sensible: false)
        let historial = casa.appendingPathComponent("historial.json")
        var llamadas: [URL] = []
        let r = Papelera.mover([h], reglas: Reglas(inicio: casa), historial: historial) { llamadas.append($0); return nil }
        XCTAssertEqual(llamadas, [])
        XCTAssertEqual(r.movidos.count, 0)
        XCTAssertEqual(r.errores.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historial.path))
    }

    func testMoverAnotaHistorial() throws {
        let url = try crear("Downloads/instalador.dmg", kb: 1)
        let h = Hallazgo(url: url, categoria: .instaladores, bytes: 1024, fecha: Date(), tipoFecha: .modificacion, sensible: false)
        let historial = casa.appendingPathComponent("soporte/historial.json")
        let falsa = casa.appendingPathComponent("PapeleraFalsa/instalador.dmg")
        let r = Papelera.mover([h], reglas: Reglas(inicio: casa), historial: historial) { _ in falsa }
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.bytes, 1024)
        let texto = try String(contentsOf: historial)
        XCTAssertTrue(texto.contains("PapeleraFalsa/instalador.dmg"))
    }
}
