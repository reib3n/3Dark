import SwiftUI

extension View {
    /// Liquid Glass background on macOS 26+ (new Apple design language),
    /// material fallback before that — same visual intent, older look.
    @ViewBuilder
    func glassBackground(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }
}
