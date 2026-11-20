import SwiftUI
import AVFoundation
import AVKit

struct PlayerDeck: View {
    @EnvironmentObject var player: Transport
    @EnvironmentObject var library: Library
    @State private var details = false
    var advance: (Int) -> Void
    var add: () -> Void
    var showRack: () -> Void
    private var song: Song? { library.catalog.songs.first { $0.id == player.song?.id } }
    var body: some View {
        GeometryReader { viewport in
            StudioScroll {
                VStack(alignment: .leading,spacing: 16) {
                    OrbStage(meter: player.meter, active: player.playing)
                        .frame(height: max(140,min(365,viewport.size.height*0.43)))
                    if let song {
                        trackHeading(song)
                        ScrubWave(song: song,meter: player.meter,seek: player.seek).id(song.id)
                    } else {
                        Text("Your music").font(StudioStyle.heading(30))
                        Button(action: add) {
                            Label("Import from Files",systemImage: "plus").font(.headline)
                                .padding(.vertical,12).padding(.horizontal,18)
                                .background(.primary.opacity(0.08),in: Capsule())
                        }.buttonStyle(.plain).disabled(library.importing)
                    }
                }.padding(.horizontal,24).padding(.bottom,14)
            }
        }
        .safeAreaInset(edge: .bottom,spacing: 0) {
            if song != nil {
                VStack(spacing: 5) {
                    transport
                    OutputLinks(showRack: showRack)
                }.padding(.horizontal,20).padding(.bottom,5)
            }
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
    private func trackHeading(_ song: Song) -> some View {
        HStack(spacing: 12) {
            if song.cover != nil {
                Sleeve(cover: song.cover).frame(width: 44,height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading,spacing: 4) {
                Text(song.name).font(StudioStyle.heading(27)).tracking(-0.8).lineLimit(2)
                Text(song.artist.flatMap { $0.isEmpty ? nil : $0 } ?? song.album ?? song.ext)
                    .font(.subheadline).foregroundStyle(StudioStyle.muted).lineLimit(1)
            }
            Spacer()
            Button { details = true } label: {
                Image(systemName: "info").frame(width: 40,height: 40)
                    .background(.primary.opacity(0.05),in: Circle())
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.10)) }
            }.buttonStyle(.plain).accessibilityLabel("Track information")
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
                    .frame(width: 54,height: 54).foregroundStyle(Color(uiColor: .systemBackground))
                    .background(.primary,in: Circle()).shadow(color: .primary.opacity(0.16),radius: 9)
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
    @AppStorage("reactiveOrb") private var reactive = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let animate = reactive && active && !reduce
        let bass = animate ? Double(meter.spectrum.prefix(17).reduce(0,+))/17 : 0
        let treble = animate ? Double(meter.spectrum.suffix(24).max() ?? 0) : 0
        Orb(phase: reactive && !reduce ? meter.seconds*0.9 : 0, bass: bass, brightness: treble)
            .frame(maxWidth: .infinity)
    }
}

private struct OutputLinks: View {
    let showRack: () -> Void
    @State private var output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Audio output"
    var body: some View {
        HStack {
            HStack(spacing: 2) {
                RouteButton().frame(width: 34,height: 36)
                Text(output).lineLimit(1)
            }
            Spacer()
            Button(action: showRack) { Label("DSP rack",systemImage: "slider.horizontal.3").frame(minHeight: 36) }
        }.font(StudioStyle.readout(12)).foregroundStyle(StudioStyle.muted).buttonStyle(.plain)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
                output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Audio output"
            }
    }
}
private struct RouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(StudioStyle.signal)
        view.tintColor = UIColor(StudioStyle.muted)
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView,context: Context) {}
}

private struct ScrubWave: View {
    let song: Song
    @ObservedObject var meter: Meter
    let seek: (Double) -> Void
    var expanded = false
    @State private var cursor: Double?
    @State private var origin: Double?
    @State private var window: ClosedRange<Double> = 0...1
    @State private var hold: Task<Void,Never>?
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    let isWave = expanded || window.upperBound-window.lowerBound < 0.99
                    let relative = (cursor ?? meter.seconds/song.seconds)-window.lowerBound
                    let fraction = min(1,max(0,relative/(window.upperBound-window.lowerBound)))
                    if isWave {
                        AnalyzerView(song: song,meter: meter,kind: .waveform,window: window,cursor: cursor)
                        Rectangle().fill(.white).frame(width: 2)
                            .position(x: geo.size.width*fraction,y: geo.size.height/2)
                    } else {
                        Capsule().fill(Color.primary.opacity(0.13)).frame(height: 3)
                        Capsule().fill(twilight).frame(width: max(1,geo.size.width*fraction),height: 3)
                            .frame(maxWidth: .infinity,alignment: .leading)
                        Circle().fill(.primary).frame(width: 12,height: 12)
                            .overlay { Circle().fill(StudioStyle.signal).frame(width: 4,height: 4) }
                            .position(x: min(geo.size.width-6,max(6,geo.size.width*fraction)),y: geo.size.height/2)
                    }
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
            }.frame(height: expanded ? 128 : 44)
                .background(expanded ? ink : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text(stamp(cursor.map { $0*song.seconds } ?? meter.seconds))
                Spacer()
                if window.upperBound-window.lowerBound < 0.99 { Text("5×") }
                Spacer(); Text(stamp(song.seconds))
            }.font(StudioStyle.readout(12)).foregroundStyle(StudioStyle.muted)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Playback position")
            .accessibilityValue(stamp(meter.seconds))
            .accessibilityAdjustableAction { direction in seek(meter.seconds + (direction == .increment ? 5 : -5)) }
            .onDisappear { hold?.cancel() }
    }
}


struct VisualRoom: View {
    @EnvironmentObject var player: Transport
    @Environment(\.studioChrome) private var chrome
    @AppStorage("visualMode") private var mode = Visual.waveform.rawValue
    var body: some View {
        StudioScroll {
            VStack(alignment: .leading,spacing: 20) {
                Text("Visualizer").font(StudioStyle.heading(30))
                if let song = player.song {
                    SectionSwitch(labels: Visual.allCases.map(\.rawValue),selection: $mode)
                    if mode != Visual.waveform.rawValue {
                        AnalyzerView(song: song,meter: player.meter,kind: Visual(rawValue: mode) ?? .scope)
                            .padding(14).frame(height: 220).background(ink,in: RoundedRectangle(cornerRadius: 14))
                    }
                    ScrubWave(song: song,meter: player.meter,seek: player.seek,expanded: mode == Visual.waveform.rawValue).id(song.id)
                    HStack {
                        Text(song.name).font(StudioStyle.heading(18)).lineLimit(2)
                        Spacer()
                        Button { player.toggle() } label: {
                            Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 46,height: 46).glassPanel(24)
                        }.accessibilityLabel(player.playing ? "Pause" : "Play")
                    }
                } else {
                    Button("Import audio",action: chrome.add).buttonStyle(.bordered)
                }
            }.padding(22)
        }
    }
}
