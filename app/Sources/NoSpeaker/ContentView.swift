import HapticEngine
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Lockup(size: 10.5)
                .frame(maxWidth: .infinity)
                .padding(.top, 34)
                .padding(.bottom, 22)
            Hairline()
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 268)
                Hairline(vertical: true)
                VStack(spacing: 0) {
                    TabBar()
                    Hairline()
                    panel
                        .padding(.horizontal, 32)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            Hairline()
            StatusBar()
            Marquee()
        }
        .background(Color.paper)
        .foregroundStyle(Color.ink)
        .ignoresSafeArea(.container, edges: .top)
        .task { await model.follow() }
        .background(EscapeKey { model.stop() })
    }

    @ViewBuilder private var panel: some View {
        switch model.tab {
        case .music: MusicPanel()
        case .say: SayPanel()
        case .play: PlayPanel()
        case .show: ShowPanel()
        }
    }
}

// MARK: - Tabs

struct TabBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppModel.Tab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    Text(String(format: "%02d  ", tab.number) + tab.rawValue.uppercased())
                }
                .buttonStyle(ChipStyle(selected: model.tab == tab, size: 12, padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)))
                .keyboardShortcut(KeyEquivalent(Character(String(tab.number))), modifiers: .command)
                .accessibilityLabel(tab.rawValue.capitalized)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
            Spacer()
            if let playing = model.playing {
                PlayingBadge(kind: playing, stage: model.stage)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }
}

/// "● PLAYING · music — waiting for music", with a dot that pulses.
struct PlayingBadge: View {
    let kind: Piece.Kind
    let stage: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2.5) % 2 == 0
            HStack(spacing: 6) {
                Text(on ? "●" : "○").foregroundStyle(Color.ink)
                Text(kind.rawValue.uppercased()).bold()
                if !stage.isEmpty { Text("· " + stage).foregroundStyle(Color.mid) }
            }
            .font(.mono(11.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playing \(kind.rawValue), \(stage)")
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(title: "Output", trailing: "\(model.trackpads.count) found")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppModel.Output.allCases) { option in
                    OutputRow(option: option)
                }
            }
            .padding(.top, 10)
            Button("rescan", action: model.rescan)
                .disabled(model.playing != nil)
                .buttonStyle(.plain)
                .font(.mono(11))
                .foregroundStyle(Color.dim)
                .padding(.top, 6)
                .padding(.leading, 2)

            SectionRule(title: "Volume").padding(.top, 26)
            AsciiSlider(value: $model.volume, columns: 20, label: "Trackpad volume")
                .padding(.top, 10)

            SectionRule(title: "Motor").padding(.top, 26)
            MotorReadout().padding(.top, 10)

            Spacer(minLength: 20)

            Button {
                model.stop()
            } label: {
                HStack {
                    Text("■  STOP")
                    Spacer()
                    Text("esc").foregroundStyle(Color.paper.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryStyle())
            .disabled(model.playing == nil)
            .help("Stop (esc or ⌘.)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct OutputRow: View {
    @Environment(AppModel.self) private var model
    let option: AppModel.Output
    @State private var hovering = false

    var body: some View {
        let available = model.isAvailable(option)
        let chosen = model.output == option
        Button {
            model.output = option
        } label: {
            HStack(spacing: 10) {
                Text(chosen ? "[■]" : "[ ]")
                    .foregroundStyle(available ? Color.ink : Color.faint)
                Text(option.title)
                    .fontWeight(chosen ? .bold : .regular)
                    .foregroundStyle(available ? Color.ink : Color.dim)
                Spacer()
                if !available {
                    Text("not here").foregroundStyle(Color.dim).font(.mono(10.5))
                }
            }
            .font(.mono(12.5))
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(hovering && available ? Color.wash : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The motor, live: its frequency, its strength, and how many times it has moved.
struct MotorReadout: View {
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sample == nil && model.playing == nil)) { _ in
            let live = sample ?? Haptics.shared.snapshot()
            let t = sample == nil ? Haptics.shared.time : live.lastPlay
            let active = t - live.lastPlay < 0.08
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(active ? String(format: "%.0f", live.hz) : "idle")
                        .font(.mono(30, .bold))
                        .monospacedDigit()
                        .foregroundStyle(active ? Color.ink : Color.faint)
                    if active { Text("hz").font(.mono(13)).foregroundStyle(Color.mid) }
                }
                Text(asciiBar(active ? live.level : 0, columns: 26))
                    .font(.mono(12))
                    .foregroundStyle(active ? Color.ink : Color.faint)
                Text("vibrations  \(live.actuations.formatted())")
                    .font(.mono(11))
                    .foregroundStyle(Color.dim)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(active ? "Motor at \(Int(live.hz)) hertz" : "Motor idle")
        }
    }
}

// MARK: - Status bar and scroller

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: " %02d/%02d ", model.tab.number, AppModel.Tab.allCases.count))
                .font(.mono(11.5, .bold))
                .foregroundStyle(Color.paper)
                .background(Color.ink)
            Text(model.tab.rawValue.uppercased()).font(.mono(11.5, .bold))
            Text("·").foregroundStyle(Color.dim)
            Text(model.chosenTrackpads.isEmpty ? "no trackpad" : model.chosenTrackpads.map(\.name).joined(separator: " + "))
                .font(.mono(11.5))
                .foregroundStyle(Color.mid)
            Spacer()
            SpeakerChip(muted: model.speakersMuted)
        }
        .padding(.horizontal, 20)
        .frame(height: 34)
    }
}

/// The proof: speakers muted, or a blinking reminder to mute.
struct SpeakerChip: View {
    let muted: Bool?

    var body: some View {
        if let muted {
            TimelineView(.animation(minimumInterval: 1.0 / 5)) { context in
                let blink = !muted && Int(context.date.timeIntervalSinceReferenceDate * 2.5) % 2 == 0
                Text(muted ? " SPEAKERS MUTED · ALL YOU HEAR IS THE TRACKPAD " : " SPEAKERS ON · MUTE YOUR MAC ")
                    .font(.mono(11, .bold))
                    .foregroundStyle(blink ? Color.ink : Color.paper)
                    .padding(.vertical, 2)
                    .background(blink ? Color.faint : Color.ink)
            }
            .help(muted ? "Your Mac's sound is off: every sound is the trackpad's motor." : "Mute your Mac to hear that it's really the trackpad.")
        }
    }
}

let scrollText = "      ·  a90.com presents  NO SPEAKER  ·    the trackpad has no speaker. every sound you hear is its haptic motor, driven through MultitouchSupport, a private macOS framework.    range: 100 to 4000 vibrations per second.    music: the strongest notes and the kick drum, retriggered every few milliseconds.    voice: two formants, retriggered on every pitch beat.    thanks for listening.    a90.com    "

/// The scroller along the bottom, stepping one character at a time, twelve a second, like the terminal show's.
/// Two copies side by side so the seam never shows; laid out once, only moved.
struct Marquee: View {
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
            let characters = CGFloat(scrollText.count)
            let step = CGFloat(Int(context.date.timeIntervalSinceReferenceDate * 12) % scrollText.count)
            HStack(spacing: 0) {
                line.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                line
            }
            .offset(x: width > 0 ? -(step * width / characters).rounded() : 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        .padding(.horizontal, 20)
        .clipped()
        .background(Color.paper)
        .accessibilityHidden(true)
    }

    private var line: some View {
        Text(scrollText)
            .font(.mono(11, .bold))
            .foregroundStyle(Color.mid)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Esc

/// Esc stops whatever is playing, wherever the keyboard focus is (when nothing plays, Esc does its usual
/// thing). A local key monitor, because focus-based handling misses tabs with nothing focusable.
struct EscapeKey: View {
    let action: () -> Void
    @State private var monitor: Any?

    var body: some View {
        Color.clear
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 53, Haptics.shared.snapshot().playing != nil else { return event }
                    action()
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

// MARK: - Sample live state for design snapshots

private struct LiveSampleKey: EnvironmentKey { static let defaultValue: LiveState? = nil }
extension EnvironmentValues {
    var liveSample: LiveState? {
        get { self[LiveSampleKey.self] }
        set { self[LiveSampleKey.self] = newValue }
    }
}
