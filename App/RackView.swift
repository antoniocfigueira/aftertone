import SwiftUI

struct Parameter: View {
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
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack {
                Image(systemName: icon).font(.title3).foregroundStyle(twilight)
                Text(title).font(.title3.bold()).tracking(-0.6)
                Spacer()
            }
            Divider()
            content
        }.padding(16).glassPanel(20)
    }
}
struct RackView: View {
    @EnvironmentObject var p: Transport
    @State private var section = "Motion"
    @State private var confirmReset = false
    var body: some View {
        StudioScroll {
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
                    Picker("Rack section",selection: $section) {
                        ForEach(["Motion","Tone","Space","Output"],id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    if section == "Output" {
                        HStack {
                            VStack(alignment: .leading,spacing: 6) {
                                Label("Magic",systemImage: "sparkles").font(.title2.bold())
                                Text("Saturation · Compression · Tone").font(.caption)
                                Text("\(Int(p.mix.magic*100))%").monospacedDigit().font(.headline).foregroundStyle(sea)
                            }; Spacer(); Dial(value: $p.mix.magic)
                        }.foregroundStyle(.white).padding(18).background(ink,in: RoundedRectangle(cornerRadius: 23))
                    }
                    if section == "Motion" {
                        Module(title: "Speed & pitch",icon: "speedometer") {
                            Parameter(name: "Tempo",value: $p.mix.rate,range: 0.25...3,format: "%.2f",unit: "×")
                            Picker("Speed and pitch",selection: Binding(get: { p.mix.lockPitch },set: { independent in
                                var mix = p.mix
                                mix.lockPitch = independent; mix.pitch = 0; p.mix = mix
                            })) {
                                Text("Independent").tag(true); Text("Linked · tape").tag(false)
                            }.pickerStyle(.segmented)
                            Parameter(name: "Pitch",value: Binding(get: { p.mix.heardPitch },set: { p.mix.setHeardPitch($0) }),
                                      range: p.mix.lockPitch ? -12...12 : -24...(12*log2(3.0)),format: "%+.1f",unit: " st",step: 0.1)
                            Text(p.mix.lockPitch ? "Tempo and pitch can be adjusted separately." : "Tape mode links both controls. Doubling speed raises pitch one octave.")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("Reverse playback",isOn: $p.mix.reverse)
                        }
                    }
                    if section == "Tone" {
                        Module(title: "Parametric EQ",icon: "slider.vertical.3") {
                            EqualizerGraph(mix: $p.mix,sampleRate: song.sampleRate)
                        }
                        Module(title: "Distortion",icon: "waveform.path.ecg") {
                            DriveGraph(mix: $p.mix)
                            Parameter(name: "Full-band drive",value: $p.mix.drive,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                            ForEach(0..<3,id: \.self) { i in
                                Parameter(name: ["Low drive","Mid drive","High drive"][i],
                                          value: $p.mix.bandDrive[i],range: 0...1,format: "%.0f",unit: "%",scale: 100)
                            }
                        }
                    }
                    if section == "Space" {
                        Module(title: "Reverb",icon: "dot.radiowaves.left.and.right") {
                            ReverbField(mix: $p.mix)
                            Picker("Space",selection: $p.mix.space) {
                                ForEach(Mix.spaces.indices,id: \.self) { i in Text(Mix.spaces[i]).tag(i) }
                            }.pickerStyle(.segmented)
                            Parameter(name: "Dry signal",value: Binding(get: { p.mix.dryGain },set: { p.mix.dry = $0 }),
                                      range: 0...1,format: "%.0f",unit: "%",scale: 100)
                            Parameter(name: "Wet return",value: Binding(get: { p.mix.wet },set: { wet in
                                var next = p.mix; next.dry = next.dryGain; next.wet = wet; p.mix = next
                            }),range: 0...1,format: "%.0f",unit: "%",scale: 100)
                            Parameter(name: "Room size",value: $p.mix.size,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                            Parameter(name: "Damping",value: $p.mix.damping,range: 0...1,format: "%.0f",unit: "%",scale: 100)
                            Parameter(name: "Return low cut",value: $p.mix.lowCut,range: 20...1600,format: "%.0f",unit: " Hz",step: 10)
                            Parameter(name: "Return high cut",value: $p.mix.highCut,range: 1800...20000,format: "%.0f",unit: " Hz",step: 100)
                        }
                    }
                    if section == "Output" {
                        Module(title: "Stereo & output",icon: "speaker.wave.2") {
                            Parameter(name: "Width",value: $p.mix.width,range: 0...2,format: "%.0f",unit: "%",scale: 100)
                            Button(p.mix.width == 0 ? "Restore stereo" : "Sum to mono") { p.mix.width = p.mix.width == 0 ? 1 : 0 }
                                .buttonStyle(.bordered)
                            Parameter(name: "Protected preamp",value: $p.mix.preamp,range: -18...18,format: "%+.1f",unit: " dB",step: 0.1)
                            Text("A stereo-linked limiter controls peaks as you raise the gain.").font(.caption).foregroundStyle(.secondary)
                        }
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

