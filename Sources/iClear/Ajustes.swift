import AppKit
import iClearNucleo
import SwiftUI

/// Preferencias guardadas en UserDefaults. Las vistas usan @AppStorage con las mismas claves.
enum Ajustes {
    static let claveUmbral = "umbralMB"
    static let claveViejos = "mesesViejos"
    static let claveDormidos = "mesesDormidos"
    static let claveProtegidas = "protegidas"
    static let claveBienvenida = "bienvenidaVista"

    static var configuracion: Configuracion {
        let d = UserDefaults.standard
        var c = Configuracion()
        if d.object(forKey: claveUmbral) != nil { c.umbralGrandes = Int64(d.integer(forKey: claveUmbral)) * 1_000_000 }
        if d.object(forKey: claveViejos) != nil { c.mesesViejos = d.integer(forKey: claveViejos) }
        if d.object(forKey: claveDormidos) != nil { c.mesesDormidos = d.integer(forKey: claveDormidos) }
        return c
    }

    /// La app se llamaba LimpiaMac (identificador local.enrique.LimpiaMac). Una sola vez copia
    /// sus ajustes y mueve su historial al nombre nuevo. Devuelve los errores para mostrarlos.
    static func migrarNombreAnterior() -> [String] {
        let d = UserDefaults.standard
        let marca = "migradoDeLimpiaMac"
        guard !d.bool(forKey: marca) else { return [] }
        var errores: [String] = []
        if let anterior = UserDefaults(suiteName: "local.enrique.LimpiaMac") {
            for clave in [claveUmbral, claveViejos, claveDormidos, claveProtegidas] where d.object(forKey: clave) == nil {
                if let valor = anterior.object(forKey: clave) { d.set(valor, forKey: clave) }
            }
        }
        let soporte = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let viejo = soporte.appendingPathComponent("LimpiaMac/historial.json")
        let nuevo = Papelera.historialPorDefecto
        if FileManager.default.fileExists(atPath: viejo.path) && !FileManager.default.fileExists(atPath: nuevo.path) {
            do {
                try FileManager.default.createDirectory(at: nuevo.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: viejo, to: nuevo)
            } catch {
                errores.append("No se pudo mover el historial de LimpiaMac: \(error.localizedDescription)")
            }
        }
        d.set(true, forKey: marca)
        return errores
    }

    static var protegidas: [URL] {
        (UserDefaults.standard.string(forKey: claveProtegidas) ?? "")
            .split(separator: "\n").map { URL(fileURLWithPath: String($0), isDirectory: true) }
    }
}

@MainActor struct AjustesView: View {
    @AppStorage(Ajustes.claveUmbral) private var umbralMB = 500
    @AppStorage(Ajustes.claveViejos) private var mesesViejos = 12
    @AppStorage(Ajustes.claveDormidos) private var mesesDormidos = 18
    @Environment(Estado.self) private var estado

    var body: some View {
        Form {
            Section("Criterios") {
                Stepper("Archivo grande desde \(tamano(Int64(umbralMB) * 1_000_000))", value: $umbralMB, in: 100...20_000, step: 100)
                Stepper("Viejo después de \(mesesViejos) meses sin abrir", value: $mesesViejos, in: 3...120)
                Stepper("Proyecto dormido después de \(mesesDormidos) meses sin cambios", value: $mesesDormidos, in: 6...120)
            }
            Section {
                ForEach(Reglas.intocablesFijos, id: \.self) { ruta in
                    Label("~/" + ruta, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                Label("Proyectos .flp y apps de FL Studio", systemImage: "lock.fill").foregroundStyle(.secondary)
                ForEach(estado.enUsoFL, id: \.self) { url in
                    Label(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "waveform")
                        .foregroundStyle(.secondary)
                        .help("FL Studio usa samples de aquí")
                }
                CarpetasPropias()
            } header: {
                Text("Carpetas protegidas")
            } footer: {
                Text("La app nunca revisa ni mueve nada dentro de estas carpetas. Las que tienen onda las detectó en tus proyectos de FL Studio y en su navegador de sonidos.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}

/// Las carpetas y archivos que cada quien protege. Se usa en Ajustes y en la bienvenida.
@MainActor struct CarpetasPropias: View {
    @AppStorage(Ajustes.claveProtegidas) private var protegidas = ""

    private var lista: [String] { protegidas.split(separator: "\n").map(String.init) }

    var body: some View {
        ForEach(lista, id: \.self) { ruta in
            HStack {
                Label(ruta.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "lock")
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Quitar", role: .destructive) {
                    protegidas = lista.filter { $0 != ruta }.joined(separator: "\n")
                }
                .buttonStyle(.borderless)
            }
        }
        Button("Agregar carpeta o archivo…", action: agregar)
    }

    private func agregar() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Proteger"
        guard panel.runModal() == .OK else { return }
        let nuevas = panel.urls.map(\.path).filter { !lista.contains($0) }
        protegidas = (lista + nuevas).joined(separator: "\n")
    }
}
