import AppKit
import LimpiaNucleo
import SwiftUI

/// Preferencias guardadas en UserDefaults. Las vistas usan @AppStorage con las mismas claves.
enum Ajustes {
    static let claveUmbral = "umbralMB"
    static let claveViejos = "mesesViejos"
    static let claveDormidos = "mesesDormidos"
    static let claveProtegidas = "protegidas"

    static var configuracion: Configuracion {
        let d = UserDefaults.standard
        var c = Configuracion()
        if d.object(forKey: claveUmbral) != nil { c.umbralGrandes = Int64(d.integer(forKey: claveUmbral)) * 1_000_000 }
        if d.object(forKey: claveViejos) != nil { c.mesesViejos = d.integer(forKey: claveViejos) }
        if d.object(forKey: claveDormidos) != nil { c.mesesDormidos = d.integer(forKey: claveDormidos) }
        return c
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
    @AppStorage(Ajustes.claveProtegidas) private var protegidas = ""
    @Environment(Estado.self) private var estado

    private var lista: [String] { protegidas.split(separator: "\n").map(String.init) }

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
                Label("Carpetas con proyectos .flp, FL Studio y beats", systemImage: "lock.fill").foregroundStyle(.secondary)
                Label("Carpetas Quaio y LexColab", systemImage: "lock.fill").foregroundStyle(.secondary)
                ForEach(estado.enUsoFL, id: \.self) { url in
                    Label(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "waveform")
                        .foregroundStyle(.secondary)
                        .help("FL Studio usa samples de aquí")
                }
                ForEach(lista, id: \.self) { ruta in
                    HStack {
                        Label(ruta.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "lock")
                        Spacer()
                        Button("Quitar", role: .destructive) {
                            protegidas = lista.filter { $0 != ruta }.joined(separator: "\n")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Agregar carpeta…", action: agregar)
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

    private func agregar() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Proteger"
        guard panel.runModal() == .OK else { return }
        let nuevas = panel.urls.map(\.path).filter { !lista.contains($0) }
        protegidas = (lista + nuevas).joined(separator: "\n")
    }
}
