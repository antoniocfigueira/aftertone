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
let sea = Color(red: 1.0, green: 0.46, blue: 0.72)
let ink = Color(red: 0.045, green: 0.038, blue: 0.135)

func stamp(_ seconds: Double) -> String {
    let s = max(0, Int(seconds)); return String(format: "%d:%02d", s / 60, s % 60)
}
let ultraviolet = Color(red: 0.55, green: 0.38, blue: 1)
let twilight = LinearGradient(colors: [sea, ultraviolet, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

struct Orb: View {
    var phase = 0.0
    var bass = 0.0
    var brightness = 0.0
    var body: some View {
        Canvas { ctx, size in
            let radius = min(size.width,size.height) * (0.39 + 0.045*bass)
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let hot = Color(hue: 0.93 - brightness*0.14, saturation: 0.65, brightness: 1)
            let gradient = Gradient(colors: [hot, .pink, ultraviolet, .blue])
            ctx.fill(Path(ellipseIn: CGRect(x: center.x-radius*1.15,y: center.y-radius*1.15,width: radius*2.3,height: radius*2.3)),
                     with: .radialGradient(Gradient(colors: [hot.opacity(0.3), .purple.opacity(0.12), .clear]), center: center, startRadius: 0, endRadius: radius*1.15))
            for latitude in -13...13 {
                let v = Double(latitude)/14 * .pi/2
                var line = Path()
                for j in 0...72 {
                    let t = Double(j)*2 * .pi/72
                    let r = radius*(1 + bass*0.09*sin(3*t+phase)*cos(2*v))
                    let x = r*cos(v)*cos(t)
                    let y = r*(sin(v)*0.94 + cos(v)*sin(t)*0.34)
                    let point = CGPoint(x: center.x + x*0.96-y*0.28, y: center.y+x*0.28+y*0.96)
                    if j == 0 { line.move(to: point) } else { line.addLine(to: point) }
                }
                ctx.stroke(line, with: .linearGradient(gradient, startPoint: .zero,
                    endPoint: CGPoint(x: size.width,y: size.height)), lineWidth: max(0.8,radius/72))
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
            LinearGradient(colors: [Color(red: 0.15, green: 0.055, blue: 0.26), ink, Color(red: 0.12, green: 0.08, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Orb(phase: seed, bass: 0.18, brightness: seed.truncatingRemainder(dividingBy: 8)/8) }
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
    var window: ClosedRange<Double> = 0...1
    var cursor: Double?
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
                let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [sea, .purple, .cyan]), startPoint: .zero, endPoint: CGPoint(x: w,y: h))
                g.stroke(path, with: .color(sea.opacity(0.18)), lineWidth: 6)
                g.stroke(path, with: shade, lineWidth: 1.8)
            } else {
                let n = kind == .spectrum ? 64 : min(112, song.overview.count)
                for i in 0..<n {
                    let x = w*CGFloat(i)/CGFloat(n)
                    let a: Float
                    if kind == .spectrum { a = meter.spectrum[i] }
                    else {
                        let scale = Double(song.overview.count)
                        let span = window.upperBound-window.lowerBound
                        let lo = min(song.overview.count-1,Int(scale*(window.lowerBound + Double(i)/Double(n)*span)))
                        let hi = min(song.overview.count,max(lo+1,Int(scale*(window.lowerBound + Double(i+1)/Double(n)*span))))
                        a = song.overview[lo..<hi].max() ?? 0
                    }
                    let height = max(2, h*0.96*CGFloat(min(1,a)))
                    let rect = CGRect(x: x,y: kind == .spectrum ? h-height : (h-height)/2,
                                      width: max(1,w/CGFloat(n)-1),height: height)
                    let played = window.lowerBound + Double(i)/Double(n)*(window.upperBound-window.lowerBound) <= (cursor ?? meter.seconds/song.seconds)
                    g.fill(Path(roundedRect: rect, cornerRadius: 1),
                           with: .color(kind == .spectrum ? Color(hue: 0.92-Double(i)/180,saturation: 0.65,brightness: 1) : (played ? sea : .white.opacity(0.38))))
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

