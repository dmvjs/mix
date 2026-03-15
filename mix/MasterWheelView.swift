import SwiftUI

/// Small passive indicator: rotating tick shows position within the current loop,
/// four dots around the rim show which of the 4 body loops is active.
struct MasterWheelView: View {
    let angle:     Double   // 0 ..< 2π, position within current loop
    let loopIndex: Int      // 0-3, which body loop

    var size: CGFloat = 64

    var body: some View {
        ZStack {
            // Ring
            Circle()
                .stroke(Color(white: 0.25), lineWidth: 0.5)

            // 4 loop-index dots at N/E/S/W
            ForEach(0..<4, id: \.self) { i in
                let a = Double(i) * .pi / 2   // 0, π/2, π, 3π/2
                Circle()
                    .fill(i == loopIndex % 4 ? Color.white : Color(white: 0.3))
                    .frame(width: 4, height: 4)
                    .offset(x: CGFloat(sin(a)) * (size / 2 - 6),
                            y: -CGFloat(cos(a)) * (size / 2 - 6))
            }

            // Position tick
            Capsule()
                .fill(Color.white)
                .frame(width: 2, height: size * 0.18)
                .offset(y: -(size / 2 - size * 0.09))
                .rotationEffect(.radians(angle))
        }
        .frame(width: size, height: size)
    }
}
