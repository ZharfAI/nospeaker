import AppKit
import HapticEngine
import SwiftUI

/// Everything the window shows and changes. Lives on the main actor; the engine does the timing-critical work
/// on its own threads and is read here ten times a second.
@Observable
final class AppModel {
    enum Output: String, CaseIterable, Identifiable {
        case magic, builtIn, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .magic: "Magic Trackpad"
            case .builtIn: "MacBook trackpad"
            case .both: "Both at once"
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case music, say, play, classics, show
        var id: String { rawValue }
        var number: Int { Tab.allCases.firstIndex(of: self)! + 1 }
    }

    // Output
    var trackpads: [Trackpad] = []
    var output: Output = .magic { didSet { if output != oldValue { replayOnNewOutput() } } }
    var volume = 0.6 { didSet { Haptics.shared.volume = Float(volume) } }

    // What's playing (from the engine)
    private(set) var playing: Piece.Kind?
    private(set) var stage = ""
    private(set) var problem: String?
    private(set) var speakersMuted: Bool?
    private var lastPiece: Piece?
    /// When the current piece started.
    private(set) var startedAt = Date()

    // Panels
    var tab: Tab = .music
    var sayText = ""
    var voices: [Voice] = []
    var voiceName: String?
    var musicSource: MusicSource = .appleMusic { didSet { if musicSource != oldValue { replayMusic() } } }
    var speakersToo = false { didSet { if speakersToo != oldValue { replayMusic() } } }
    /// What of the music the motor plays: the tune (one clean note), the kick drum, or both.
    var musicMelody = true { didSet { if musicMelody != oldValue { replayMusic() } } }
    var musicBeat = true { didSet { if musicBeat != oldValue { replayMusic() } } }
    let music = MusicApp()

    /// For design snapshots: no engine, no AppleScript.
    let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        Haptics.shared.volume = Float(volume)
    }

    // MARK: Trackpads

    var chosenTrackpads: [Trackpad] {
        switch output {
        case .magic: trackpads.filter { !$0.isBuiltIn }
        case .builtIn: trackpads.filter(\.isBuiltIn)
        case .both: trackpads
        }
    }

    func isAvailable(_ option: Output) -> Bool {
        switch option {
        case .magic: trackpads.contains { !$0.isBuiltIn }
        case .builtIn: trackpads.contains(where: \.isBuiltIn)
        case .both: trackpads.contains(where: \.isBuiltIn) && trackpads.contains { !$0.isBuiltIn }
        }
    }

    /// Looks for trackpads again (silent: opens and closes each motor). Keeps the choice if it's still there.
    /// Not while something plays: it would open a motor that's already playing.
    func rescan() {
        guard !preview, playing == nil else { return }
        trackpads = findTrackpads()
        if !isAvailable(output) {
            output = Output.allCases.first(where: isAvailable) ?? .magic
        }
    }

    // MARK: Playing

    func play(_ piece: Piece) {
        guard !preview else { return }
        if chosenTrackpads.isEmpty { rescan() }
        lastPiece = piece
        playing = piece.kind
        startedAt = Date()
        problem = nil
        Haptics.shared.start(piece, on: chosenTrackpads)
    }

    func toggle(_ piece: Piece) {
        if isPlaying(piece) { stop() } else { play(piece) }
    }

    /// This exact piece is playing (not just one of the same kind: every classic is a `.classic`).
    func isPlaying(_ piece: Piece) -> Bool { playing == piece.kind && lastPiece == piece }

    func stop() {
        Haptics.shared.stop()
        playing = nil
    }

    func playMusic() {
        var settings = MusicSettings()
        settings.source = musicSource
        settings.speakersToo = speakersToo
        settings.melody = musicMelody
        settings.beat = musicBeat
        play(.music(settings))
    }

    func say() {
        let words = sayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        play(.say(words, voice: voiceName))
    }

    /// The music and the instrument run until stopped, so they follow a change of trackpad; anything else
    /// just stops.
    private func replayOnNewOutput() {
        guard let lastPiece, let playing else { return }
        if playing == .music || playing == .instrument { play(lastPiece) } else { stop() }
    }

    private func replayMusic() {
        if playing == .music { playMusic() }
    }

    // MARK: Keeping up with the engine

    private var lastSpeakerCheck = Date.distantPast

    /// Runs while the window is open.
    func follow() async {
        guard !preview else { return }
        rescan()
        voices = await Self.loadVoices()
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func refresh() {
        let live = Haptics.shared.snapshot()
        if playing != live.playing { playing = live.playing }
        if stage != live.stage { stage = live.stage }
        if problem != live.problem { problem = live.problem }
        if Date().timeIntervalSince(lastSpeakerCheck) > 0.5 {
            lastSpeakerCheck = Date()
            let muted = speakersAreMuted()
            if muted != speakersMuted { speakersMuted = muted }
            if tab == .music || playing == .music { music.poll() }
        }
    }

    // MARK: Design snapshots

    /// Sample state for a snapshot of `tab`: no engine, no AppleScript.
    func showPreview(tab: Tab) {
        self.tab = tab
        trackpads = [Trackpad(id: 1, isBuiltIn: true), Trackpad(id: 2, isBuiltIn: false)]
        output = .magic
        speakersMuted = true
        music.showSample()
        voiceName = "Daniel"
        switch tab {
        case .music: playing = .music; stage = "playing"
        case .say: playing = .say; stage = "speaking"; sayText = "hello from the trackpad"
        case .play: playing = .instrument; stage = "playing"
        case .classics: playing = .classic; stage = "Für Elise · Beethoven"; lastPiece = .classic("fur-elise")
        case .show: playing = .melody; stage = "an original hook"; lastPiece = .melody
        }
    }

    @concurrent
    private static func loadVoices() async -> [Voice] { installedVoices() }
}
