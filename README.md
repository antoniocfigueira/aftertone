# Aftertone

Aftertone is a local music player and effects studio for iPhone, targeting iOS 17 and newer. The player uses native Liquid Glass on iOS 26 and translucent materials on earlier releases. Audio import, analysis, cover selection and export run on the device.

## Build your IPA from Windows

1. Sign in to GitHub Desktop. Choose **File → New repository**, name it **Aftertone**, and choose a location outside your current project.
2. Copy all the files from the Aftertone source ZIP into that new repository. At the top level you should see `App`, `Audio`, `Build`, `Tests`, `project.yml`, and `.github`. Include the dot-prefixed files and folders.
3. In GitHub Desktop, commit the files to the default branch, then choose **Publish repository**. You can keep the repository private.
4. Open the repository on github.com. Under **Actions → Build iPhone app**, choose **Run workflow**. The workflow runs audio checks, builds the decoders and app, and packages the iPhone binary. Its first build compiles FFmpeg from source. Later builds can reuse the decoder cache.
5. Open the successful run and download the **Aftertone-iPhone** artifact. Extract the ZIP to get **Aftertone.ipa**.
6. Upload the IPA to your Signulous signing dashboard, sign it for your registered iPhone, and install it. The workflow produces an unsigned device IPA for this step.

See [GitHub’s manual workflow instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) and [Signulous](https://www.signulous.com/).

## Play and edit a track

- Tap **+** to pick one or more files in Files. Aftertone makes a local stereo floating-point working copy at the source sample rate. At 44.1 kHz this uses about 20 MiB per minute. Removing a track in its library menu releases that copy.
- Use the player to seek, skip or repeat. Open Visualizer from the floating dock to switch between Waveform, Scope and Spectrum. The full waveform represents the source. Scope and Spectrum use the live output. BPM and key are estimates of the original recording. Silence or weak evidence can produce an unknown result.
- Use the **Library** folder button to create or edit a named, colored folder or playlist. A song’s **…** menu assigns its folder, toggles playlist membership or changes its cover. Playing a track from a filtered collection uses those tracks as the playback queue.
- Open **Effects** to change the current track. Speed ranges from 0.25× to 3×. Choose Independent for separate pitch and tempo adjustments. In Linked · tape mode, dragging either control updates the other. The pitch offset also works at a fixed tempo. Large stretches can introduce audible artifacts.
- The rack has ten draggable parametric EQ bands with adjustable frequency, gain and Q, full-band and three-band saturation, four reverb spaces with wet-return low/high cuts, stereo width, mono and a peak-limited preamp. Drag the **Magic** dial vertically to blend compression, saturation and tonal shaping. **Reset** restores the current track’s defaults.
- Tap the export icon or **Export processed WAV** and select a destination in Files. Playback and export use the same effects graph. Export writes a separate 24-bit stereo WAV at the track’s sample rate, with the selected rate, direction and reverb tail. A limiter reduces peaks when boosting hot material. The imported source file stays intact.
- Open Settings using the gear to choose light, dark or system appearance and toggle the music-reactive sphere.

## Player and library gestures

Hold the player’s progress rail or the visualizer waveform to magnify a five-times narrower window. Drag to preview the time and release to seek. The info button reveals source key and tempo. Playback controls stay below the scrolling content. The scope and spectrum use output render callbacks and target 60 frames per second while the display is active.

The Albums view groups imported tracks by album and artist tags. An untagged recording appears as a single until assigned an album through the track menu. Choosing a track keeps the library open. System media commands support playback, seeking and moving through the current queue while the screen is locked.

The Tone section includes draggable EQ points and two adjustable multiband drive crossovers. Space offers independent dry and wet levels and a size/damping touch pad. Existing saved mixes retain their original EQ centers, filter Q, crossovers and reverb balance.

## File support and implementation

The decoder supports common unprotected formats including MP3, WAV, AIFF, M4A/AAC, ALAC, FLAC, Ogg Vorbis, Opus and WMA. Import tests the actual file contents and falls back to Apple’s system decoder. Encrypted media, damaged files and unsupported codecs can fail. Surround material is mixed to stereo.

The app uses SwiftUI, AVAudioEngine, a C DSP rack and a source-built FFmpeg decoder. The room and plate modes are algorithmic reverb tunings. The Magic processor is an original effect. A mapped PCM file supplies forward and reverse playback. Speed and pitch use Apple’s Varispeed and Time Pitch units. Musical analysis combines onset autocorrelation with spectral pitch-class matching.

The build uses unmodified [FFmpeg 8.1.3 source](https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz) with LGPL components. Its [license](App/FFmpeg-LICENSE.txt) is included in the app. The decoder configuration and link settings are in [decoder.sh](Build/decoder.sh) and [project.yml](project.yml). To rebuild with a modified compatible decoder, provide its headers and static libraries under `.build/decoder` and run the project-generation and compilation steps from the workflow.

## Verification

The portable C checks cover neutral rendering, reverse, mono, gain limiting, reverb tails, spectrum, silence and a 120 BPM C-major fixture. The workflow also renders a reference track through the Apple audio engine on macOS and checks WAV duration and output frequency in neutral, pitch-locked, tape-speed and reverse modes. Signing, device playback, Files access and listening quality require testing on the target iPhone.


The UI bundles Plus Jakarta Sans and Space Grotesk for offline use. Their SIL Open Font Licenses are included in `App/Fonts`.
