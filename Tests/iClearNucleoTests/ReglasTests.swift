import XCTest
@testable import iClearNucleo

final class ReglasTests: XCTestCase {
    let casa = URL(fileURLWithPath: "/Users/prueba")

    func testIntocablesDeFabrica() {
        let r = Reglas(inicio: casa)
        let protegidas = [
            ".ssh/id_ed25519",
            ".gnupg/llave.gpg",
            "Documents/Image-Line/FL Studio/Projects/Backup/a.flp",
            "Library/Application Support/Image-Line/datos",
            "Music/Audio Music Apps/Plug-In Settings/Ultrabeat/x.pst",
            "Desktop/cancion.flp",
        ]
        for ruta in protegidas {
            XCTAssertTrue(r.esIntocable(casa.appendingPathComponent(ruta)), ruta)
        }
        XCTAssertTrue(r.esIntocable(URL(fileURLWithPath: "/Applications/FL Studio 2025.app")))
        // Nada personal viene de fábrica: eso se agrega en Ajustes.
        let libres = ["Downloads/instalador.dmg", "Movies/video.mov", "Documents/Escuela/tarea.docx",
                      "Downloads/Importantes/contrato.pdf", "Trabajo/datos.csv", "Music/Mis Beats/kick.wav"]
        for ruta in libres {
            XCTAssertFalse(r.esIntocable(casa.appendingPathComponent(ruta)), ruta)
        }
    }

    func testCarpetasExtra() {
        let r = Reglas(inicio: casa, extras: [casa.appendingPathComponent("Pictures/Familia"), casa.appendingPathComponent("Trabajo")])
        XCTAssertTrue(r.esIntocable(casa.appendingPathComponent("Pictures/Familia/foto.jpg")))
        XCTAssertTrue(r.esIntocable(casa.appendingPathComponent("trabajo/datos.csv")), "Sin distinguir mayúsculas")
        XCTAssertFalse(r.esIntocable(casa.appendingPathComponent("Pictures/FamiliaVieja/foto.jpg")))
    }

    func testSensibles() {
        let si = [
            "INE frente.jpg", "Estado de Cuenta Octubre.pdf", "contraseñas.txt", "RFC_2024.pdf", "mi-curp.pdf",
            "Pasaporte.png", "factura-0012.xml", "Contrato arrendamiento.docx", "receta médica.pdf",
            ".env", ".env.local", "id_rsa", "servidor.pem", "Backup codes github.txt",
        ]
        for nombre in si {
            XCTAssertTrue(Reglas.esSensible(URL(fileURLWithPath: "/x/" + nombre)), nombre)
        }
        let no = ["machine learning.pdf", "vacaciones.mp4", "Satélite.png", "tarea historia.docx", "actualizacion.zip"]
        for nombre in no {
            XCTAssertFalse(Reglas.esSensible(URL(fileURLWithPath: "/x/" + nombre)), nombre)
        }
    }
}
