import Foundation

struct StudioError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Mix: Codable, Equatable {
    static let frequencies = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let spaces = ["Room", "Chamber", "Plate", "Hall"]
    var rate = 1.0, pitch = 0.0, lockPitch = true, reverse = false
    var eq = Array(repeating: 0.0, count: 10)
    var bandDrive = [0.0, 0.0, 0.0]
    var drive = 0.0, width = 1.0, preamp = 0.0, magic = 0.0
    var wet = 0.0, size = 0.5, damping = 0.4, lowCut = 80.0, highCut = 12000.0
    var space = 0
    var tail: Double { wet > 0 ? 2 + 6 * size : 0 }
    var settings: ATSettings {
        var s = ATSettings()
        withUnsafeMutableBytes(of: &s.eq) { bytes in
            for i in 0..<10 { bytes.bindMemory(to: Float.self)[i] = Float(eq[i]) }
        }
        withUnsafeMutableBytes(of: &s.bandDrive) { bytes in
            for i in 0..<3 { bytes.bindMemory(to: Float.self)[i] = Float(bandDrive[i]) }
        }
        s.drive = Float(drive); s.width = Float(width); s.preampDB = Float(preamp)
        s.magic = Float(magic); s.wet = Float(wet); s.size = Float(size)
        s.damping = Float(damping); s.wetLow = Float(lowCut); s.wetHigh = Float(highCut)
        s.space = Int32(space)
        return s
    }
}
struct Song: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String, ext: String, sampleRate: Double, frames: Int64
    var overview: [Float], bpm: Int, key: Int
    var mix = Mix()
    var folder: UUID?
    var cover: String?
    var seconds: Double { Double(frames) / sampleRate }
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Aftertone", isDirectory: true)
    var pcm: URL { Self.directory.appendingPathComponent(id.uuidString + ".f32") }
    var keyName: String {
        guard key >= 0 else { return "—" }
        return ["C","D♭","D","E♭","E","F","F♯","G","A♭","A","B♭","B"][key % 12] + (key >= 12 ? " min" : " maj")
    }
}
