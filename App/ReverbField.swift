import SwiftUI

struct ReverbField: View {
    @Binding var mix: Mix
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Canvas { g,size in
                    let x = size.width*(0.12+0.76*mix.size)
                    let y = size.height*(0.12+0.65*(1-mix.damping))
                    let origin = CGPoint(x: x,y: y)
                    for i in 1...18 {
                        let distance = Double(i)*(4+mix.size*6)
                        let rect = CGRect(x: x-distance,y: y-distance*0.52,width: 2*distance,height: distance*1.04)
                        let shape: Path
                        if mix.space == 2 { shape = Path(roundedRect: rect,cornerRadius: 8) }
                        else { shape = Path(ellipseIn: rect) }
                        let intensity = (1-Double(i)/19)*(0.38+mix.wet*0.62)
                        g.stroke(shape,with: .color((i%3 == 0 ? sea : ultraviolet).opacity(intensity)),lineWidth: 1)
                    }
                    g.fill(Path(ellipseIn: CGRect(x: origin.x-4,y: origin.y-4,width: 8,height: 8)),with: .color(.white))
                }
                Text("Size × Damping").font(.caption2.monospaced()).foregroundStyle(.white).padding(8)
            }.background(ink).clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    var next = mix
                    next.size = min(1,max(0,(drag.location.x/geo.size.width-0.12)/0.76))
                    next.damping = min(1,max(0,1-(drag.location.y/geo.size.height-0.12)/0.65))
                    mix = next
                })
        }.frame(height: 114)
    }
}

