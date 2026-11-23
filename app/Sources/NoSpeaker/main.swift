// NoSpeaker: your trackpad has no speaker. This makes it one.
//
//   NoSpeaker                       the app
//   NoSpeaker --snapshot <folder>   renders every tab, light and dark, to PNGs (sample data, no sound)

import AppKit
import HapticEngine
import SwiftUI

struct NoSpeakerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("NoSpeaker", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 720)
                .onDisappear { model.stop() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 800)
        .commands {
            CommandMenu("Playback") {
                Button("Play Music Through the Trackpad") { model.playMusic() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                Divider()
                Button("Volume Up") { model.volume = min(1, model.volume + 0.1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Volume Down") { model.volume = max(0, model.volume - 0.1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button("Look for Trackpads Again") { model.rescan() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    /// The motors close and the music tap goes away before the app does.
    func applicationWillTerminate(_ notification: Notification) {
        Haptics.shared.stop()
        usleep(120_000)
    }
}

// MARK: - Design snapshots

enum Snapshots {
    static func render(to folder: URL) throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            for tab in AppModel.Tab.allCases {
                let model = AppModel(preview: true)
                model.showPreview(tab: tab)
                let root = ContentView()
                    .environment(model)
                    .environment(\.liveSample, sampleLive(tab))
                let view = NSHostingView(rootView: root)
                view.frame = NSRect(x: 0, y: 0, width: 1120, height: 800)
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = folder.appending(path: "\(tab.number)-\(tab.rawValue)-\(dark ? "dark" : "light").png")
                try rep.representation(using: .png, properties: [:])?.write(to: file)
                let smallest = NSHostingController(rootView: root).sizeThatFits(in: .zero)
                print(file.lastPathComponent, "— smallest window: \(Int(smallest.width)) × \(Int(smallest.height))")
            }
        }
    }

    /// What the readouts show in a snapshot: a moment of playing.
    static func sampleLive(_ tab: AppModel.Tab) -> LiveState {
        var live = LiveState()
        live.lastPlay = 10
        live.actuations = 18_342
        switch tab {
        case .music:
            live.playing = .music
            live.tones = [Tone(523, 0.5), Tone(784, 0.3), Tone(1318, 0.15), Tone(880, 0.25)]
            live.hz = 523; live.level = 0.7; live.input = 0.64
        case .say:
            live.playing = .say
            live.caption = "hello from the trackpad"; live.captionStart = 9; live.captionDuration = 1.6
            live.f0 = 118; live.f1 = 610; live.f2 = 1720; live.hz = 610; live.level = 0.8
            live.tones = [Tone(610, 0.55), Tone(1720, 0.45)]
        case .play:
            live.playing = .instrument
            live.touchDown = true; live.touchX = 0.62; live.touchY = 0.55
            live.note = "G6"; live.hz = 1568; live.level = 0.75
        case .show:
            live.playing = .melody
            live.note = "A6"; live.hz = 1760; live.level = 0.9
        }
        return live
    }
}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let folder = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : "snapshots"
    do { try Snapshots.render(to: URL(fileURLWithPath: folder)) } catch { print("snapshot failed: \(error)"); exit(1) }
    exit(0)
}

NoSpeakerApp.main()
