import AppKit
import SwiftUI

/// The Music app: what's playing, and play/pause/next/previous, through AppleScript. It never opens Music by
/// itself: it only asks while Music is running, and only opens it when you press a button.
@Observable
final class MusicApp {
    nonisolated enum State: Equatable, Sendable { case notRunning, stopped, paused, playing }

    private(set) var state: State = .notRunning
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var duration = 0.0
    private(set) var artwork: NSImage?
    /// macOS said no to controlling Music (System Settings › Privacy & Security › Automation).
    private(set) var notAllowed = false
    private var position = 0.0
    private var positionAt = Date()
    private var trackID = ""
    private var asking = false
    private var lastAsked = Date.distantPast

    nonisolated static let bundleID = "com.apple.Music"

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }

    /// Where the song is now, counting on from the last answer while it plays.
    func elapsed(at date: Date) -> Double {
        let moved = state == .playing ? date.timeIntervalSince(positionAt) : 0
        return min(duration, position + moved)
    }

    // MARK: Asking Music

    func poll() {
        guard !asking, Date().timeIntervalSince(lastAsked) > 0.9 else { return }
        guard isRunning else {
            if state != .notRunning { clear(); state = .notRunning }
            return
        }
        asking = true
        lastAsked = Date()
        let knownTrack = trackID
        Task {
            let answer = await Self.ask(knownTrack: knownTrack)
            apply(answer)
            asking = false
        }
    }

    private func clear() {
        title = ""; artist = ""; album = ""; duration = 0; position = 0; artwork = nil; trackID = ""
    }

    private func apply(_ answer: Answer) {
        notAllowed = answer.notAllowed
        guard !answer.notAllowed, let state = answer.state else { return }
        self.state = state
        guard state != .stopped, let track = answer.track else { clear(); return }
        title = track.title; artist = track.artist; album = track.album; duration = track.duration
        position = track.position; positionAt = Date()
        if track.id != trackID {
            trackID = track.id
            artwork = answer.artwork.flatMap(NSImage.init(data:))
        }
    }

    // MARK: Buttons

    func playPause() { command(isRunning ? "playpause" : "play") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func command(_ verb: String) {
        if state == .playing, verb == "playpause" { state = .paused } else if verb == "playpause" { state = .playing }
        Task {
            await Self.run("tell application id \"\(Self.bundleID)\" to \(verb)")
            lastAsked = .distantPast
            poll()
        }
    }

    // MARK: AppleScript, through osascript: one script at a time, in its own process, off the main thread

    nonisolated struct Track: Sendable { var id, title, artist, album: String; var duration, position: Double }
    nonisolated struct Answer: Sendable { var state: State?; var track: Track?; var artwork: Data?; var notAllowed = false }

    private nonisolated static let queue = DispatchQueue(label: "nospeaker.music-app")

    @concurrent
    private static func ask(knownTrack: String) async -> Answer {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: askNow(knownTrack: knownTrack)) }
        }
    }

    @concurrent
    @discardableResult
    private static func run(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: osascript(source).status == 0) }
        }
    }

    /// Runs a script in osascript. A separate process, so a slow or stuck Music can't hang the app: it's
    /// stopped after `timeout` seconds. macOS still asks about controlling Music on NoSpeaker's behalf.
    private nonisolated static func osascript(_ source: String, timeout: Double = 4) -> (output: String, error: String, status: Int32) {
        let process = Process(), out = Pipe(), err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = out
        process.standardError = err
        guard (try? process.run()) != nil else { return ("", "", -1) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        let text = { (pipe: Pipe) in String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" }
        return (text(out).trimmingCharacters(in: .newlines), text(err), process.terminationStatus)
    }

    private nonisolated static func askNow(knownTrack: String) -> Answer {
        // Fields joined by the unit separator (character 31), which no title contains.
        let script = """
        tell application id "\(bundleID)"
            set s to player state as text
            if s is "stopped" then return s
            try
                set t to current track
                set AppleScript's text item delimiters to (character id 31)
                return {s, persistent ID of t, name of t, artist of t, album of t, (duration of t) as text, (player position) as text} as text
            on error
                return s
            end try
        end tell
        """
        let result = osascript(script)
        guard result.status == 0 else { return Answer(notAllowed: result.error.contains("-1743")) }
        let fields = result.output.components(separatedBy: "\u{1F}")
        let state: State = switch fields[0] {
        case "playing": .playing
        case "paused": .paused
        default: .stopped
        }
        var answer = Answer(state: state)
        guard fields.count >= 7 else { return answer }
        func number(_ text: String) -> Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let track = Track(id: fields[1], title: fields[2], artist: fields[3], album: fields[4],
                          duration: number(fields[5]), position: number(fields[6]))
        answer.track = track
        if track.id != knownTrack { answer.artwork = artwork() }
        return answer
    }

    /// The current song's artwork, written to a temporary file by Music and read back.
    private nonisolated static func artwork() -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nospeaker-artwork-\(getpid())")
        defer { try? FileManager.default.removeItem(at: file) }
        let script = """
        tell application id "\(bundleID)" to set d to raw data of artwork 1 of current track
        set f to open for access (POSIX file "\(file.path)") with write permission
        try
            set eof f to 0
            write d to f
        end try
        close access f
        """
        guard osascript(script).status == 0, let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        return data
    }

    // MARK: Previews

    /// Sample content for design snapshots only.
    func showSample() {
        state = .playing; title = "Sample Song"; artist = "Sample Artist"; album = "Sample Album"
        duration = 214; position = 83; positionAt = Date()
    }
}
