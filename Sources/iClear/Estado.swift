import AppKit
import iClearNucleo
import Observation

enum Seccion: Hashable {
    case resumen
    case categoria(Categoria)
    case recientes
    case papelera
}

@Observable @MainActor
final class Estado {
    var seccion: Seccion? = .resumen
    var hallazgos: [Hallazgo] = []
    var errores: [String] = []
    var seleccion: Set<String> = []
    /// Filas resaltadas en la tabla (clic), distintas de las marcadas para la Papelera.
    /// Viven aquí para que el panel de vista previa, que macOS dibuja aparte, vea el cambio.
    var filas: Set<String> = []
    var confirmando = false
    /// Lo que iClear movió y todavía se puede restaurar.
    var recientes: [Movimiento] = []
    var escaneando = false
    var escaneado = false
    var progreso = ""
    var papeleraBytes: Int64?
    var ultimaLimpieza: ResultadoLimpieza?
    var ultimoGuardado: ResultadoGuardado?
    var accesoCompleto: Bool?

    private var tarea: Task<Void, Never>?
    let inicio = FileManager.default.homeDirectoryForCurrentUser

    /// Carpetas de samples que usa FL Studio. Se recalculan en cada escaneo y quedan protegidas.
    var enUsoFL: [URL] = []

    var reglas: Reglas { Reglas(inicio: inicio, extras: Ajustes.protegidas + enUsoFL, protegerFL: Ajustes.protegerFL) }

    init() {
        accesoCompleto = Papelera.tieneAccesoCompleto(inicio: inicio)
        medirPapelera()
        cargarRecientes()
        let inicio = inicio
        Task {
            guard Ajustes.protegerFL else { return }
            enUsoFL = await Task.detached { FLStudio.carpetasEnUso(inicio: inicio).sorted { $0.path < $1.path } }.value
        }
    }

    // MARK: - Escaneo

    func escanear() {
        tarea?.cancel()
        escaneando = true
        progreso = "Preparing"
        errores = []
        let inicio = inicio
        let extras = Ajustes.protegidas
        let config = Ajustes.configuracion
        let protegerFL = Ajustes.protegerFL
        tarea = Task {
            let trabajo = Task.detached(priority: .userInitiated) { () throws -> (ResultadoEscaneo, [URL]) in
                let avisar: @Sendable (String) -> Void = { texto in Task { @MainActor in self.progreso = texto } }
                var fl: [URL] = []
                if protegerFL {
                    avisar("Finding the samples FL Studio uses")
                    fl = FLStudio.carpetasEnUso(inicio: inicio).sorted { $0.path < $1.path }
                }
                let escaner = Escaner(reglas: Reglas(inicio: inicio, extras: extras + fl, protegerFL: protegerFL), config: config)
                return (try escaner.escanear(progreso: avisar), fl)
            }
            let resultado = await withTaskCancellationHandler {
                await trabajo.result
            } onCancel: {
                trabajo.cancel()
            }
            switch resultado {
            case .success(let (r, fl)):
                enUsoFL = fl
                hallazgos = r.hallazgos
                errores = r.errores
                seleccion = Set(r.hallazgos.filter { $0.categoria.preseleccion && !$0.sensible }.map(\.id))
                escaneado = true
            case .failure(is CancellationError):
                break
            case .failure(let error):
                errores = ["The scan stopped: \(error.localizedDescription)"]
            }
            escaneando = false
            accesoCompleto = Papelera.tieneAccesoCompleto(inicio: inicio)
        }
    }

    func cancelar() { tarea?.cancel() }

    // MARK: - Consultas

    func hallazgos(en categoria: Categoria) -> [Hallazgo] { hallazgos.filter { $0.categoria == categoria } }

    func total(_ categoria: Categoria) -> Int64 {
        Papelera.unicos(hallazgos(en: categoria)).reduce(0) { $0 + $1.bytes }
    }

    var seleccionados: [Hallazgo] { Papelera.unicos(hallazgos.filter { seleccion.contains($0.id) }) }
    var bytesSeleccionados: Int64 { seleccionados.reduce(0) { $0 + $1.bytes } }

    func marcar(_ ids: some Sequence<String>, _ valor: Bool) {
        if valor { seleccion.formUnion(ids) } else { seleccion.subtract(ids) }
    }

    // MARK: - Limpieza

    func limpiar() {
        let elegidos = seleccionados
        let reglas = reglas
        Task {
            let r = await Task.detached { Papelera.mover(elegidos, reglas: reglas) }.value
            quitar(r.movidos.map(\.original))
            ultimaLimpieza = r
            medirPapelera()
            cargarRecientes()
        }
    }

    /// Finder sí puede mover apps del sistema: pide la contraseña de la Mac. Queda anotado como lo demás.
    func moverConFinder(_ pendientes: [Pendiente]) {
        let urls = pendientes.map(\.url)
        let bytes = Dictionary(pendientes.map { ($0.url, $0.bytes) }, uniquingKeysWith: max)
        NSWorkspace.shared.recycle(urls) { movidas, error in
            Task { @MainActor in
                var r = ResultadoLimpieza()
                r.movidos = movidas.map { Movimiento(original: $0.key.path, enPapelera: $0.value.path, bytes: bytes[$0.key] ?? 0, fecha: Date()) }
                if let error, movidas.count < urls.count { r.errores.append(error.localizedDescription) }
                do { try Papelera.anotarMovidos(r.movidos) } catch {
                    r.errores.append("Couldn't save the history: \(error.localizedDescription)")
                }
                self.quitar(r.movidos.map(\.original))
                self.ultimaLimpieza = r
                self.medirPapelera()
                self.cargarRecientes()
            }
        }
    }

    /// Quita de la lista lo que ya se movió (y lo que iba dentro), con su selección.
    private func quitar(_ rutas: [String]) {
        hallazgos.removeAll { h in rutas.contains { h.url.path == $0 || h.url.path.hasPrefix($0 + "/") } }
        seleccion = seleccion.intersection(hallazgos.map(\.id))
    }

    // MARK: - Guardar

    var carpetaGuardar: URL { Guardar.carpetaPorDefecto(inicio: inicio) }

    /// Lo marcado que se puede guardar: todo menos apps y basura del sistema.
    var paraGuardar: [Hallazgo] { seleccionados.filter(Guardar.sePuedeGuardar) }

    func guardar(_ lista: [Hallazgo]) {
        let carpeta = carpetaGuardar
        let reglas = reglas
        Task {
            let r = await Task.detached { Guardar.mover(lista, a: carpeta, reglas: reglas) }.value
            // Se protege desde el primer uso, para que lo guardado no vuelva a salir en el escaneo.
            if FileManager.default.fileExists(atPath: carpeta.path) { Ajustes.proteger(carpeta) }
            quitar(r.guardados)
            ultimoGuardado = r
        }
    }

    /// Apps de la lista que están abiertas ahora mismo.
    func abiertas(_ lista: [Hallazgo]) -> [NSRunningApplication] {
        let rutas = Set(lista.filter { $0.categoria == .aplicaciones }.map { $0.url.standardizedFileURL.path })
        return NSWorkspace.shared.runningApplications.filter { app in
            app.bundleURL.map { rutas.contains($0.standardizedFileURL.path) } ?? false
        }
    }

    func cargarRecientes() {
        Task {
            let r = await Task.detached { Result { try Papelera.restaurables() } }.value
            switch r {
            case .success(let lista): recientes = lista
            case .failure(let error): errores.append("Couldn't read the history: \(error.localizedDescription)")
            }
        }
    }

    /// Devuelve los errores, uno por elemento que no se pudo restaurar.
    func restaurar(_ movimientos: [Movimiento]) async -> [String] {
        let errores = await Task.detached { () -> [String] in
            movimientos.compactMap { m in
                do { try Papelera.restaurar(m); return nil } catch { return "\(m.nombre): \(error.localizedDescription)" }
            }
        }.value
        cargarRecientes()
        medirPapelera()
        return errores
    }

    func medirPapelera() {
        let papelera = inicio.appendingPathComponent(".Trash")
        Task {
            let bytes = await Task.detached { () -> Int64? in
                guard (try? FileManager.default.contentsOfDirectory(atPath: papelera.path)) != nil else { return nil }
                var errores: [String] = []
                return Escaner.ocupado(papelera, errores: &errores)
            }.value
            papeleraBytes = bytes
        }
    }

    /// La única acción definitiva de la app. Antes se le pedía a Finder, pero Finder falla completo
    /// con un error genérico si un solo elemento no se puede borrar.
    func vaciarPapelera() async -> ResultadoVaciado {
        let papelera = inicio.appendingPathComponent(".Trash")
        let r = await Task.detached { Papelera.vaciar(papelera) }.value
        medirPapelera()
        cargarRecientes()
        return r
    }
}

func tamano(_ bytes: Int64) -> String {
    textoTamano(bytes)
}
