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
    static let claveFL = "protegerFL"

    static var protegerFL: Bool { UserDefaults.standard.bool(forKey: claveFL) }

    static var configuracion: Configuracion {
        let d = UserDefaults.standard
        var c = Configuracion()
        if d.object(forKey: claveUmbral) != nil { c.umbralGrandes = Int64(d.integer(forKey: claveUmbral)) * 1_000_000 }
        if d.object(forKey: claveViejos) != nil { c.mesesViejos = d.integer(forKey: claveViejos) }
        if d.object(forKey: claveDormidos) != nil { c.mesesDormidos = d.integer(forKey: claveDormidos) }
        return c
    }

    /// Agrega una ruta a las carpetas protegidas, si no estaba.
    static func proteger(_ url: URL) {
        let d = UserDefaults.standard
        var lista = (d.string(forKey: claveProtegidas) ?? "").split(separator: "\n").map(String.init)
        guard !lista.contains(url.path) else { return }
        lista.append(url.path)
        d.set(lista.joined(separator: "\n"), forKey: claveProtegidas)
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
    @AppStorage(Ajustes.claveFL) private var protegerFL = false

    var body: some View {
        Form {
            Section("Criteria") {
                Stepper("Large file from \(tamano(Int64(umbralMB) * 1_000_000))", value: $umbralMB, in: 100...20_000, step: 100)
                Stepper("Old after \(mesesViejos) months unopened", value: $mesesViejos, in: 3...120)
                Stepper("Old folder after \(mesesDormidos) months unchanged", value: $mesesDormidos, in: 6...120)
            }
            Section {
                ForEach(Reglas.intocablesFijos, id: \.self) { ruta in
                    Label("~/" + ruta, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                Toggle(isOn: $protegerFL) {
                    Text("Protect FL Studio")
                    Text(".flp projects, the samples they use, and the FL Studio apps.")
                }
                if protegerFL {
                    ForEach(estado.enUsoFL, id: \.self) { url in
                        Label(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "waveform")
                            .foregroundStyle(.secondary)
                            .help("FL Studio uses samples from here")
                    }
                }
                CarpetasPropias()
            } header: {
                Text("Protected folders")
            } footer: {
                Text("iClear never scans or moves anything inside these folders. With FL Studio protected, the folders with a wave are detected from your projects and its sound browser.")
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
                Button("Remove", role: .destructive) {
                    protegidas = lista.filter { $0 != ruta }.joined(separator: "\n")
                }
                .buttonStyle(.borderless)
            }
        }
        Button("Add Folder or File…", action: agregar)
    }

    private func agregar() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Protect"
        guard panel.runModal() == .OK else { return }
        let nuevas = panel.urls.map(\.path).filter { !lista.contains($0) }
        protegidas = (lista + nuevas).joined(separator: "\n")
    }
}
