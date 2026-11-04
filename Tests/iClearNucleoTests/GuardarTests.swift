import XCTest
@testable import iClearNucleo

/// Todo pasa en una carpeta ficticia del directorio temporal.
final class GuardarTests: XCTestCase {
    var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("iClearGuardar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = Reglas.canonica(casa)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: casa)
    }

    func crear(_ ruta: String) throws -> URL {
        let url = casa.appendingPathComponent(ruta)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    func hallazgo(_ url: URL, _ c: Categoria = .viejos) -> Hallazgo {
        Hallazgo(url: url, categoria: c, bytes: 1, fecha: Date(), tipoFecha: .estimada, sensible: false)
    }

    func testCreaLaCarpetaYNoSobrescribe() throws {
        let keep = Guardar.carpetaPorDefecto(inicio: casa)
        let video = try crear("Movies/viaje.mov")
        let otro = try crear("Desktop/viaje.mov")
        let r = Guardar.mover([hallazgo(video), hallazgo(otro, .grandes)], a: keep, reglas: Reglas(inicio: casa))
        XCTAssertEqual(r.errores, [])
        XCTAssertEqual(r.guardados.count, 2)
        let dentro = try FileManager.default.contentsOfDirectory(atPath: keep.path).sorted()
        XCTAssertEqual(dentro, ["viaje 2.mov", "viaje.mov"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.path))
    }

    func testNoGuardaAppsNiProtegidos() throws {
        let keep = Guardar.carpetaPorDefecto(inicio: casa)
        let app = try crear("Applications/Algo.app/x")
        let protegido = try crear("Importantes/foto.jpg")
        let reglas = Reglas(inicio: casa, extras: [casa.appendingPathComponent("Importantes")])
        let r = Guardar.mover([hallazgo(app.deletingLastPathComponent(), .aplicaciones), hallazgo(protegido)], a: keep, reglas: reglas)
        XCTAssertEqual(r.guardados, [])
        XCTAssertEqual(r.errores.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: protegido.path))
    }
}
