import AVFoundation
import AudioToolbox
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor private final class ScreenClock: NSObject {
    var frame: (() -> Void)?
    @objc func refresh() { frame?() }
}

final class Meter: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var seconds = 0.0
    var wave = [Float](repeating: 0, count: 128)
    var spectrum = [Float](repeating: 0, count: 64)
}

@MainActor final class Transport: ObservableObject {
    @Published private(set) var song: Song?
    @Published private(set) var playing = false
    @Published var mix = Mix() { didSet { changed(oldValue) } }
    @Published var message: String?
    @Published var exporting = false
    @Published var exportFile: URL?
    @Published var loop = false
    let meter = Meter()
    var skip: ((Int) -> Void)?
    var finished: (() -> Void)?
    var persist: ((UUID, Mix) -> Void)?
    private var graph: SignalGraph?
    private var timer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var loading = false
    private var saveTask: Task<Void, Never>?
    private let clock = ScreenClock()
    private var display: CADisplayLink?
    private var commands: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?
    init() {
        clock.frame = { [weak self] in self?.tick() }
        let link = CADisplayLink(target: clock, selector: #selector(ScreenClock.refresh))
        link.preferredFramesPerSecond = 60
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        display = link
        configureCommands()
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            if UIApplication.shared.applicationState != .active { self?.tick(visuals: false) }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
    }
    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping @MainActor (Transport) -> Void) {
            let token = command.addTarget { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
                return .success
            }
            commands.append((command, token))
        }
        bind(center.playCommand) { if !$0.playing { $0.start() } }
        bind(center.pauseCommand) { $0.pause() }
        bind(center.togglePlayPauseCommand) { $0.toggle() }
        bind(center.nextTrackCommand) { $0.skip?(1) }
        bind(center.previousTrackCommand) { $0.skip?(-1) }
        let seek = center.changePlaybackPositionCommand
        let token = seek.addTarget { [weak self] event in
            guard let change = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = change.positionTime
            Task { @MainActor in self?.seek(time) }
            return .success
        }
        commands.append((seek, token))
        updateSystemPlayer()
    }
    private func updateSystemPlayer() {
        for (command, _) in commands { command.isEnabled = song != nil }
        let center = MPNowPlayingInfoCenter.default()
        guard let song else { center.nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyPlaybackDuration: song.seconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: meter.seconds,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? mix.rate * (mix.reverse ? -1 : 1) : 0
        ]
        info[MPMediaItemPropertyArtwork] = artwork
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPMediaItemPropertyArtist] = song.artist
        center.nowPlayingInfo = info
    }
    func flush() {
        saveTask?.cancel()
        if let song, song.mix != mix { persist?(song.id, mix); self.song?.mix = mix }
    }
    private func changed(_ old: Mix) {
        guard !loading, old != mix, song != nil else { return }
        if old.reverse != mix.reverse {
            seek(meter.seconds)
        } else { graph?.apply(mix) }
        if old.rate != mix.rate || old.reverse != mix.reverse { updateSystemPlayer() }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { flush() }
        }
    }
    func load(_ next: Song, play: Bool = true) {
        flush(); pause(); graph = nil; loading = true
        song = next; mix = next.mix; loading = false
        meter.seconds = mix.reverse ? next.seconds : 0
        meter.wave = Array(repeating: 0, count: 128); meter.spectrum = Array(repeating: 0, count: 64)
        artwork = next.cover.flatMap { UIImage(contentsOfFile: Song.directory.appendingPathComponent($0).path) }
            .map { image in MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        meter.objectWillChange.send()
        updateSystemPlayer()
        if play { start() }
    }
    func toggle() { if playing { pause() } else { start() } }
    func unload() {
        saveTask?.cancel(); pause(); graph = nil; song = nil; meter.seconds = 0; updateSystemPlayer()
    }
    func pause() { graph?.engine.pause(); playing = false; display?.isPaused = true; updateSystemPlayer() }
    func seek(_ seconds: Double) {
        guard let song else { return }
        let resume = playing
        pause(); graph = nil; meter.seconds = min(song.seconds, max(0, seconds))
        meter.objectWillChange.send(); updateSystemPlayer()
        if resume { start() }
    }
    private func start() {
        guard let song else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try? session.setPreferredIOBufferDuration(0.008)
            try session.setActive(true)
            if graph == nil {
                if mix.reverse && meter.seconds <= 0 { meter.seconds = song.seconds }
                if !mix.reverse && meter.seconds >= song.seconds { meter.seconds = 0 }
                let frame = min(song.frames-1, Int64(meter.seconds * song.sampleRate))
                graph = try SignalGraph(song: song, mix: mix, frame: frame, offline: false)
            }
            try graph?.engine.start(); playing = true; display?.isPaused = false; updateSystemPlayer()
        } catch { playing = false; graph = nil; message = error.localizedDescription }
    }
    private func tick(visuals: Bool = true) {
        guard playing, let graph, let song else { return }
        meter.seconds = max(0, min(song.seconds, Double(at_position(graph.voice.handle)) / song.sampleRate))
        if visuals {
            var wave = meter.wave, spectrum = meter.spectrum
        at_scope_read(graph.scope.handle, &wave, &spectrum, graph.tapRate)
            for i in spectrum.indices {
                let old = meter.spectrum[i]
                spectrum[i] = old + (spectrum[i]-old) * (spectrum[i] > old ? 0.75 : 0.22)
            }
            meter.wave = wave; meter.spectrum = spectrum
            meter.objectWillChange.send()
        }
        let remaining = mix.reverse ? graph.startFrame + 1 : song.frames - graph.startFrame
        let tail = (mix.tail + 0.12 * mix.rate) * song.sampleRate
        if Double(at_elapsed(graph.voice.handle) - remaining) >= tail {
            pause(); self.graph = nil
            if loop { start() } else { finished?() }
        }
    }
    func export() async {
        guard let song, !exporting else { return }
        exporting = true
        let snapshot = mix
        defer { exporting = false }
        do {
            exportFile = try await Task.detached(priority: .userInitiated) { try WaveExport.render(song, snapshot) }.value
        } catch { message = error.localizedDescription }
    }
}
