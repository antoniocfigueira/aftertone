import SwiftUI

extension View {
    @ViewBuilder func glassPanel(_ radius: CGFloat = 24) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.09)) }
        }
    }
}
let sea = Color(red: 0.27, green: 0.88, blue: 0.72)
let ink = Color(red: 0.045, green: 0.082, blue: 0.105)

func stamp(_ seconds: Double) -> String {
    let s = max(0, Int(seconds)); return String(format: "%d:%02d", s / 60, s % 60)
}
struct Ribbon: View {
    var animated: Bool
    var seed = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/24, paused: !animated || reduce)) { timeline in
            let phase = animated && !reduce ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) * .pi / 30 : 0
            Canvas { context, size in
                let w = size.width, h = size.height, scale = min(w, h)
                for ring in 0..<80 {
                    let u = Double(ring)/80 * 2 * .pi
                    var path = Path()
                    for j in 0...112 {
                        let t = Double(j)/112 * 2 * .pi
                        let twist = 2*t + u + seed
                        let r = 0.31 + 0.105*cos(twist)
                        let x = r*cos(t), y = r*sin(t), z = 0.13*sin(twist) + 0.08*sin(t*2+phase)
                        let xx = x*0.92 - y*0.39
                        let yy = x*0.32 + y*0.57 - z*1.12
                        let p = CGPoint(x: w/2 + scale*xx, y: h/2 + scale*yy)
                        if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .linearGradient(Gradient(colors: [
                        .cyan.opacity(0.32), sea.opacity(0.88), .white.opacity(0.75), .purple.opacity(0.66)
                    ]), startPoint: CGPoint(x: 0, y: h), endPoint: CGPoint(x: w, y: 0)), lineWidth: max(0.55, scale/460))
                }
            }
        }.accessibilityHidden(true)
    }
}
struct Sleeve: View {
    var cover: String?
    var seed = 0.0
    var playing = false
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.045, green: 0.14, blue: 0.17), ink, Color(red: 0.12, green: 0.08, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Ribbon(animated: playing, seed: seed) }
        }
        .clipped()
        .task(id: cover) {
            image = cover.flatMap { UIImage(contentsOfFile: Library.directory.appendingPathComponent($0).path) }
        }
    }
}
enum Visual: String, CaseIterable { case waveform = "Waveform", scope = "Scope", spectrum = "Spectrum" }
struct AnalyzerView: View {
    var song: Song
    @ObservedObject var meter: Meter
    var kind: Visual
    var body: some View {
        Canvas { g, size in
            let w = size.width, h = size.height
            for line in 0...4 {
                let y = h*CGFloat(line)/4
                var path = Path(); path.move(to: CGPoint(x: 0,y: y)); path.addLine(to: CGPoint(x: w,y: y))
                g.stroke(path, with: .color(.white.opacity(0.1)), lineWidth: 0.6)
            }
            if kind == .scope {
                var path = Path()
                for (i, a) in meter.wave.enumerated() {
                    let p = CGPoint(x: w*CGFloat(i)/127, y: h*(0.5-0.47*CGFloat(a)))
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                g.stroke(path, with: .color(sea), lineWidth: 1.8)
            } else {
                let n = kind == .spectrum ? 64 : min(112, song.overview.count)
                for i in 0..<n {
                    let x = w*CGFloat(i)/CGFloat(n)
                    let a: Float
                    if kind == .spectrum { a = meter.spectrum[i] }
                    else {
                        let lo = i*song.overview.count/n, hi = (i+1)*song.overview.count/n
                        a = song.overview[lo..<hi].max() ?? 0
                    }
                    let height = max(2, h*0.96*CGFloat(min(1,a)))
                    let rect = CGRect(x: x,y: kind == .spectrum ? h-height : (h-height)/2,
                                      width: max(1,w/CGFloat(n)-1),height: height)
                    let played = Double(i)/Double(n) <= meter.seconds/song.seconds
                    g.fill(Path(roundedRect: rect, cornerRadius: 1),
                           with: .color(kind == .spectrum || played ? sea : .white.opacity(0.45)))
                }
            }
        }.accessibilityLabel(kind.rawValue)
    }
}
struct Dial: View {
    @Binding var value: Double
    @State private var origin: Double?
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.18), lineWidth: 4)
            Circle().trim(from: 0, to: value*0.8).stroke(sea,style: StrokeStyle(lineWidth: 4,lineCap: .round))
                .rotationEffect(.degrees(126))
            Circle().fill(LinearGradient(colors: [ink.opacity(0.72),ink],startPoint: .topLeading,endPoint: .bottomTrailing)).padding(7)
            Capsule().fill(sea).frame(width: 3,height: 9).offset(y: -17).rotationEffect(.degrees(-144+288*value))
        }.frame(width: 58,height: 58)
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            let start = origin ?? value; origin = start
            value = min(1,max(0,start-Double(drag.translation.height)/140 + Double(drag.translation.width)/240))
        }.onEnded { _ in origin = nil })
        .accessibilityLabel("Magic amount").accessibilityValue("\(Int(value*100)) percent")
        .accessibilityAdjustableAction { direction in value = min(1,max(0,value+(direction == .increment ? 0.05 : -0.05))) }
    }
}

