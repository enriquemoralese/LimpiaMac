// Dibuja el ícono de la app (1024 px) siguiendo la retícula de íconos de macOS.
// Uso: swift Recursos/generar_icono.swift <salida.png>
import AppKit

let lado: CGFloat = 1024
let salida = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icono.png"

let imagen = NSImage(size: NSSize(width: lado, height: lado))
imagen.lockFocus()

// Cuadro de 824 px centrado, como los íconos de Apple, con sombra suave.
let cuadro = NSRect(x: 100, y: 100, width: 824, height: 824)
let forma = NSBezierPath(roundedRect: cuadro, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let sombra = NSShadow()
sombra.shadowColor = NSColor.black.withAlphaComponent(0.28)
sombra.shadowBlurRadius = 24
sombra.shadowOffset = NSSize(width: 0, height: -10)
sombra.set()
NSColor.white.setFill()
forma.fill()
NSGraphicsContext.restoreGraphicsState()

let degradado = NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.74, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.04, green: 0.42, blue: 0.93, alpha: 1),
])!
degradado.draw(in: forma, angle: -90)

// Brillo sutil en la mitad superior.
NSGraphicsContext.saveGraphicsState()
forma.addClip()
let brillo = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
brillo.draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Basurero blanco de SF Symbols, centrado ópticamente.
let configuracion = NSImage.SymbolConfiguration(pointSize: 420, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let simbolo = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuracion) else {
    fatalError("No se encontró el símbolo trash.fill")
}
let tam = simbolo.size
NSGraphicsContext.saveGraphicsState()
let sombraSimbolo = NSShadow()
sombraSimbolo.shadowColor = NSColor(srgbRed: 0.0, green: 0.2, blue: 0.5, alpha: 0.35)
sombraSimbolo.shadowBlurRadius = 18
sombraSimbolo.shadowOffset = NSSize(width: 0, height: -8)
sombraSimbolo.set()
simbolo.draw(in: NSRect(x: (lado - tam.width) / 2, y: (lado - tam.height) / 2 - 6, width: tam.width, height: tam.height))
NSGraphicsContext.restoreGraphicsState()

imagen.unlockFocus()

guard let tiff = imagen.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("No se pudo generar el PNG")
}
try png.write(to: URL(fileURLWithPath: salida))
print("Ícono: \(salida) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
