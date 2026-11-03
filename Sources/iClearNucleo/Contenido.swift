import Foundation
import PDFKit
import Vision

/// Detecta documentos sensibles por lo que dicen, no solo por su nombre: una foto de tu INE
/// llamada "scan001.jpg". Lee el texto de imágenes (Vision) y PDF (PDFKit) dentro de la Mac;
/// nada sale a internet.
public enum Contenido {
    static let extensionesImagen: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]
    static let maximoBytes: Int64 = 40 * 1_000_000

    static let frases = [
        "CREDENCIAL PARA VOTAR", "INSTITUTO NACIONAL ELECTORAL", "ESTADO DE CUENTA", "PASAPORTE", "PASSPORT",
        "CLABE", "NUMERO DE SEGURIDAD SOCIAL", "SOCIAL SECURITY", "ACTA DE NACIMIENTO", "CONTRASENA", "PASSWORD",
        "LICENCIA DE CONDUCIR", "CEDULA PROFESIONAL", "CONSTANCIA DE SITUACION FISCAL",
    ]
    static let patrones: [NSRegularExpression] = [
        #"\b[A-Z]{4}\d{6}[HM][A-Z]{5}[0-9A-Z]\d\b"#,  // CURP
        #"\b[A-Z&]{3,4}\d{6}[A-Z0-9]{3}\b"#,          // RFC
        #"\b\d{18}\b"#,                                // CLABE
        #"\b(?:\d{4}[ -]?){3}\d{4}\b"#,                // tarjeta
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func puedeRevisar(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || extensionesImagen.contains(ext)
    }

    public static func esSensible(_ url: URL) -> Bool {
        guard let texto = texto(url) else { return false }
        return esSensible(texto: texto)
    }

    static func esSensible(texto: String) -> Bool {
        let normal = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
            .uppercased().replacingOccurrences(of: "Ñ", with: "N")
        if frases.contains(where: normal.contains) { return true }
        let rango = NSRange(normal.startIndex..., in: normal)
        return patrones.contains { $0.firstMatch(in: normal, range: rango) != nil }
    }

    /// `nil` si no es imagen ni PDF, pesa demasiado o no se pudo leer.
    static func texto(_ url: URL) -> String? {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard Int64(bytes) <= maximoBytes else { return nil }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return nil }
            // Las primeras páginas bastan: un estado de cuenta o un INE lo dicen al principio.
            let paginas = (0..<min(pdf.pageCount, 3)).compactMap { pdf.page(at: $0)?.string }
            let texto = paginas.joined(separator: "\n")
            if !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return texto }
            // PDF escaneado (solo imagen): se lee la primera página con Vision.
            guard let pagina = pdf.page(at: 0) else { return nil }
            let imagen = pagina.thumbnail(of: CGSize(width: 1600, height: 1600), for: .mediaBox)
            guard let cg = imagen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return reconocer(VNImageRequestHandler(cgImage: cg))
        }
        guard extensionesImagen.contains(url.pathExtension.lowercased()) else { return nil }
        return reconocer(VNImageRequestHandler(url: url))
    }

    static func reconocer(_ manejador: VNImageRequestHandler) -> String? {
        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.recognitionLanguages = ["es-ES", "en-US"]
        do { try manejador.perform([pedido]) } catch { return nil }
        return pedido.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
