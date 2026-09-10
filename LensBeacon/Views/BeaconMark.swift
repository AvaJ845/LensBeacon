import SwiftUI

/// The LensBeacon mark — two opposing arcs around a single optical centre, the same
/// geometry as the app icon (`Icon_Source/LensBeacon_Master_1024.svg`). Drawn as a
/// vector so it stays crisp at any size and ties every screen back to the icon.
///
/// It carries no glasses, shield, warning triangle, or Bluetooth glyph — the brand
/// spec is explicit about that.
struct BeaconMark: View {
    /// 0 = still. Drives a gentle breath of the arcs (opacity + a hair of scale).
    var breath: Double = 0
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 1024   // master viewBox is 1024

            ZStack {
                arcs(k: k)
                    .stroke(tint, style: StrokeStyle(lineWidth: 78 * k, lineCap: .round))
                    .opacity(0.9 - 0.15 * breath)
                    .scaleEffect(1 + 0.012 * breath)

                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 300 * k, height: 300 * k)
                Circle()
                    .strokeBorder(tint, lineWidth: 14 * k)
                    .frame(width: 250 * k, height: 250 * k)
                Circle()
                    .fill(tint)
                    .frame(width: 70 * k, height: 70 * k)
                    .opacity(0.9)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The two C-curves from the master, scaled by `k`.
    private func arcs(k: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        var path = Path()
        // upper
        path.move(to: p(145, 478))
        path.addCurve(to: p(512, 194), control1: p(275, 270), control2: p(430, 194))
        path.addCurve(to: p(879, 478), control1: p(594, 194), control2: p(749, 270))
        // lower
        path.move(to: p(145, 546))
        path.addCurve(to: p(512, 830), control1: p(275, 754), control2: p(430, 830))
        path.addCurve(to: p(879, 546), control1: p(594, 830), control2: p(749, 754))
        return path
    }
}

/// The calm "the beacon is listening" moment for the Dashboard: the mark with two
/// slow rings expanding outward. Static under Reduce Motion. Never a radar sweep,
/// never red — presence, not alarm.
struct ScanField: View {
    var active: Bool
    var tint: Color = Palette.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expand = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .strokeBorder(tint.opacity(expand ? 0 : 0.28), lineWidth: 1.5)
                        .scaleEffect(expand ? 1.0 : 0.5)
                        .animation(
                            .easeOut(duration: 5).repeatForever(autoreverses: false)
                                .delay(Double(i) * 2.5),
                            value: expand)
                }
            } else {
                Circle().strokeBorder(tint.opacity(0.14), lineWidth: 1.5).scaleEffect(0.82)
            }

            BeaconMark(breath: breathe ? 1 : 0, tint: tint)
                .padding(20)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.2).repeatForever(autoreverses: true),
                           value: breathe)
        }
        .frame(width: 112, height: 112)
        .onAppear { expand = active; breathe = active }
        .onDisappear { expand = false; breathe = false }   // stop the loop off-screen
        .onChange(of: active) { _, on in expand = on; breathe = on }
        .accessibilityHidden(true)
    }
}
