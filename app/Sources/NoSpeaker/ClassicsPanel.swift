import HapticEngine
import SwiftUI

struct ClassicsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("▸ THE CLASSICS").font(.mono(13, .bold))
                Spacer()
                Text("\(Classic.all.count) pieces · all public domain").font(.mono(11)).foregroundStyle(Color.dim)
            }
            Text("famous openings, one clean note at a time, in the motor's best octave.")
                .font(.mono(12))
                .foregroundStyle(Color.mid)
                .padding(.top, 4)

            HStack(alignment: .center, spacing: 24) {
                PianoRoll()
                    .frame(maxWidth: .infinity, alignment: .leading)
                NoteReadout()
                    .frame(width: 180, alignment: .leading)
            }
            .padding(.top, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                    ForEach(Classic.all) { piece in
                        ClassicRow(piece: piece, playing: model.isPlaying(.classic(piece.id))) {
                            model.toggle(.classic(piece.id))
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
            .padding(.top, 16)
        }
    }
}

struct ClassicRow: View {
    let piece: Classic
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(playing ? "■" : "▶")
                    .font(.mono(12, .bold))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(piece.title).font(.mono(13, .bold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(duration).font(.mono(11)).foregroundStyle(playing ? Color.paper.opacity(0.7) : Color.dim)
                    }
                    Text("\(piece.composer) · \(String(piece.year))")
                        .font(.mono(11.5))
                        .foregroundStyle(playing ? Color.paper.opacity(0.85) : Color.body)
                    Text(piece.work)
                        .font(.mono(10.5))
                        .foregroundStyle(playing ? Color.paper.opacity(0.65) : Color.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(playing ? Color.paper : Color.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(playing ? Color.ink : hovering ? Color.wash : Color.clear)
            .overlay(Rectangle().strokeBorder(playing || hovering ? Color.ink : Color.faint, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(playing ? "Stop \(piece.title)" : "Play \(piece.title) by \(piece.composer), \(duration)")
    }

    private var duration: String {
        let s = Int(piece.seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The notes as they pass, in ASCII, like the terminal show's piano roll: higher notes higher, the newest on
/// the right.
struct PianoRoll: View {
    @Environment(\.liveSample) private var sample
    @Environment(AppModel.self) private var model
    @State private var memory = RollMemory()

    static let rows = 9, columns = 58
    /// The range drawn: the classics sit around 700 Hz to 1.4 kHz once moved into the motor's octave.
    static let low = 420.0, high = 2800.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sample == nil && model.playing == nil)) { context in
            let live = sample ?? Haptics.shared.snapshot()
            let t = sample == nil ? Haptics.shared.time : live.lastPlay
            let on = t - live.lastPlay < 0.06 && !live.note.isEmpty
            let history = memory.advance(to: context.date, row: on ? Self.row(live.hz) : nil, sample: sample != nil)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<Self.rows, id: \.self) { r in
                    Text(line(r, history)).lineLimit(1).fixedSize()
                }
            }
            .font(.mono(11, .bold))
        }
        .accessibilityHidden(true)
    }

    static func row(_ hz: Double) -> Int {
        let u = log2(max(low, min(high, hz)) / low) / log2(high / low)
        return max(0, min(rows - 1, rows - 1 - Int((u * Double(rows)).rounded(.down))))
    }

    private func line(_ r: Int, _ history: [Int?]) -> AttributedString {
        var out = AttributedString()
        var run = "", runInk = false
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            piece.foregroundColor = runInk ? Color.ink : Color.faint
            out += piece
            run = ""
        }
        for (c, row) in history.enumerated() {
            let hit = row == r
            let ch: Character = hit ? (c == history.count - 1 ? "o" : "=") : "·"
            if hit != runInk { flush(); runInk = hit }
            run.append(ch)
        }
        flush()
        return out
    }
}

/// The roll's memory, outside SwiftUI's state so drawing a frame can move it on.
final class RollMemory {
    private(set) var columns = [Int?](repeating: nil, count: PianoRoll.columns)
    private var last = Date.distantPast

    func advance(to date: Date, row: Int?, sample: Bool) -> [Int?] {
        if sample {
            // A contour to show in design snapshots.
            let tune = [6, 6, 5, 5, 6, 6, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 8, 8, 6, 6, 4, 4, 5, 5, 6, 6, 6, 6]
            columns = [Int?](repeating: nil, count: PianoRoll.columns - tune.count) + tune.map { Optional(PianoRoll.rows - 1 - $0) }
            return columns
        }
        if date.timeIntervalSince(last) >= 1.0 / 15 {
            last = date
            columns.removeFirst()
            columns.append(row)
        }
        return columns
    }
}
