// Driving the motors. Each open trackpad gets its own thread, so two trackpads play side by side and a slow
// driver call on one (the built-in one takes ~3.7 ms a call) never holds up the other or the timing loop.

import Foundation

/// A sound to play: sine tones (Hz, relative strength) for a stretch of time.
public struct Tone: Sendable, Equatable {
    public var hz: Double
    public var amp: Double
    public init(_ hz: Double, _ amp: Double) { self.hz = hz; self.amp = amp }
}

/// One actuation, ready for any motor: the waveform description (immutable, so safe to share) and its strength.
struct Command: @unchecked Sendable {
    let shape: CFDictionary
    let level: Float
}

/// One trackpad's motor and the thread that plays on it. Commands queue at most two deep: if the driver falls
/// behind, the oldest is dropped rather than letting a backlog build up (a backlog would play late).
final class Motor: @unchecked Sendable {
    let id: UInt64
    private let actuator: CFTypeRef
    private let condition = NSCondition()
    private var pending: [Command] = []     // guarded by `condition`
    private var open = true                 // guarded by `condition`
    private var finished = false            // guarded by `condition`

    init?(id: UInt64) {
        let api = MultitouchAPI.shared
        guard api.canDriveMotor, let ref = api.actuatorCreate!(id)?.takeRetainedValue(), api.actuatorOpen!(ref) == 0 else {
            return nil
        }
        self.id = id
        actuator = ref
        let thread = Thread { [self] in run() }
        thread.qualityOfService = .userInteractive
        thread.name = "motor \(id)"
        thread.start()
    }

    func post(_ command: Command) {
        condition.lock()
        if pending.count >= 2 { pending.removeFirst() }
        pending.append(command)
        condition.signal()
        condition.unlock()
    }

    /// Stops the thread and closes the motor; returns once it's closed.
    func close() {
        condition.lock()
        open = false
        pending.removeAll()
        condition.broadcast()
        while !finished { condition.wait() }
        condition.unlock()
    }

    private func run() {
        let api = MultitouchAPI.shared
        let pointer = Unmanaged.passUnretained(actuator as AnyObject).toOpaque()
        while true {
            condition.lock()
            while pending.isEmpty && open { condition.wait() }
            guard open else { condition.unlock(); break }
            let command = pending.removeFirst()
            condition.unlock()
            guard let actuation = api.actuationCreate!(command.shape, 0) else { continue }
            _ = api.actuationPlay!(actuation, pointer, 0, command.level, 0)
            Unmanaged<AnyObject>.fromOpaque(actuation).release()
        }
        _ = api.actuatorClose!(actuator)
        condition.lock()
        finished = true
        condition.broadcast()
        condition.unlock()
    }
}

/// The motors one performance plays on: every chosen trackpad, playing the same thing.
final class MotorBank: Sendable {
    let motors: [Motor]

    init(trackpads ids: [UInt64]) {
        motors = ids.compactMap { Motor(id: $0) }
    }

    /// Tones together for `ms` at overall `level` (0…1). Strengths are scaled to add up to 1: past that is
    /// louder, but the driver starts stalling on long runs.
    func play(_ tones: [Tone], ms: Double, level: Float) {
        guard !tones.isEmpty, !motors.isEmpty else { return }
        let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
            "Tones": tones.map {
                ["Type": "Sine", "Amplitude": $0.amp / sum, "DurationMS": ms, "DelayMS": 0.0, "FrequencykHz": $0.hz / 1000]
            },
        ]
        let command = Command(shape: shape as CFDictionary, level: min(1, max(0, level)))
        for motor in motors { motor.post(command) }
    }

    func close() { for motor in motors { motor.close() } }
}
