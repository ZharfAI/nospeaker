import HapticEngine
import SwiftUI

// MARK: - Say

/// Lines to try, from the terminal show.
let saySuggestions = ["can you hear me?", "please stop clicking me", "this is not a speaker", "nobody believes me",
                      "i live under the glass", "hello from the trackpad"]

struct SayPanel: View {
    @Environment(AppModel.self) private var model
    @FocusState private var typing: Bool

    var body: some View {
        @Bindable var model = model
        let speaking = model.playing == .say
        VStack(alignment: .leading, spacing: 0) {
            Text("▸ SAY ANYTHING").font(.mono(13, .bold))
            Text("type a line and press return. the trackpad says it, in any of your Mac's voices.")
                .font(.mono(12))
                .foregroundStyle(Color.mid)
                .padding(.top, 4)

            HStack(spacing: 10) {
                Text(">").font(.mono(16, .bold)).foregroundStyle(Color.mid)
                TextField("", text: $model.sayText, prompt: Text("hello there").foregroundStyle(Color.faint))
                    .textFieldStyle(.plain)
                    .font(.mono(17, .bold))
                    .focused($typing)
                    .onSubmit(model.say)
                    .accessibilityLabel("Line to say")
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .overlay(Rectangle().strokeBorder(typing ? Color.ink : Color.rule, lineWidth: typing ? 1.5 : 1))
            .padding(.top, 16)

            HStack(spacing: 6) {
                Text("TRY").font(.mono(10.5, .bold)).tracking(1.2).foregroundStyle(Color.dim)
                ForEach(saySuggestions.prefix(4), id: \.self) { line in
                    Button(line) { model.sayText = line; model.say() }
                        .buttonStyle(ChipStyle(size: 11, padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)))
                }
            }
            .padding(.top, 10)

            HStack(spacing: 12) {
                OptionRow(title: "voice") {
                    Menu {
                        Button("Your Mac's default voice") { model.voiceName = nil }
                        Divider()
                        ForEach(model.voices) { voice in
                            Button("\(voice.name)  ·  \(voice.locale)") { model.voiceName = voice.name }
                        }
                    } label: {
                        Text((model.voiceName ?? "default") + "  ▾").font(.mono(12))
                    }
                    .menuStyle(.button)
                    .buttonStyle(ChipStyle(size: 12))
                    .fixedSize()
                }
                Spacer()
                Button {
                    speaking ? model.stop() : model.say()
                } label: {
                    Text(speaking ? "■  STOP" : "SAY IT  ↵").frame(minWidth: 150)
                }
                .buttonStyle(PrimaryStyle(active: speaking))
                .disabled(!speaking && model.sayText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 18)

            SectionRule(title: "What it's saying").padding(.top, 26)
            Caption().padding(.top, 14)
            Formants().padding(.top, 16)
            Spacer(minLength: 0)
        }
        .onAppear { typing = true }
    }
}

/// The line as it's spoken, typed out in step with the voice.
struct Caption: View {
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sample == nil && model.playing == nil)) { context in
            let live = sample ?? Haptics.shared.snapshot()
            let t = sample == nil ? Haptics.shared.time : live.captionStart + live.captionDuration * 0.6
            let progress = live.caption.isEmpty ? 0 : min(1, (t - live.captionStart) / max(0.2, live.captionDuration) * 1.15)
            let shown = String(live.caption.prefix(Int(Double(live.caption.count) * progress)))
            let caret = progress >= 1 ? "”" : Int(context.date.timeIntervalSinceReferenceDate * 3) % 2 == 0 ? "█" : " "
            Text(live.caption.isEmpty ? "“…”" : "“" + shown + caret)
                .font(.mono(20, .bold))
                .foregroundStyle(live.caption.isEmpty ? Color.faint : Color.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        }
    }
}

/// F0, F1 and F2: the voice's pitch and its two strongest resonances, as the motor plays them.
struct Formants: View {
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sample == nil && model.playing == nil)) { _ in
            let live = sample ?? Haptics.shared.snapshot()
            VStack(alignment: .leading, spacing: 5) {
                meter("F0", live.f0, 60, 260, "pitch")
                meter("F1", live.f1, 150, 1000, "first formant")
                meter("F2", live.f2, 600, 2800, "second formant")
            }
            .font(.mono(12))
        }
        .accessibilityHidden(true)
    }

    private func meter(_ label: String, _ value: Double, _ lo: Double, _ hi: Double, _ name: String) -> some View {
        HStack(spacing: 10) {
            Text(label).bold().frame(width: 24, alignment: .leading)
            Text(asciiBar(value > 0 ? (value - lo) / (hi - lo) : 0, columns: 44)).foregroundStyle(value > 0 ? Color.ink : Color.faint)
            Text(value > 0 ? String(format: "%5.0f hz", value) : "    -   ").foregroundStyle(value > 0 ? Color.ink : Color.dim)
            Text(name).foregroundStyle(Color.dim)
        }
    }
}

// MARK: - Play (the instrument)

struct PlayPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Side by side when there's room, stacked when the window is narrow.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 30) { pad; controls; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 22) { pad; controls }
        }
    }

    private var pad: some View {
        TouchPad(active: model.playing == .instrument)
            .frame(width: 380, height: 250)
    }

    private var controls: some View {
        let on = model.playing == .instrument
        return VStack(alignment: .leading, spacing: 0) {
            Text("TOUCH TO PLAY").font(.mono(13, .bold))
            VStack(alignment: .leading, spacing: 4) {
                Text("slide left / right    pitch")
                Text("move up               vibrato")
                Text("more finger           louder")
            }
            .font(.mono(12))
            .foregroundStyle(Color.body)
            .padding(.top, 12)
            Text("glide lightly, no need to click. it plays on the trackpad you touch, through the trackpads chosen on the left.")
                .font(.mono(11))
                .foregroundStyle(Color.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            NoteReadout().padding(.top, 18)
            Button {
                on ? model.stop() : model.play(.instrument)
            } label: {
                Text(on ? "■  STOP" : "▶  START THE INSTRUMENT").frame(minWidth: 240)
            }
            .buttonStyle(PrimaryStyle(active: on))
            .padding(.top, 20)
        }
        .frame(width: 330, alignment: .leading)
    }
}

/// The trackpad, drawn: where your finger is, with a short trail.
struct TouchPad: View {
    let active: Bool
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model
    @State private var trail: [CGPoint] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: sample == nil && model.playing == nil)) { _ in
            let live = sample ?? Haptics.shared.snapshot()
            Canvas { context, size in
                let inset = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                context.stroke(Path(roundedRect: inset, cornerRadius: 14), with: .color(live.touchDown ? .ink : .rule), lineWidth: live.touchDown ? 1.5 : 1)
                // Note names along the bottom, where they sit under your finger.
                let names = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"]
                for (i, name) in names.enumerated() {
                    let x = inset.minX + (CGFloat(i) + 0.5) / CGFloat(names.count) * inset.width
                    context.draw(Text(name).font(.mono(10)).foregroundStyle(Color.dim), at: CGPoint(x: x, y: inset.maxY - 14))
                    if i > 0 {
                        let gx = inset.minX + CGFloat(i) / CGFloat(names.count) * inset.width
                        context.stroke(Path { $0.move(to: CGPoint(x: gx, y: inset.maxY - 26)); $0.addLine(to: CGPoint(x: gx, y: inset.maxY - 4)) },
                                       with: .color(.faint), lineWidth: 1)
                    }
                }
                for (k, point) in trail.enumerated() {
                    let r = 3 + CGFloat(k) / CGFloat(max(1, trail.count)) * 5
                    context.fill(Path(ellipseIn: CGRect(x: point.x * size.width - r, y: (1 - point.y) * size.height - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.mix(0.25 + 0.6 * Double(k) / Double(max(1, trail.count)))))
                }
                if live.touchDown {
                    let p = CGPoint(x: live.touchX * size.width, y: (1 - live.touchY) * size.height)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(.ink))
                } else {
                    context.draw(Text(active ? "put a finger on the trackpad" : "press start, then touch the trackpad")
                        .font(.mono(12, .bold)).foregroundStyle(active ? Color.ink : Color.dim),
                                 at: CGPoint(x: size.width / 2, y: size.height / 2 - 10))
                }
            }
            .onChange(of: live.touchDown ? CGPoint(x: live.touchX, y: live.touchY) : nil) { _, point in
                if let point { trail.append(point); if trail.count > 16 { trail.removeFirst() } } else { trail.removeAll() }
            }
        }
        .accessibilityLabel("Trackpad drawing")
    }
}

struct NoteReadout: View {
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sample == nil && model.playing == nil)) { _ in
            let live = sample ?? Haptics.shared.snapshot()
            let t = sample == nil ? Haptics.shared.time : live.lastPlay
            let on = t - live.lastPlay < 0.08 && !live.note.isEmpty
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("note").font(.mono(11)).foregroundStyle(Color.dim)
                Text(on ? live.note : "–").font(.mono(34, .bold)).foregroundStyle(on ? Color.ink : Color.faint)
                if on { Text(String(format: "%4.0f hz", live.hz)).font(.mono(12)).foregroundStyle(Color.mid) }
            }
        }
    }
}

// MARK: - Show

struct ShowPanel: View {
    @Environment(AppModel.self) private var model

    private struct Item: Identifiable {
        let piece: Piece
        let title: String
        let length: String
        let blurb: String
        let art: String
        var id: String { title }
    }

    private let items: [Item] = [
        Item(piece: .show, title: "THE WHOLE SHOW", length: "about a minute",
             blurb: "heartbeat, first words, sweep, melody, beat and rap, goodbye",
             art: "  _   __ ____\n / | / // __ \\\n/  |/ // / / /\n/ /|  // /_/ /\n/_/ |_/ \\____/"),
        Item(piece: .heartbeat, title: "HEARTBEAT", length: "4 s", blurb: "the motor waking up: thumps you feel and hear",
             art: ",d88b.d88b,\n88888888888\n`Y8888888Y'\n  `Y888Y'\n    `Y'"),
        Item(piece: .sweep, title: "SWEEP", length: "6 s", blurb: "a rising tone, 100 Hz to 4 kHz: its whole range",
             art: "        .-.  .\n   .-. /   \\/\n__/   V\n100 ───▶ 4k"),
        Item(piece: .melody, title: "MELODY", length: "10 s", blurb: "an original hook in its loudest, cleanest octave",
             art: "C7 ·····=·\nA6 ··==··=\nG6 ·=··==·\nE6 =·····="),
        Item(piece: .beat, title: "BEAT + RAP", length: "10 s", blurb: "kick, snare, hats and bass, then a rapped line",
             art: "K X.........X..x\nS ....X.......X.\nH x.x.x.x.x.x.xx"),
        Item(piece: .sparkle, title: "SPARKLE", length: "1 s", blurb: "an arpeggio up, then its purest note",
             art: "      *\n   *  |  *\n *  \\ | /  *\n  -- (o) --"),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(items) { item in
                    ShowCard(title: item.title, length: item.length, blurb: item.blurb, art: item.art,
                             playing: model.playing == item.piece.kind) {
                        model.toggle(item.piece)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

struct ShowCard: View {
    let title: String
    let length: String
    let blurb: String
    let art: String
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(art)
                    .font(.mono(11, .bold))
                    .foregroundStyle(playing ? Color.paper : Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                HStack {
                    Text(title).font(.mono(13, .bold))
                    Spacer()
                    Text(playing ? "■ stop" : length).font(.mono(11))
                        .foregroundStyle(playing ? Color.paper : Color.dim)
                }
                .padding(.top, 12)
                Text(blurb)
                    .font(.mono(11))
                    .foregroundStyle(playing ? Color.paper.opacity(0.75) : Color.mid)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 4)
            }
            .foregroundStyle(playing ? Color.paper : Color.ink)
            .padding(16)
            .background(playing ? Color.ink : hovering ? Color.wash : Color.clear)
            .overlay(Rectangle().strokeBorder(playing || hovering ? Color.ink : Color.faint, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(playing ? "Stop \(title.lowercased())" : "Play \(title.lowercased()), \(length)")
    }
}
