// Mirrors PieChart.swift from the app target; the widget extension cannot
// link executable target source, so we duplicate the SwiftUI pie here.
// Keep in sync with ClaudeMeterApp/PieChart.swift.

import SwiftUI

struct FilledPie: View {
    let fraction: Double
    var fillColor: Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.2))
            PieSlice(fraction: max(0.001, min(1.0, fraction))).fill(fillColor)
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
        }
    }
}

struct PieSlice: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        p.move(to: center)
        p.addArc(center: center,
                 radius: radius,
                 startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + fraction * 360),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}
