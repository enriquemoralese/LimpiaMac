import XCTest
@testable import iClearNucleo

/// Una "papelera" ficticia en el directorio temporal. Nunca toca la Papelera real.
final class RestaurarTests: XCTestCase {
    var casa: URL!
    var historial: URL { casa.appendingPathComponent("historial.json") }

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("iClearRestaurar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa.appendingPathComponent("Papelera"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: casa)
    }

    /// Simula lo que hace Papelera.mover: mueve el archivo y lo anota.
    func moverFicticio(_ relativa: String) throws -> Movimiento {
        let original = casa.appendingPathComponent(relativa)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("contenido".utf8).write(to: original)
        let enPapelera = casa.appendingPathComponent("Papelera/" + original.lastPathComponent)
        let r = Papelera.mover([Hallazgo(url: original, categoria: .viejos, bytes: 9, fecha: Date(), tipoFecha: .estimada, sensible: false)],
                               reglas: Reglas(inicio: casa), historial: historial) { url in
            try FileManager.default.moveItem(at: url, to: enPapelera)
            return enPapelera
        }
        XCTAssertEqual(r.errores, [])
        return try XCTUnwrap(r.movidos.first)
    }

    func testRestauraASuLugarYLoQuitaDelHistorial() throws {
        let m = try moverFicticio("Documents/Escuela/tarea.docx")
        // La carpeta original ya no existe: se vuelve a crear.
        try FileManager.default.removeItem(at: casa.appendingPathComponent("Documents/Escuela"))
        XCTAssertEqual(try Papelera.restaurables(historial).map(\.nombre), ["tarea.docx"])

        try Papelera.restaurar(m, historial: historial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: m.original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: m.enPapelera))
        XCTAssertEqual(try Papelera.restaurables(historial), [])
    }

    func testNuncaSobrescribe() throws {
        let m = try moverFicticio("Desktop/foto.jpg")
        try Data("otra".utf8).write(to: URL(fileURLWithPath: m.original))
        XCTAssertThrowsError(try Papelera.restaurar(m, historial: historial))
        XCTAssertEqual(try String(contentsOfFile: m.original), "otra")
        XCTAssertTrue(FileManager.default.fileExists(atPath: m.enPapelera))
    }

    func testLoQueYaNoEstaEnLaPapeleraNoSeOfrece() throws {
        let m = try moverFicticio("Movies/video.mov")
        try FileManager.default.removeItem(atPath: m.enPapelera)
        XCTAssertEqual(try Papelera.restaurables(historial), [])
        XCTAssertThrowsError(try Papelera.restaurar(m, historial: historial))
    }
}

final class PermisoTests: XCTestCase {
    func testSeparaLoQueNoSePudoMoverPorPermiso() throws {
        let casa = FileManager.default.temporaryDirectory.appendingPathComponent("iClearPermiso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: casa) }
        let app = Hallazgo(url: URL(fileURLWithPath: "/Applications/Ficticia.app"), categoria: .aplicaciones, bytes: 900,
                           fecha: Date(), tipoFecha: .apertura, sensible: false)
        let roto = Hallazgo(url: casa.appendingPathComponent("roto.mov"), categoria: .grandes, bytes: 5,
                            fecha: Date(), tipoFecha: .estimada, sensible: false)
        let r = Papelera.mover([app, roto], reglas: Reglas(inicio: casa), historial: casa.appendingPathComponent("h.json")) { url in
            if url.pathExtension == "app" { throw CocoaError(.fileWriteNoPermission) }
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertEqual(r.errores.count, 2)
        XCTAssertEqual(r.sinPermiso, [Pendiente(url: app.url, bytes: 900)])
    }
}
