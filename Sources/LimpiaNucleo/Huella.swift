import CryptoKit
import Foundation

enum Huella {
    /// SHA-256 del contenido, leído en bloques de 1 MB para no cargar videos completos en memoria.
    static func sha256(_ url: URL) throws -> String {
        let archivo = try FileHandle(forReadingFrom: url)
        defer { try? archivo.close() }
        var hasher = SHA256()
        while let bloque = try archivo.read(upToCount: 1 << 20), !bloque.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: bloque)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
