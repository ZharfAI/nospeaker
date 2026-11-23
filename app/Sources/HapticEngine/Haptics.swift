// The engine's front door. One performance at a time, on its own high-priority thread (timing to the
// millisecond is the whole job, so it can't share the main thread). The UI starts and stops pieces, sets the
// volume, and reads a snapshot of what's playing.

import Darwin
import Foundation
import Synchronization

/// Something to play.
public enum Piece: Sendable, Equatable {
    case say(String, voice: String?)
    case heartbeat
    case sweep
    case melody
    case beat
    case sparkle
    case show
    case music(MusicSource, speakersToo: Bool)
    case instrument

    public var kind: Kind {
        switch self {
        case .say: .say
        case .heartbeat: .heartbeat
        case .sweep: .sweep
        case .melody: .melody
        case .beat: .beat
        case .sparkle: .sparkle
        case .show: .show
        case .music: .music
        case .instrument: .instrument
        }
    }

    public enum Kind: String, Sendable, CaseIterable {
        case say, heartbeat, sweep, melody, beat, sparkle, show, music, instrument
    }
}

/// What the motors are doing right now, for the screen.
public struct LiveState: Sendable {
    public var playing: Piece.Kind?
    public var stage = ""                       // what part of the piece, in words ("rap", "preparing the voice")
    public var hz = 0.0, level = 0.0, lastPlay = -9.0
    public var tones: [Tone] = []
    public var actuations = 0
    public var f0 = 0.0, f1 = 0.0, f2 = 0.0
    public var caption = "", captionStart = 0.0, captionDuration = 1.0
    public var note = ""
    public var kick = -9.0, snare = -9.0, hat = -9.0, step = -1
    public var touchDown = false, touchX = 0.5, touchY = 0.5
    public var input = 0.0                      // music: how loud the tapped audio is (0…1)
    public var problem: String?                 // a plain explanation when something can't play
    public init() {}
}

public final class Haptics: Sendable {
    public static let shared = Haptics()

    private struct Request: Sendable { let piece: Piece; let trackpads: [UInt64]; let performance: Performance }
    /// A request waits in `pending` until the conductor takes it, and is `running` from that moment (one lock
    /// step), so stop() always finds it in one or the other.
    private struct Control {
        var volume: Float = 0.6
        var pending: Request?
        var running: Performance?
        mutating func cancelAll() { running?.cancel(); pending?.performance.cancel(); pending = nil }
    }

    private let control = Mutex(Control())
    private let wake = NSCondition()
    private let live = Mutex(LiveState())

    private init() {
        let thread = Thread { [self] in runLoop() }
        thread.qualityOfService = .userInteractive
        thread.name = "nospeaker conductor"
        thread.start()
    }

    // MARK: Controls

    /// Overall strength, 0…1, applied to everything as it plays.
    public var volume: Float {
        get { control.withLock { $0.volume } }
        set { control.withLock { $0.volume = min(1, max(0, newValue)) } }
    }

    /// Plays `piece` on these trackpads, stopping whatever is playing first.
    public func start(_ piece: Piece, on trackpads: [Trackpad]) {
        let request = Request(piece: piece, trackpads: trackpads.map(\.id), performance: Performance())
        control.withLock { $0.cancelAll(); $0.pending = request }
        wake.lock(); wake.signal(); wake.unlock()
    }

    /// Stops whatever is playing. The motors close within a few milliseconds.
    public func stop() {
        control.withLock { $0.cancelAll() }
    }

    public func snapshot() -> LiveState { live.withLock { $0 } }

    /// The engine's clock, in seconds: LiveState's times (lastPlay, kick, captionStart…) are on it.
    public var time: Double { now() }

    func update(_ change: (inout LiveState) -> Void) { live.withLock { change(&$0) } }

    // MARK: The conductor thread

    private func runLoop() {
        while true {
            wake.lock()
            var request = take()
            while request == nil {
                wake.wait()
                request = take()
            }
            wake.unlock()
            perform(request!)
        }
    }

    private func take() -> Request? {
        control.withLock { c in
            let r = c.pending
            c.pending = nil
            if let r { c.running = r.performance }
            return r
        }
    }

    private func perform(_ request: Request) {
        let performance = request.performance
        guard !performance.isCancelled else {
            control.withLock { if $0.running === performance { $0.running = nil } }
            return
        }
        update { s in
            let count = s.actuations
            s = LiveState()
            s.actuations = count
            s.playing = request.piece.kind
        }
        let bank = MotorBank(trackpads: request.trackpads)
        if bank.motors.isEmpty {
            update { $0.problem = request.trackpads.isEmpty
                ? "No trackpad is chosen."
                : "That trackpad's motor didn't open. Check it's on and connected, then try again." }
        } else {
            let stage = Stage(bank: bank, performance: performance, haptics: self)
            Pieces.play(request.piece, on: stage, trackpads: Set(request.trackpads))
        }
        bank.close()
        control.withLock { if $0.running === performance { $0.running = nil } }
        update { $0.playing = nil; $0.tones = []; $0.f0 = 0; $0.f1 = 0; $0.f2 = 0; $0.step = -1; $0.touchDown = false; $0.input = 0 }
    }
}

/// One run of one piece; cancelled from any thread.
final class Performance: Sendable {
    private let cancelled = Atomic(false)
    func cancel() { cancelled.store(true, ordering: .relaxed) }
    var isCancelled: Bool { cancelled.load(ordering: .relaxed) }
}

// MARK: - The clock

private let ticksPerSecond: Double = {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return 1e9 * Double(timebase.denom) / Double(timebase.numer)
}()
private let clockStart = mach_absolute_time()

/// Seconds since the engine started (monotonic). `clockStart` is read first: globals start lazily, on first
/// use, so reading the time before it would put "now" before the start.
func now() -> Double {
    let start = clockStart
    return Double(mach_absolute_time() - start) / ticksPerSecond
}
func ticks(_ seconds: Double) -> UInt64 { UInt64(max(0, seconds) * ticksPerSecond) }

/// What a piece plays through: the motors, the clock, and whether to stop.
final class Stage {
    let bank: MotorBank
    let performance: Performance
    let haptics: Haptics

    init(bank: MotorBank, performance: Performance, haptics: Haptics) {
        self.bank = bank
        self.performance = performance
        self.haptics = haptics
    }

    var cancelled: Bool { performance.isCancelled }

    func play(_ tones: [Tone], ms: Double, level: Float) {
        guard !tones.isEmpty else { return }
        let volume = haptics.volume
        bank.play(tones, ms: ms, level: level * volume)
        let first = tones.max { $0.amp < $1.amp }!.hz
        let t = now()
        haptics.update {
            $0.actuations += 1; $0.hz = first; $0.level = Double(level * volume); $0.lastPlay = t; $0.tones = tones
        }
    }

    /// Waits for a moment on the clock: sleeps, and spins only for the last ~1.5 ms (tight timing without
    /// pinning a core).
    func waitUntil(_ t: UInt64) {
        let margin = ticks(0.0015)
        while !cancelled {
            let n = mach_absolute_time()
            if n >= t { return }
            if t - n > margin { usleep(useconds_t(Double(t - n - margin) / ticksPerSecond * 1e6)) }
        }
    }

    func pause(_ seconds: Double) {
        let end = now() + seconds
        while now() < end && !cancelled { usleep(5000) }
    }

    func say(_ words: String) { haptics.update { $0.stage = words } }
    func caption(_ text: String, seconds: Double) {
        let t = now()
        haptics.update { $0.caption = text; $0.captionStart = t; $0.captionDuration = seconds }
    }
}
