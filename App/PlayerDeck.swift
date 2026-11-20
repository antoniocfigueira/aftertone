import SwiftUI

struct StudioScroll<Content: View>: View {
    @Namespace private var space
    @State private var depth = 0.0
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    Color.clear.preference(key: ScrollDepth.self, value: -proxy.frame(in: .named(space)).minY)
                }.frame(height: 0)
                content
            }
        }.coordinateSpace(name: space)
            .onPreferenceChange(ScrollDepth.self) { depth = min(1,max(0,$0/32)) }
            .overlay(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial).frame(height: 25)
                    .mask(LinearGradient(colors: [.black,.clear],startPoint: .top,endPoint: .bottom))
                    .opacity(depth).allowsHitTesting(false)
            }
    }
}
private struct ScrollDepth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PlayerDeck: View {
    @EnvironmentObject var player: Transport
    @EnvironmentObject var library: Library
    @State private var details = false
    @AppStorage("visualMode") private var visual = Visual.waveform.rawValue
    var advance: (Int) -> Void
    var add: () -> Void
    private var song: Song? { library.catalog.songs.first { $0.id == player.song?.id } }
    var body: some View {
        StudioScroll {
            VStack(alignment: .leading,spacing: 14) {
                OrbStage(meter: player.meter, active: player.playing, cover: song?.cover)
                    .frame(height: 148).clipShape(RoundedRectangle(cornerRadius: 22))
                if let song {
                    HStack {
                        if song.cover != nil {
                            Sleeve(cover: song.cover).frame(width: 44,height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(song.name).font(.title.bold()).tracking(-1).lineLimit(2)
                        Spacer()
                        Button { details.toggle() } label: { Image(systemName: "info.circle").padding(10) }
                            .accessibilityLabel("Track information")
                    }
                    Picker("Visualization",selection: $visual) {
                        ForEach(Visual.allCases,id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                    if visual != Visual.waveform.rawValue {
                        AnalyzerView(song: song,meter: player.meter,kind: Visual(rawValue: visual) ?? .scope)
                            .padding(12).frame(height: 80).background(ink,in: RoundedRectangle(cornerRadius: 14))
                    }
                    ScrubWave(song: song,meter: player.meter,seek: player.seek).id(song.id)
                } else {
                    Text("Your turntable").font(.largeTitle.bold())
                    Button("Import audio",action: add).buttonStyle(.borderedProminent)
                }
            }.padding(.horizontal,18).padding(.vertical,10)
        }
        .safeAreaInset(edge: .bottom) {
            if song != nil { transport.padding(.horizontal,18).padding(.vertical,6) }
        }
        .sheet(isPresented: $details) {
            if let song {
                NavigationStack {
                    Form {
                        LabeledContent("Tempo",value: song.bpm > 0 ? "≈ \(song.bpm) BPM" : "Unknown")
                        LabeledContent("Key",value: song.keyName)
                        LabeledContent("Source",value: "\(song.ext) · \(Int(song.sampleRate)) Hz")
                        LabeledContent("Duration",value: stamp(song.seconds))
                    }.navigationTitle("Track information")
                        .toolbar { Button("Done") { details = false } }
                }.presentationDetents([.medium])
            }
        }
    }
    private var transport: some View {
        HStack {
            Button { player.loop.toggle() } label: {
                Image(systemName: "repeat.1").foregroundStyle(player.loop ? sea : .secondary)
            }.accessibilityLabel("Repeat track")
            Spacer()
            Button { advance(-1) } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Previous")
            Spacer()
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .frame(width: 55,height: 55).foregroundStyle(.white).background(twilight,in: Circle())
            }.accessibilityLabel(player.playing ? "Pause" : "Play")
            Spacer()
            Button { advance(1) } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Next")
            Spacer()
            Button { Task { await player.export() } } label: {
                if player.exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
            }.disabled(player.exporting).accessibilityLabel("Export WAV")
        }.font(.title3).buttonStyle(.plain).padding(.horizontal,20).padding(.vertical,7).glassPanel(36)
    }
}

private struct OrbStage: View {
    @ObservedObject var meter: Meter
    var active: Bool
    var cover: String?
    @AppStorage("reactiveOrb") private var reactive = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var image: UIImage?
    var body: some View {
        let animate = reactive && active && !reduce
        let bass = animate ? Double(meter.spectrum.prefix(17).reduce(0,+))/17 : 0
        let treble = animate ? Double(meter.spectrum.suffix(24).max() ?? 0) : 0
        ZStack {
            LinearGradient(colors: [ink, Color(red: 0.19,green: 0.065,blue: 0.26), .indigo.opacity(0.86)],
                           startPoint: .bottomLeading,endPoint: .topTrailing)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 15).opacity(0.3)
            }
            Orb(phase: animate ? meter.seconds*2 : 0, bass: bass, brightness: min(1,0.55*bass+0.65*treble))
        }.task(id: cover) { image = cover.flatMap { UIImage(contentsOfFile: Song.directory.appendingPathComponent($0).path) } }
    }
}

private struct ScrubWave: View {
    let song: Song
    @ObservedObject var meter: Meter
    let seek: (Double) -> Void
    @State private var cursor: Double?
    @State private var origin: Double?
    @State private var window: ClosedRange<Double> = 0...1
    @State private var hold: Task<Void,Never>?
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    AnalyzerView(song: song,meter: meter,kind: .waveform,window: window,cursor: cursor)
                    let pos = (cursor ?? meter.seconds/song.seconds)-window.lowerBound
                    Rectangle().fill(.white).frame(width: 2)
                        .position(x: geo.size.width*pos/(window.upperBound-window.lowerBound),y: geo.size.height/2)
                }.clipped().contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let x = min(1,max(0,value.location.x/max(1,geo.size.width)))
                        if origin == nil {
                            origin = x
                            hold = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(320))
                                guard !Task.isCancelled, let anchor = cursor else { return }
                                let lower = max(0,min(0.8,anchor-x*0.2))
                                window = lower...(lower+0.2)
                            }
                        } else if abs(value.translation.width) > 6 { hold?.cancel() }
                        cursor = window.lowerBound+x*(window.upperBound-window.lowerBound)
                    }.onEnded { _ in
                        hold?.cancel()
                        if let cursor { seek(cursor*song.seconds) }
                        origin = nil; cursor = nil; window = 0...1
                    })
            }.frame(height: 52).padding(8).background(ink,in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Text(stamp(cursor.map { $0*song.seconds } ?? meter.seconds))
                Spacer()
                Text(window.lowerBound == 0 && window.upperBound == 1 ? "Hold to zoom" : "5×")
                Spacer(); Text(stamp(song.seconds))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Playback position")
            .accessibilityValue(stamp(meter.seconds))
            .accessibilityAdjustableAction { direction in seek(meter.seconds + (direction == .increment ? 5 : -5)) }
            .onDisappear { hold?.cancel() }
    }
}

