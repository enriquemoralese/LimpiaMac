import XCTest
@testable import iClearNucleo

final class FLStudioTests: XCTestCase {
    var casa: URL!
    let hace3Anios = Date().addingTimeInterval(-3 * 365 * 86_400)

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("iClearFL-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = Reglas.canonica(casa)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: casa)
    }

    func escribir(_ ruta: String, _ datos: Data, fecha: Date? = nil) throws {
        let url = casa.appendingPathComponent(ruta)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: url)
        if let fecha {
            try FileManager.default.setAttributes([.modificationDate: fecha, .creationDate: fecha], ofItemAtPath: url.path)
        }
    }

    /// Imita las tres fuentes reales: archivos recientes, caché del navegador y un .flp en UTF-16LE.
    func prepararFL() throws {
        let navegador = "Documents/Image-Line/FL Studio/Settings/Browser/"
        try escribir(navegador + "Recent files.scr",
                     Data("\u{FEFF}\(casa.path)/Downloads/KIT RECIENTE/Kicks/kick.wav\n/Applications/FL Studio 2025.app/x.fst\n".utf8))
        try escribir(navegador + "SearchCache",
                     Data("'\(casa.path)/Downloads/KIT NAVEGADOR/|0'\n'kick.wav','',0,1,4\n".utf8))
        var flp = Data([0x46, 0x4C, 0x68, 0x64, 0x00, 0x00])
        flp += Data("\(casa.path)/Downloads/KIT ÑANDÚ/Snares/snare.wav".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        flp += Data([0x00, 0x00, 0xC4, 0x01])
        try escribir("Documents/Image-Line/FL Studio/Projects/cancion.flp", flp)
    }

    func testDetectaLasTresFuentes() throws {
        try prepararFL()
        let carpetas = Set(FLStudio.carpetasEnUso(inicio: casa).map(\.lastPathComponent))
        XCTAssertEqual(carpetas, ["KIT RECIENTE", "KIT NAVEGADOR", "KIT ÑANDÚ"])
    }

    func testLasCarpetasEnUsoNoAparecenEnElEscaneo() throws {
        try prepararFL()
        let megas = Data(repeating: 3, count: 2_000_000)
        try escribir("Downloads/KIT RECIENTE/Kicks/kick.wav", megas, fecha: hace3Anios)
        try escribir("Downloads/KIT NAVEGADOR/a.wav", Data(repeating: 4, count: 2_000_000), fecha: hace3Anios)
        try escribir("Downloads/KIT ÑANDÚ/Snares/snare.wav", Data(repeating: 5, count: 2_000_000), fecha: hace3Anios)
        try escribir("Downloads/KIT OLVIDADO/b.wav", Data(repeating: 6, count: 2_000_000), fecha: hace3Anios)

        var c = Configuracion()
        c.minimoViejos = 1_000_000
        c.minimoDormidos = 1_000_000
        c.carpetasApps = []
        let reglas = Reglas(inicio: casa, extras: Array(FLStudio.carpetasEnUso(inicio: casa)))
        let r = try Escaner(reglas: reglas, config: c).escanear()

        let nombres = Set(r.hallazgos.map(\.url.path))
        XCTAssertFalse(nombres.contains { $0.contains("KIT RECIENTE") || $0.contains("KIT NAVEGADOR") || $0.contains("KIT ÑANDÚ") })
        XCTAssertTrue(nombres.contains { $0.hasSuffix("Downloads/KIT OLVIDADO") }, "El kit sin uso sí debe salir como dormido")
    }

    func testSampleSueltoSoloProtegeElArchivo() {
        let url = FLStudio.raizDeKit(casa.path + "/Downloads/loop.wav", inicio: casa)
        XCTAssertEqual(url?.path, casa.path + "/Downloads/loop.wav")
        XCTAssertNil(FLStudio.raizDeKit("/Applications/FL Studio 2025.app/x.fst", inicio: casa))
        XCTAssertNil(FLStudio.raizDeKit(casa.path + "/Library/Caches/x", inicio: casa))
    }

    /// Solo lectura sobre la carpeta real; se corre a mano con ICLEAR_REAL=1 para ver qué detecta.
    func testMostrarCarpetasReales() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ICLEAR_REAL"] == "1")
        let reales = FLStudio.carpetasEnUso(inicio: FileManager.default.homeDirectoryForCurrentUser)
        for url in reales.sorted(by: { $0.path < $1.path }) { print("FL en uso:", url.path) }
    }
}
