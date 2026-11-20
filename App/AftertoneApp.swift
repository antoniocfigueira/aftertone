import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

@main struct AftertoneApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = Transport()
    @AppStorage("appearance") private var appearance = "Dark"
    var body: some Scene {
        WindowGroup {
            Studio().environmentObject(library).environmentObject(player)
                .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        }
    }
}
private enum Screen: String, CaseIterable {
    case player = "Player", effects = "DSP rack", visual = "Visualizer", library = "Library"
    var icon: String {
        switch self {
        case .player: "record.circle"
        case .effects: "slider.horizontal.3"
        case .visual: "waveform"
        case .library: "square.grid.2x2"
        }
    }
}

private struct SlidingTabs: View {
    @Binding var screen: Screen
    @State private var finger: CGFloat?
    var body: some View {
        GeometryReader { proxy in
            let count = Screen.allCases.count
            let cell = proxy.size.width/CGFloat(count)
            let index = Screen.allCases.firstIndex(of: screen) ?? 0
            let center = finger ?? cell*(CGFloat(index)+0.5)
            ZStack(alignment: .leading) {
                Circle().fill(Color.primary.opacity(0.09)).frame(width: 40,height: 40)
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.09)) }
                    .offset(x: center-20)
                HStack(spacing: 0) {
                    ForEach(Screen.allCases,id: \.self) { item in
                        Button { screen = item } label: {
                            Image(systemName: item.icon).font(.system(size: 19,weight: .medium))
                                .foregroundStyle(screen == item ? StudioStyle.accent : StudioStyle.muted)
                                .frame(maxWidth: .infinity,maxHeight: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(item.rawValue)
                            .accessibilityAddTraits(screen == item ? .isSelected : [])
                    }
                }
            }.contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 6)
                .onChanged { finger = min(proxy.size.width-cell/2,max(cell/2,$0.location.x)) }
                .onEnded { value in
                    let i = Int(value.location.x/max(1,cell))
                    screen = Screen.allCases[min(count-1,max(0,i))]
                    withAnimation(.snappy) { finger = nil }
                })
        }.frame(height: 44).padding(.horizontal,8).padding(.vertical,4)
            .glassPanel(30).frame(maxWidth: 290).padding(.horizontal,24).padding(.bottom,2)
    }
}
struct Studio: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Transport
    @Environment(\.scenePhase) private var phase
    @State private var screen = Screen.player
    @State private var importer = false
    @State private var queue: [UUID] = []
    @AppStorage("appearance") private var appearance = "Dark"
    @State private var settings = false
    @AppStorage("reactiveOrb") private var reactive = true
    var body: some View {
        GeometryReader { viewport in
            ZStack {
                StudioBackdrop()
                page(screen)
                    .environment(\.studioChrome, StudioChrome(topInset: viewport.safeAreaInsets.top,
                        section: screen.rawValue, settings: { settings = true }, add: { importer = true }))
                    .ignoresSafeArea(.container,edges: .top)
                    .safeAreaInset(edge: .bottom,spacing: 4) { SlidingTabs(screen: $screen) }
            }
        }
        .tint(StudioStyle.accent)
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Picker("Appearance",selection: $appearance) {
                        ForEach(["System","Light","Dark"],id: \.self) { Text($0) }
                    }
                    Toggle("Music-reactive sphere",isOn: $reactive)
                }.navigationTitle("Settings").toolbar { Button("Done") { settings = false } }
            }
        }
        .sheet(isPresented: $importer) {
            AudioImportPicker { batch in
                importer = false
                Task {
                    let added = await library.add(batch)
                    if player.song == nil, let first = added.first { player.load(first, play: false) }
                }
            } cancelled: { importer = false }
        }
        .onAppear {
            player.persist = { id, mix in library.update(id) { $0.mix = mix } }
            player.skip = { advance($0) }
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
    private func page(_ item: Screen) -> some View {
        Group {
            switch item {
            case .player:
                PlayerDeck(advance: { advance($0) },add: { if !library.importing { importer = true } },
                           showRack: { screen = .effects })
            case .library:
                LibraryView { song, songs in
                    queue = songs.map(\.id)
                    player.load(song)
                } importAudio: { if !library.importing { importer = true } }
            case .effects: RackView()
            case .visual: VisualRoom()
            }
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

