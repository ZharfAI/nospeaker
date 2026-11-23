import HapticEngine
import SwiftUI

struct MusicPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let music = model.music
        let on = model.playing == .music
        VStack(alignment: .leading, spacing: 0) {
            NowPlaying(music: music)

            HStack(spacing: 14) {
                Button {
                    on ? model.stop() : model.playMusic()
                } label: {
                    Text(on ? "■  STOP THE TRACKPAD" : "▶  PLAY IT THROUGH THE TRACKPAD")
                        .frame(minWidth: 300)
                }
                .buttonStyle(PrimaryStyle(active: on))
                .help("⌘↩")

                VStack(alignment: .leading, spacing: 3) {
                    Text(on ? model.stage : "music → motor, live").font(.mono(12, .bold))
                    Text(on ? "trackpad volume \(Int(model.volume * 100))%" : "the strongest notes and the kick drum")
                        .font(.mono(11))
                        .foregroundStyle(Color.dim)
                }
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                OptionRow(title: "listen to") {
                    Button("APPLE MUSIC") { model.musicSource = .appleMusic }
                        .buttonStyle(ChipStyle(selected: model.musicSource == .appleMusic, size: 11.5))
                    Button("EVERYTHING ON THIS MAC") { model.musicSource = .everything }
                        .buttonStyle(ChipStyle(selected: model.musicSource == .everything, size: 11.5))
                }
                OptionRow(title: "speakers") {
                    Button("OFF · TRACKPAD ONLY") { model.speakersToo = false }
                        .buttonStyle(ChipStyle(selected: model.musicSource == .appleMusic && !model.speakersToo, size: 11.5))
                    Button("ON TOO") { model.speakersToo = true }
                        .buttonStyle(ChipStyle(selected: model.musicSource == .everything || model.speakersToo, size: 11.5))
                }
                .disabled(model.musicSource == .everything)
                if model.musicSource == .everything {
                    Text("from every app, so the speakers stay on: mute your Mac to hear only the trackpad")
                        .font(.mono(11))
                        .foregroundStyle(Color.dim)
                        .padding(.leading, 104)
                }
            }
            .padding(.top, 20)

            SectionRule(title: "What the motor plays", trailing: "100 hz – 4 khz").padding(.top, 24)
            Spectrum().padding(.top, 12)

            ProblemLine(problem: model.problem, music: music, listeningSince: on ? model.startedAt : nil)
                .padding(.top, 14)
            Spacer(minLength: 0)
        }
    }
}

struct OptionRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.mono(10.5, .bold))
                .tracking(1.2)
                .foregroundStyle(Color.mid)
                .frame(width: 96, alignment: .leading)
            content
        }
    }
}

// MARK: - Now playing

struct NowPlaying: View {
    let music: MusicApp

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Artwork(image: music.artwork)
            VStack(alignment: .leading, spacing: 6) {
                Text("NOW PLAYING IN MUSIC")
                    .font(.mono(10.5, .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.mid)
                switch music.state {
                case .notRunning:
                    Text("Music isn't open").font(.mono(22, .bold))
                    Text("open it, start a song, and play it through the trackpad")
                        .font(.mono(12)).foregroundStyle(Color.mid)
                    Button("OPEN MUSIC", action: music.open)
                        .buttonStyle(ChipStyle(size: 11.5))
                        .padding(.top, 8)
                case .stopped:
                    Text("Nothing playing").font(.mono(22, .bold))
                    Text("start a song in Music").font(.mono(12)).foregroundStyle(Color.mid)
                    transport.padding(.top, 8)
                default:
                    Text(music.title.isEmpty ? "Playing in Music" : music.title)
                        .font(.mono(22, .bold))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text([music.artist, music.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.mono(12))
                        .foregroundStyle(Color.mid)
                        .lineLimit(1)
                    Progress(music: music).padding(.top, 4)
                    transport.padding(.top, 6)
                }
                if music.notAllowed {
                    Text("macOS blocked NoSpeaker from asking Music what's playing. Allow it in System Settings › Privacy & Security › Automation.")
                        .font(.mono(11)).foregroundStyle(Color.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button("|◀◀", action: music.previous)
                .buttonStyle(ChipStyle(size: 12))
                .accessibilityLabel("Previous song")
            Button(music.state == .playing ? "❚❚  PAUSE" : "▶  PLAY", action: music.playPause)
                .buttonStyle(ChipStyle(selected: music.state == .playing, size: 12))
                .frame(minWidth: 96)
            Button("▶▶|", action: music.next)
                .buttonStyle(ChipStyle(size: 12))
                .accessibilityLabel("Next song")
        }
    }
}

struct Progress: View {
    let music: MusicApp

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let at = music.elapsed(at: context.date)
            HStack(spacing: 10) {
                Text(asciiBar(music.duration > 0 ? at / music.duration : 0, columns: 30))
                Text("\(clock(at)) / \(clock(music.duration))").foregroundStyle(Color.mid).monospacedDigit()
            }
            .font(.mono(12))
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The album art in the show's mono, framed by a hairline; an ASCII note when there isn't any.
struct Artwork: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            Color.wash
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .grayscale(1)
                    .contrast(1.08)
            } else {
                VStack(spacing: 6) {
                    Text("♪").font(.system(size: 54, weight: .light))
                    Text("no artwork").font(.mono(10.5))
                }
                .foregroundStyle(Color.rule)
            }
        }
        .frame(width: 150, height: 150)
        .clipped()
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - The spectrum

/// The tones on the motor, as ASCII shading along a log scale from 100 Hz to 4 kHz.
struct Spectrum: View {
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model
    @State private var columns = 72
    private static let rows = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sample == nil && model.playing == nil)) { _ in
            let live = sample ?? Haptics.shared.snapshot()
            let t = sample == nil ? Haptics.shared.time : live.lastPlay
            let on = t - live.lastPlay < 0.1
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<Self.rows, id: \.self) { row in
                    Text(strip(live, on: on, row: row)).lineLimit(1).fixedSize()
                }
                Text(axis)
                    .foregroundStyle(Color.dim)
                    .lineLimit(1)
                    .fixedSize()
                HStack(spacing: 0) {
                    Text("input  ").foregroundStyle(Color.dim)
                    Text(asciiBar(live.input, columns: 24)).foregroundStyle(live.input > 0.02 ? Color.ink : Color.faint)
                    Spacer()
                    Text(on ? "\(live.tones.count) tones · 1 motor · 0 speakers" : "motor idle").foregroundStyle(Color.mid)
                }
                .padding(.top, 6)
            }
            .font(.mono(12))
        }
        .onGeometryChange(for: Int.self) { proxy in
            // One column per character of 12-pt monospace (0.6 em wide).
            max(40, Int(proxy.size.width / (12 * 0.62)) - 2)
        } action: { columns = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spectrum of what the motor plays")
    }

    /// Rows stacked bottom up, so louder tones stand taller; the loudest reaches the top at full strength.
    private func strip(_ live: LiveState, on: Bool, row: Int) -> AttributedString {
        var out = AttributedString()
        let loudest = max(live.tones.map(\.amp).max() ?? 0, 0.0001)
        let rows = Double(Self.rows)
        for x in 0..<columns {
            let fx = 100 * pow(40, Double(x) / Double(columns - 1))
            var v = 0.0
            if on {
                for tone in live.tones where tone.hz > 0 { v = max(v, (tone.amp / loudest) * exp(-pow(log(fx / tone.hz) / 0.09, 2))) }
                v *= 0.35 + 0.65 * live.level
            }
            let floor = (rows - 1 - Double(row)) / rows
            let local = max(0, min(1, (v - floor) * rows))
            let c = shade(local)
            var piece = AttributedString(String(c == " " ? (row == Self.rows - 1 ? "." : " ") : c))
            piece.foregroundColor = c == " " ? Color.faint : Color.ink
            out += piece
        }
        return out
    }

    private var axis: String {
        var chars = Array(String(repeating: " ", count: columns))
        for (hz, name) in [(100.0, "100"), (250, "250"), (500, "500"), (1000, "1k"), (2000, "2k"), (4000, "4k")] {
            let x = Int((log(hz / 100) / log(40) * Double(columns - 1)).rounded())
            let start = max(0, min(columns - name.count, x - name.count / 2))
            for (i, ch) in name.enumerated() { chars[start + i] = ch }
        }
        return String(chars)
    }
}

// MARK: - Problems, in plain words

struct ProblemLine: View {
    let problem: String?
    let music: MusicApp
    let listeningSince: Date?
    @Environment(\.liveSample) private var sample

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = sample ?? Haptics.shared.snapshot()
            if let problem {
                line(problem)
            } else if let since = listeningSince, context.date.timeIntervalSince(since) > 3, music.state == .playing,
                      live.input < 0.001, live.stage == "listening" {
                // Music says it's playing, but no sound arrives: macOS hasn't allowed the recording.
                HStack(spacing: 12) {
                    line("No sound is reaching NoSpeaker. Allow it under Screen & System Audio Recording.")
                    Button("OPEN SETTINGS") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                    }
                    .buttonStyle(ChipStyle(size: 11))
                }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text("! " + text)
            .font(.mono(11.5, .bold))
            .foregroundStyle(Color.alarm)
            .fixedSize(horizontal: false, vertical: true)
    }
}
