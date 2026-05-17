import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassPanel() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        #else
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        #endif
    }

    @ViewBuilder
    func liquidGlassBar() -> some View {
        clearLiquidGlass(Capsule(), strokeOpacity: 0.22)
    }

    @ViewBuilder
    func liquidGlassControl() -> some View {
        clearLiquidGlass(Circle(), strokeOpacity: 0.18)
    }

    @ViewBuilder
    func liquidGlassChip() -> some View {
        clearLiquidGlass(Capsule(), strokeOpacity: 0.16)
    }

    @ViewBuilder
    func liquidGlassMenuPill() -> some View {
        clearLiquidGlass(Capsule(), strokeOpacity: 0.24)
    }

    @ViewBuilder
    private func clearLiquidGlass<S: InsettableShape>(_ shape: S, strokeOpacity: Double) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.identity, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(strokeOpacity), lineWidth: 1))
        } else {
            self.clearGlassFallback(shape, strokeOpacity: strokeOpacity)
        }
        #else
        self.clearGlassFallback(shape, strokeOpacity: strokeOpacity)
        #endif
    }

    private func clearGlassFallback<S: InsettableShape>(_ shape: S, strokeOpacity: Double) -> some View {
        self
            .background(.clear, in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(strokeOpacity), lineWidth: 1))
    }
}
