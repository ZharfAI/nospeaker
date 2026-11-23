# NoSpeaker (the window app)

Your trackpad has no speaker. This window makes it one: play **Apple Music** through the trackpad (with the
speakers muted, so all you hear is the motor), **say** anything, **play** it like an instrument, or run the
**show**. Pick the MacBook trackpad, a Magic Trackpad, or both.

```sh
./build-app.sh            # build/NoSpeaker.app
./build-app.sh install    # and copy it to ~/Applications
swift test                # engine tests (silent: nothing plays)
.build/debug/NoSpeaker --snapshot shots/   # render every tab, light and dark, with sample data (silent)
```

- **Music** listens through a Core Audio process tap (macOS 14.4+; tapping Music by bundle ID needs macOS 26).
  The first time, macOS asks to allow **system audio recording** and **controlling Music**; both can be changed
  in System Settings › Privacy & Security.
- **Stop** is always there: the sidebar button, **esc**, or **⌘.**. Closing the window stops the motors.
- `Sources/HapticEngine` drives the motors (MultitouchSupport, a private framework: it may change with any
  macOS update). `Sources/NoSpeaker` is the SwiftUI app.

Sound design (the voice, sweep, melody, beat, heartbeat, sparkle and instrument) comes from
[nospeaker](https://github.com/os6/nospeaker) by Cody Collier, MIT License.
