import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255)/255, green: Double((rgb >> 8) & 255)/255, blue: Double(rgb & 255)/255)
    }
}

enum StudioStyle {
    static let cyan = Color(rgb: 0x4cd7f6)
    static let lilac = Color(rgb: 0xddb7ff)
    static let rose = Color(rgb: 0xffb2b7)
    static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(uiColor: UIColor { trait in UIColor(Color(rgb: trait.userInterfaceStyle == .dark ? dark : light)) })
    }
    static let background = adaptive(0x090a10,0xf4f3f7)
    static let surface = adaptive(0x1e1f26,0xffffff)
    static let muted = adaptive(0x9ba0b4,0x5b5e70)
    static let accent = adaptive(0xddb7ff,0x653a89)
    static let signal = adaptive(0x4cd7f6,0x056981)
    static func heading(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-Regular", size: size, relativeTo: .title2).weight(.semibold) }
    static func readout(_ size: CGFloat) -> Font { .custom("SpaceGrotesk-Light", size: size, relativeTo: .caption).weight(.medium).monospacedDigit() }
}

struct StudioBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height * 0.53)
            ZStack {
                StudioStyle.background
                aura(StudioStyle.lilac, at: UnitPoint(x: 0.54,y: -0.08), radius: r, strength: 0.12)
                aura(StudioStyle.cyan, at: UnitPoint(x: -0.22,y: 0.40), radius: r, strength: 0.13)
                aura(StudioStyle.rose, at: UnitPoint(x: 1.12,y: 0.7), radius: r, strength: 0.09)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
    private func aura(_ color: Color, at point: UnitPoint, radius: CGFloat, strength: Double) -> some View {
        RadialGradient(colors: [color.opacity(scheme == .dark ? strength : strength*1.4),.clear],
                       center: point, startRadius: 0, endRadius: radius)
    }
}

struct SectionSwitch: View {
    let labels: [String]
    @Binding var selection: String
    @Namespace private var marker
    var body: some View {
        HStack(spacing: 17) {
            ForEach(labels,id: \.self) { name in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = name }
                } label: {
                    VStack(alignment: .leading,spacing: 8) {
                        Text(name).font(StudioStyle.readout(14)).foregroundStyle(selection == name ? Color.primary : StudioStyle.muted)
                        ZStack {
                            Color.clear.frame(height: 2)
                            if selection == name { Capsule().fill(StudioStyle.accent).matchedGeometryEffect(id: "mark",in: marker) }
                        }.frame(height: 2)
                    }.fixedSize(horizontal: true,vertical: false)
                }.buttonStyle(.plain).accessibilityAddTraits(selection == name ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.padding(.top,5)
    }
}

