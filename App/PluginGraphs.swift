import SwiftUI

private func frequency(_ x: Double) -> Double { 20 * pow(1000, min(1,max(0,x))) }
private func axis(_ hz: Double) -> Double { log10(hz/20)/3 }
private let bandColors: [Color] = [StudioStyle.cyan,StudioStyle.lilac,StudioStyle.rose]

struct EqualizerGraph: View {
    @Binding var mix: Mix
    var sampleRate: Double
    @State private var band = 4
    @State private var dragging: Int?
    private func response(_ hz: Double) -> Double {
        let angle = 2 * Double.pi * hz / sampleRate
        let c = cos(angle), s = sin(angle)
        var db = 0.0
        let centers = mix.eqCenters, qs = mix.qValues
        for i in centers.indices where mix.eq[i] != 0 {
            let omega = 2 * Double.pi * min(centers[i],sampleRate*0.46) / sampleRate
            let alpha = sin(omega)/(2*qs[i])
            let gain = pow(10,mix.eq[i]/40)
            let real = c-cos(omega)
            let common = real*real
            let a = alpha*s*gain, b = alpha*s/gain
            db += 10*log10(max(1e-18,common+a*a)/max(1e-18,common+b*b))
        }
        return db
    }
    private func bandPoint(_ i: Int, size: CGSize) -> CGPoint {
        let x = CGFloat(axis(mix.eqCenters[i])) * size.width
        let y = CGFloat(0.5 - mix.eq[i] / 36.0) * size.height
        return CGPoint(x: x, y: y)
    }

    private func closestBand(to touch: CGPoint, size: CGSize) -> Int {
        var best = band
        var distance = CGFloat.infinity
        for i in mix.eq.indices {
            let point = bandPoint(i, size: size)
            let dx = point.x - touch.x
            let dy = point.y - touch.y
            let squared = dx * dx + dy * dy
            if squared < distance { distance = squared; best = i }
        }
        return best
    }

    private func dragBand(to touch: CGPoint, size: CGSize) {
        let selected = dragging ?? closestBand(to: touch, size: size)
        if dragging == nil { band = selected; dragging = selected }
        let x = Double(touch.x / max(1, size.width))
        let y = Double(touch.y / max(1, size.height))
        var next = mix
        var centers = next.eqCenters
        centers[selected] = min(sampleRate * 0.46, frequency(x))
        next.centers = centers
        next.eq[selected] = min(15, max(-15, (0.5 - y) * 36))
        mix = next
    }

    private func drawChart(_ g: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        for hz in [30.0,100,300,1000,3000,10000] {
            var line = Path(); let x = w*CGFloat(axis(hz))
            line.move(to: CGPoint(x: x,y: 0)); line.addLine(to: CGPoint(x: x,y: h))
            g.stroke(line,with: .color(.white.opacity(0.14)))
        }
        var curve = Path()
        for j in 0...150 {
            let x = Double(j)/150
            let db = response(min(sampleRate*0.49,frequency(x)))
            let point = CGPoint(x: CGFloat(x)*w,y: h*CGFloat(0.5-db/36))
            if j == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
        }
        g.stroke(curve,with: .color(sea.opacity(0.22)),lineWidth: 6)
        g.stroke(curve,with: .color(sea),lineWidth: 2)
        for i in mix.eq.indices {
            let center = bandPoint(i, size: size)
            g.fill(Path(ellipseIn: CGRect(x: center.x-5,y: center.y-5,width: 10,height: 10)),
                   with: .color(i == band ? .white : ultraviolet))
        }
    }

    private var chart: some View {
        GeometryReader { geo in
            Canvas { context, size in drawChart(context, size: size) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragBand(to: $0.location, size: geo.size) }
                    .onEnded { _ in dragging = nil })
        }
        .frame(height: 148)
        .background(ink)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private var controls: some View {
        VStack {
            HStack {
                Picker("Band",selection: $band) {
                    ForEach(0..<10,id: \.self) { i in Text("Band \(i+1)").tag(i) }
                }
                Spacer()
                Text("\(Int(mix.eqCenters[band])) Hz · \(mix.eq[band],specifier: "%+.1f") dB")
                    .font(.caption.monospacedDigit())
            }
            Slider(value: Binding(get: { axis(mix.eqCenters[band]) },set: { x in
                var all = mix.eqCenters; all[band] = min(sampleRate*0.46,frequency(x)); mix.centers = all
            }),in: 0...1).accessibilityLabel("Band frequency").accessibilityValue("\(Int(mix.eqCenters[band])) hertz")
            Parameter(name: "Gain",value: $mix.eq[band],range: -15...15,format: "%+.1f",unit: " dB",step: 0.1)
            Parameter(name: "Q",value: Binding(get: { mix.qValues[band] },set: { q in
                var all = mix.qValues; all[band] = q; mix.bandwidthQ = all
            }),range: 0.3...8,format: "%.2f")
        }
    }
    var body: some View {
        VStack {
            chart
            controls
        }
    }
}

struct DriveGraph: View {
    @Binding var mix: Mix
    @State private var split: Int?
    private var low: Double { mix.lowSplit ?? 220 }
    private var high: Double { mix.highSplit ?? 3200 }
    var body: some View {
        VStack {
            GeometryReader { geo in
                Canvas { g,size in
                    let edges = [0,axis(low),axis(high),1]
                    for i in 0..<3 {
                        let x = edges[i]*size.width, span = (edges[i+1]-edges[i])*size.width
                        let panel = CGRect(x: x,y: 0,width: span,height: size.height)
                        g.fill(Path(panel),with: .color(bandColors[i].opacity(0.14)))
                        var curve = Path()
                        let drive = 1+15*mix.bandDrive[i]
                        for j in 0...44 {
                            let t = Double(j)/44, input = 2*t-1
                            let shaped = drive <= 1 ? input : tanh(input*drive)/tanh(drive)
                            let full = 1 + 15*mix.drive
                            let y = full <= 1 ? shaped : tanh(shaped*full)/tanh(full)
                            let p = CGPoint(x: x+t*span,y: size.height*(0.5-0.36*y))
                            if j == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
                        }
                        g.stroke(curve,with: .color(bandColors[i]),lineWidth: 2)
                        if i > 0 { g.fill(Path(CGRect(x: x-1,y: 0,width: 2,height: size.height)),with: .color(.white.opacity(0.75))) }
                    }
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { e in
                    let x = e.location.x/max(1,geo.size.width)
                    if split == nil { split = abs(axis(low)-x) < abs(axis(high)-x) ? 0 : 1 }
                    if split == 0 { mix.lowSplit = min(8000,high/1.2,max(40,frequency(x))) }
                    else { mix.highSplit = max(300,low*1.2,min(16000,frequency(x))) }
                }.onEnded { _ in split = nil })
            }.frame(height: 110).background(ink).clipShape(RoundedRectangle(cornerRadius: 12))
            Parameter(name: "Low crossover",value: Binding(get: { low },set: { mix.lowSplit = $0 }),
                      range: 40...min(8000,high/1.2),format: "%.0f",unit: " Hz",step: 1)
            Parameter(name: "High crossover",value: Binding(get: { high },set: { mix.highSplit = $0 }),
                      range: max(300,low*1.2)...16000,format: "%.0f",unit: " Hz",step: 1)
        }
    }
}

