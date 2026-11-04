import Darwin
import Foundation

/// En APFS, una copia hecha con Finder puede compartir sus bloques con el original (clon).
/// Borrarla no libera nada. macOS sabe cuántos bytes son solo de ese archivo: eso es lo que
/// de verdad se recupera al borrarlo.
enum EspacioAPFS {
    /// `nil` si el volumen no lo soporta (no APFS) o no se pudo leer; entonces se usa el tamaño en disco.
    static func bytesPropios(_ ruta: String) -> Int64? {
        var lista = attrlist()
        lista.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        lista.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        // Respuesta: longitud (u_int32_t) seguida del valor (off_t).
        var buffer = [UInt8](repeating: 0, count: 32)
        let opciones = UInt32(FSOPT_ATTR_CMN_EXTENDED) | UInt32(FSOPT_NOFOLLOW)
        guard getattrlist(ruta, &lista, &buffer, buffer.count, opciones) == 0 else { return nil }
        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }

    /// Espacio que se libera al borrar este archivo.
    static func liberable(_ ruta: String, enDisco: Int64) -> Int64 {
        guard let propios = bytesPropios(ruta) else { return enDisco }
        return min(propios, enDisco)
    }
}

/// Tamaño legible, siempre con número: "0 KB" en lugar de "Zero KB".
public func textoTamano(_ bytes: Int64) -> String {
    let formato = ByteCountFormatter()
    formato.countStyle = .file
    formato.allowsNonnumericFormatting = false
    return formato.string(fromByteCount: bytes)
}
