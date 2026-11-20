import AVFoundation
import AudioToolbox
import Combine
import Foundation

final class Meter: ObservableObject {
    @Published var seconds = 0.0
    @Published var wave = [Float](repeating: 0, count: 128)
    @Published var spectrum = [Float](repeating: 0, count: 64)
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
    var finished: (() -> Void)?
    var persist: ((UUID, Mix) -> Void)?
    private var graph: SignalGraph?
    private var timer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var loading = false
    private var saveTask: Task<Void, Never>?
    init() {
        timer = Timer.publish(every: 1/24, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
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
    func flush() {
        saveTask?.cancel()
        if let song, song.mix != mix { persist?(song.id, mix); self.song?.mix = mix }
    }
    private func changed(_ old: Mix) {
        guard !loading, old != mix, song != nil else { return }
        if old.reverse != mix.reverse {
            seek(meter.seconds)
        } else { graph?.apply(mix) }
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
        if play { start() }
    }
    func toggle() { if playing { pause() } else { start() } }
    func unload() {
        saveTask?.cancel(); pause(); graph = nil; song = nil; meter.seconds = 0
    }
    func pause() { graph?.engine.pause(); playing = false }
    func seek(_ seconds: Double) {
        guard let song else { return }
        let resume = playing
        pause(); graph = nil; meter.seconds = min(song.seconds, max(0, seconds))
        if resume { start() }
    }
    private func start() {
        guard let song else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if graph == nil {
                if mix.reverse && meter.seconds <= 0 { meter.seconds = song.seconds }
                if !mix.reverse && meter.seconds >= song.seconds { meter.seconds = 0 }
                let frame = min(song.frames-1, Int64(meter.seconds * song.sampleRate))
                graph = try SignalGraph(song: song, mix: mix, frame: frame, offline: false)
            }
            try graph?.engine.start(); playing = true
        } catch { playing = false; graph = nil; message = error.localizedDescription }
    }
    private func tick() {
        guard playing, let graph, let song else { return }
        meter.seconds = max(0, min(song.seconds, Double(at_position(graph.voice.handle)) / song.sampleRate))
        var wave = meter.wave, spectrum = meter.spectrum
        at_scope_read(graph.scope.handle, &wave, &spectrum, graph.tapRate)
        meter.wave = wave; meter.spectrum = spectrum
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
