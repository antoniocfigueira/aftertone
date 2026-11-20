import PhotosUI
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: Transport
    var open: (Song, [Song]) -> Void
    var importAudio: () -> Void
    @State private var search = ""
    @AppStorage("libraryLayout") private var layout = "Tracks"
    @State private var albumID: String?
    @State private var editingAlbum: Song?
    @State private var albumTitle = ""
    @State private var albumArtist = ""
    @State private var groupID: UUID?
    @State private var editor: SongGroup?
    @State private var coverSong: UUID?
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var removal: Song?
    private var group: SongGroup? { library.catalog.groups.first { $0.id == groupID } }
    private func albumKey(_ song: Song) -> String {
        guard let title = song.album, !title.isEmpty else { return song.id.uuidString }
        return (song.artist ?? "").lowercased() + "\u{1f}" + title.lowercased()
    }
    private var matches: [Song] {
        library.songs(in: group).filter { song in
            search.isEmpty || [song.name,song.album ?? "",song.artist ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    private var albums: [[Song]] {
        Dictionary(grouping: matches,by: albumKey).values.sorted {
            ($0[0].album ?? $0[0].name).localizedStandardCompare($1[0].album ?? $1[0].name) == .orderedAscending
        }
    }
    private var songs: [Song] {
        if layout == "Albums", let albumID { return matches.filter { albumKey($0) == albumID } }
        return matches
    }
    var body: some View {
        StudioScroll {
            VStack(alignment: .leading,spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library").font(StudioStyle.heading(30)).tracking(-1)
                    Spacer()
                    Text("\(library.catalog.songs.count) tracks").font(StudioStyle.readout(12)).foregroundStyle(StudioStyle.muted)
                }
                SectionSwitch(labels: ["Tracks","Albums"],selection: $layout)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your files",text: $search).textInputAutocapitalization(.never)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                }.padding(12).background(StudioStyle.surface.opacity(0.74),in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Menu {
                        Button("All tracks") { groupID = nil }
                        ForEach(library.catalog.groups) { g in
                            Button { groupID = g.id } label: { Label(g.title,systemImage: g.kind == .folder ? "folder" : "music.note.list") }
                        }
                    } label: {
                        HStack {
                            Circle().fill(group.map { SongGroup.colors[$0.color] } ?? sea).frame(width: 9,height: 9)
                            Text(group?.title ?? "All tracks").font(.headline)
                            Image(systemName: "chevron.down").font(.caption)
                        }
                    }
                    Spacer()
                    Menu {
                        ForEach(GroupKind.allCases,id: \.self) { kind in
                            Button("New \(kind.rawValue.lowercased())") {
                                editor = SongGroup(title: "",kind: kind,color: 0)
                            }
                        }
                        if let group { Button("Edit \(group.kind.rawValue.lowercased())") { editor = group } }
                    } label: { Image(systemName: "folder.badge.plus").frame(width: 44,height: 44) }
                        .accessibilityLabel("Manage folders and playlists")
                }
                if songs.isEmpty {
                    ContentUnavailableView(group == nil && search.isEmpty ? "No tracks yet" : "No matching tracks",
                        systemImage: "music.note.list", description: Text(search.isEmpty && group != nil ?
                        "Use a track’s menu in All tracks to add it here." : "Import audio or try another search."))
                    if group == nil && search.isEmpty {
                        Button("Import audio", action: importAudio).buttonStyle(.borderedProminent)
                    }
                }
                if layout == "Albums" && albumID == nil {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138),spacing: 15)],spacing: 20) {
                        ForEach(albums,id: \.first?.id) { tracks in
                            if let first = tracks.first {
                                Button { albumID = albumKey(first) } label: {
                                    VStack(alignment: .leading,spacing: 6) {
                                        Sleeve(cover: tracks.compactMap(\.cover).first,seed: Double(first.name.count))
                                            .aspectRatio(1,contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                                            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)) }
                                        Text(first.album ?? first.name).font(StudioStyle.heading(16)).lineLimit(1)
                                        Text([first.artist, "\(tracks.count) tracks"].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    if layout == "Albums" { Button("All albums",systemImage: "chevron.left") { albumID = nil } }
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        HStack(spacing: 12) {
                            Button { if player.song?.id == song.id { player.toggle() } else { open(song,songs) } } label: {
                                HStack(spacing: 12) {
                                    Thumb(song: song).overlay(alignment: .bottomTrailing) {
                                        if player.song?.id == song.id {
                                            Image(systemName: player.playing ? "waveform" : "pause.fill")
                                                .font(.caption2).foregroundStyle(ink).padding(4).background(StudioStyle.cyan,in: Circle())
                                        }
                                    }
                                    VStack(alignment: .leading,spacing: 5) {
                                        Text(song.name).font(StudioStyle.heading(15)).lineLimit(1)
                                        Text("\(song.ext)  ·  \(stamp(song.seconds))").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.contentShape(Rectangle())
                            }
                            Menu {
                                Button("Choose cover",systemImage: "photo") { coverSong = song.id; photo = nil; showPhotos = true }
                                Button("Edit album",systemImage: "opticaldisc") {
                                    albumTitle = song.album ?? ""; albumArtist = song.artist ?? ""; editingAlbum = song
                                }
                                Menu("Move to folder") {
                                    Button("No folder") { library.update(song.id) { $0.folder = nil } }
                                    ForEach(library.catalog.groups.filter { $0.kind == .folder }) { g in
                                        Button(g.title) { library.update(song.id) { $0.folder = g.id } }
                                    }
                                }
                                Menu("Playlists") {
                                    if !library.catalog.groups.contains(where: { $0.kind == .playlist }) {
                                        Button("Create playlist") {
                                            editor = SongGroup(title: "", kind: .playlist,color: 0,members: [song.id])
                                        }
                                    }
                                    ForEach(library.catalog.groups.filter { $0.kind == .playlist }) { g in
                                        Button {
                                            library.edit { catalog in
                                                guard let i = catalog.groups.firstIndex(where: { $0.id == g.id }) else { return }
                                                if catalog.groups[i].members.contains(song.id) { catalog.groups[i].members.removeAll { $0 == song.id } }
                                                else { catalog.groups[i].members.append(song.id) }
                                            }
                                        } label: {
                                            Label(g.title, systemImage: g.members.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                        }
                                    }
                                }
                                Button("Remove from library", systemImage: "trash", role: .destructive) { removal = song }
                            } label: { Image(systemName: "ellipsis").frame(width: 44,height: 44) }.accessibilityLabel("Options for \(song.name)")
                        }.padding(.vertical,8)
                        Divider()
                    }
                }
                }
            }.padding(20)
        }
        .onChange(of: groupID) { _,_ in albumID = nil }
        .sheet(item: $editingAlbum) { song in
            NavigationStack {
                Form { TextField("Album",text: $albumTitle); TextField("Album artist",text: $albumArtist) }
                    .navigationTitle("Edit album").toolbar {
                        Button("Save") {
                            library.update(song.id) {
                                $0.album = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                $0.artist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            albumID = nil; editingAlbum = nil
                        }
                    }
            }.presentationDetents([.medium])
        }
        .sheet(item: $editor) { initial in GroupEditor(group: initial) { saved in
            if library.edit({ catalog in
                if let i = catalog.groups.firstIndex(where: { $0.id == saved.id }) { catalog.groups[i] = saved }
                else { catalog.groups.append(saved) }
            }) { groupID = saved.id; editor = nil }
        }}
        .photosPicker(isPresented: $showPhotos,selection: $photo,matching: .images)
        .confirmationDialog("Remove this imported copy from Aftertone?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal) { song in
            Button("Remove track", role: .destructive) {
                if library.remove(song), player.song?.id == song.id { player.unload() }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item, let id = coverSong else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw StudioError("The image is unavailable.") }
                    try library.setCover(data,for: id)
                } catch { library.message = error.localizedDescription }
            }
        }
    }
}
private struct Thumb: View {
    let song: Song
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(ink)
            if song.cover != nil { Sleeve(cover: song.cover) }
            else { Image(systemName: "waveform").foregroundStyle(sea) }
        }.frame(width: 48,height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
private struct GroupEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var group: SongGroup
    var save: (SongGroup) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name",text: $group.title)
                HStack {
                    ForEach(SongGroup.colors.indices,id: \.self) { i in
                        Button { group.color = i } label: {
                            Circle().fill(SongGroup.colors[i]).overlay {
                                if group.color == i { Image(systemName: "checkmark").foregroundStyle(.black) }
                            }
                        }.buttonStyle(.plain).accessibilityLabel(["Mint","Indigo","Orange","Pink","Cyan","Purple"][i])
                    }
                }
            }.navigationTitle(group.kind.rawValue)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { group.title = group.title.trimmingCharacters(in: .whitespacesAndNewlines); save(group) }
                            .disabled(group.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.presentationDetents([.medium])
    }
}

