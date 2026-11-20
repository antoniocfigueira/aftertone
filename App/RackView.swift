import SwiftUI

private struct Parameter: View {
    let name: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var unit = ""
    var scale = 1.0
    var step = 0.01
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text(String(format: format,value*scale) + unit).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value,in: range,step: step).accessibilityLabel(name)
        }
    }
}
private struct Module<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 15) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: icon).frame(width: 24)
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption).rotationEffect(.degrees(expanded ? 180 : 0))
                }.contentShape(Rectangle())
            }
            if expanded { content.transition(.opacity.combined(with: .move(edge: .top))) }
        }.padding(17).glassPanel(20)
    }
}
struct RackView: View {
    @EnvironmentObject var p: Transport
    @State private var confirmReset = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 14) {
                HStack {
                    Text("Effects").font(.largeTitle.bold()).tracking(-1.5); Spacer()
                    Button("Reset") { confirmReset = true }.disabled(p.song == nil)
                }
                if let song = p.song {
                    HStack {
                        Image(systemName: "waveform")
                        Text(song.name).font(.subheadline.bold()).lineLimit(1); Spacer()
                        Button { p.toggle() } label: { Image(systemName: p.playing ? "pause.fill" : "play.fill").padding(8) }
                            .accessibilityLabel(p.playing ? "Pause" : "Play")
                    }.padding(.horizontal,5)
                    HStack {
                        VStack(alignment: .leading,spacing: 6) {
                            Label("Magic",systemImage: "sparkles").font(.title2.bold())
                            Text("Saturation · Compression · Tone").font(.caption)
                            Text("\(Int(p.mix.magic*100))%").monospacedDigit().font(.headline).foregroundStyle(sea)
                        }; Spacer(); Dial(value: $p.mix.magic)
                    }.foregroundStyle(.white).padding(18).background(ink,in: RoundedRectangle(cornerRadius: 23))
                    Module(title: "Speed & pitch",icon: "speedometer") {
                        Parameter(name: "Tempo",value: $p.mix.rate,range: 0.25...3,format: "%.2f",unit: "×")
                        Toggle("Keep pitch when changing speed",isOn: $p.mix.lockPitch)
                        Parameter(name: "Pitch offset",value: $p.mix.pitch,range: -12...12,format: "%+.1f",unit: " st",step: 0.1)
                        Toggle("Reverse playback",isOn: $p.mix.reverse)
                    }
                    Module(title: "10-band equalizer",icon: "slider.vertical.3") {
                        ForEach(Mix.frequencies.indices,id: \.self) { i in
                            Parameter(name: "\(Mix.frequencies[i]) Hz",value: $p.mix.eq[i],range: -15...15,format: "%+.1f",unit: " dB",step: 0.1)
                        }
                    }
                    Module(title: "Distortion",icon: "waveform.path.ecg") {
                        Parameter(name: "Full-band drive",value: $p.mix.drive,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                        ForEach(0..<3,id: \.self) { i in
                            Parameter(name: ["Low · below 220 Hz","Mid · 220 Hz–3.2 kHz","High · above 3.2 kHz"][i],
                                      value: $p.mix.bandDrive[i],range: 0...1,format: "%.0f",unit: "%",scale: 100)
                        }
                    }
                    Module(title: "Reverb",icon: "dot.radiowaves.left.and.right") {
                        Picker("Space",selection: $p.mix.space) {
                            ForEach(Mix.spaces.indices,id: \.self) { i in Text(Mix.spaces[i]).tag(i) }
                        }.pickerStyle(.segmented)
                        Parameter(name: "Wet mix",value: $p.mix.wet,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                        Parameter(name: "Room size",value: $p.mix.size,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                        Parameter(name: "Damping",value: $p.mix.damping,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                        Parameter(name: "Return low cut",value: $p.mix.lowCut,range: 20...1600,format: "%.0f",unit: " Hz",step: 10)
                        Parameter(name: "Return high cut",value: $p.mix.highCut,range: 1800...20000,format: "%.0f",unit: " Hz",step: 100)
                    }
                    Module(title: "Stereo & output",icon: "speaker.wave.2") {
                        Parameter(name: "Width",value: $p.mix.width,range: 0...2,format: "%.0f",unit: "%",scale: 100)
                        Button(p.mix.width == 0 ? "Restore stereo" : "Sum to mono") { p.mix.width = p.mix.width == 0 ? 1 : 0 }
                            .buttonStyle(.bordered)
                        Parameter(name: "Protected preamp",value: $p.mix.preamp,range: -18...18,format: "%+.1f",unit: " dB",step: 0.1)
                        Text("A stereo-linked limiter controls peaks as you raise the gain.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { Task { await p.export() } } label: {
                        Label(p.exporting ? "Rendering…" : "Export processed WAV",systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).padding().glassPanel(18)
                    }.disabled(p.exporting)
                } else {
                    ContentUnavailableView("Choose a track",systemImage: "slider.horizontal.3",description: Text("Open a track in the library to edit its sound."))
                }
            }.padding(20)
        }
        .confirmationDialog("Restore this track’s speed, pitch and effects to their defaults?",isPresented: $confirmReset,titleVisibility: .visible) {
            Button("Reset track settings",role: .destructive) { p.mix = Mix() }
        }
    }
}

