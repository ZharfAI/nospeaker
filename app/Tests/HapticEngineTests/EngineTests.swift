// Silent tests: nothing here plays on a motor.
import CoreAudio
import Foundation
import Testing
@testable import HapticEngine

/// A test signal: sines at these frequencies, at 48 kHz.
func chord(_ freqs: [Double], count: Int = MusicAnalyser.size, rate: Double = 48000, amp: Float = 0.2) -> [Float] {
    (0..<count).map { i in freqs.reduce(Float(0)) { $0 + amp * Float(sin(2 * .pi * $1 * Double(i) / rate)) } }
}

@Test func `the analyser finds the notes of a chord`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    var moment = MusicAnalyser.Moment()
    for step in 0..<20 { moment = analyser.next(chord([440, 660, 990]), at: Double(step) * 0.012) }
    let found = moment.tones.map(\.hz).sorted()
    #expect(found.count == 3)
    for (got, want) in zip(found, [440.0, 660, 990]) { #expect(abs(got - want) < 6, "found \(got) Hz, wanted \(want)") }
    #expect(moment.level > 0.3)
    #expect(moment.tones.allSatisfy { $0.hz >= 100 && $0.hz <= 4000 })
}

@Test func `silence plays nothing`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    let moment = analyser.next([Float](repeating: 0, count: MusicAnalyser.size), at: 0)
    #expect(moment.tones.isEmpty)
    #expect(moment.level == 0)
}

@Test func `a kick drum becomes a thump`() {
    var analyser = MusicAnalyser(sampleRate: 48000)
    // A steady high note, then a burst of 60 Hz on top.
    for step in 0..<30 { _ = analyser.next(chord([1200]), at: Double(step) * 0.012) }
    let kick = analyser.next(chord([1200]) .enumerated().map { $1 + chord([60], amp: 0.8)[$0] }, at: 0.4)
    #expect(kick.tones.contains { $0.hz > 700 && $0.hz < 1000.1 && $0.hz != 1200 }, "tones: \(kick.tones)")
    #expect(kick.step <= 0.012)
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
