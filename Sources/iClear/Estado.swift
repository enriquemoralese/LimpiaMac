import AppKit
import iClearNucleo
import Observation

enum Seccion: Hashable {
    case resumen
    case categoria(Categoria)
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
    var escaneando = false
    var escaneado = false
    var progreso = ""
    var papeleraBytes: Int64?
    var ultimaLimpieza: ResultadoLimpieza?
    var accesoCompleto: Bool?

    private var tarea: Task<Void, Never>?
    let inicio = FileManager.default.homeDirectoryForCurrentUser

    /// Carpetas de samples que usa FL Studio. Se recalculan en cada escaneo y quedan protegidas.
    var enUsoFL: [URL] = []

    var reglas: Reglas { Reglas(inicio: inicio, extras: Ajustes.protegidas + enUsoFL) }

    init() {
        errores = Ajustes.migrarNombreAnterior()
        accesoCompleto = Papelera.tieneAccesoCompleto(inicio: inicio)
        medirPapelera()
        let inicio = inicio
        Task {
            enUsoFL = await Task.detached { FLStudio.carpetasEnUso(inicio: inicio).sorted { $0.path < $1.path } }.value
        }
    }

    // MARK: - Escaneo

    func escanear() {
        tarea?.cancel()
        escaneando = true
        progreso = "Preparando"
        errores = []
        let inicio = inicio
        let extras = Ajustes.protegidas
        let config = Ajustes.configuracion
        tarea = Task {
            let trabajo = Task.detached(priority: .userInitiated) { () throws -> (ResultadoEscaneo, [URL]) in
                let avisar: @Sendable (String) -> Void = { texto in Task { @MainActor in self.progreso = texto } }
                avisar("Buscando los samples que usa FL Studio")
                let fl = FLStudio.carpetasEnUso(inicio: inicio).sorted { $0.path < $1.path }
                let escaner = Escaner(reglas: Reglas(inicio: inicio, extras: extras + fl), config: config)
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
                errores = ["El escaneo se detuvo: \(error.localizedDescription)"]
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
            let movidas = r.movidos.map(\.original)
            hallazgos.removeAll { h in movidas.contains { h.url.path == $0 || h.url.path.hasPrefix($0 + "/") } }
            seleccion = seleccion.intersection(hallazgos.map(\.id))
            ultimaLimpieza = r
            medirPapelera()
        }
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
        return r
    }
}

func tamano(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
