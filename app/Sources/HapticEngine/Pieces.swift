// The pieces: talking, the sweep, the melody, the beat with its rap, the heartbeat, the sparkle, the show, and
// the instrument under your finger. Sound design from nospeaker.swift (github.com/os6/nospeaker, MIT,
// © 2026 Cody Collier).

import Foundation
import Synchronization

enum Pieces {
    static func play(_ piece: Piece, on stage: Stage, trackpads: Set<UInt64>) {
        switch piece {
        case let .say(text, voice): say(text, voice: voice, on: stage)
        case .heartbeat: heartbeat(stage)
        case .sweep: stage.say("100 Hz → 4 kHz"); sweep(stage)
        case .melody: stage.say("an original hook"); sing(stage)
        case .beat: beatAndRap(stage, voice: nil)
        case .sparkle: sparkle(stage)
        case .show: show(stage)
        case let .music(settings): MusicPlayer.play(settings, on: stage)
        case .instrument: instrument(stage, trackpads: trackpads)
        case let .classic(id): playClassic(id, on: stage)
        }
    }

    // MARK: Talking

    static func say(_ text: String, voice: String?, on stage: Stage) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        stage.say("preparing the voice")
        do {
            let frames = try render(words, voice: voice, stage: stage)
            stage.say("speaking")
            talk(frames, text: words, on: stage)
        } catch .cancelled {
        } catch {
            stage.haptics.update { $0.problem = "macOS's voice couldn't speak that line. Try another voice." }
        }
    }

    static func talk(_ frames: [Frame], text: String, on stage: Stage) {
        guard !frames.isEmpty else { return }
        let total = Double(frames.count) * hop
        stage.caption(text, seconds: total)
        let start = mach_absolute_time()
        var t = 0.0
        while t < total && !stage.cancelled {
            let f = frames[min(frames.count - 1, Int(t / hop))]
            var step = 0.005
            if f.level > 0 {
                if f.voiced {
                    step = 1 / f.f0
                    stage.play(voiceTones(f), ms: step * 1000, level: f.level)
                    stage.haptics.update { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
                } else {
                    step = 0.004
                    stage.play((0..<3).map { _ in Tone(Double.random(in: 2700...4300), 1) }, ms: step * 1000, level: f.level * 0.7)
                }
            }
            t += step
            stage.waitUntil(start + ticks(t))
        }
        stage.haptics.update { $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
    }

    // MARK: Sounds

    /// A felt-and-heard thump: a fast pitch dive.
    static func thump(_ stage: Stage, _ amp: Double) {
        let start = mach_absolute_time()
        var t = 0.0
        while t < 0.11 && !stage.cancelled {
            let f = 120 + 780 * exp(-t / 0.02)
            let seg = 1 / f
            stage.play([Tone(f, 1)], ms: seg * 1000, level: Float(amp * exp(-t / 0.05)))
            t += seg
            stage.waitUntil(start + ticks(t))
        }
    }

    static func heartbeat(_ stage: Stage) {
        stage.say("waking up the motor")
        for _ in 0..<3 where !stage.cancelled {
            thump(stage, 1); stage.pause(0.17); thump(stage, 0.7); stage.pause(0.75)
        }
    }

    static func sweep(_ stage: Stage, seconds: Double = 6) {
        let start = mach_absolute_time()
        var t = 0.0
        while t < seconds && !stage.cancelled {
            let f = 100 * pow(40, t / seconds)
            let seg = max(1, (0.02 * f).rounded()) / f
            stage.play([Tone(f, 1)], ms: seg * 1000, level: 1)
            t += seg
            stage.waitUntil(start + ticks(t))
        }
    }

    static func hz(_ note: String) -> Double {
        let names: [String: Int] = ["C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2]
        guard let octave = Int(String(note.last!)), let semi = names[String(note.dropLast())] else { return 440 }
        return 440 * pow(2, Double(semi + (octave - 4) * 12) / 12)
    }

    static func noteName(_ f: Double) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let midi = Int((69 + 12 * log2(f / 440)).rounded())
        return names[(midi % 12 + 12) % 12] + String(midi / 12 - 1)
    }

    /// An original hook in the motor's loudest, cleanest octave, with scoops, glides and vibrato.
    static func sing(_ stage: Stage) {
        let beat = 60.0 / 112
        let melody: [(String, Double)] = [("E6", 0.5), ("G6", 0.5), ("A6", 1), ("G6", 0.5), ("E6", 0.5), ("C6", 1),
                                          ("E6", 0.5), ("G6", 0.5), ("A6", 0.5), ("C7", 0.5), ("A6", 1), ("G6", 1),
                                          ("E6", 0.5), ("C6", 0.5), ("A5", 1), ("C6", 0.5), ("E6", 0.5), ("A6", 2.5)]
        let phraseEnds: Set<Int> = [5, 11, 17]
        var previous: Double?
        let start = mach_absolute_time()
        var t = 0.0, at = 0.0
        for (i, (name, beats)) in melody.enumerated() {
            if stage.cancelled { break }
            let target = hz(name), length = beats * beat
            let sounding = phraseEnds.contains(i) ? length * 0.86 : length
            stage.haptics.update { $0.note = name }
            let from = previous
            while t < at + sounding && !stage.cancelled {
                let age = t - at
                var f = target
                if let from, age < 0.045 { f = from * pow(target / from, age / 0.045) }
                else if from == nil, age < 0.04 { f = target * pow(2, -0.6 * (1 - age / 0.04) / 12) }
                if age > 0.2 { f *= pow(2, min(1, (age - 0.2) / 0.25) * 0.22 * sin(2 * .pi * 5.8 * age) / 12) }
                var level = age < 0.015 ? 0.6 + 0.4 * age / 0.015 : 1.0
                if i == melody.count - 1 { level *= max(0, 1 - age / length) }
                let seg = max(1, ((age < 0.06 ? 0.02 : 0.045) * f).rounded()) / f
                stage.play([Tone(f, 1)], ms: min(seg, at + sounding - t + 0.004) * 1000, level: Float(level))
                t += seg
                stage.waitUntil(start + ticks(t))
            }
            previous = phraseEnds.contains(i) ? nil : target
            stage.haptics.update { $0.note = "" }
            at += length
            if t < at { t = at; stage.waitUntil(start + ticks(t)) }
        }
    }

    static let rapLine = "No speaker. No wires. Just a motor and a beat."

    static func beatAndRap(_ stage: Stage, voice: String?) {
        stage.say("preparing the rap")
        let rap = (try? render(rapLine, voice: voice, stage: stage)) ?? []
        guard !stage.cancelled else { return }
        stage.say("beat")
        groove(stage, bars: 4, rapBar: 2, rap: rap, rapText: rapLine)
    }

    /// Drums, bass and (from `rapBar`) a rapped line, mixed into each actuation. Everything restarts on one
    /// carrier period: the bass note, or the voice's own pitch while it raps, so the ear hears that as the low
    /// note. While the voice talks, the bass drops out and the drums duck.
    static func groove(_ stage: Stage, bars: Int, rapBar: Int, rap: [Frame], rapText: String) {
        let bpm = 92.0
        let s16 = 15 / bpm, barLen = 16 * s16
        let kickP = Array("X.........X..x.."), snareP = Array("....X.......X..."), hatP = Array("x.x.x.x.x.x.xxx.")
        let bassHz = [110.0, 87.31, 130.81, 98.0]
        let bassRhythm = Array("x.....x...x.....")
        struct Hit { let t: Double; let kind: Int; let acc: Double }
        var hits: [Hit] = []
        for i in 0..<(bars * 16) {
            for (k, p) in [kickP, snareP, hatP].enumerated() where p[i % 16] != "." {
                hits.append(Hit(t: Double(i) * s16, kind: k, acc: p[i % 16] == "X" ? 1 : 0.65))
            }
        }
        hits.sort { $0.t < $1.t }
        let rapStart = Double(rapBar) * barLen
        let end = Double(bars) * barLen
        var t = 0.0, next = 0, rapping = false
        var ringing: [Hit] = []
        let start = mach_absolute_time()
        while t < end && !stage.cancelled {
            while next < hits.count, hits[next].t <= t + 0.0005 {
                let h = hits[next]
                ringing.append(h)
                let when = now()
                stage.haptics.update { if h.kind == 0 { $0.kick = when } else if h.kind == 1 { $0.snare = when } else { $0.hat = when } }
                next += 1
            }
            ringing.removeAll { t - $0.t > 0.2 }
            let i16 = Int(t / s16)
            stage.haptics.update { $0.step = i16 % 16 }
            if !rapping, t >= rapStart, !rap.isEmpty {
                rapping = true
                stage.say("rap")
                stage.caption(rapText, seconds: Double(rap.count) * hop)
            }
            var frame: Frame?
            if t >= rapStart { let idx = Int((t - rapStart) / hop); if idx < rap.count { frame = rap[idx] } }
            let talking = (frame?.level ?? 0) > 0
            let bass = bassHz[(i16 / 16) % bassHz.count]
            var carrier = bass
            if let f = frame, talking, f.voiced { carrier = f.f0 }
            var tones: [Tone] = []
            var step = 1 / carrier
            if let f = frame, talking {
                if f.voiced {
                    for v in voiceTones(f) { tones.append(Tone(v.hz, Double(f.level) * v.amp)) }
                    stage.haptics.update { $0.f0 = f.f0; $0.f1 = f.formants[0]; $0.f2 = f.formants[1] }
                } else {
                    step = 0.004
                    for _ in 0..<2 { tones.append(Tone(Double.random(in: 2700...4300), Double(f.level) * 0.4)) }
                }
            } else {
                let pos = i16 % 16
                let lastHit = (0...pos).last { bassRhythm[$0] != "." } ?? 0
                let age = t - Double((i16 / 16) * 16 + lastHit) * s16
                let env = (age < 0.01 ? age / 0.01 : 1) * (0.25 + 0.75 * exp(-age * 7))
                for (target, w) in [(880.0, 0.6), (1320.0, 0.4)] {
                    tones.append(Tone(max(1, (target / bass).rounded()) * bass, 0.45 * env * w))
                }
            }
            for h in ringing {
                let age = t - h.t
                let duck = talking ? [0.4, 0.25, 0.0][h.kind] : 1.0
                switch h.kind {
                case 0 where age < 0.14:
                    tones.append(Tone(150 + 850 * exp(-age / 0.018), duck * 0.9 * h.acc * 1.3 * exp(-age / 0.05)))
                case 1 where age < 0.16:
                    let e = duck * 0.9 * h.acc * exp(-age / 0.045)
                    tones.append(Tone(Double.random(in: 1300...3800), e * 0.55))
                    tones.append(Tone(Double.random(in: 1300...3800), e * 0.45))
                case 2 where age < 0.05 && duck > 0:
                    tones.append(Tone(3951, 0.9 * h.acc * 0.55 * exp(-age / 0.012)))
                default: break
                }
            }
            if next < hits.count {
                let dt = hits[next].t - t
                if dt > 0.0035, dt < step { step = dt }
            }
            tones.sort { $0.amp > $1.amp }
            let use = Array(tones.prefix(6))
            let total = use.reduce(0) { $0 + $1.amp }
            if total > 0.01 { stage.play(use, ms: step * 1000, level: Float(min(1, total))) }
            t += step
            stage.waitUntil(start + ticks(t))
        }
        stage.haptics.update { $0.step = -1; $0.f0 = 0; $0.f1 = 0; $0.f2 = 0 }
    }

    /// A sparkle to close: an arpeggio up, then the motor's purest note.
    static func sparkle(_ stage: Stage) {
        stage.say("sparkle")
        for n in ["A5", "C6", "E6", "A6", "C7"] where !stage.cancelled {
            let f = hz(n)
            let seg = (0.07 * f).rounded() / f
            stage.play([Tone(f, 1)], ms: seg * 1000, level: 0.9)
            stage.waitUntil(mach_absolute_time() + ticks(seg))
        }
        let start = mach_absolute_time()
        var t = 0.0
        while t < 0.6 && !stage.cancelled {
            let seg = (0.02 * 3951).rounded() / 3951
            stage.play([Tone(3951, 1)], ms: seg * 1000, level: Float(exp(-t / 0.18)))
            t += seg
            stage.waitUntil(start + ticks(t))
        }
    }

    /// The show from the terminal, without the parts that need typing: heartbeat, first words, sweep, melody,
    /// beat and rap, goodbye, sparkle.
    static func show(_ stage: Stage) {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 5 ? "You're up late." : hour < 12 ? "Good morning." : hour < 17 ? "Good afternoon." : hour < 22 ? "Good evening." : "You're up late."
        let greeting = "\(hello) I'm your trackpad. I don't have a speaker. I've been meaning to say something."
        let bye = "Okay. Back to clicking."
        stage.say("preparing the voice")
        var voices: [String: [Frame]] = [:]
        for line in [greeting, rapLine, bye] where !stage.cancelled {
            voices[line] = (try? render(line, voice: nil, stage: stage)) ?? []
        }
        let parts: [(String, () -> Void)] = [
            ("waking up", { heartbeat(stage) }),
            ("first words", { talk(voices[greeting] ?? [], text: greeting, on: stage) }),
            ("100 Hz → 4 kHz", { sweep(stage) }),
            ("an original hook", { sing(stage) }),
            ("beat", { groove(stage, bars: 4, rapBar: 2, rap: voices[rapLine] ?? [], rapText: rapLine) }),
            ("goodbye", { talk(voices[bye] ?? [], text: bye, on: stage) }),
            ("sparkle", { sparkle(stage) }),
        ]
        for (name, part) in parts where !stage.cancelled {
            stage.say(name)
            stage.pause(0.4)
            part()
            stage.pause(0.5)
        }
    }

    // MARK: The instrument

    /// The trackpad as an instrument: slide for pitch (snapped to the motor's cleanest notes, with a glide), move
    /// up for more vibrato, touch with more of your finger for louder. Plays until stopped.
    static func instrument(_ stage: Stage, trackpads: Set<UInt64>) {
        guard let touch = TouchTracker(trackpads: trackpads) else {
            stage.haptics.update { $0.problem = "Touch tracking isn't available on this macOS." }
            return
        }
        defer { touch.stop() }
        stage.say("put a finger on the trackpad")
        let scale = ["G5", "A5", "B5", "C6", "E6", "F6", "G6", "A6", "B6", "C7"].map(hz)
        var current = scale[4]
        var lastDown = false, downAt = 0.0
        while !stage.cancelled {
            let c = touch.contact
            stage.haptics.update { $0.touchDown = c.down; if c.down { $0.touchX = Double(c.x); $0.touchY = Double(c.y) } }
            guard c.down else { lastDown = false; usleep(3000); continue }
            if !lastDown { downAt = now(); stage.say("playing") }
            lastDown = true
            let idx = min(scale.count - 1, max(0, Int((Double(c.x) * Double(scale.count)).rounded(.down))))
            current *= pow(scale[idx] / current, 0.3)
            let age = now() - downAt
            let depth = 0.05 + 0.45 * Double(max(0, min(1, c.y)))
            let f = current * pow(2, depth * sin(2 * .pi * 6 * age) / 12)
            let level = min(1, max(0.5, 0.3 + Double(c.size) * 0.8))
            let seg = max(1, (0.02 * f).rounded()) / f
            let t0 = mach_absolute_time()
            stage.play([Tone(f, 1)], ms: seg * 1000, level: Float(level))
            let name = noteName(f)
            stage.haptics.update { $0.note = name }
            stage.waitUntil(t0 + ticks(seg))
        }
    }
}

// MARK: - Touch

struct Contact: Sendable { var down = false; var x: Float = 0; var y: Float = 0; var size: Float = 0 }

/// The latest finger on each tracked trackpad (keyed by device), written by MultitouchSupport's callback
/// thread. One per trackpad, so an empty frame from an idle trackpad can't lift the finger on the other.
private let contacts = Mutex([Int: Contact]())

private let contactCallback: MultitouchAPI.FrameCallback = { device, data, count, _, _ in
    var best = Contact()
    if let data, count > 0 {
        for i in 0..<Int(count) {
            let record = data.advanced(by: i * 96)
            let state = record.load(fromByteOffset: 20, as: Int32.self)
            guard (3...5).contains(state) else { continue }
            best = Contact(down: true, x: record.load(fromByteOffset: 32, as: Float.self),
                           y: record.load(fromByteOffset: 36, as: Float.self), size: record.load(fromByteOffset: 48, as: Float.self))
        }
    }
    let key = Int(bitPattern: device)
    contacts.withLock { $0[key] = best }
    return 0
}

/// Follows fingers on the chosen trackpads while it's alive.
final class TouchTracker {
    private let list: DeviceList
    private let devices: [UnsafeMutableRawPointer]

    init?(trackpads: Set<UInt64>) {
        let api = MultitouchAPI.shared
        guard let register = api.registerCallback, let start = api.deviceStart, let list = DeviceList() else { return nil }
        self.list = list
        devices = list.pointers(for: trackpads)
        guard !devices.isEmpty else { return nil }
        contacts.withLock { $0.removeAll() }
        for device in devices { register(device, contactCallback); start(device, 0) }
    }

    /// A finger that's down on any of the trackpads, if there is one.
    var contact: Contact { contacts.withLock { all in all.values.first(where: \.down) ?? Contact() } }

    func stop() {
        let api = MultitouchAPI.shared
        for device in devices {
            api.unregisterCallback?(device, contactCallback)
            api.deviceStop?(device)
        }
        _ = list
    }
}
