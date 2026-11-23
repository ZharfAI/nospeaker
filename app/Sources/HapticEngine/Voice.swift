// How it talks, from nospeaker.swift (github.com/os6/nospeaker, MIT, © 2026 Cody Collier): macOS's own voice
// (`say`) speaks the line into memory. Every 10 ms, linear prediction finds the voice's strongest resonances
// (formants), its loudness and its pitch. The motor plays the first two as sine tones, restarted on every beat
// of the pitch, so they buzz like a voice.

import AVFoundation
import Foundation

struct Frame {
    var formants: [Double] = [500, 1500, 2500]
    var amps: [Double] = [1, 0.5, 0.25]
    var level: Float = 0
    var voiced = false
    var f0 = 110.0
}

let hop = 0.010
private let sampleRate = 16000.0

/// A voice from `say -v '?'`.
public struct Voice: Identifiable, Hashable, Sendable {
    public let name: String
    public let locale: String
    public var id: String { name }
    public var language: String { String(locale.prefix { $0 != "_" }) }
    public init(name: String, locale: String) { self.name = name; self.locale = locale }
}

/// The voices this Mac has, English first.
public func installedVoices() -> [Voice] {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-v", "?"]
    process.standardOutput = pipe
    guard (try? process.run()) != nil else { return [] }
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    // "Eddy (English (US)) en_US    # Hello! My name is Eddy." — the name, then the locale, then a sample.
    let voices = text.split(separator: "\n").compactMap { row -> Voice? in
        guard let hash = row.firstIndex(of: "#") else { return nil }
        let words = row[..<hash].split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 2, let locale = words.last, locale.contains("_") else { return nil }
        return Voice(name: words.dropLast().joined(separator: " "), locale: String(locale))
    }
    return voices.sorted { a, b in
        let ae = a.language == "en", be = b.language == "en"
        return ae != be ? ae : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

enum VoiceError: Error { case sayFailed, cancelled }

/// Speaks `text` into memory with `say` and analyses it. Stops early (and throws `.cancelled`) if the stage is
/// cancelled, so Stop never waits on a long line.
func render(_ text: String, voice: String?, stage: Stage) throws(VoiceError) -> [Frame] {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nospeaker-\(getpid())-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000"] + (voice.map { ["-v", $0] } ?? []) + [text]
    do { try process.run() } catch { throw .sayFailed }
    while process.isRunning {
        if stage.cancelled { process.terminate(); throw .cancelled }
        usleep(10_000)
    }
    guard process.terminationStatus == 0, let file = try? AVAudioFile(forReading: url),
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0] else { throw .sayFailed }
    var frames = analyse(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
    while let first = frames.first, first.level == 0 { frames.removeFirst() }
    while let last = frames.last, last.level == 0 { frames.removeLast() }
    return frames
}

/// A voiced frame as two tones, F1 and F2. Two rather than three: in a blind test two were clearer, and louder,
/// because the motor's strength is split fewer ways.
func voiceTones(_ f: Frame) -> [Tone] {
    let w = [f.amps[0], f.amps[1] * 1.8]
    let sum = max(w[0] + w[1], 1e-9)
    return [Tone(f.formants[0], w[0] / sum), Tone(f.formants[1], w[1] / sum)]
}

// MARK: - Analysis

private func lpc(_ x: [Double], order p: Int) -> ([Double], Double) {
    var r = [Double](repeating: 0, count: p + 1)
    for k in 0...p { var s = 0.0; for i in k..<x.count { s += x[i] * x[i - k] }; r[k] = s }
    var a = [Double](repeating: 0, count: p + 1); a[0] = 1
    guard r[0] > 1e-12 else { return (a, 0) }
    r[0] *= 1.0001
    var e = r[0]
    for i in 1...p {
        var acc = r[i]
        for j in 1..<i { acc += a[j] * r[i - j] }
        let k = -acc / e
        var na = a
        for j in 1..<i { na[j] = a[j] + k * a[i - j] }
        na[i] = k
        a = na
        e *= 1 - k * k
    }
    return (a, e)
}

private struct Complex {
    var re: Double, im: Double
    static func + (l: Complex, r: Complex) -> Complex { Complex(re: l.re + r.re, im: l.im + r.im) }
    static func - (l: Complex, r: Complex) -> Complex { Complex(re: l.re - r.re, im: l.im - r.im) }
    static func * (l: Complex, r: Complex) -> Complex { Complex(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re) }
    static func / (l: Complex, r: Complex) -> Complex {
        let d = r.re * r.re + r.im * r.im
        return Complex(re: (l.re * r.re + l.im * r.im) / d, im: (l.im * r.re - l.re * r.im) / d)
    }
}

/// The polynomial's roots (Durand–Kerner).
private func roots(_ a: [Double]) -> [Complex] {
    let p = a.count - 1
    var z = (0..<p).map { k -> Complex in
        let angle = 2 * Double.pi * Double(k) / Double(p) + 0.4
        return Complex(re: 0.9 * cos(angle), im: 0.9 * sin(angle))
    }
    func poly(_ x: Complex) -> Complex { var s = Complex(re: 1, im: 0); for k in 1...p { s = s * x + Complex(re: a[k], im: 0) }; return s }
    for _ in 0..<300 {
        var moved = 0.0
        for i in 0..<p {
            var d = Complex(re: 1, im: 0)
            for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
            if d.re == 0 && d.im == 0 { d = Complex(re: 1e-12, im: 0) }
            let step = poly(z[i]) / d
            z[i] = z[i] - step
            moved = max(moved, abs(step.re) + abs(step.im))
        }
        if moved < 1e-10 { break }
    }
    return z
}

private func analyse(_ x: [Float]) -> [Frame] {
    let win = Int(0.025 * sampleRate), hopN = Int(hop * sampleRate), order = 18
    let hamming = (0..<win).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(win - 1)) }
    var frames: [Frame] = [], rmsList: [Double] = []
    var prev = Frame()
    var i = 0
    while i + win <= x.count {
        let seg = (0..<win).map { Double(x[i + $0]) }
        rmsList.append(sqrt(seg.reduce(0) { $0 + $1 * $1 } / Double(win)))
        var f = prev
        var zc = 0
        for k in 1..<win where (seg[k] >= 0) != (seg[k - 1] >= 0) { zc += 1 }
        var bestLag = 0, bestR = 0.0
        for lag in Int(sampleRate / 300)...Int(sampleRate / 70) where lag < win - 40 {
            var s = 0.0, ea = 0.0, eb = 0.0
            for k in 0..<(win - lag) { s += seg[k] * seg[k + lag]; ea += seg[k] * seg[k]; eb += seg[k + lag] * seg[k + lag] }
            let r = s / max(sqrt(ea * eb), 1e-12)
            if r > bestR { bestR = r; bestLag = lag }
        }
        f.voiced = bestR > 0.35 && Double(zc) / Double(win) < 0.22
        if f.voiced, bestLag > 0 { f.f0 = sampleRate / Double(bestLag) }
        var pe = [Double](repeating: 0, count: win)
        for k in 0..<win { pe[k] = (seg[k] - 0.97 * (k > 0 ? seg[k - 1] : 0)) * hamming[k] }
        let (a, err) = lpc(pe, order: order)
        var candidates: [Double] = []
        if err > 0 {
            for z in roots(a) where z.im > 0 {
                let hz = atan2(z.im, z.re) * sampleRate / (2 * .pi)
                let bw = -log(max(1e-9, sqrt(z.re * z.re + z.im * z.im))) * sampleRate / .pi
                if hz > 150, hz < 4200, bw < 500 { candidates.append(hz) }
            }
        }
        func pick(_ lo: Double, _ hi: Double, near: Double) -> Double? {
            candidates.filter { $0 >= lo && $0 <= hi }.min { abs($0 - near) < abs($1 - near) }
        }
        if let f1 = pick(200, 1000, near: prev.formants[0]) { f.formants[0] = f1 }
        if let f2 = pick(max(f.formants[0] + 200, 650), 2700, near: prev.formants[1]) { f.formants[1] = f2 }
        if let f3 = pick(max(f.formants[1] + 300, 1700), 3900, near: prev.formants[2]) { f.formants[2] = f3 }
        if err > 0 {
            f.amps = f.formants.map { hz in
                let w = 2 * Double.pi * hz / sampleRate
                var re = 0.0, im = 0.0
                for k in 0...order { re += a[k] * cos(w * Double(k)); im -= a[k] * sin(w * Double(k)) }
                return 1 / max(sqrt(re * re + im * im), 1e-6)
            }
        }
        frames.append(f)
        prev = f
        i += hopN
    }
    let peak = rmsList.max() ?? 1
    for k in frames.indices {
        let rel = rmsList[k] / max(peak, 1e-9)
        frames[k].level = rel < 0.02 ? 0 : Float(min(1, pow(rel, 0.45)))
        if frames[k].level == 0 { frames[k].voiced = false }
    }
    func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
    let raw = frames
    for k in frames.indices {
        let lo = max(0, k - 2), hi = min(frames.count - 1, k + 2)
        for j in 0..<3 { frames[k].formants[j] = median((lo...hi).map { raw[$0].formants[j] }) }
        frames[k].f0 = min(250, max(70, median((lo...hi).map { raw[$0].f0 })))
    }
    return frames
}
