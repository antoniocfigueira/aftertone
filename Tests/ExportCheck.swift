import AVFoundation
import Foundation

@main struct ExportCheck {
    static func main() throws {
        let rate = 48000, frames = 96000
        let song = Song(name: "Export check", ext: "PCM", sampleRate: Double(rate),
                        frames: Int64(frames), overview: [], bpm: 0, key: -1)
        try FileManager.default.createDirectory(at: Song.directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: song.pcm) }
        var raw = [Float](repeating: 0, count: frames*2)
        for i in 0..<frames {
            let hz = i < frames/2 ? 330.0 : 660.0
            let sample = Float(0.28 * sin(2 * .pi * hz * Double(i) / Double(rate)))
            raw[i*2] = sample; raw[i*2 + 1] = sample
        }
        try raw.withUnsafeBytes { try Data($0).write(to: song.pcm) }
        for (speed, locked, reverse, expected) in [(1.0,true,false,330.0),(0.75,true,false,330.0),
                (1.5,false,false,495.0),(1.0,true,true,660.0)] {
            var mix = Mix()
            mix.rate = speed; mix.lockPitch = locked; mix.reverse = reverse
            let file = try WaveExport.render(song, mix)
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let audio = try AVAudioFile(forReading: file)
            precondition(abs(Double(audio.length) - Double(frames)/speed) <= 1, "Incorrect WAV duration")
            audio.framePosition = 12000
            let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 12000)!
            try audio.read(into: buffer)
            let samples = buffer.floatChannelData![0]
            var crossings = 0
            for i in 1..<Int(buffer.frameLength) where samples[i-1] < 0 && samples[i] >= 0 { crossings += 1 }
            let measured = Double(crossings) * Double(rate) / Double(buffer.frameLength)
            precondition(abs(measured-expected) < 12, "Unexpected frequency \(measured) Hz for \(speed)×")
        }
        print("WAV length, reverse, pitch lock and linked-speed checks passed.")
    }
}

