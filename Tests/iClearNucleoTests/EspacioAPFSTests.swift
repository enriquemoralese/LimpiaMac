import XCTest
@testable import iClearNucleo

/// Copias clonadas de APFS en el directorio temporal (que está en APFS en cualquier Mac reciente).
final class EspacioAPFSTests: XCTestCase {
    var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("iClearAPFS-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = Reglas.canonica(casa)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: casa)
    }

    func testUnClonNoLiberaEspacio() throws {
        let original = casa.appendingPathComponent("video.mov")
        try Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: original)
        let propiosAntes = try XCTUnwrap(EspacioAPFS.bytesPropios(original.path))
        XCTAssertGreaterThanOrEqual(propiosAntes, 3_000_000)

        // FileManager.copyItem hace un clon en APFS, igual que Finder.
        let copia = casa.appendingPathComponent("video copia.mov")
        try FileManager.default.copyItem(at: original, to: copia)
        XCTAssertEqual(EspacioAPFS.bytesPropios(copia.path), 0)
        XCTAssertEqual(EspacioAPFS.bytesPropios(original.path), 0)
    }

    func testLasCopiasClonadasNoSalenComoDuplicados() throws {
        let fotos = casa.appendingPathComponent("Pictures")
        try FileManager.default.createDirectory(at: fotos, withIntermediateDirectories: true)
        let original = fotos.appendingPathComponent("foto.jpg")
        try Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }).write(to: original)
        try FileManager.default.copyItem(at: original, to: fotos.appendingPathComponent("foto clon.jpg"))
        // Una copia real (bytes escritos de nuevo) sí ocupa su propio espacio.
        try Data(contentsOf: original).write(to: fotos.appendingPathComponent("foto copia real.jpg"))

        var c = Configuracion()
        c.minimoDuplicados = 100_000
        c.carpetasApps = []
        let r = try Escaner(reglas: Reglas(inicio: casa), config: c).escanear()
        let duplicados = r.hallazgos.filter { $0.categoria == .duplicados }.map(\.nombre)
        XCTAssertEqual(duplicados, ["foto copia real.jpg"])
    }
}

final class HuellaTests: XCTestCase {
    func testArchivosQueSoloDifierenEnMedioNoSonDuplicados() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("iClearHuella-\(UUID().uuidString)/Pictures")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: carpeta.deletingLastPathComponent()) }
        var datos = Data(repeating: 9, count: 1_000_000)
        try datos.write(to: carpeta.appendingPathComponent("a.bin"))
        datos[500_000] = 1
        try datos.write(to: carpeta.appendingPathComponent("b.bin"))

        XCTAssertEqual(try Huella.parcial(carpeta.appendingPathComponent("a.bin")),
                       try Huella.parcial(carpeta.appendingPathComponent("b.bin")), "Iguales al principio y al final")
        var c = Configuracion()
        c.minimoDuplicados = 100_000
        c.carpetasApps = []
        let casa = Reglas.canonica(carpeta.deletingLastPathComponent())
        let r = try Escaner(reglas: Reglas(inicio: casa), config: c).escanear()
        XCTAssertTrue(r.hallazgos.filter { $0.categoria == .duplicados }.isEmpty, "La comparación completa los distingue")
    }
}
