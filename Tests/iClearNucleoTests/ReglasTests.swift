import XCTest
@testable import iClearNucleo

final class ReglasTests: XCTestCase {
    let casa = URL(fileURLWithPath: "/Users/prueba")

    func testIntocables() {
        let r = Reglas(inicio: casa)
        let protegidas = [
            "Downloads/Useful_docs/contrato.pdf",
            "Downloads/useful_docs/otro.pdf",
            "Downloads/beats/loop.wav",
            "Documents/Image-Line/FL Studio/Projects/Backup/a.flp",
            "Music/Mis Beats 2023/kick.wav",
            "Desktop/cancion.flp",
            "LexColab/app/main.py",
            "Quaio-Finance/datos.csv",
            "quaio-eco-agent/x.py",
            "Documents/Obsidian Vault/nota.md",
            "eco_backup.dump",
        ]
        for ruta in protegidas {
            XCTAssertTrue(r.esIntocable(casa.appendingPathComponent(ruta)), ruta)
        }
        let libres = ["Downloads/instalador.dmg", "Movies/video.mov", "Documents/Escuela/tarea.docx", "Downloads/Useful.pdf"]
        for ruta in libres {
            XCTAssertFalse(r.esIntocable(casa.appendingPathComponent(ruta)), ruta)
        }
    }

    func testCarpetasExtra() {
        let r = Reglas(inicio: casa, extras: [casa.appendingPathComponent("Pictures/Familia")])
        XCTAssertTrue(r.esIntocable(casa.appendingPathComponent("Pictures/Familia/foto.jpg")))
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
