import Foundation

/// Qué carpetas no se tocan y qué nombres se consideran sensibles.
/// Todo se decide por ruta y nombre; nunca se lee el contenido de un archivo.
public struct Reglas: Sendable {
    public let inicio: URL
    /// Rutas absolutas en minúsculas (APFS no distingue mayúsculas).
    let intocables: [String]

    /// Protecciones que sirven a cualquier persona. Relativas a la carpeta de inicio.
    /// Las carpetas de cada quien se agregan en Ajustes, no aquí.
    public static let intocablesFijos = [
        ".ssh",
        ".gnupg",
        ".config",
        "Documents/Image-Line",
        "Library/Application Support/Image-Line",
        "Music/Audio Music Apps",
    ]
    /// FL Studio: cualquier carpeta o app cuyo nombre lo contenga.
    static let fragmentosIntocables = ["image-line", "fl studio", "fl cloud"]
    static let extensionesIntocables: Set<String> = ["flp", "fst"]

    public init(inicio: URL, extras: [URL] = []) {
        let base = Self.canonica(inicio)
        self.inicio = base
        // Las fijas se arman sobre la base ya normalizada: `realpath` falla con rutas que aún no existen.
        intocables = (Self.intocablesFijos.map { base.appendingPathComponent($0) } + extras.map(Self.canonica))
            .map { $0.path.lowercased() }
    }

    /// Ruta real, como la devuelve el recorrido del disco. `resolvingSymlinksInPath` le quita
    /// "/private" a rutas como /private/var y deja de coincidir, por eso se usa `realpath`.
    static func canonica(_ url: URL) -> URL {
        guard let real = realpath(url.path, nil) else { return url }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }

    public func esIntocable(_ url: URL) -> Bool {
        // Sin standardizedFileURL: también quita "/private" y la ruta dejaría de coincidir con la base.
        let ruta = url.path.lowercased()
        if intocables.contains(where: { ruta == $0 || ruta.hasPrefix($0 + "/") }) { return true }
        if Self.extensionesIntocables.contains(url.pathExtension.lowercased()) { return true }
        let base = inicio.path.lowercased()
        // Fuera de la carpeta de inicio (por ejemplo /Applications) solo cuenta el nombre del elemento.
        guard ruta.hasPrefix(base + "/") else {
            let nombre = url.lastPathComponent.lowercased()
            return Self.fragmentosIntocables.contains { nombre.contains($0) }
        }
        let componentes = ruta.dropFirst(base.count + 1).split(separator: "/").map(String.init)
        return componentes.contains { c in Self.fragmentosIntocables.contains { c.contains($0) } }
    }

    // MARK: - Nombres sensibles

    /// Palabras cortas: solo cuentan como palabra completa ("ine" no debe pegar en "machine").
    static let palabrasExactas: Set<String> = [
        "rfc", "curp", "ine", "sat", "cfdi", "nss", "imss", "tax", "2fa", "w2", "pin", "clabe", "iban", "ssn",
    ]
    /// Raíces: cuentan si alguna palabra del nombre empieza con ellas.
    static let raices = [
        "contrasen", "password", "passwd", "pasaporte", "passport", "acta", "escritura", "testament",
        "contrato", "contract", "banco", "bank", "nomina", "payroll", "factura", "invoice", "fiscal",
        "medic", "receta", "prescription", "seguro", "insurance", "poliza", "recovery", "credencial",
        "credential", "licencia", "cedula", "identificacion", "constancia", "comprobante", "statement",
        "secret", "wallet", "seed", "privad", "private", "confidencial", "confidential", "diagnostic",
        "laboratorio", "hipoteca", "mortgage", "demanda", "juicio", "pagare",
    ]
    static let frases = [
        "estado de cuenta", "backup codes", "codigos de respaldo", "recovery codes", "private key",
        "llave privada", "id rsa", "id ed25519",
    ]
    static let extensionesSensibles: Set<String> = [
        "env", "pem", "key", "p12", "pfx", "kdbx", "keychain", "ovpn", "gpg", "asc", "cer", "crt",
    ]

    public static func esSensible(_ url: URL) -> Bool {
        let nombre = url.lastPathComponent
        if nombre.lowercased().hasPrefix(".env") { return true }
        if extensionesSensibles.contains(url.pathExtension.lowercased()) { return true }
        let normal = normalizar(url.deletingPathExtension().lastPathComponent)
        let palabras = normal.split(separator: " ").map(String.init)
        if palabras.contains(where: palabrasExactas.contains) { return true }
        if palabras.contains(where: { p in raices.contains { p.hasPrefix($0) } }) { return true }
        let unido = " " + palabras.joined(separator: " ") + " "
        return frases.contains { unido.contains(" " + $0 + " ") }
    }

    /// Minúsculas, sin acentos y con todo lo que no sea letra o número convertido en espacio.
    static func normalizar(_ texto: String) -> String {
        let plano = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX")).lowercased()
        return String(plano.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
    }
}
