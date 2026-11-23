// Music through the trackpad. A Core Audio process tap hears what Music (or the whole Mac) is playing, and can
// mute it on the speakers while it listens. Every ~12 ms, an FFT finds the strongest notes the motor can play
// (100 Hz–4 kHz) and the kick drum, and the motor plays them.

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import os
import Synchronization

/// Read with: log stream --predicate 'subsystem == "app.nospeaker"'
let musicLog = Logger(subsystem: "app.nospeaker", category: "music")

public enum MusicSource: String, Sendable, CaseIterable, Identifiable {
    case appleMusic, everything
    public var id: String { rawValue }
}

enum TapError: Error {
    case noOutputDevice
    case musicNotOpen
    case failed(String, OSStatus)

    var explanation: String {
        switch self {
        case .noOutputDevice: "There's no sound output on this Mac to listen to."
        case .musicNotOpen: "Open Music and start a song, then press play here."
        case let .failed(step, status): "Couldn't listen to the music (\(step), error \(status))."
        }
    }
}

// MARK: - Samples from the tap

/// The most recent audio, mixed to mono. Written on Core Audio's I/O thread, read by the music loop.
final class SampleRing: Sendable {
    private struct Storage {
        var samples = [Float](repeating: 0, count: 1 << 15)
        var written = 0
        var heard = false
        mutating func push(_ x: Float) {
            samples[written & (samples.count - 1)] = x
            written &+= 1
            if x != 0 { heard = true }
        }
    }
    private let storage = Mutex(Storage())

    func write(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mDataByteSize > 0 else { return }
        storage.withLock { s in
            if buffers.count == 1 {
                // Interleaved: every frame holds every channel.
                let channels = max(1, Int(first.mNumberChannels))
                let frames = Int(first.mDataByteSize) / (4 * channels)
                guard let p = first.mData?.assumingMemoryBound(to: Float.self) else { return }
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += p[f * channels + c] }
                    s.push(sum / Float(channels))
                }
            } else {
                // One buffer per channel.
                let frames = Int(first.mDataByteSize) / 4
                for f in 0..<frames {
                    var sum: Float = 0, n: Float = 0
                    for b in buffers { if let p = b.mData?.assumingMemoryBound(to: Float.self) { sum += p[f]; n += 1 } }
                    s.push(sum / max(1, n))
                }
            }
        }
    }

    /// Copies the newest `out.count` samples into `out`. Returns whether any sound has arrived yet.
    @discardableResult
    func latest(into out: inout [Float]) -> Bool {
        storage.withLock { s in
            let n = out.count, size = s.samples.count
            for i in 0..<n { out[i] = s.samples[(s.written - n + i) & (size - 1)] }
            return s.heard
        }
    }
}

// MARK: - The tap

/// Listens to Music (or everything) through a private process tap and a private aggregate device. Nothing is
/// left behind: close() removes both, and macOS removes them if the app quits.
final class AudioTap {
    let ring = SampleRing()
    private(set) var sampleRate = 48000.0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "nospeaker tap", qos: .userInteractive)

    init(source: MusicSource, muteSpeakers: Bool) throws(TapError) {
        guard let outputUID = Self.defaultOutputUID() else { throw .noOutputDevice }

        let description: CATapDescription
        switch source {
        case .appleMusic:
            let processes = Self.audioProcesses().filter { Self.bundleID(of: $0)?.hasPrefix("com.apple.Music") == true }
            musicLog.notice("Music audio processes: \(processes.map { "\($0) (\(Self.bundleID(of: $0) ?? "?"))" }.joined(separator: ", "), privacy: .public)")
            description = CATapDescription(stereoMixdownOfProcesses: processes)
            if #available(macOS 26.0, *) {
                // Follows Music by name, so it keeps listening if Music restarts.
                description.bundleIDs = ["com.apple.Music"]
                description.isProcessRestoreEnabled = true
            } else if processes.isEmpty {
                throw .musicNotOpen
            }
            description.muteBehavior = muteSpeakers ? .mutedWhenTapped : .unmuted
        case .everything:
            // Never muted: muting a whole-Mac tap would silence every app.
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.muteBehavior = .unmuted
        }
        description.uuid = UUID()
        description.name = "NoSpeaker"
        description.isPrivate = true

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        musicLog.notice("create tap (\(source.rawValue, privacy: .public), mute \(muteSpeakers)): status \(status), tap \(self.tapID)")
        guard status == noErr else { throw .failed("creating the tap", status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }
        musicLog.notice("tap format: \(format.mSampleRate) Hz, \(format.mChannelsPerFrame) ch, \(format.mBitsPerChannel) bit, flags \(format.mFormatFlags), output \(outputUID, privacy: .public)")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            close()
            throw .failed("reading the tap's format", -1)
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NoSpeaker Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        musicLog.notice("create aggregate device: status \(status), device \(self.aggregateID)")
        guard status == noErr else { close(); throw .failed("creating the listening device", status) }

        let ring = self.ring
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in ring.write(input) }
        guard status == noErr else { close(); throw .failed("starting to listen", status) }
        status = AudioDeviceStart(aggregateID, procID)
        musicLog.notice("start listening: status \(status)")
        guard status == noErr else { close(); throw .failed("starting to listen", status) }
    }

    func close() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { close() }

    // MARK: Core Audio lookups

    static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func bundleID(of process: AudioObjectID) -> String? {
        string(process, kAudioProcessPropertyBundleID)
    }

    static func defaultOutputUID() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: - From music to motor

/// How the music plays on the motor.
public struct MusicSettings: Sendable, Equatable {
    public var source: MusicSource = .appleMusic
    public var speakersToo = false
    /// The tune: one clean note at a time.
    public var melody = true
    /// The kick drum: a thump.
    public var beat = true
    public init() {}
}

/// Turns the newest slice of music into what the motor plays next, kept simple on purpose: one note of the
/// tune, rounded to the nearest semitone and moved into the octave where the motor rings cleanest, plus a
/// thump on each kick drum. Chords and noise are left out: on one small motor they only buzz.
struct MusicAnalyser {
    struct Moment { var tones: [Tone] = []; var level: Float = 0; var step = 0.03; var loudness = 0.0; var note = "" }

    let sampleRate: Double
    var melody = true, beat = true
    static let size = 2048
    /// Where the tune is played: F#5 to F#6, the motor's loudest, cleanest octave.
    static let low = 740.0, high = 1480.0

    private let fft: FFT
    private let window: [Float]
    private var peakRMS: Float = 0.01
    private var bassAverage: Float = 0
    private var lastKick = -9.0
    private var heldNote: Int?, heldSince = -9.0, heldLastClear = -9.0
    private var candidate: Int?, candidateSince = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        fft = FFT(size: Self.size)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
    }

    /// The pitch of a MIDI note, moved by octaves into the clean range.
    static func motorHz(_ midi: Int) -> Double {
        var f = 440 * pow(2, Double(midi - 69) / 12)
        while f < low { f *= 2 }
        while f >= high { f /= 2 }
        return f
    }

    mutating func next(_ samples: [Float], at t: Double) -> Moment {
        var moment = Moment()
        // Loudness, against a slow-moving peak (so quiet songs still play, and loud ones don't clip).
        let recent = samples.suffix(1024)
        let rms = sqrt(recent.reduce(0) { $0 + $1 * $1 } / Float(recent.count))
        peakRMS = max(rms, peakRMS * 0.9995, 0.003)
        let loud = rms / peakRMS
        moment.loudness = Double(min(1, loud))
        guard loud > 0.06, rms > 1e-5 else { heldNote = nil; candidate = nil; return moment }
        let level = Double(pow(loud, 0.6))

        let mags = fft.magnitudes(vDSP.multiply(samples, window))
        let binHz = sampleRate / Double(Self.size)
        func bin(_ hz: Double) -> Int { min(mags.count - 2, max(1, Int(hz / binHz))) }

        // The kick drum: a jump in the low band.
        var bass: Float = 0
        for k in bin(40)...bin(140) { bass += mags[k] * mags[k] }
        if bass > 2.2 * bassAverage, bass > 1e-6, t - lastKick > 0.15 { lastKick = t }
        bassAverage = 0.85 * bassAverage + 0.15 * bass

        if melody, let note = tuneNote(mags, binHz: binHz, at: t) {
            let f = Self.motorHz(note)
            let age = t - heldSince
            let attack = age < 0.012 ? 0.55 + 0.45 * age / 0.012 : 1
            moment.tones.append(Tone(f, 0.75 * level * attack))
            moment.note = Pieces.noteName(f)
            // Restart on a whole number of periods (~30 ms), so the note rings instead of clicking.
            moment.step = max(1, (0.03 * f).rounded()) / f
        }

        let age = t - lastKick
        if beat, age < 0.12 {
            let f = 120 + 780 * exp(-age / 0.02)
            moment.tones.append(Tone(f, Double(min(1, loud)) * exp(-age / 0.05)))
            moment.step = min(moment.step, max(0.004, 1 / f))
        }
        moment.level = Float(min(1, moment.tones.reduce(0) { $0 + $1.amp }))
        return moment
    }

    /// The tune's note right now (a MIDI number), or nil. A harmonic sum finds the strongest pitch between
    /// 150 Hz and 1.6 kHz; it has to stand out from the rest, and a new note has to last 50 ms before it
    /// takes over, so the motor doesn't flicker between notes.
    private mutating func tuneNote(_ mags: [Float], binHz: Double, at t: Double) -> Int? {
        let lo = max(2, Int(150 / binHz)), hi = min(mags.count / 3 - 2, Int(1600 / binHz))
        var best = lo, bestScore: Float = 0, sum: Float = 0
        for k in lo...hi {
            let h2 = max(mags[2 * k - 1], mags[2 * k], mags[2 * k + 1])
            let h3 = max(mags[3 * k - 1], mags[3 * k], mags[3 * k + 1])
            let score = mags[k] + 0.6 * h2 + 0.35 * h3
            sum += mags[k]
            if score > bestScore { bestScore = score; best = k }
        }
        let mean = sum / Float(hi - lo + 1)
        let clear = mags[best] > 5 * mean
        var note: Int?
        if clear {
            let a = log(mags[best - 1] + 1e-9), b = log(mags[best] + 1e-9), c = log(mags[best + 1] + 1e-9)
            let shift = Double(0.5 * (a - c) / (a - 2 * b + c))
            let hz = (Double(best) + (shift.isFinite ? max(-0.5, min(0.5, shift)) : 0)) * binHz
            note = Int((69 + 12 * log2(hz / 440)).rounded())
            heldLastClear = t
        }
        if let note, note != heldNote {
            if note != candidate { candidate = note; candidateSince = t }
            if t - candidateSince >= 0.05 || heldNote == nil && t - candidateSince >= 0.02 {
                heldNote = note; heldSince = t; candidate = nil
            }
        } else if note == heldNote {
            candidate = nil
        }
        // No clear note for a moment: let the held one go.
        if t - heldLastClear > 0.12 { heldNote = nil }
        return heldNote
    }
}

/// A real-input FFT of a fixed size, returning magnitudes.
final class FFT {
    private let setup: FFTSetup
    private let log2n: vDSP_Length
    private let half: Int
    private var real: [Float], imag: [Float]

    init(size: Int) {
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        half = size / 2
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func magnitudes(_ x: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0      // that slot holds the Nyquist bin, not part of bin 0
                vDSP_zvabs(&split, 1, &out, 1, vDSP_Length(half))
            }
        }
        return out
    }
}

// MARK: - The music loop

enum MusicPlayer {
    static func play(_ settings: MusicSettings, on stage: Stage) {
        stage.say("listening")
        let tap: AudioTap
        do {
            tap = try AudioTap(source: settings.source, muteSpeakers: settings.source == .appleMusic && !settings.speakersToo)
        } catch {
            musicLog.error("couldn't listen: \(error.explanation, privacy: .public)")
            stage.haptics.update { $0.problem = error.explanation }
            return
        }
        defer { tap.close(); musicLog.notice("stopped listening") }
        var analyser = MusicAnalyser(sampleRate: tap.sampleRate)
        analyser.melody = settings.melody
        analyser.beat = settings.beat
        var samples = [Float](repeating: 0, count: MusicAnalyser.size)
        let start = mach_absolute_time()
        var t = 0.0
        var waiting = true, everHeard = false
        while !stage.cancelled {
            let heard = tap.ring.latest(into: &samples)
            if heard, !everHeard {
                everHeard = true
                musicLog.notice("first sound arrived after \(String(format: "%.2f", t), privacy: .public) s")
            }
            let moment = analyser.next(samples, at: t)
            let playing = moment.level > 0.01 && !moment.tones.isEmpty
            if playing == waiting {
                waiting = !playing
                stage.say(waiting ? (heard ? "waiting for music" : "listening") : "playing")
            }
            stage.haptics.update { $0.input = moment.loudness; $0.note = moment.note; if heard { $0.problem = nil } }
            if playing { stage.play(moment.tones, ms: moment.step * 1000 + 1, level: moment.level) }
            t += playing ? moment.step : 0.02
            // Fell behind (a busy moment): skip ahead rather than rushing to catch up.
            let elapsed = Double(mach_absolute_time() - start) / Double(ticks(1))
            if elapsed - t > 0.05 { t = elapsed }
            stage.waitUntil(start + ticks(t))
        }
    }
}
