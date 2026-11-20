import AVFoundation
import SwiftUI
import UIKit

enum GroupKind: String, Codable, CaseIterable { case folder = "Folder", playlist = "Playlist" }
struct SongGroup: Codable, Identifiable {
    var id = UUID()
    var title: String, kind: GroupKind, color: Int
    var members: [UUID] = []
    static let colors: [Color] = [.mint, .indigo, .orange, .pink, .cyan, .purple]
}
struct Catalog: Codable {
    var songs: [Song] = []
    var groups: [SongGroup] = []
}
final class Library: ObservableObject {
    static let directory = Song.directory
    private static let index = directory.appendingPathComponent("library.json")
    @Published private(set) var catalog = Catalog()
    @Published var message: String?
    @Published var importing = false
    @Published var importStatus: String?
    private var readable = true
    init() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: Self.index.path) {
                catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.index))
            }
        } catch { readable = false; message = error.localizedDescription }
    }
    @discardableResult func edit(_ change: (inout Catalog) -> Void) -> Bool {
        guard readable else { message = "The library could not be opened."; return false }
        var next = catalog
        change(&next)
        do {
            try JSONEncoder().encode(next).write(to: Self.index, options: .atomic)
            catalog = next
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func update(_ id: UUID, _ change: (inout Song) -> Void) {
        edit { catalog in
            if let i = catalog.songs.firstIndex(where: { $0.id == id }) { change(&catalog.songs[i]) }
        }
    }
    func remove(_ song: Song) -> Bool {
        guard edit({ catalog in
            catalog.songs.removeAll { $0.id == song.id }
            for i in catalog.groups.indices { catalog.groups[i].members.removeAll { $0 == song.id } }
        }) else { return false }
        do {
            try FileManager.default.removeItem(at: song.pcm)
            if let cover = song.cover { try FileManager.default.removeItem(at: Self.directory.appendingPathComponent(cover)) }
        } catch { message = error.localizedDescription }
        return true
    }
    func songs(in group: SongGroup?) -> [Song] {
        guard let group else { return catalog.songs }
        if group.kind == .folder { return catalog.songs.filter { $0.folder == group.id } }
        let songs = Dictionary(uniqueKeysWithValues: catalog.songs.map { ($0.id, $0) })
        return group.members.compactMap { songs[$0] }
    }
    @MainActor func add(_ batch: PickedAudio) async -> [Song] {
        defer { try? FileManager.default.removeItem(at: batch.directory) }
        guard !importing else { return [] }
        importing = true
        defer { importing = false }
        var failures = batch.failures
        var added: [Song] = []
        for (index, url) in batch.files.enumerated() {
            do {
                let position = "\(index + 1)/\(batch.files.count)"
                importStatus = "Opening \(url.lastPathComponent) · \(position)"
                let decoded = try await Task.detached(priority: .userInitiated) { try Self.decode(url) }.value
                do {
                    importStatus = "Analyzing \(url.lastPathComponent) · \(position)"
                    let song = try await Task.detached(priority: .userInitiated) { try Self.analyze(decoded) }.value
                    guard edit({ $0.songs.append(song) }) else { throw StudioError(message ?? "Couldn’t save the track.") }
                    added.append(song)
                } catch {
                    try? FileManager.default.removeItem(at: decoded.pcm)
                    if let cover = decoded.cover { try? FileManager.default.removeItem(at: Song.directory.appendingPathComponent(cover)) }
                    throw error
                }
            } catch { failures.append("\(url.lastPathComponent) — \(error.localizedDescription)") }
        }
        if !failures.isEmpty {
            importStatus = "Imported \(added.count) · Failed \(failures.count)\n" + failures.joined(separator: "\n")
        } else {
            importStatus = added.count == 1 ? "Added \(added[0].name) to Library" : "Added \(added.count) tracks to Library"
        }
        return added
    }
    private static func decode(_ url: URL) throws -> Song {
        var song = Song(name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.uppercased(),
                        sampleRate: 0, frames: 0, overview: [], bpm: 0, key: -1)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: song.pcm) } }
        var rate: Int32 = 0
        var error = [CChar](repeating: 0, count: 256)
        var album = [CChar](repeating: 0,count: 512)
        var artist = album
        if at_decode(url.path, song.pcm.path, &rate, &error, 256, &album, &artist, 512) < 0 {
            let decoderMessage = String(cString: error)
            do { rate = try Self.decodeWithSystem(url, destination: song.pcm) }
            catch { throw StudioError("Couldn’t decode this file. \(decoderMessage). \(error.localizedDescription)") }
        }
        song.album = album[0] == 0 ? nil : String(cString: album)
        song.artist = artist[0] == 0 ? nil : String(cString: artist)
        let metadata = AVURLAsset(url: url).commonMetadata
        func tag(_ key: AVMetadataKey) -> AVMetadataItem? {
            AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common).first
        }
        if song.album == nil { song.album = tag(.commonKeyAlbumName)?.stringValue }
        if song.artist == nil { song.artist = tag(.commonKeyArtist)?.stringValue }
        if let data = tag(.commonKeyArtwork)?.dataValue, data.count < 24_000_000,
           let artwork = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 800,height: 800)),
           let jpeg = artwork.jpegData(compressionQuality: 0.85) {
            let name = song.id.uuidString + ".jpg"
            if (try? jpeg.write(to: Song.directory.appendingPathComponent(name), options: .atomic)) != nil { song.cover = name }
        }
        song.sampleRate = Double(rate)
        completed = true
        return song
    }
    private static func analyze(_ decoded: Song) throws -> Song {
        var song = decoded
        let mapped = try NSData(contentsOf: song.pcm, options: .alwaysMapped)
        var overview = [Float](repeating: 0, count: 512)
        var bpm: Int32 = 0, key: Int32 = -1
        song.frames = Int64(mapped.length / 8)
        guard song.frames > 0 else { throw StudioError("The decoded file is empty.") }
        at_analyze(mapped.bytes.assumingMemoryBound(to: Float.self), song.frames, song.sampleRate,
                   &overview, 512, &bpm, &key)
        song.overview = overview; song.bpm = Int(bpm); song.key = Int(key)
        return song
    }
    private static func decodeWithSystem(_ url: URL, destination: URL) throws -> Int32 {
        let input = try AVAudioFile(forReading: url)
        let rate = input.processingFormat.sampleRate
        guard rate >= 4000, rate <= 384000,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: true),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let source = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192),
              let stereo = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)
        else { throw StudioError("Unsupported channel layout or sample rate.") }
        try Data().write(to: destination)
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        repeat {
            try input.read(into: source)
            if source.frameLength == 0 { break }
            try converter.convert(to: stereo, from: source)
            let bytes = stereo.audioBufferList.pointee.mBuffers
            guard let address = bytes.mData, bytes.mDataByteSize > 0 else { throw StudioError("Empty audio buffer.") }
            try file.write(contentsOf: Data(bytesNoCopy: address, count: Int(bytes.mDataByteSize), deallocator: .none))
        } while input.framePosition < input.length
        guard try file.offset() > 0 else { throw StudioError("This file contains no audio samples.") }
        return Int32(rate.rounded())
    }
    func setCover(_ data: Data, for id: UUID) throws {
        guard let image = UIImage(data: data),
              let thumbnail = image.preparingThumbnail(of: CGSize(width: 1000, height: 1000)),
              let jpeg = thumbnail.jpegData(compressionQuality: 0.88) else { throw StudioError("Couldn’t read this image.") }
        let name = UUID().uuidString + ".jpg"
        let old = catalog.songs.first { $0.id == id }?.cover
        let file = Self.directory.appendingPathComponent(name)
        try jpeg.write(to: file, options: .atomic)
        if edit({ catalog in
            if let i = catalog.songs.firstIndex(where: { $0.id == id }) { catalog.songs[i].cover = name }
        }) {
            if let old { try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(old)) }
        } else { try? FileManager.default.removeItem(at: file) }
    }
}

