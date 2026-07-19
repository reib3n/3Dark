import SwiftUI

extension View {
    /// Liquid-Glass-Hintergrund ab macOS 26 (neue Apple-Designsprache),
    /// davor Material-Fallback — gleiche Optik-Absicht, ältere Umsetzung.
    @ViewBuilder
    func glassBackground(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }
}
