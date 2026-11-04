import XCTest
@testable import iClearNucleo

/// Una papelera ficticia en el directorio temporal. Nunca toca la Papelera real.
final class VaciarTests: XCTestCase {
    var papelera: URL!

    override func setUpWithError() throws {
        papelera = FileManager.default.temporaryDirectory.appendingPathComponent("iClearPapelera-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: papelera.appendingPathComponent("carpeta"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 50_000).write(to: papelera.appendingPathComponent("normal.mov"))
        try Data(repeating: 2, count: 50_000).write(to: papelera.appendingPathComponent("carpeta/dentro.pdf"))
        let bloqueado = papelera.appendingPathComponent("bloqueado.txt")
        try Data("x".utf8).write(to: bloqueado)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: bloqueado.path)
    }

    override func tearDownWithError() throws {
        let bloqueado = papelera.appendingPathComponent("bloqueado.txt")
        if FileManager.default.fileExists(atPath: bloqueado.path) {
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: bloqueado.path)
        }
        try FileManager.default.removeItem(at: papelera)
    }

    func testBorraLoQueSePuedeYNombraLoQueNo() throws {
        let r = Papelera.vaciar(papelera)
        XCTAssertEqual(r.borrados, 2)
        XCTAssertGreaterThanOrEqual(r.bytes, 100_000)
        XCTAssertEqual(r.errores.count, 1)
        XCTAssertTrue(r.errores[0].hasPrefix("bloqueado.txt: "), r.errores[0])
        let quedan = try FileManager.default.contentsOfDirectory(atPath: papelera.path)
        XCTAssertEqual(quedan, ["bloqueado.txt"])
    }

    func testPapeleraIlegibleDaError() {
        let r = Papelera.vaciar(papelera.appendingPathComponent("no-existe"))
        XCTAssertEqual(r.borrados, 0)
        XCTAssertEqual(r.errores.count, 1)
        XCTAssertTrue(r.errores[0].hasPrefix("Couldn't read the Trash"))
    }
}
