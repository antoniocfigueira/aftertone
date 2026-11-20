import SwiftUI
import UIKit

struct StudioChrome {
    var topInset: CGFloat = 0
    var section = ""
    var settings: () -> Void = {}
    var add: () -> Void = {}
}
private struct ChromeKey: EnvironmentKey { static let defaultValue = StudioChrome() }
extension EnvironmentValues {
    var studioChrome: StudioChrome {
        get { self[ChromeKey.self] }
        set { self[ChromeKey.self] = newValue }
    }
}

// Sample the moving content with native backdrop effects. Only their masks
// vary; interactive content and audio visualizers keep their own render layers.
// UIKit copies masks supplied to a visual effect view. Use image masks so
// the alpha ramp survives copying and resizing on different OS versions.
@MainActor private func edgeMask(stops: [CGFloat]) -> UIImageView {
    let size = CGSize(width: 2,height: 256)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size,format: format).image { renderer in
        let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0.67).cgColor, UIColor.clear.cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors: colors as CFArray,locations: stops) else { return }
        renderer.cgContext.drawLinearGradient(gradient,start: .zero,end: CGPoint(x: 0,y: size.height),options: [.drawsAfterEndLocation])
    }
    let view = UIImageView(image: image)
    view.contentMode = .scaleToFill
    return view
}

private final class EdgeView: UIView {
    private let soft = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let near = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let softMask = edgeMask(stops: [0,0.40,1])
    private let nearMask = edgeMask(stops: [0,0.18,0.76])
    private var progress: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        addSubview(soft); addSubview(near)
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    func setProgress(_ value: CGFloat) {
        guard progress != value else { return }
        progress = value
        isHidden = value <= 0.001
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isHidden else { return }
        let height = bounds.height * progress
        let target = CGRect(x: 0,y: 0,width: bounds.width,height: height)
        guard soft.frame != target || soft.mask == nil else { return }
        soft.frame = target
        near.frame = CGRect(x: 0,y: 0,width: bounds.width,height: height * progress)
        // Reassign after resizing: UIVisualEffectView copies its mask.
        softMask.frame = soft.bounds; soft.mask = softMask
        nearMask.frame = near.bounds; near.mask = nearMask
    }
}
private struct ScrollEdge: UIViewRepresentable {
    let progress: CGFloat
    func makeUIView(context: Context) -> EdgeView { EdgeView(frame: .zero) }
    func updateUIView(_ view: EdgeView,context: Context) { view.setProgress(progress) }
}

private struct ScrollDepth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct StudioScroll<Content: View>: View {
    @Namespace private var space
    @State private var depth: CGFloat = 0
    @Environment(\.studioChrome) private var chrome
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: Transport
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollDepth.self,value: -geo.frame(in: .named(space)).minY)
                }.frame(height: 0)
                heading.padding(.top,chrome.topInset+4)
                if let status = library.importStatus {
                    HStack {
                        if library.importing { ProgressView() }
                        Text(status).font(.footnote)
                        Spacer()
                        if !library.importing {
                            Button { library.importStatus = nil } label: { Image(systemName: "xmark.circle") }
                                .accessibilityLabel("Dismiss import status")
                        }
                    }.padding(.horizontal,22).padding(.vertical,6)
                }
                content
            }
        }.coordinateSpace(name: space)
            .scrollIndicators(.hidden)
            .onPreferenceChange(ScrollDepth.self) { offset in
                depth = min(1,max(0,offset/42))
            }
            .overlay(alignment: .top) {
                ScrollEdge(progress: depth).frame(height: chrome.topInset+30)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
    private var sectionTitle: String {
        guard chrome.section == "Player", player.song != nil else { return chrome.section.uppercased() }
        return player.playing ? "PLAYING" : "PAUSED"
    }
    private var heading: some View {
        HStack {
            Button(action: chrome.settings) { Image(systemName: "gearshape").frame(width: 44,height: 44) }
                .accessibilityLabel("Settings")
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(player.playing ? StudioStyle.signal : StudioStyle.muted).frame(width: 5,height: 5)
                Text("AFTERTONE").font(StudioStyle.readout(11).bold()).tracking(2)
                Text("·").foregroundStyle(.secondary)
                Text(sectionTitle).font(StudioStyle.readout(10)).tracking(1.2).foregroundStyle(StudioStyle.muted)
            }
            Spacer()
            Button(action: chrome.add) { Image(systemName: "plus").frame(width: 44,height: 44) }
                .disabled(library.importing).accessibilityLabel("Import audio")
        }.buttonStyle(.plain).padding(.horizontal,16)
    }
}

