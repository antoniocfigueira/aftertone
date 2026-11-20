import AVFoundation
import AudioToolbox

final class Voice {
    let data: NSData
    let handle: OpaquePointer
    init(song: Song, mix: Mix, frame: Int64) throws {
        data = try NSData(contentsOf: song.pcm, options: .alwaysMapped)
        guard data.length / 8 == song.frames, song.frames > 0,
              let pointer = at_create(data.bytes.assumingMemoryBound(to: Float.self), song.frames, song.sampleRate)
        else { throw StudioError("The audio cache is unavailable. Import the track again.") }
        handle = pointer
        at_settings(handle, mix.settings)
        at_start(handle, frame, mix.reverse ? 1 : 0)
    }
    deinit { at_destroy(handle) }
}
final class Scope {
    let handle: OpaquePointer
    init() throws {
        guard let value = at_scope_create() else { throw StudioError("Insufficient memory for the scope.") }
        handle = value
    }
    deinit { at_scope_destroy(handle) }
}

final class SignalGraph {
    let engine = AVAudioEngine()
    let speed = AVAudioUnitVarispeed()
    let stretch = AVAudioUnitTimePitch()
    let voice: Voice
    let format: AVAudioFormat
    let limiter: AVAudioUnitEffect
    let scope: Scope
    let startFrame: Int64
    var tapRate: Float = 44100

    init(song: Song, mix: Mix, frame: Int64, offline: Bool) throws {
        startFrame = frame
        voice = try Voice(song: song, mix: mix, frame: frame)
        scope = try Scope()
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: song.sampleRate, channels: 2) else {
            throw StudioError("Unsupported sample rate.")
        }
        format = stereo
        let source = AVAudioSourceNode(format: stereo) { [voice] _, _, count, buffers in
            let channels = UnsafeMutableAudioBufferListPointer(buffers)
            guard channels.count == 2, let l = channels[0].mData, let r = channels[1].mData else {
                return kAudio_ParamError
            }
            at_render(voice.handle, l.assumingMemoryBound(to: Float.self),
                      r.assumingMemoryBound(to: Float.self), Int32(count))
            return noErr
        }
        limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        for node in [source as AVAudioNode, speed, stretch, limiter] { engine.attach(node) }
        engine.connect(source, to: speed, format: stereo)
        engine.connect(speed, to: stretch, format: stereo)
        engine.connect(stretch, to: limiter, format: stereo)
        engine.connect(limiter, to: engine.mainMixerNode, format: stereo)
        stretch.overlap = 16
        if offline {
            try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 4096)
        } else {
            let output = engine.mainMixerNode.outputFormat(forBus: 0)
            tapRate = Float(output.sampleRate)
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [scope] buffer, _ in
                if let data = buffer.floatChannelData {
                    at_scope_push(scope.handle, data[0], Int32(buffer.frameLength))
                }
            }
        }
        apply(mix)
    }
    func apply(_ mix: Mix) {
        speed.rate = mix.lockPitch ? 1 : Float(mix.rate)
        stretch.rate = mix.lockPitch ? Float(mix.rate) : 1
        stretch.pitch = Float(mix.pitch * 100)
        stretch.bypass = stretch.rate == 1 && mix.pitch == 0
        at_settings(voice.handle, mix.settings)
    }
}
enum WaveExport {
    static func render(_ song: Song, _ mix: Mix) throws -> URL {
        let graph = try SignalGraph(song: song, mix: mix, frame: mix.reverse ? song.frames-1 : 0, offline: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(song.name + " — Aftertone.wav")
        var success = false
        defer { graph.engine.stop(); if !success { try? FileManager.default.removeItem(at: dir) } }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: song.sampleRate,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let output = try AVAudioFile(forWriting: url, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: 4096) else {
            throw StudioError("Couldn’t allocate an export buffer.")
        }
        try graph.engine.start()
        let latency = graph.stretch.bypass ? 0 : graph.stretch.latency
        var discard = Int64((latency + graph.limiter.latency) * song.sampleRate)
        var remaining = Int64(ceil((song.seconds + mix.tail) * song.sampleRate / mix.rate))
        var stalls = 0
        while remaining > 0 {
            let n = AVAudioFrameCount(min(4096, discard > 0 ? discard : remaining))
            switch try graph.engine.renderOffline(n, to: buffer) {
            case .success where buffer.frameLength > 0:
                if discard > 0 { discard -= Int64(buffer.frameLength) }
                else { try output.write(from: buffer); remaining -= Int64(buffer.frameLength) }
                stalls = 0
            case .cannotDoInCurrentContext where stalls < 64: stalls += 1
            default: throw StudioError("The audio engine could not finish the export.")
            }
        }
        success = true; return url
    }
}
