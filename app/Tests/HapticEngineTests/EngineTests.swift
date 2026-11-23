// Silent tests: nothing here plays on a motor.
import CoreAudio
import Foundation
import Testing
@testable import HapticEngine

/// A test signal: sines at these frequencies, at 48 kHz.
func chord(_ freqs: [Double], count: Int = MusicAnalyser.size, rate: Double = 48000, amp: Float = 0.2) -> [Float] {
    (0..<count).map { i in freqs.reduce(Float(0)) { $0 + amp * Float(sin(2 * .pi * $1 * Double(i) / rate)) } }
}

/// A sung or played note: a fundamental and two weaker harmonics.
func voiced(_ hz: Double, amp: Float = 0.25) -> [Float] {
    let a = chord([hz], amp: amp), b = chord([2 * hz], amp: amp * 0.5), c = chord([3 * hz], amp: amp * 0.25)
    return (0..<a.count).map { a[$0] + b[$0] + c[$0] }
}

/// Feeds the analyser the same slice `frames` times, 30 ms apart, and returns the last moment.
func settle(_ analyser: inout MusicAnalyser, _ samples: [Float], frames: Int = 12, from start: Double = 0) -> MusicAnalyser.Moment {
    var moment = MusicAnalyser.Moment()
    for i in 0..<frames { moment = analyser.next(samples, at: start + Double(i) * 0.03) }
    return moment
}

@Test func `a note becomes one clean tone, on the semitone, in the motor's octave`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    analyser.beat = false
    let moment = settle(&analyser, voiced(335))       // a slightly sharp E4
    #expect(moment.tones.count == 1)
    let e6 = 440 * pow(2, 7.0 / 12) * 2               // E4, moved up two octaves: 1318.5 Hz
    #expect(abs((moment.tones.first?.hz ?? 0) - e6) < 0.5, "tones: \(moment.tones)")
    #expect(moment.note == "E6")
    #expect(moment.level > 0.3)
}

@Test(arguments: [110.0, 196, 440, 880, 1500])
func `every note lands in the motor's clean octave`(hz: Double) {
    var analyser = MusicAnalyser(sampleRate: 48000)
    analyser.beat = false
    let moment = settle(&analyser, voiced(hz))
    let f = moment.tones.first?.hz ?? 0
    #expect(f >= MusicAnalyser.low && f < MusicAnalyser.high, "\(hz) Hz played as \(f) Hz")
}

@Test func `a new note has to last before it takes over`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    analyser.beat = false
    _ = settle(&analyser, voiced(440))
    let blip = analyser.next(voiced(494), at: 0.40)    // one 30 ms frame of B4
    #expect(blip.note == "A5", "a blip shouldn't switch notes: \(blip.note)")
    let held = settle(&analyser, voiced(494), frames: 4, from: 0.43)
    #expect(held.note == "B5")
}

@Test func `silence plays nothing`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    let moment = analyser.next([Float](repeating: 0, count: MusicAnalyser.size), at: 0)
    #expect(moment.tones.isEmpty)
    #expect(moment.level == 0)
}

@Test func `a kick drum becomes a thump, and only the beat plays when the melody is off`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    analyser.melody = false
    _ = settle(&analyser, voiced(1200), frames: 20)
    let mixed = zip(voiced(1200), chord([60], amp: 0.8)).map { $0 + $1 }
    let kick = analyser.next(mixed, at: 0.7)
    #expect(kick.tones.count == 1, "tones: \(kick.tones)")
    #expect(abs((kick.tones.first?.hz ?? 0) - 900) < 1, "a thump starts at 900 Hz and dives")
    #expect(kick.step <= 0.004 + 1e-9)
}

@Test func `the ring returns the newest samples in order`() {
    let ring = SampleRing()
    let values = (0..<5000).map(Float.init)
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(values.count * 4), mData: nil))
    values.withUnsafeBufferPointer { p in
        list.mBuffers.mData = UnsafeMutableRawPointer(mutating: p.baseAddress)
        ring.write(&list)
    }
    var out = [Float](repeating: -1, count: 4)
    #expect(ring.latest(into: &out))
    #expect(out == [4996, 4997, 4998, 4999])
}

@Test func `voices are listed, English first, with spaces in names`() {
    let voices = installedVoices()
    #expect(!voices.isEmpty)
    #expect(voices.first?.language == "en")
    #expect(voices.allSatisfy { !$0.name.isEmpty && $0.locale.contains("_") })
}

@Test func `this Mac's trackpads are found (opens and closes motors, plays nothing)`() {
    let pads = findTrackpads()
    print("trackpads:", pads.map { "\($0.name) #\($0.id)" })
    #expect(!pads.isEmpty)
}

@Test func `the engine clock starts at zero and only moves forward`() {
    let a = now()
    let b = now()
    #expect(a >= 0)
    #expect(b >= a)
    #expect(ticks(1) > 0)
}

@Test func `stop straight after start is never lost (no trackpads, so nothing can play)`() async throws {
    for _ in 0..<20 {
        Haptics.shared.start(.sweep, on: [])
        Haptics.shared.stop()
    }
    try await Task.sleep(for: .milliseconds(300))
    #expect(Haptics.shared.snapshot().playing == nil)
}

// MARK: - The classics

@Test(arguments: Classic.all)
func `every classic reads cleanly, fills its bars, and stays in the motor's range`(piece: Classic) throws {
    let bars = try parseScore(piece.score)
    #expect(bars.count >= 2)
    for (i, bar) in bars.enumerated() {
        let beats = bar.reduce(0) { $0 + $1.beats }
        if i == 0 || i == bars.count - 1 {
            #expect(beats <= piece.beatsPerBar + 1e-9, "\(piece.id) bar \(i + 1) has \(beats) beats")
        } else {
            #expect(abs(beats - piece.beatsPerBar) < 1e-9, "\(piece.id) bar \(i + 1) has \(beats) beats, not \(piece.beatsPerBar)")
        }
    }
    let hz = try piece.notes().compactMap(\.midi).map { 440 * pow(2, Double($0 - 69) / 12) }
    #expect(!hz.isEmpty)
    #expect(hz.allSatisfy { $0 >= 150 && $0 <= 4000 }, "\(piece.id): \(hz.min() ?? 0)–\(hz.max() ?? 0) Hz")
    #expect(piece.seconds > 2.5 && piece.seconds < 45, "\(piece.id) lasts \(piece.seconds) s")
}

@Test func `note names read as MIDI numbers, and typos are refused`() throws {
    #expect(try midiNumber("A4") == 69)
    #expect(try midiNumber("C4") == 60)
    #expect(try midiNumber("C#4") == 61)
    #expect(try midiNumber("Db4") == 61)
    #expect(try midiNumber("Bb3") == 58)
    for bad in ["H4", "C", "E#", "Cx4", "c4", "C9"] {
        #expect(throws: ScoreError.self) { try midiNumber(bad) }
    }
    #expect(throws: ScoreError.self) { try parseScore("E5:.25 D5 | C5:1") }
}

@Test func `classics have unique ids`() {
    #expect(Set(Classic.all.map(\.id)).count == Classic.all.count)
}

@Test(arguments: Classic.all)
func `expressive dynamics stay in range and fade at the end`(piece: Classic) throws {
    let notes = try piece.notes()
    let levels = expressiveLevels(notes, beatsPerBar: piece.beatsPerBar, base: piece.dynamic)
    #expect(levels.count == notes.count)
    let played = zip(notes, levels).filter { $0.0.midi != nil }
    #expect(played.allSatisfy { $0.1 >= 0.3 && $0.1 <= 1 })
    #expect((played.last?.1 ?? 0) < (played.map(\.1).max() ?? 1), "\(piece.id): the last note should be softer than the loudest")
}

@Test func `downbeats lean and offbeats lighten`() throws {
    // Two bars of one repeated note in 4/4 eighths, so only the metre shapes the levels.
    let bars = try parseScore("C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 | C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 C5:.5 C5:.5")
    var notes: [ScoreNote] = []
    for bar in bars { var at = 0.0; for var n in bar { n.position = at; at += n.beats; notes.append(n) } }
    let levels = expressiveLevels(notes, beatsPerBar: 4, base: 0.8)
    #expect(levels[0] > levels[1])          // the downbeat over the "and" after it
    #expect(levels[4] > levels[5])          // beat 3 over its "and"
    #expect(levels[0] > levels[2])          // the downbeat over beat 2
}

@Test func `the Fifth lands on its long notes`() throws {
    let piece = try #require(Classic.all.first { $0.id == "fifth" })
    let notes = try piece.notes()
    let levels = expressiveLevels(notes, beatsPerBar: piece.beatsPerBar, base: piece.dynamic)
    let eFlat = try #require(notes.firstIndex { ($0.midi ?? 0) % 12 == 3 })   // E-flat, in whatever octave it was moved to
    #expect(levels[eFlat] >= levels[eFlat - 1], "da-da-da-DUM: the E-flat shouldn't fall away")
}

@Test func `pieces keep their character: the Fifth is louder than Für Elise`() throws {
    func mean(_ id: String) throws -> Double {
        let piece = try #require(Classic.all.first { $0.id == id })
        let notes = try piece.notes()
        let levels = zip(notes, expressiveLevels(notes, beatsPerBar: piece.beatsPerBar, base: piece.dynamic)).filter { $0.0.midi != nil }.map(\.1)
        return levels.reduce(0, +) / Double(levels.count)
    }
    #expect(try mean("fifth") > mean("fur-elise") + 0.15)
}

@Test func `a pickup starts so it ends on the downbeat`() throws {
    let piece = try #require(Classic.all.first { $0.id == "fur-elise" })
    let notes = try piece.notes()
    #expect(notes[0].position == 1.0)      // E5 D#5 in 3/8: the last two sixteenths of a 1.5-beat bar
    #expect(notes[2].position == 0)        // the first full bar's E5, on the downbeat
}
