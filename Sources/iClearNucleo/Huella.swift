import CryptoKit
import Foundation

enum Huella {
    static let bloqueParcial = 64 * 1024

    /// SHA-256 de los primeros y últimos 64 KB. Sirve para descartar rápido archivos distintos;
    /// dos archivos con la misma huella parcial todavía se comparan completos.
    static func parcial(_ url: URL) throws -> String {
        let archivo = try FileHandle(forReadingFrom: url)
        defer { try? archivo.close() }
        var hasher = SHA256()
        if let inicio = try archivo.read(upToCount: bloqueParcial) { hasher.update(data: inicio) }
        let fin = try archivo.seekToEnd()
        if fin > UInt64(bloqueParcial * 2) {
            try archivo.seek(toOffset: fin - UInt64(bloqueParcial))
            if let final = try archivo.read(upToCount: bloqueParcial) { hasher.update(data: final) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

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
