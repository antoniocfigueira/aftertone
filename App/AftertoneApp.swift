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
private struct SlidingTabs: View {
    @Binding var screen: Screen
    @State private var finger: CGFloat?
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width/3
            let position = finger ?? CGFloat(Screen.allCases.firstIndex(of: screen) ?? 0)*width
            ZStack(alignment: .leading) {
                Capsule().fill(twilight).opacity(0.32).frame(width: width)
                    .overlay { Capsule().stroke(.white.opacity(0.32)) }.offset(x: position)
                HStack(spacing: 0) {
                    ForEach(Screen.allCases,id: \.self) { item in
                        Button { screen = item } label: {
                            VStack(spacing: 2) { Image(systemName: item.icon); Text(item.rawValue).font(.caption2) }
                                .frame(maxWidth: .infinity,maxHeight: .infinity)
                        }.buttonStyle(.plain).accessibilityAddTraits(screen == item ? .isSelected : [])
                    }
                }
            }.contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 5)
                .onChanged { drag in finger = min(width*2,max(0,drag.location.x-width/2)) }
                .onEnded { drag in
                    screen = Screen.allCases[min(2,max(0,Int(drag.location.x/max(1,width))))]
                    withAnimation(.snappy) { finger = nil }
                })
        }.frame(height: 47).padding(4).glassPanel(30)
    }
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
    @State private var settings = false
    @AppStorage("reactiveOrb") private var reactive = true
    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 26, *) {
                    TabView(selection: $screen) {
                        ForEach(Screen.allCases,id: \.self) { item in
                            page(item).tabItem { Label(item.rawValue,systemImage: item.icon) }.tag(item)
                        }
                    }
                } else {
                    page(screen).safeAreaInset(edge: .bottom) {
                        SlidingTabs(screen: $screen).padding(.horizontal,16)

                    }
                }
            }
            .navigationTitle(screen == .player ? "Aftertone" : screen.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importer = true } label: { Image(systemName: "plus") }
                        .disabled(library.importing).accessibilityLabel("Import audio")
                }
            }
        }
        .tint(scheme == .dark ? sea : .purple)
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
        ZStack {
            LinearGradient(colors: scheme == .dark ? [ink,Color(red: 0.13,green: 0.075,blue: 0.21),ink] :
                            [Color(red: 1,green: 0.94,blue: 0.97),Color(red: 0.91,green: 0.90,blue: 0.99)],
                           startPoint: .topLeading,endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 0) {
                if let status = library.importStatus {
                    HStack {
                        if library.importing { ProgressView() }
                        Text(status).font(.footnote).frame(maxWidth: .infinity,alignment: .leading)
                        if !library.importing { Button { library.importStatus = nil } label: { Image(systemName: "xmark.circle") } }
                    }.padding(10)
                }
                switch item {
                case .player: PlayerDeck(advance: { advance($0) },add: { if !library.importing { importer = true } })
                case .library: LibraryView { song, songs in
                    queue = songs.map(\.id)
                    player.load(song)
                } importAudio: { if !library.importing { importer = true } }
                case .effects: RackView()
                }
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

