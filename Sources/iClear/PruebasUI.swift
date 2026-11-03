import AppKit
import AVKit
import iClearNucleo

/// Pruebas de la interfaz real: se activan con ICLEAR_PRUEBAS_UI=1 (ver Scripts/pruebas_ui.sh).
/// Escanean la carpeta real en modo de solo lectura y manejan la ventana desde el código.
/// Nunca mueven ni borran archivos ni guardan ajustes. Cada resultado sale en una línea
/// "PRUEBA OK|FALLA <nombre>: <detalle>" y la app termina con 0 si todo pasó.
@MainActor enum PruebasUI {
    static var activas: Bool { ProcessInfo.processInfo.environment["ICLEAR_PRUEBAS_UI"] == "1" }

    /// Antes de crear la ventana: esconde la bienvenida sin guardar nada (dominio de registro, no persistente).
    static func preparar() {
        guard activas else { return }
        UserDefaults.standard.register(defaults: [Ajustes.claveBienvenida: true])
    }

    private static var fallas = 0

    static func correr(_ estado: Estado) async {
        guard activas else { return }
        let inicio = Date()
        resultado(true, "inicio", hora(inicio))
        estado.escanear()
        while !estado.escaneado || estado.escaneando {
            try? await Task.sleep(for: .milliseconds(500))
            if Date().timeIntervalSince(inicio) > 900 { resultado(false, "escaneo", "no terminó en 15 minutos"); salir() }
        }
        resultado(true, "escaneo", "terminó \(hora(Date())), \(Int(Date().timeIntervalSince(inicio))) s, \(estado.hallazgos.count) hallazgos, \(estado.errores.count) rutas sin leer")

        // ICLEAR_PRUEBAS_SOLO=reproductor corre solo esa prueba (para depurarla sin esperar las demás).
        if ProcessInfo.processInfo.environment["ICLEAR_PRUEBAS_SOLO"] == "reproductor" {
            await reproductor(estado)
            salir()
        }

        let reglas = estado.reglas
        let dentro = estado.hallazgos.flatMap { [$0.url] + $0.extras }.filter(reglas.esIntocable)
        resultado(dentro.isEmpty, "protegidas", dentro.isEmpty ? "ningún hallazgo en carpetas protegidas"
                  : dentro.prefix(3).map { $0.path }.joined(separator: ", "))

        for c in Categoria.allCases {
            estado.seccion = .categoria(c)
            try? await Task.sleep(for: .seconds(2))
            let esperadas = estado.hallazgos(en: c).count
            let filas = tablaPrincipal()?.numberOfRows ?? 0
            resultado(esperadas == 0 || filas == esperadas, "tabla \(c.rawValue)", "\(filas) filas, \(esperadas) hallazgos")
        }
        for s in [Seccion.recientes, .papelera, .resumen] {
            estado.seccion = s
            try? await Task.sleep(for: .seconds(1))
        }
        resultado(true, "secciones", "todas abrieron sin tronar")

        await barraLateral(estado)
        await casillaEncabezado(estado)
        await reproductor(estado)
        salir()
    }

    // MARK: - Escenarios

    static func barraLateral(_ estado: Estado) async {
        guard let c = estado.hallazgos.first?.categoria else { return }
        for pantallaCompleta in [false, true] {
            if pantallaCompleta { ventana()?.toggleFullScreen(nil); try? await Task.sleep(for: .seconds(3)) }
            estado.seccion = .categoria(c)
            estado.filas = []
            try? await Task.sleep(for: .seconds(2))
            let sin = filaLateral()
            estado.filas = [estado.hallazgos(en: c)[0].id]
            try? await Task.sleep(for: .seconds(2))
            let con = filaLateral()
            // macOS puede abrir la app ya en pantalla completa: la etiqueta dice el estado real.
            let nombre = ventana()?.styleMask.contains(.fullScreen) == true ? "barra lateral (pantalla completa)" : "barra lateral (ventana)"
            resultado(sin != nil && sin == con, nombre, "primera fila en y=\(sin.map { Int($0) } ?? -1) sin selección, y=\(con.map { Int($0) } ?? -1) con selección")
        }
        ventana()?.toggleFullScreen(nil)
        try? await Task.sleep(for: .seconds(3))
        estado.filas = []
    }

    static func casillaEncabezado(_ estado: Estado) async {
        guard let c = Categoria.allCases.first(where: { estado.hallazgos(en: $0).count > 1 }) else { return }
        let antes = estado.seleccion
        defer { estado.seleccion = antes }
        estado.seccion = .categoria(c)
        try? await Task.sleep(for: .seconds(2))
        guard let w = ventana(), let tabla = tablaPrincipal()?.enclosingScrollView, let contenido = w.contentView else {
            resultado(false, "casilla encabezado", "no se encontró la tabla"); return
        }
        let deFilas = vistas(NSButton.self, en: tabla)
        guard let cabecera = vistas(NSButton.self, en: contenido).first(where: { $0.allowsMixedState && !deFilas.contains($0) }),
              let fila = deFilas.first else {
            resultado(false, "casilla encabezado", "no se encontró la casilla"); return
        }
        // El botón nativo mide 22 pt con 2 pt de margen alrededor de la casilla de 18 pt.
        let xCabecera = cabecera.convert(cabecera.bounds, to: nil).minX + 2
        let xFila = fila.convert(fila.bounds, to: nil).minX
        resultado(abs(xCabecera - xFila) < 1, "casilla alineada", "encabezado x=\(Int(xCabecera)), filas x=\(Int(xFila))")

        let lista = estado.hallazgos(en: c)
        estado.marcar(lista.map(\.id), false)
        try? await Task.sleep(for: .milliseconds(500))
        cabecera.performClick(nil)
        try? await Task.sleep(for: .milliseconds(500))
        let marcadas = lista.filter { estado.seleccion.contains($0.id) }.count
        let marcables = lista.filter { !$0.sensible }.count
        cabecera.performClick(nil)
        try? await Task.sleep(for: .milliseconds(500))
        let despues = lista.filter { estado.seleccion.contains($0.id) }.count
        estado.marcar([lista[0].id], true)
        try? await Task.sleep(for: .milliseconds(500))
        resultado(marcadas == marcables && despues == 0 && cabecera.state == .mixed, "casilla marcar todo",
                  "marcó \(marcadas) de \(marcables), luego \(despues), con una queda en guion: \(cabecera.state == .mixed)")
    }

    static func reproductor(_ estado: Estado) async {
        let videos = estado.hallazgos.filter { Reproductor.puedeReproducir($0.url) && $0.url.pathExtension.lowercased() != "mp3" }
        guard let video = videos.first, let w = ventana(), let contenido = w.contentView else {
            resultado(true, "reproductor", "sin videos que probar"); return
        }
        // Los clics simulados solo llegan si la ventana está al frente.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        for _ in 0..<20 where !NSApp.isActive { try? await Task.sleep(for: .milliseconds(250)) }
        // El primer clic sobre una ventana que no es la clave solo la activa; no llega al botón.
        for _ in 0..<8 where !w.isKeyWindow {
            w.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard NSApp.isActive && w.isKeyWindow else {
            // macOS 14 no deja que la app se ponga al frente sola si otra ventana lo tomó durante el escaneo.
            omitida("reproductor", "la ventana no estaba al frente; vuelve a correr sin usar la Mac mientras escanea")
            return
        }
        estado.seccion = .categoria(video.categoria)
        try? await Task.sleep(for: .seconds(2))
        estado.filas = [video.id]
        try? await Task.sleep(for: .seconds(3))
        let tabla = tablaPrincipal()?.enclosingScrollView.map { $0.convert($0.bounds, to: nil) } ?? .zero
        let x = tabla.maxX + (contenido.bounds.width - tabla.maxX) / 2
        var y = contenido.bounds.height * 0.8
        var reproductores: [AVPlayerView] = []
        while y > contenido.bounds.height * 0.25 && reproductores.isEmpty {
            guard NSApp.isActive && w.isKeyWindow else {
                omitida("reproductor", "otra app tomó el frente durante la prueba; vuelve a correrla sin usar la Mac")
                estado.filas = []
                return
            }
            clic(en: NSPoint(x: x, y: y), w)
            try? await Task.sleep(for: .milliseconds(700))
            reproductores = vistas(AVPlayerView.self, en: contenido)
            y -= 40
        }
        try? await Task.sleep(for: .seconds(1.5))
        let jugando = reproductores.first?.player?.timeControlStatus == .playing
        let datos = "pantalla completa: \(w.styleMask.contains(.fullScreen)), ventana clave: \(w.isKeyWindow), " +
            "clic en x=\(Int(x)), contenido \(Int(contenido.bounds.width))x\(Int(contenido.bounds.height)), tabla hasta x=\(Int(tabla.maxX))"
        resultado(jugando, "reproductor", "\(video.nombre): \(jugando ? "reproduciendo" : "no arrancó") (\(datos))")
        estado.filas = []
    }

    // MARK: - Utilidades

    static func resultado(_ ok: Bool, _ nombre: String, _ detalle: String) {
        if !ok { fallas += 1 }
        FileHandle.standardError.write(Data("PRUEBA \(ok ? "OK" : "FALLA") \(nombre): \(detalle)\n".utf8))
    }

    static func omitida(_ nombre: String, _ motivo: String) {
        FileHandle.standardError.write(Data("PRUEBA OMITIDA \(nombre): \(motivo)\n".utf8))
    }

    static func hora(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))
    }

    static func salir() -> Never {
        FileHandle.standardError.write(Data("PRUEBA FIN fallas=\(fallas)\n".utf8))
        exit(fallas == 0 ? 0 : 1)
    }

    static func ventana() -> NSWindow? { NSApp.windows.first { $0.canBecomeMain && $0.isVisible } }

    static func vistas<T: NSView>(_ tipo: T.Type, en vista: NSView) -> [T] {
        ([vista as? T].compactMap { $0 }) + vista.subviews.flatMap { vistas(tipo, en: $0) }
    }

    /// La tabla de hallazgos es la única con más de dos columnas (la barra lateral tiene una).
    static func tablaPrincipal() -> NSTableView? {
        guard let c = ventana()?.contentView else { return nil }
        return vistas(NSTableView.self, en: c).first { $0.numberOfColumns > 2 && !$0.isHiddenOrHasHiddenAncestor }
    }

    static func filaLateral() -> CGFloat? {
        guard let c = ventana()?.contentView,
              let lateral = vistas(NSTableView.self, en: c).first(where: { $0.numberOfColumns == 1 }),
              lateral.numberOfRows > 0 else { return nil }
        return lateral.convert(lateral.rect(ofRow: 0), to: nil).minY
    }

    static func clic(en punto: NSPoint, _ w: NSWindow) {
        for tipo in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: tipo, location: punto, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                w.sendEvent(e)
            }
        }
    }
}
