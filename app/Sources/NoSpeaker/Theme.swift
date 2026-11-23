// The look, taken from the terminal show: ink on off-white paper (white on black in dark mode), greys mixed
// between the two, monospaced type, the slanted ASCII logo, square inverted chips and ASCII meters. No
// gradients, no glass; red only for problems.

import AppKit
import SwiftUI

// MARK: - Colour

extension Color {
    /// A grey `u` of the way from paper (0) to ink (1), in both appearances.
    static func mix(_ u: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let paper: (Double, Double, Double) = dark ? (0, 0, 0) : (246, 245, 241)
            let ink: (Double, Double, Double) = dark ? (255, 255, 255) : (12, 12, 12)
            func c(_ p: Double, _ i: Double) -> CGFloat { CGFloat((p + (i - p) * u) / 255) }
            return NSColor(srgbRed: c(paper.0, ink.0), green: c(paper.1, ink.1), blue: c(paper.2, ink.2), alpha: 1)
        })
    }

    static let paper = mix(0)
    static let ink = mix(1)
    static let body = mix(0.84)    // the terminal's grey 251
    static let mid = mix(0.67)     // 247
    static let dim = mix(0.50)     // 243
    static let rule = mix(0.38)    // 240
    static let faint = mix(0.22)   // 236
    static let wash = mix(0.06)    // hover
    static let alarm = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0.42, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.78, green: 0.12, blue: 0.10, alpha: 1)
    })
}

// MARK: - Type

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - The logo

let asciiLogo = [
    "    _   __ ____      _____  ____   ______ ___     __ __  ______ ____",
    "   / | / // __ \\    / ___/ / __ \\ / ____//   |   / //_/ / ____// __ \\",
    "  /  |/ // / / /    \\__ \\ / /_/ // __/  / /| |  / ,<   / __/  / /_/ /",
    " / /|  // /_/ /    ___/ // ____// /___ / ___ | / /| | / /___ / _, _/",
    "/_/ |_/ \\____/    /____//_/    /_____//_/  |_|/_/ |_|/_____//_/ |_|",
]
let logoColumns = asciiLogo.map(\.count).max() ?? 0

/// "a90.com presents" between rules, the slanted NO SPEAKER, and the tag rule under it — the terminal show's
/// lockup, column for column.
struct Lockup: View {
    var size: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ruleLine(center: "a90.com presents")
                .padding(.bottom, size * 0.9)
            Text(asciiLogo.joined(separator: "\n"))
                .font(.mono(size, .bold))
                .foregroundStyle(Color.ink)
                .lineSpacing(0)
                .fixedSize()
                .accessibilityLabel("No Speaker")
            tagLine
                .padding(.top, size * 0.9)
        }
        .fixedSize()
    }

    private func ruleLine(center: String) -> some View {
        let side = (logoColumns - center.count - 4) / 2
        return (Text(String(repeating: "─", count: side) + "  ").foregroundStyle(Color.dim)
            + Text(center).foregroundStyle(Color.body).bold()
            + Text("  " + String(repeating: "─", count: logoColumns - center.count - 4 - side)).foregroundStyle(Color.dim))
            .font(.mono(size))
    }

    private var tagLine: some View {
        let left = "─  haptic voice synthesis  ", right = "  trackpad  ─"
        let fill = String(repeating: "─", count: max(1, logoColumns - left.count - right.count))
        return (Text("─  ").foregroundStyle(Color.dim)
            + Text("haptic voice synthesis").foregroundStyle(Color.mid)
            + Text("  " + fill + "  ").foregroundStyle(Color.dim)
            + Text("trackpad").foregroundStyle(Color.ink).bold()
            + Text("  ─").foregroundStyle(Color.dim))
            .font(.mono(size))
    }
}

// MARK: - Pieces of the look

/// A section label: "VOLUME ───────────".
struct SectionRule: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.mono(10.5, .bold))
                .tracking(1.5)
                .foregroundStyle(Color.ink)
            Rectangle().fill(Color.faint).frame(height: 1)
            if let trailing {
                Text(trailing).font(.mono(10.5)).foregroundStyle(Color.dim)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// "[=========>        ]"
func asciiBar(_ value: Double, columns: Int) -> String {
    let inner = max(1, columns - 2)
    let fill = Int((max(0, min(1, value)) * Double(inner)).rounded())
    return "[" + String(repeating: "=", count: max(0, fill - 1)) + (fill > 0 ? ">" : "") + String(repeating: " ", count: inner - fill) + "]"
}

/// Classic ASCII shading, light to dense.
let shadeRamp: [Character] = [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"]
func shade(_ v: Double) -> Character { shadeRamp[max(0, min(shadeRamp.count - 1, Int(v * Double(shadeRamp.count - 1) + 0.5)))] }

/// A square chip: hairline border, inverted when selected or pressed, a light wash on hover.
struct ChipStyle: ButtonStyle {
    var selected = false
    var size: CGFloat = 12
    var padding = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, selected: selected, size: size, padding: padding)
    }

    private struct ChipBody: View {
        let configuration: Configuration
        let selected: Bool
        let size: CGFloat
        let padding: EdgeInsets
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let on = selected || configuration.isPressed
            configuration.label
                .font(.mono(size, on ? .bold : .regular))
                .foregroundStyle(on ? Color.paper : enabled ? Color.ink : Color.dim)
                .padding(padding)
                .background(on ? Color.ink : hovering && enabled ? Color.wash : Color.clear)
                .overlay(Rectangle().strokeBorder(on ? Color.ink : enabled ? Color.rule : Color.faint, lineWidth: 1))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// The one big action on a panel: solid ink, paper text.
struct PrimaryStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, active: active)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        let active: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.mono(13, .bold))
                .tracking(1)
                .foregroundStyle(enabled ? Color.paper : Color.mid)
                .padding(.horizontal, 18)
                .frame(minHeight: 42)
                .background(enabled ? (configuration.isPressed ? Color.body : Color.ink) : Color.faint)
                .overlay(alignment: .bottom) {
                    // A strip that grows under the label while it plays: the motor's "on" light.
                    if active { Rectangle().fill(Color.paper.opacity(0.85)).frame(height: 3) }
                }
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .opacity(hovering && enabled && !configuration.isPressed ? 0.92 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// An ASCII slider: "[=========>        ] 60%". Drag or click along it, or use the arrow keys.
struct AsciiSlider: View {
    @Binding var value: Double
    var columns = 22
    var label: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(asciiBar(value, columns: columns))
                .font(.mono(13))
                .foregroundStyle(Color.ink)
                .fixedSize()
                .overlay {
                    GeometryReader { proxy in
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                // The brackets take one column each; the fill runs between them.
                                let column = proxy.size.width / CGFloat(columns)
                                let x = (drag.location.x - column) / (proxy.size.width - 2 * column)
                                value = (Double(max(0, min(1, x))) * 20).rounded() / 20
                            })
                    }
                }
            Text("\(Int((value * 100).rounded()))%")
                .font(.mono(12, .bold))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) { if focused { Rectangle().fill(Color.ink).frame(height: 1).offset(y: 3) } }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { value = max(0, value - 0.05); return .handled }
        .onKeyPress(.rightArrow) { value = min(1, value + 0.05); return .handled }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }
}

/// A hairline.
struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(Color.faint).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
