import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

@main struct AftertoneApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = Transport()
    @AppStorage("appearance") private var appearance = "System"
    var body: some Scene {
        WindowGroup {
            Studio().environmentObject(library).environmentObject(player)
                .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        }
    }
}
private enum Screen: String, CaseIterable {
    case player = "Player", library = "Library", effects = "Effects"
    var icon: String { switch self { case .player: "waveform"; case .library: "square.stack.3d.up"; case .effects: "slider.horizontal.3" } }
}
struct Studio: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Transport
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @State private var screen = Screen.player
    @State private var importer = false
    @State private var queue: [UUID] = []
    @AppStorage("appearance") private var appearance = "System"
    @State private var visual = Visual.waveform
    private var selected: Song? { library.catalog.songs.first { $0.id == player.song?.id } }
    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark ? [Color(red: 0.06,green: 0.12,blue: 0.15),Color(red: 0.055,green: 0.06,blue: 0.095)] :
                [Color(red: 0.89,green: 0.95,blue: 0.93),Color(red: 0.94,green: 0.93,blue: 0.97)],
                           startPoint: .topLeading,endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.path").fontWeight(.heavy)
                        Text("Aftertone").font(.title2.bold()).tracking(-1)
                    }
                    Spacer()
                    if library.importing { ProgressView().accessibilityLabel("Importing audio") }
                    Button { importer = true } label: { Image(systemName: "plus").frame(width: 42,height: 42).glassPanel(25) }
                        .accessibilityLabel("Import audio").disabled(library.importing)
                    Menu {
                        Picker("Appearance", selection: $appearance) { ForEach(["System","Light","Dark"],id: \.self) { Text($0) } }
                    } label: { Image(systemName: "circle.lefthalf.filled").frame(width: 42,height: 42).glassPanel(25) }
                    .accessibilityLabel("Appearance")
                }.padding(.horizontal,20).padding(.vertical,8)
                Group {
                    switch screen {
                    case .player: playerView
                    case .library: LibraryView { song, songs in
                        queue = songs.map(\.id); player.load(song); screen = .player
                    } importAudio: { importer = true }
                    case .effects: RackView()
                    }
                }.frame(maxWidth: .infinity,maxHeight: .infinity)
                HStack(spacing: 4) {
                    ForEach(Screen.allCases,id: \.self) { item in
                        Button {
                            withAnimation(.snappy) { screen = item }
                        } label: {
                            Label(item.rawValue,systemImage: item.icon).font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical,12)
                                .foregroundStyle(item == screen ? Color.white : .primary)
                                .background { if item == screen { Capsule().fill(ink) } }
                        }.accessibilityAddTraits(screen == item ? .isSelected : [])
                    }
                }.padding(5).glassPanel(32).padding(.horizontal,16).padding(.vertical,6)
            }
        }
        .buttonStyle(.plain)
        .tint(scheme == .dark ? sea : Color(red: 0.03,green: 0.43,blue: 0.35))
        .fileImporter(isPresented: $importer, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    let before = Set(library.catalog.songs.map(\.id))
                    await library.add(urls)
                    if player.song == nil, let first = library.catalog.songs.first(where: { !before.contains($0.id) }) {
                        player.load(first, play: false)
                    }
                }
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { library.message = error.localizedDescription }
            }
        }
        .onAppear {
            player.persist = { id, mix in library.update(id) { $0.mix = mix } }
            player.finished = { advance(1, wrap: false) }
            if player.song == nil, let first = library.catalog.songs.first { player.load(first, play: false) }
        }
        .onChange(of: phase) { _, next in if next != .active { player.flush() } }
        .alert("Aftertone", isPresented: Binding(get: { library.message != nil || player.message != nil },
                set: { if !$0 { library.message = nil; player.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(library.message ?? player.message ?? "") }
        .sheet(isPresented: Binding(get: { player.exportFile != nil }, set: { shown in
            if !shown, let url = player.exportFile {
                player.exportFile = nil; try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        })) {
            if let url = player.exportFile { ExportPicker(url: url).ignoresSafeArea() }
        }
    }
    private func advance(_ step: Int, wrap: Bool = true) {
        let available = Set(library.catalog.songs.map(\.id))
        let ids = queue.isEmpty ? library.catalog.songs.map(\.id) : queue.filter(available.contains)
        guard !ids.isEmpty else { return }
        let i = player.song.flatMap { ids.firstIndex(of: $0.id) } ?? 0
        let next = i + step
        guard wrap || ids.indices.contains(next) else { return }
        let id = ids[(next+ids.count)%ids.count]
        if let song = library.catalog.songs.first(where: { $0.id == id }) { player.load(song) }
    }
    private var playerView: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 17) {
                ZStack(alignment: .bottomLeading) {
                    Sleeve(cover: selected?.cover, seed: Double(selected?.name.count ?? 0)/8, playing: player.playing)
                        .frame(maxWidth: .infinity).frame(height: 256).clipped()
                    LinearGradient(colors: [.clear,.black.opacity(0.62)],startPoint: .center,endPoint: .bottom)
                    HStack {
                        Label(player.playing ? "ON AIR" : "TURNTABLE",systemImage: "circle.fill")
                            .font(.caption2.monospaced().bold()).tracking(1.5)
                        Spacer()
                        Text(selected?.ext ?? "AFTERTONE").font(.caption2.monospaced()).tracking(1.5)
                    }.foregroundStyle(.white).padding(18)
                }.clipShape(RoundedRectangle(cornerRadius: 28))
                if let song = selected {
                    VStack(alignment: .leading,spacing: 5) {
                        Text(song.name).font(.largeTitle.bold()).tracking(-1.8).lineLimit(2)
                        Text("\(song.bpm > 0 ? "≈ \(song.bpm) BPM" : "BPM —")   ·   \(song.keyName)   ·   \(song.sampleRate / 1000, specifier: "%.1f") kHz")
                            .font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                    HStack {
                        Picker("Visualization", selection: $visual) {
                            ForEach(Visual.allCases,id: \.self) { Text($0.rawValue) }
                        }.pickerStyle(.segmented)
                    }
                    PositionView(song: song, meter: player.meter, visual: visual, seek: player.seek)
                    HStack {
                        Button { player.loop.toggle() } label: {
                            Image(systemName: "repeat.1").foregroundStyle(player.loop ? Color.accentColor : .secondary)
                        }.accessibilityLabel(player.loop ? "Turn repeat off" : "Repeat track")
                        Spacer()
                        Button { advance(-1) } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Previous track")
                        Spacer()
                        Button { withAnimation(.snappy) { player.toggle() } } label: {
                            Image(systemName: player.playing ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace))
                                .font(.title2).foregroundStyle(ink).frame(width: 66,height: 66).background(sea,in: Circle())
                        }.accessibilityLabel(player.playing ? "Pause" : "Play")
                        Spacer()
                        Button { advance(1) } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Next track")
                        Spacer()
                        Button { Task { await player.export() } } label: {
                            if player.exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                        }.disabled(player.exporting).accessibilityLabel("Export processed WAV to Files")
                    }.font(.title3).padding(.horizontal,20)
                } else {
                    Text("Your turntable").font(.largeTitle.bold()).tracking(-1.6)
                    Text("Import a track from Files to play it, shape its sound, and save your mix.").foregroundStyle(.secondary)
                    Button { importer = true } label: {
                        Label("Import audio",systemImage: "plus").font(.headline).foregroundStyle(ink)
                            .padding(.horizontal,20).padding(.vertical,14).background(sea,in: Capsule())
                    }.disabled(library.importing)
                }
            }.padding(20)
        }
    }
}
private struct PositionView: View {
    let song: Song
    @ObservedObject var meter: Meter
    var visual: Visual
    let seek: (Double) -> Void
    @State private var drag: Double?
    var body: some View {
        VStack(spacing: 8) {
            AnalyzerView(song: song,meter: meter,kind: visual).frame(height: 62).padding(10)
                .background(ink,in: RoundedRectangle(cornerRadius: 14))
            Slider(value: Binding(get: { drag ?? meter.seconds }, set: { drag = $0 }), in: 0...max(0.001,song.seconds), onEditingChanged: { editing in
                if !editing, let drag { seek(drag); self.drag = nil }
            }).accessibilityLabel("Playback position")
            HStack { Text(stamp(drag ?? meter.seconds)); Spacer(); Text(stamp(song.seconds)) }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
private struct ExportPicker: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

