import AppKit
import SwiftUI

/// Fondo translúcido que deja ver, borroso, lo que hay detrás de la ventana (como el perfil Pro de Terminal).
/// macOS 14 no tiene Liquid Glass; esto usa el mismo efecto que la barra lateral del sistema.
struct Vidrio: NSViewRepresentable {
    @Environment(\.colorScheme) private var esquema

    /// En modo oscuro, el material HUD deja pasar más del fondo; en claro se ve gris, así que se usa el de popover.
    private var material: NSVisualEffectView.Material { esquema == .dark ? .hudWindow : .popover }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let vista = NSVisualEffectView()
        vista.material = material
        vista.blendingMode = .behindWindow
        // Siempre activo: sin esto, el vidrio se vuelve gris opaco cuando la ventana no está al frente.
        vista.state = .active
        return vista
    }

    func updateNSView(_ vista: NSVisualEffectView, context: Context) {
        vista.material = material
    }
}

extension View {
    /// Tarjeta de vidrio: material translúcido con un borde fino de luz.
    func tarjetaDeVidrio(radio: CGFloat, resaltada: Bool = false) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radio))
            .overlay(RoundedRectangle(cornerRadius: radio).strokeBorder(.white.opacity(resaltada ? 0.22 : 0.09)))
    }
}
