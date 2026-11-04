import CoreText
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import iClearNucleo

/// Imágenes y PDF generados en el directorio temporal, con texto ficticio.
final class ContenidoTests: XCTestCase {
    var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("iClearContenido-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = Reglas.canonica(casa)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: casa)
    }

    func dibujar(_ texto: String, en contexto: CGContext, alto: CGFloat) {
        let fuente = CTFontCreateWithName("Helvetica-Bold" as CFString, 44, nil)
        for (i, linea) in texto.split(separator: "\n").enumerated() {
            let atributos = [kCTFontAttributeName: fuente, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)] as CFDictionary
            let ct = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, String(linea) as CFString, atributos))
            contexto.textPosition = CGPoint(x: 40, y: alto - 90 - CGFloat(i) * 70)
            CTLineDraw(ct, contexto)
        }
    }

    func crearImagen(_ nombre: String, texto: String) throws -> URL {
        let (ancho, alto) = (1400, 600)
        let contexto = try XCTUnwrap(CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        contexto.setFillColor(CGColor(gray: 1, alpha: 1))
        contexto.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        dibujar(texto, en: contexto, alto: CGFloat(alto))
        let url = casa.appendingPathComponent(nombre)
        let destino = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destino, try XCTUnwrap(contexto.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destino))
        return url
    }

    func crearPDF(_ nombre: String, texto: String) throws -> URL {
        let url = casa.appendingPathComponent(nombre)
        var caja = CGRect(x: 0, y: 0, width: 1400, height: 600)
        let contexto = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &caja, nil))
        contexto.beginPDFPage(nil)
        dibujar(texto, en: contexto, alto: caja.height)
        contexto.endPDFPage()
        contexto.closePDF()
        return url
    }

    func testClasificaTextos() {
        XCTAssertTrue(Contenido.esSensible(texto: "INSTITUTO NACIONAL ELECTORAL\nCredencial para votar"))
        XCTAssertTrue(Contenido.esSensible(texto: "Banco ficticio · Estado de Cuenta octubre"))
        XCTAssertTrue(Contenido.esSensible(texto: "CURP GODE561231HDFRRN09"))
        XCTAssertTrue(Contenido.esSensible(texto: "CLABE 012345678901234567"))
        XCTAssertTrue(Contenido.esSensible(texto: "Contraseña del wifi"))
        XCTAssertFalse(Contenido.esSensible(texto: "Tarea de historia: la Revolución Mexicana de 1910"))
        XCTAssertFalse(Contenido.esSensible(texto: "Lista del súper: leche, huevo, pan"))
    }

    func testLeeTextoDeImagenYPDF() throws {
        let imagen = try crearImagen("scan001.png", texto: "INSTITUTO NACIONAL ELECTORAL\nCREDENCIAL PARA VOTAR")
        let pdf = try crearPDF("doc.pdf", texto: "BANCO FICTICIO\nESTADO DE CUENTA")
        let tarea = try crearImagen("tarea.png", texto: "LA REVOLUCION MEXICANA\nTAREA DE HISTORIA")
        XCTAssertTrue(Contenido.esSensible(imagen))
        XCTAssertTrue(Contenido.esSensible(pdf))
        XCTAssertFalse(Contenido.esSensible(tarea))
    }

    func testElEscaneoMarcaElContenidoSensible() throws {
        let carpeta = casa.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let imagen = try crearImagen("scan001.png", texto: "INSTITUTO NACIONAL ELECTORAL\nCREDENCIAL PARA VOTAR")
        let destino = carpeta.appendingPathComponent("scan001.png")
        try FileManager.default.moveItem(at: imagen, to: destino)
        let viejo = Date().addingTimeInterval(-3 * 365 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: viejo, .creationDate: viejo], ofItemAtPath: destino.path)

        var c = Configuracion()
        c.minimoViejos = 1_000
        c.carpetasApps = []
        let r = try Escaner(reglas: Reglas(inicio: casa), config: c).escanear()
        let h = try XCTUnwrap(r.hallazgos.first { $0.nombre == "scan001.png" })
        XCTAssertFalse(Reglas.esSensible(destino), "El nombre no lo delata")
        XCTAssertTrue(h.sensible)
        XCTAssertEqual(h.nota, "Its contents look like a sensitive document")
    }
}

/// Solo lectura sobre la carpeta real; se corre a mano con ICLEAR_REAL=1 para medir tiempos.
final class TiemposRealesTests: XCTestCase {
    func testMedirEscaneoReal() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ICLEAR_REAL"] == "1")
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let reglas = Reglas(inicio: casa, extras: Array(FLStudio.carpetasEnUso(inicio: casa)))
        var c = Configuracion()
        c.revisarContenido = false
        var t = Date()
        let sin = try Escaner(reglas: reglas, config: c).escanear()
        print("TIEMPO sin contenido: \(Int(Date().timeIntervalSince(t)))s hallazgos=\(sin.hallazgos.count)")
        let candidatos = Set(sin.hallazgos.filter { !$0.sensible && Contenido.puedeRevisar($0.url) }.map(\.url))
        t = Date()
        let sensibles = candidatos.filter { Contenido.esSensible($0) }
        print("TIEMPO contenido: \(Int(Date().timeIntervalSince(t)))s revisados=\(candidatos.count) sensibles=\(sensibles.count)")
        for u in sensibles { print("SENSIBLE", u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) }
    }
}
