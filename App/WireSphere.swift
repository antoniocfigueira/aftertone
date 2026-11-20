import SwiftUI

struct Orb: View {
    var phase = 0.0
    var bass = 0.0
    var brightness = 0.0
    @Environment(\.colorScheme) private var scheme

    private static func vertex(_ lat: Double, _ lon: Double) -> SIMD3<Double> {
        SIMD3(cos(lat)*cos(lon), sin(lat), cos(lat)*sin(lon))
    }
    private static let wires: [[SIMD3<Double>]] = {
        var lines = [[SIMD3<Double>]]()
        for i in 1..<12 {
            let lat = Double(i) * .pi / 12 - .pi/2
            lines.append((0...80).map { vertex(lat, Double($0) * .pi/40) })
        }
        for i in 0..<22 {
            let lon = Double(i) * .pi / 11
            lines.append((0...48).map { vertex(Double($0) * .pi/48 - .pi/2, lon) })
        }
        return lines
    }()
    var body: some View {
        Canvas { context, size in render(context, size: size) }
            .accessibilityHidden(true)
    }
    private func render(_ context: GraphicsContext, size: CGSize) {
        let cx = Double(size.width)/2, cy = Double(size.height)/2
        let radius = min(cx,cy) * (0.81 + 0.065*bass)
        let rotation = phase*0.24+0.35
        let c = cos(rotation), s = sin(rotation)
        var near = Path(), far = Path()
        for wire in Self.wires {
            var previous: CGPoint?
            for v in wire {
                let x = v.x*c - v.z*s
                let z = v.x*s + v.z*c
                let y = 0.96*v.y - 0.28*z
                let depth = 0.28*v.y + 0.96*z
                let wave = 1 + 0.045*bass*sin(5*v.y+phase)*cos(3*x)
                let px = (0.985*x - 0.174*y)*radius*wave + cx
                let py = (0.174*x + 0.985*y)*radius*wave + cy
                let point = CGPoint(x: px,y: py)
                if let previous {
                    if depth >= 0 { near.move(to: previous); near.addLine(to: point) }
                    else { far.move(to: previous); far.addLine(to: point) }
                }
                previous = point
            }
        }
        let cool = scheme == .dark ? StudioStyle.cyan : Color(rgb: 0x186f83)
        let light = scheme == .dark ? Color(rgb: 0xe2fdff) : Color(rgb: 0x263953)
        let top = CGPoint(x: cx-radius,y: cy-radius)
        let bottom = CGPoint(x: cx+radius,y: cy+radius)
        let violet = scheme == .dark ? StudioStyle.lilac : Color(rgb: 0x705683)
        let gradient = Gradient(colors: [light,cool,violet.opacity(0.6+0.4*brightness)])
        let tint = GraphicsContext.Shading.linearGradient(gradient,startPoint: top,endPoint: bottom)
        context.stroke(far,with: .color(cool.opacity(0.12)),lineWidth: 0.55)
        context.stroke(near,with: .color(cool.opacity(0.09)),lineWidth: 2.4)
        context.stroke(near,with: tint,lineWidth: max(0.65,radius/140))
    }
}

