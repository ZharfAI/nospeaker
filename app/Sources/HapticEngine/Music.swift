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

/// Turns the newest slice of music into what the motor plays next.
struct MusicAnalyser {
    struct Moment { var tones: [Tone] = []; var level: Float = 0; var step = 0.012; var loudness = 0.0 }

    let sampleRate: Double
    static let size = 2048
    private let fft: FFT
    private let window: [Float]
    private var peakRMS: Float = 0.01
    private var bassAverage: Float = 0
    private var lastKick = -9.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        fft = FFT(size: Self.size)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
    }

    mutating func next(_ samples: [Float], at t: Double) -> Moment {
        var moment = Moment()
        // Loudness, against a slow-moving peak (so quiet songs still play, and loud ones don't clip).
        let recent = samples.suffix(1024)
        let rms = sqrt(recent.reduce(0) { $0 + $1 * $1 } / Float(recent.count))
        peakRMS = max(rms, peakRMS * 0.9995, 0.003)
        let loud = rms / peakRMS
        moment.loudness = Double(min(1, loud))
        guard loud > 0.05, rms > 1e-5 else { return moment }
        let level = pow(loud, 0.7)

        let mags = fft.magnitudes(vDSP.multiply(samples, window))
        let binHz = sampleRate / Double(Self.size)
        func bin(_ hz: Double) -> Int { min(mags.count - 2, max(1, Int(hz / binHz))) }

        // The kick drum: a jump in the low band.
        var bass: Float = 0
        for k in bin(40)...bin(140) { bass += mags[k] * mags[k] }
        if bass > 2.2 * bassAverage, bass > 1e-6, t - lastKick > 0.15 { lastKick = t }
        bassAverage = 0.85 * bassAverage + 0.15 * bass

        // The strongest notes the motor can play, favouring its clearest range.
        let top = mags[bin(110)...bin(4000)].max() ?? 0
        var peaks: [(hz: Double, score: Float)] = []
        for k in bin(110)...bin(4000) where mags[k] > mags[k - 1] && mags[k] >= mags[k + 1] && mags[k] > top * 0.08 {
            let a = log(mags[k - 1] + 1e-9), b = log(mags[k] + 1e-9), c = log(mags[k + 1] + 1e-9)
            let shift = Double(0.5 * (a - c) / (a - 2 * b + c))
            let hz = (Double(k) + (shift.isFinite ? max(-0.5, min(0.5, shift)) : 0)) * binHz
            let weight: Float = hz < 250 ? 0.6 : hz > 3000 ? 0.7 : 1
            peaks.append((hz, mags[k] * weight))
        }
        peaks.sort { $0.score > $1.score }
        var chosen: [(hz: Double, score: Float)] = []
        for p in peaks where chosen.count < 3 && !chosen.contains(where: { max($0.hz, p.hz) / min($0.hz, p.hz) < 1.09 }) {
            chosen.append(p)
        }
        if let best = chosen.first?.score, best > 0 {
            for p in chosen { moment.tones.append(Tone(p.hz, 0.8 * Double(level) * pow(Double(p.score / best), 1.5))) }
        }
        // Restart on a whole number of the main note's periods, so it rings cleanly.
        if let f = chosen.first?.hz { moment.step = max(1, (0.012 * f).rounded()) / f }

        let age = t - lastKick
        if age < 0.14 {
            let f = 150 + 850 * exp(-age / 0.018)
            moment.tones.append(Tone(f, 1.1 * Double(min(1, loud)) * exp(-age / 0.05)))
            moment.step = max(0.004, min(moment.step, 1 / f * max(1, (0.006 * f).rounded())))
        }
        moment.tones.sort { $0.amp > $1.amp }
        moment.tones = Array(moment.tones.prefix(4))
        moment.level = Float(min(1, moment.tones.reduce(0) { $0 + $1.amp }))
        return moment
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
    static func play(_ source: MusicSource, speakersToo: Bool, on stage: Stage) {
        stage.say("listening")
        let tap: AudioTap
        do {
            tap = try AudioTap(source: source, muteSpeakers: source == .appleMusic && !speakersToo)
        } catch {
            musicLog.error("couldn't listen: \(error.explanation, privacy: .public)")
            stage.haptics.update { $0.problem = error.explanation }
            return
        }
        defer { tap.close(); musicLog.notice("stopped listening") }
        var analyser = MusicAnalyser(sampleRate: tap.sampleRate)
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
            stage.haptics.update { $0.input = moment.loudness; if heard { $0.problem = nil } }
            if playing { stage.play(moment.tones, ms: moment.step * 1000 + 1, level: moment.level) }
            t += playing ? moment.step : 0.02
            // Fell behind (a busy moment): skip ahead rather than rushing to catch up.
            let elapsed = Double(mach_absolute_time() - start) / Double(ticks(1))
            if elapsed - t > 0.05 { t = elapsed }
            stage.waitUntil(start + ticks(t))
        }
    }
}
