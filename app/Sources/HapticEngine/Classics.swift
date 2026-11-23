// The classics: the openings of famous pieces (all long out of copyright), one note at a time, as the motor
// plays best. Each is moved by whole octaves into the motor's clean range; nothing else is changed. Every
// score was checked against a published edition (Mutopia, Wikipedia's notated examples, the music21 corpus,
// the ASAP dataset); grace notes, trills and turns are left out, and each keeps its top line.
//
// Score notation, one token per note, bars split by "|":
//   E5:.25      a note and its length in quarter notes (so .25 is a sixteenth, 1.5 a dotted quarter)
//   D#4  Bb3    sharps and flats
//   r:1         a rest
//   G4:2~       tied into the next note (no new attack)
//   D#4:2^      a fermata: held longer than written
// The first bar may be a pickup and the last may be short; every other bar fills its time signature (the
// tests check this, and that every note parses and lands inside the motor's range).

import Foundation

public struct Classic: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let composer: String
    public let year: Int
    public let work: String
    /// Quarter notes per minute.
    let bpm: Double
    /// Quarter notes per bar (3/8 is 1.5, 6/8 is 3, 12/8 is 6).
    let beatsPerBar: Double
    let score: String
}

extension Classic {
    public static let all: [Classic] = [
        Classic(id: "fur-elise", title: "Für Elise", composer: "Beethoven", year: 1810,
                work: "Bagatelle No. 25 in A minor, WoO 59", bpm: 72, beatsPerBar: 1.5, score: """
                E5:.25 D#5:.25 |
                E5:.25 D#5:.25 E5:.25 B4:.25 D5:.25 C5:.25 | A4:.5 r:.25 C4:.25 E4:.25 A4:.25 |
                B4:.5 r:.25 E4:.25 G#4:.25 B4:.25 | C5:.5 r:.25 E4:.25 E5:.25 D#5:.25 |
                E5:.25 D#5:.25 E5:.25 B4:.25 D5:.25 C5:.25 | A4:.5 r:.25 C4:.25 E4:.25 A4:.25 |
                B4:.5 r:.25 E4:.25 C5:.25 B4:.25 | A4:1.5
                """),
        Classic(id: "ode-to-joy", title: "Ode to Joy", composer: "Beethoven", year: 1824,
                work: "Symphony No. 9 in D minor, finale: the theme", bpm: 120, beatsPerBar: 4, score: """
                F#4:1 F#4:1 G4:1 A4:1 | A4:1 G4:1 F#4:1 E4:1 | D4:1 D4:1 E4:1 F#4:1 | F#4:1.5 E4:.5 E4:2 |
                F#4:1 F#4:1 G4:1 A4:1 | A4:1 G4:1 F#4:1 E4:1 | D4:1 D4:1 E4:1 F#4:1 | E4:1.5 D4:.5 D4:2 |
                E4:1 E4:1 F#4:1 D4:1 | E4:1 F#4:.5 G4:.5 F#4:1 D4:1 | E4:1 F#4:.5 G4:.5 F#4:1 E4:1 | D4:1 E4:1 A3:1 F#4:1~ |
                F#4:1 F#4:1 G4:1 A4:1 | A4:1 G4:1 F#4:1 E4:1 | D4:1 D4:1 E4:1 F#4:1 | E4:1.5 D4:.5 D4:2
                """),
        Classic(id: "fifth", title: "Symphony No. 5", composer: "Beethoven", year: 1808,
                work: "Symphony No. 5 in C minor, the opening", bpm: 216, beatsPerBar: 2, score: """
                r:.5 G4:.5 G4:.5 G4:.5 | Eb4:2^ | r:.5 F4:.5 F4:.5 F4:.5 | D4:2~ | D4:2^
                """),
        Classic(id: "nachtmusik", title: "Eine kleine Nachtmusik", composer: "Mozart", year: 1787,
                work: "Serenade No. 13, K. 525, the first ten bars", bpm: 132, beatsPerBar: 4, score: """
                G4:1 r:.5 D4:.5 G4:1 r:.5 D4:.5 | G4:.5 D4:.5 G4:.5 B4:.5 D5:1 r:1 |
                C5:1 r:.5 A4:.5 C5:1 r:.5 A4:.5 | C5:.5 A4:.5 F#4:.5 A4:.5 D4:1 r:1 |
                G4:.5 r:.5 G4:1.5 B4:.5 A4:.5 G4:.5 | G4:.5 F#4:.5 F#4:1.5 A4:.5 C5:.5 F#4:.5 |
                A4:.5 G4:.5 G4:1.5 B4:.5 A4:.5 G4:.5 | G4:.5 F#4:.5 F#4:1.5 A4:.5 C5:.5 F#4:.5 |
                G4:.5 G4:.5 F#4:.5 E4:.25 F#4:.25 G4:.5 G4:.5 A4:.5 G4:.25 A4:.25 | B4:.5 B4:.5 C5:.5 B4:.25 C5:.25 D5:1
                """),
        Classic(id: "alla-turca", title: "Rondo alla Turca", composer: "Mozart", year: 1783,
                work: "Piano Sonata No. 11, K. 331, finale: the first section", bpm: 120, beatsPerBar: 2, score: """
                B4:.25 A4:.25 G#4:.25 A4:.25 |
                C5:.5 r:.5 D5:.25 C5:.25 B4:.25 C5:.25 | E5:.5 r:.5 F5:.25 E5:.25 D#5:.25 E5:.25 |
                B5:.25 A5:.25 G#5:.25 A5:.25 B5:.25 A5:.25 G#5:.25 A5:.25 | C6:1 A5:.5 C6:.5 |
                B5:.5 A5:.5 G5:.5 A5:.5 | B5:.5 A5:.5 G5:.5 A5:.5 | B5:.5 A5:.5 G5:.5 F#5:.5 | E5:1 E5:.5 F5:.5 |
                G5:.5 G5:.5 A5:.25 G5:.25 F5:.25 E5:.25 | D5:1 E5:.5 F5:.5 | G5:.5 G5:.5 A5:.25 G5:.25 F5:.25 E5:.25 | D5:1 C5:.5 D5:.5 |
                E5:.5 E5:.5 F5:.25 E5:.25 D5:.25 C5:.25 | B4:1 C5:.5 D5:.5 | E5:.5 E5:.5 F5:.25 E5:.25 D5:.25 C5:.25 | B4:1 B4:.25 A4:.25 G#4:.25 A4:.25 |
                C5:.5 r:.5 D5:.25 C5:.25 B4:.25 C5:.25 | E5:.5 r:.5 F5:.25 E5:.25 D#5:.25 E5:.25 |
                B5:.25 A5:.25 G#5:.25 A5:.25 B5:.25 A5:.25 G#5:.25 A5:.25 | C6:1 A5:.5 B5:.5 |
                C6:.5 B5:.5 A5:.5 G#5:.5 | A5:.5 E5:.5 F5:.5 D5:.5 | C5:1 B4:.75 A4:.125 B4:.125 | A4:1
                """),
        Classic(id: "twinkle", title: "Twinkle Variations", composer: "Mozart", year: 1781,
                work: "12 Variations on \"Ah vous dirai-je, maman\", K. 265, the theme", bpm: 112, beatsPerBar: 2, score: """
                C4:1 C4:1 | G4:1 G4:1 | A4:1 A4:1 | G4:1 G4:1 | F4:1 F4:1 | E4:1 E4:1 | D4:1 D4:.75 E4:.25 | C4:2 |
                G4:1 G4:1 | F4:1 F4:1 | E4:1 E4:1 | D4:1 D4:1 | G4:1 G4:1 | F4:1 F4:1 | E4:1 E4:.75 F4:.25 | E4:1 D4:1 |
                C4:1 C4:1 | G4:1 G4:1 | A4:1 A4:1 | G4:1 G4:1 | F4:1 F4:1 | E4:1 E4:1 | D4:1 D4:.75 E4:.25 | C4:2
                """),
        Classic(id: "symphony-40", title: "Symphony No. 40", composer: "Mozart", year: 1788,
                work: "Symphony No. 40 in G minor, K. 550, the opening", bpm: 216, beatsPerBar: 4, score: """
                Eb5:.5 D5:.5 |
                D5:1 Eb5:.5 D5:.5 D5:1 Eb5:.5 D5:.5 | D5:1 Bb5:1 r:1 Bb5:.5 A5:.5 |
                G5:1 G5:.5 F5:.5 Eb5:1 Eb5:.5 D5:.5 | C5:1 C5:1
                """),
        Classic(id: "prelude-c", title: "Prelude in C", composer: "Bach", year: 1722,
                work: "The Well-Tempered Clavier I, BWV 846", bpm: 66, beatsPerBar: 4,
                score: preludeBars([["C4", "E4", "G4", "C5", "E5"], ["C4", "D4", "A4", "D5", "F5"],
                                    ["B3", "D4", "G4", "D5", "F5"], ["C4", "E4", "G4", "C5", "E5"]])),
        Classic(id: "entertainer", title: "The Entertainer", composer: "Joplin", year: 1902,
                work: "A rag time two-step: the first strain", bpm: 76, beatsPerBar: 2, score: """
                D4:.25 D#4:.25 |
                E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:.25~ | C5:1.25 C5:.25 D5:.25 D#5:.25 |
                E5:.25 C5:.25 D5:.25 E5:.5 B4:.25 D5:.5 | C5:1.5 D4:.25 D#4:.25 |
                E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:.25~ | C5:1.5 A4:.25 G4:.25 |
                F#4:.25 A4:.25 C5:.25 E5:.5 D5:.25 C5:.25 A4:.25 | D5:1.5 D4:.25 D#4:.25 |
                E4:.25 C5:.5 E4:.25 C5:.5 E4:.25 C5:.25~ | C5:1.25 C5:.25 D5:.25 D#5:.25 |
                E5:.25 C5:.25 D5:.25 E5:.5 B4:.25 D5:.5 | C5:1.5 C5:.25 D5:.25 |
                E5:.25 C5:.25 D5:.25 E5:.5 C5:.25 D5:.25 C5:.25 | E5:.25 C5:.25 D5:.25 E5:.5 C5:.25 D5:.25 C5:.25 |
                E5:.25 C5:.25 D5:.25 E5:.5 B4:.25 D5:.5 | C5:1.5
                """),
        Classic(id: "canon", title: "Canon in D", composer: "Pachelbel", year: 1680,
                work: "Canon and Gigue in D: the violin's first lines", bpm: 60, beatsPerBar: 4, score: """
                F#5:1 E5:1 D5:1 C#5:1 | B4:1 A4:1 B4:1 C#5:1 | D5:1 C#5:1 B4:1 A4:1 | G4:1 F#4:1 G4:1 E4:1 |
                D4:.5 F#4:.5 A4:.5 G4:.5 F#4:.5 D4:.5 F#4:.5 E4:.5 | D4:.5 B3:.5 D4:.5 A4:.5 G4:.5 B4:.5 A4:.5 G4:.5 | F#4:1
                """),
        Classic(id: "gymnopedie", title: "Gymnopédie No. 1", composer: "Satie", year: 1888,
                work: "Lent et douloureux, the melody", bpm: 66, beatsPerBar: 3, score: """
                r:1 F#5:1 A5:1 | G5:1 F#5:1 C#5:1 | B4:1 C#5:1 D5:1 | A4:3 | F#4:3~ | F#4:3~ | F#4:3~ | F#4:3
                """),
        Classic(id: "nocturne", title: "Nocturne in E-flat", composer: "Chopin", year: 1832,
                work: "Nocturne Op. 9 No. 2, the opening", bpm: 66, beatsPerBar: 6, score: """
                Bb4:.5 |
                G5:2 F5:.5 G5:.5 F5:1.5 Eb5:1 Bb4:.5 | G5:1 C5:.5 C6:1 G5:.5 Bb5:1.5 Ab5:1 G5:.5 |
                F5:1.5 G5:1 D5:.5 Eb5:1.5 C5:1.5 | Bb4:.5 D6:.5 C6:.5 Bb5:.25 Ab5:.25 G5:.25 Ab5:.25 C5:.25 D5:.25 Eb5:1.5
                """),
        Classic(id: "funeral-march", title: "Funeral March", composer: "Chopin", year: 1839,
                work: "Piano Sonata No. 2, Op. 35, third movement", bpm: 54, beatsPerBar: 4, score: """
                Bb3:1 Bb3:.75 Bb3:.25 Bb3:2 | Bb3:1 Bb3:.75 Bb3:.25 Bb3:2 |
                Bb3:1 Bb3:.75 Bb3:.25 Bb3:1 Db4:.75 C4:.25 | C4:.75 Bb3:.25 Bb3:.75 Bb3:.25 Bb3:2
                """),
    ]

    /// The prelude's pattern: each bar's five notes as 1 2 3 4 5 3 4 5, twice, in sixteenths.
    static func preludeBars(_ chords: [[String]]) -> String {
        chords.map { c in
            let figure = [c[0], c[1], c[2], c[3], c[4], c[2], c[3], c[4]].map { $0 + ":.25" }.joined(separator: " ")
            return figure + " " + figure
        }.joined(separator: " | ")
    }
}

// MARK: - Reading a score

struct ScoreNote: Equatable {
    var midi: Int?          // nil for a rest
    var beats: Double
    var tied = false
    var fermata = false
}

enum ScoreError: Error, CustomStringConvertible {
    case token(String)
    case note(String)
    var description: String {
        switch self {
        case let .token(t): "can't read \"\(t)\""
        case let .note(n): "no such note \"\(n)\""
        }
    }
}

/// A note name ("C#4", "Bb3", "E5") as a MIDI number. Throws on anything else, so a typo can't play as a wrong A.
func midiNumber(_ name: String) throws(ScoreError) -> Int {
    let steps: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    var chars = Array(name)
    guard let letter = chars.first, let step = steps[letter], chars.count >= 2 else { throw .note(name) }
    chars.removeFirst()
    var shift = 0
    if chars.first == "#" { shift = 1; chars.removeFirst() } else if chars.first == "b" { shift = -1; chars.removeFirst() }
    guard let octave = Int(String(chars)), (0...8).contains(octave) else { throw .note(name) }
    return 12 * (octave + 1) + step + shift
}

/// The score as bars of notes.
func parseScore(_ score: String) throws(ScoreError) -> [[ScoreNote]] {
    var bars: [[ScoreNote]] = []
    for barText in score.split(separator: "|") {
        var bar: [ScoreNote] = []
        for token in barText.split(whereSeparator: \.isWhitespace) {
            var t = String(token)
            var note = ScoreNote(beats: 0)
            if t.hasSuffix("~") { note.tied = true; t.removeLast() }
            if t.hasSuffix("^") { note.fermata = true; t.removeLast() }
            let parts = t.split(separator: ":")
            guard parts.count == 2, let beats = Double(parts[1]), beats > 0 else { throw .token(String(token)) }
            note.beats = beats
            if parts[0] != "r" { note.midi = try midiNumber(String(parts[0])) }
            bar.append(note)
        }
        if !bar.isEmpty { bars.append(bar) }
    }
    return bars
}

extension Classic {
    /// The notes, moved by whole octaves so the middle of the tune sits in the motor's cleanest range
    /// (about 700 Hz to 1.4 kHz).
    func notes() throws(ScoreError) -> [ScoreNote] {
        let flat = try parseScore(score).flatMap { $0 }
        let pitches = flat.compactMap(\.midi).sorted()
        guard !pitches.isEmpty else { return flat }
        let middle = Double(pitches[pitches.count / 2])
        var shift = 0
        while 440 * pow(2, (middle + Double(shift) - 69) / 12) < 700 { shift += 12 }
        while 440 * pow(2, (middle + Double(shift) - 69) / 12) >= 1400 { shift -= 12 }
        return flat.map { var n = $0; n.midi = n.midi.map { $0 + shift }; return n }
    }

    /// How long it plays, in seconds.
    public var seconds: Double {
        let notes = (try? notes()) ?? []
        return notes.reduce(0) { $0 + $1.beats * ($1.fermata ? 1.75 : 1) } * 60 / bpm
    }
}

// MARK: - Playing one

extension Pieces {
    static func playClassic(_ id: String, on stage: Stage) {
        guard let piece = Classic.all.first(where: { $0.id == id }), let notes = try? piece.notes() else { return }
        stage.say("\(piece.title) · \(piece.composer)")
        let beat = 60 / piece.bpm
        let start = mach_absolute_time()
        var at = 0.0, t = 0.0
        var previousTied = false
        for (i, note) in notes.enumerated() where !stage.cancelled {
            let length = note.beats * beat * (note.fermata ? 1.75 : 1)
            defer { at += length; previousTied = note.tied }
            guard let midi = note.midi else {
                stage.haptics.update { $0.note = "" }
                t = at + length
                stage.waitUntil(start + ticks(t))
                continue
            }
            let f = 440 * pow(2, Double(midi - 69) / 12)
            let name = noteName(f)
            stage.haptics.update { $0.note = name }
            // A short breath before the next note, so repeated notes stay separate (none when tied).
            let gap = note.tied ? 0 : min(0.06, max(0.02, length * 0.1))
            let sounding = length - gap
            let last = i == notes.count - 1
            t = at
            while t < at + sounding && !stage.cancelled {
                let age = t - at
                var level = previousTied || age >= 0.012 ? 1.0 : 0.6 + 0.4 * age / 0.012
                if last { level *= max(0.15, 1 - age / sounding) }
                // A little vibrato on long notes, like a singer.
                let vibrato = age > 0.25 ? 0.15 * min(1, (age - 0.25) / 0.3) * sin(2 * .pi * 5.5 * age) : 0
                let freq = f * pow(2, vibrato / 12)
                let seg = max(1, (0.03 * freq).rounded()) / freq
                stage.play([Tone(freq, 1)], ms: min(seg, at + sounding - t + 0.002) * 1000, level: Float(0.95 * level))
                t += seg
                stage.waitUntil(start + ticks(t))
            }
            t = at + length
            stage.waitUntil(start + ticks(t))
        }
        stage.haptics.update { $0.note = "" }
    }
}
