import CoreServices
import Foundation

public struct Configuracion: Sendable {
    public var umbralGrandes: Int64 = 500 * 1_000_000
    public var mesesViejos = 12
    public var mesesDormidos = 18
    /// Debajo de estos tamaños el hallazgo es ruido: libera poco y llena la lista.
    public var minimoViejos: Int64 = 5 * 1_000_000
    public var minimoDormidos: Int64 = 50 * 1_000_000
    public var minimoDuplicados: Int64 = 1_000_000
    public var minimoBasura: Int64 = 1_000_000
    /// `nil` usa /Applications y ~/Applications. Las pruebas pasan carpetas ficticias.
    public var carpetasApps: [URL]?
    /// Lee el texto de imágenes y PDF encontrados para detectar documentos sensibles.
    public var revisarContenido = true

    public init() {}
}

/// Recorre la carpeta de inicio en modo de solo lectura. Nunca mueve ni borra nada.
public struct Escaner: Sendable {
    public let reglas: Reglas
    public let config: Configuracion
    public let ahora: Date

    public init(reglas: Reglas, config: Configuracion = Configuracion(), ahora: Date = Date()) {
        self.reglas = reglas
        self.config = config
        self.ahora = ahora
    }

    struct Archivo {
        let url: URL
        let bytes: Int64      // espacio que ocupa en disco
        let tamano: Int64     // tamaño lógico, para comparar duplicados
        let modificado: Date
        let creado: Date
        let sensible: Bool
    }

    static let claves: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
    ]
    /// Carpetas regenerables de desarrollo: se saltan para no llenar la lista de ruido.
    static let carpetasOmitidas: Set<String> = ["node_modules", "__pycache__", "site-packages", "venv", "DerivedData"]
    static let extensionesInstalador: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
    static let extensionesVideo: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mts", "braw", "r3d"]

    /// Llama a `progreso` de vez en cuando con un texto para la interfaz. Lanza `CancellationError` si se cancela la tarea.
    public func escanear(progreso: @Sendable (String) -> Void = { _ in }) throws -> ResultadoEscaneo {
        var errores: [String] = []
        var hallazgos: [Hallazgo] = []

        progreso("Revisando cachés y registros")
        hallazgos += try basura(errores: &errores)

        let (archivos, carpetasFL, raices) = try recorrer(progreso: progreso, errores: &errores)
        let visibles = archivos.filter { a in !carpetasFL.contains { a.url.path.hasPrefix($0 + "/") } }

        progreso("Clasificando \(visibles.count) archivos")
        hallazgos += try porArchivo(visibles)
        hallazgos += dormidos(visibles, carpetasFL: carpetasFL, raices: raices)

        progreso("Buscando duplicados")
        hallazgos += try duplicados(visibles, errores: &errores)

        progreso("Revisando aplicaciones")
        hallazgos += try aplicaciones(errores: &errores)

        if config.revisarContenido {
            hallazgos = try marcarContenidoSensible(hallazgos, progreso: progreso)
        }

        return ResultadoEscaneo(hallazgos: hallazgos, errores: errores)
    }

    // MARK: - Basura del sistema

    func basura(errores: inout [String]) throws -> [Hallazgo] {
        let lib = reglas.inicio.appendingPathComponent("Library")
        let porHijos = [
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("Logs"),
            lib.appendingPathComponent("Developer/Xcode/DerivedData"),
            lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
            lib.appendingPathComponent("Developer/CoreSimulator/Caches"),
        ]
        let completas = [reglas.inicio.appendingPathComponent(".npm/_cacache")]

        var candidatos: [URL] = completas.filter { FileManager.default.fileExists(atPath: $0.path) }
        for carpeta in porHijos where FileManager.default.fileExists(atPath: carpeta.path) {
            do {
                let hijos = try FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)
                // Las cachés de Apple las protege el sistema y se regeneran solas; se dejan en paz.
                candidatos += hijos.filter { !$0.lastPathComponent.hasPrefix("com.apple.") && $0.lastPathComponent != "CloudKit" }
            } catch {
                errores.append("\(carpeta.path): \(error.localizedDescription)")
            }
        }

        var hallazgos: [Hallazgo] = []
        for url in candidatos where !reglas.esIntocable(url) {
            try Task.checkCancellation()
            let bytes = Self.ocupado(url, errores: &errores)
            guard bytes >= config.minimoBasura else { continue }
            let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? ahora
            hallazgos.append(Hallazgo(url: url, categoria: .basura, bytes: bytes, fecha: fecha,
                                      tipoFecha: .modificacion, sensible: false))
        }
        return hallazgos
    }

    // MARK: - Recorrido

    /// Devuelve los archivos visibles, las carpetas que contienen proyectos de FL Studio y las raíces recorridas.
    func recorrer(progreso: @Sendable (String) -> Void, errores: inout [String]) throws -> ([Archivo], Set<String>, Set<String>) {
        let fm = FileManager.default
        let raices: [URL]
        do {
            raices = try fm.contentsOfDirectory(at: reglas.inicio, includingPropertiesForKeys: Self.claves, options: [.skipsHiddenFiles])
                .filter { $0.lastPathComponent != "Library" && !reglas.esIntocable($0) }
        } catch {
            errores.append("\(reglas.inicio.path): \(error.localizedDescription)")
            return ([], [], [])
        }
        let rutasRaiz = Set(raices.map(\.path))

        var archivos: [Archivo] = []
        var carpetasFL: Set<String> = []
        let fallas = Fallas()

        for raiz in raices {
            progreso("Recorriendo \(raiz.lastPathComponent)")
            let v: URLResourceValues
            do { v = try raiz.resourceValues(forKeys: Set(Self.claves)) } catch {
                errores.append("\(raiz.path): \(error.localizedDescription)")
                continue
            }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory != true {
                // Archivo suelto en la raíz de inicio.
                registrar(raiz, v, en: &archivos, carpetasFL: &carpetasFL, raices: rutasRaiz)
                continue
            }
            if v.isPackage == true { continue }
            do {
                guard let e = fm.enumerator(at: raiz, includingPropertiesForKeys: Self.claves,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                            errorHandler: { url, error in fallas.agregar("\(url.path): \(error.localizedDescription)"); return true })
                else {
                    errores.append("\(raiz.path): no se pudo recorrer")
                    continue
                }
                var contador = 0
                while let url = e.nextObject() as? URL {
                    contador += 1
                    if contador % 1000 == 0 {
                        try Task.checkCancellation()
                        progreso("Recorriendo \(raiz.lastPathComponent) · \(archivos.count) archivos")
                    }
                    let v: URLResourceValues
                    do { v = try url.resourceValues(forKeys: Set(Self.claves)) } catch {
                        errores.append("\(url.path): \(error.localizedDescription)")
                        continue
                    }
                    if v.isSymbolicLink == true { continue }
                    if v.isDirectory == true {
                        // Los paquetes (apps, fototecas, bibliotecas) se omiten completos.
                        if v.isPackage == true || reglas.esIntocable(url) || Self.carpetasOmitidas.contains(url.lastPathComponent) {
                            e.skipDescendants()
                        }
                        continue
                    }
                    registrar(url, v, en: &archivos, carpetasFL: &carpetasFL, raices: rutasRaiz)
                }
            }
        }
        errores += fallas.lista
        return (archivos, carpetasFL, rutasRaiz)
    }

    private func registrar(_ url: URL, _ v: URLResourceValues, en archivos: inout [Archivo], carpetasFL: inout Set<String>, raices: Set<String>) {
        guard v.isRegularFile == true else { return }
        if reglas.protegerFL && url.pathExtension.lowercased() == "flp" {
            // La carpeta de un proyecto de FL Studio queda protegida completa, con sus samples.
            // Si el .flp está suelto en Descargas o similar, solo se protege el archivo.
            let carpeta = url.deletingLastPathComponent().path
            if !raices.contains(carpeta) && carpeta != reglas.inicio.path { carpetasFL.insert(carpeta) }
            return
        }
        if reglas.esIntocable(url) || Self.esDataless(url) { return }
        archivos.append(Archivo(
            url: url,
            bytes: EspacioAPFS.liberable(url.path, enDisco: Int64(v.totalFileAllocatedSize ?? 0)),
            tamano: Int64(v.fileSize ?? 0),
            modificado: v.contentModificationDate ?? ahora,
            creado: v.creationDate ?? ahora,
            sensible: Reglas.esSensible(url)
        ))
    }

    /// Archivos de iCloud que solo existen en la nube: no ocupan espacio local.
    static func esDataless(_ url: URL) -> Bool {
        var st = stat()
        let datalessFlag: UInt32 = 0x4000_0000 // SF_DATALESS en sys/stat.h
        return lstat(url.path, &st) == 0 && (st.st_flags & datalessFlag) != 0
    }

    // MARK: - Instaladores, grandes y viejos

    func porArchivo(_ archivos: [Archivo]) throws -> [Hallazgo] {
        let descargas = reglas.inicio.appendingPathComponent("Downloads").path + "/"
        let limite = Calendar.current.date(byAdding: .month, value: -config.mesesViejos, to: ahora)!
        var hallazgos: [Hallazgo] = []

        for (i, a) in archivos.enumerated() {
            if i % 1000 == 0 { try Task.checkCancellation() }
            if a.url.path.hasPrefix(descargas) && Self.esInstalador(a.url) {
                hallazgos.append(Hallazgo(url: a.url, categoria: .instaladores, bytes: a.bytes, fecha: a.modificado,
                                          tipoFecha: .modificacion, sensible: a.sensible))
                continue
            }
            guard a.bytes >= min(config.umbralGrandes, config.minimoViejos) else { continue }
            let (fecha, tipo) = ultimaApertura(a)
            if a.bytes >= config.umbralGrandes {
                let nota = Self.extensionesVideo.contains(a.url.pathExtension.lowercased()) ? "Video" : nil
                hallazgos.append(Hallazgo(url: a.url, categoria: .grandes, bytes: a.bytes, fecha: fecha,
                                          tipoFecha: tipo, sensible: a.sensible, nota: nota))
            }
            if a.bytes >= config.minimoViejos && fecha < limite {
                hallazgos.append(Hallazgo(url: a.url, categoria: .viejos, bytes: a.bytes, fecha: fecha,
                                          tipoFecha: tipo, sensible: a.sensible))
            }
        }
        return hallazgos
    }

    static func esInstalador(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if extensionesInstalador.contains(ext) { return true }
        let nombre = url.lastPathComponent.lowercased()
        return ext == "zip" && ["install", "setup", "instalador"].contains { nombre.contains($0) }
    }

    func ultimaApertura(_ a: Archivo) -> (Date, TipoFecha) {
        let item = MDItemCreateWithURL(kCFAllocatorDefault, a.url as CFURL)
        if let item, let fecha = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date,
           // Sin registro real, Spotlight devuelve la fecha de modificación o creación; esa no cuenta como apertura.
           abs(fecha.timeIntervalSince(a.modificado)) > 2, abs(fecha.timeIntervalSince(a.creado)) > 2 {
            return (fecha, .apertura)
        }
        // Sin apertura registrada se toma la fecha más reciente que se conozca, para no marcar como viejo
        // algo que llegó hace poco: la fecha en que se agregó a su carpeta (por ejemplo, cuando se descargó)
        // cuenta igual que la de modificación o creación.
        let agregado = item.flatMap { MDItemCopyAttribute($0, kMDItemDateAdded) as? Date } ?? .distantPast
        return (max(a.modificado, a.creado, agregado), .estimada)
    }

    // MARK: - Proyectos dormidos

    func dormidos(_ archivos: [Archivo], carpetasFL: Set<String>, raices: Set<String>) -> [Hallazgo] {
        struct Suma { var bytes: Int64 = 0; var reciente = Date.distantPast; var archivos = 0; var sensibles = 0 }
        var sumas: [String: Suma] = [:]
        for a in archivos {
            var carpeta = a.url.deletingLastPathComponent().path
            // Se suma a cada carpeta hasta llegar a la raíz (Documents, Desktop...), que nunca es candidata.
            while !raices.contains(carpeta) && carpeta.count > reglas.inicio.path.count {
                var s = sumas[carpeta, default: Suma()]
                s.bytes += a.bytes
                s.reciente = max(s.reciente, a.modificado)
                s.archivos += 1
                if a.sensible { s.sensibles += 1 }
                sumas[carpeta] = s
                carpeta = (carpeta as NSString).deletingLastPathComponent
            }
        }

        let limite = Calendar.current.date(byAdding: .month, value: -config.mesesDormidos, to: ahora)!
        let candidatas = sumas.filter { ruta, s in
            s.reciente < limite && s.bytes >= config.minimoDormidos
                && !carpetasFL.contains { $0 == ruta || $0.hasPrefix(ruta + "/") }
        }
        // Solo la carpeta más alta de cada rama: si "Escuela" está dormida, no se lista también "Escuela/2021".
        return candidatas.compactMap { ruta, s in
            var padre = (ruta as NSString).deletingLastPathComponent
            while padre.count > reglas.inicio.path.count {
                if candidatas[padre] != nil { return nil }
                padre = (padre as NSString).deletingLastPathComponent
            }
            var nota = "\(s.archivos) archivos"
            if s.sensibles > 0 { nota += " · \(s.sensibles) con nombre sensible" }
            return Hallazgo(url: URL(fileURLWithPath: ruta, isDirectory: true), categoria: .dormidos, bytes: s.bytes,
                            fecha: s.reciente, tipoFecha: .modificacion, sensible: s.sensibles > 0, nota: nota)
        }
    }

    // MARK: - Duplicados

    func duplicados(_ archivos: [Archivo], errores: inout [String]) throws -> [Hallazgo] {
        let grupos = Dictionary(grouping: archivos.filter { $0.tamano >= config.minimoDuplicados }, by: \.tamano)
            .values.filter { $0.count > 1 }
        var hallazgos: [Hallazgo] = []
        // Primero se compara el principio y el final (barato); solo los que coinciden se leen completos.
        let candidatos = try grupos.flatMap { grupo in
            try agrupar(grupo, por: Huella.parcial, errores: &errores).filter { $0.count > 1 }
        }
        for grupo in candidatos {
            let porHuella = try agrupar(grupo, por: Huella.sha256, errores: &errores)
            for iguales in porHuella where iguales.count > 1 {
                let ordenados = iguales.sorted { $0.creado < $1.creado }
                let original = ordenados[0]
                let rutaOriginal = original.url.path.replacingOccurrences(of: reglas.inicio.path, with: "~")
                // Una copia clonada en APFS comparte bloques con el original: borrarla no libera espacio.
                for copia in ordenados.dropFirst() where copia.bytes >= config.minimoDuplicados {
                    hallazgos.append(Hallazgo(url: copia.url, categoria: .duplicados, bytes: copia.bytes, fecha: copia.creado,
                                              tipoFecha: .modificacion, sensible: copia.sensible,
                                              nota: "Igual a \(rutaOriginal)"))
                }
            }
        }
        return hallazgos
    }

    /// Solo revisa archivos que ya salieron como hallazgo: leer todas las fotos de la Mac tardaría demasiado.
    func marcarContenidoSensible(_ hallazgos: [Hallazgo], progreso: @Sendable (String) -> Void) throws -> [Hallazgo] {
        let revisar = Set(hallazgos.filter { !$0.sensible && $0.categoria != .dormidos && $0.categoria != .aplicaciones
            && Contenido.puedeRevisar($0.url) }.map(\.url))
        progreso("Revisando el contenido de \(revisar.count) documentos")
        // Reconocer texto es lento: se reparte entre todos los núcleos.
        let lista = Array(revisar)
        let marcas = Marcas(cantidad: lista.count)
        DispatchQueue.concurrentPerform(iterations: lista.count) { i in
            if Task.isCancelled { return }
            if Contenido.esSensible(lista[i]) { marcas.marcar(i) }
        }
        try Task.checkCancellation()
        let sensibles = Set(marcas.indices.map { lista[$0] })
        return hallazgos.map { h in
            guard sensibles.contains(h.url) else { return h }
            let nota = [h.nota, "Su contenido parece un documento sensible"].compactMap { $0 }.joined(separator: " · ")
            return Hallazgo(url: h.url, categoria: h.categoria, bytes: h.bytes, fecha: h.fecha, tipoFecha: h.tipoFecha,
                            sensible: true, nota: nota, extras: h.extras)
        }
    }

    func agrupar(_ archivos: [Archivo], por huella: (URL) throws -> String, errores: inout [String]) throws -> [[Archivo]] {
        var grupos: [String: [Archivo]] = [:]
        for a in archivos {
            do { grupos[try huella(a.url), default: []].append(a) } catch is CancellationError {
                throw CancellationError()
            } catch {
                errores.append("\(a.url.path): \(error.localizedDescription)")
            }
        }
        return Array(grupos.values)
    }

    // MARK: - Utilidades

    /// Espacio en disco de un archivo o carpeta completa.
    public static func ocupado(_ url: URL, errores: inout [String]) -> Int64 {
        let claves: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: claves) else {
            errores.append("\(url.path): no se pudo leer")
            return 0
        }
        guard v.isDirectory == true else {
            return EspacioAPFS.liberable(url.path, enDisco: Int64(v.totalFileAllocatedSize ?? 0))
        }
        let fallas = Fallas()
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(claves), options: [],
                                               errorHandler: { u, error in fallas.agregar("\(u.path): \(error.localizedDescription)"); return true })
        var total: Int64 = 0
        while let u = e?.nextObject() as? URL {
            let enDisco = Int64((try? u.resourceValues(forKeys: claves))?.totalFileAllocatedSize ?? 0)
            total += enDisco > 0 ? EspacioAPFS.liberable(u.path, enDisco: enDisco) : 0
        }
        errores += fallas.lista
        return total
    }
}

/// Resultados de la revisión en paralelo, con candado porque varios hilos escriben a la vez.
final class Marcas: @unchecked Sendable {
    private let candado = NSLock()
    private var conjunto = Set<Int>()
    init(cantidad: Int) { conjunto.reserveCapacity(cantidad) }
    func marcar(_ i: Int) { candado.lock(); conjunto.insert(i); candado.unlock() }
    var indices: Set<Int> { candado.lock(); defer { candado.unlock() }; return conjunto }
}

/// Junta errores desde los manejadores del enumerador, que no pueden capturar variables `inout`.
final class Fallas: @unchecked Sendable {
    private(set) var lista: [String] = []
    func agregar(_ texto: String) { lista.append(texto) }
}
