# Pitatto

**English** | [日本語](README.ja.md)

A menu bar app that maximizes the front window on macOS or moves it to an edge of the screen with one shortcut.
Pressing the same key again changes the size from 1/2 to 1/4 to 3/4. Left and right change the width,
top and bottom change the height. Maximize goes from the whole screen to a 64 pt margin and then a 24 pt one,
with the window centred and the margin on all four sides. Each size can also have a key of its own.

| Action | Default key |
| --- | --- |
| Maximize | ⌃⌘↩ |
| Move left | ⌃⌘← |
| Move right | ⌃⌘→ |
| Move up | ⌃⌘↑ |
| Move down | ⌃⌘↓ |
| Move to the left desktop | ⌃⇧⌘← |
| Move to the right desktop | ⌃⇧⌘→ |

Maximize fills the screen minus the menu bar and the Dock; it does not enter macOS full screen.
Moving to a desktop switches the screen to that desktop along with the window. It needs "Move left
a space" and "Move right a space" turned on in System Settings, under Keyboard Shortcuts > Mission Control.
The app lives in the menu bar and shows a Dock icon only while its settings window is open.
It goes online only to check for and download updates.

The interface is in Japanese.

## Requirements

macOS 14 or later, and the Accessibility permission to move windows. On first launch, choose
「アクセシビリティを許可…」 in the menu to open System Settings, then turn Pitatto on.

## Install

Download `Pitatto-<version>.zip` from [Releases](https://github.com/senkentarou/pitatto/releases),
unzip it, and move `Pitatto.app` to `/Applications`.

## Updates

Pitatto checks for a new release at launch and once a day. When one is out, the menu shows
「新しいバージョン x.y.z があります…」, which opens the update window; 「更新して再起動」 there
downloads the release and replaces the app. 「アップデートを確認…」 in the menu checks on demand.

## Build

```
make check   # lint, build, test
make run     # install to /Applications and launch
```

`make app` and `make run` sign the `.app`. The default identity is `Pitatto Dev`, a self-signed
code signing certificate you create once with Certificate Assistant in Keychain Access.
To sign with another certificate, pass it in the environment:

```
CODESIGN_IDENTITY="Developer ID Application: ..." make run
```

Do not sign ad hoc (`-`). A signature that changes on every build makes macOS treat each build as
a new app and drop the Accessibility permission.

`Sources/PitattoCore` holds the decisions and imports only Foundation and CoreGraphics;
`Sources/Pitatto` holds the OS calls. `make lint` fails on any other import in Core.

`Pitatto.app/Contents/MacOS/Pitatto --print-frame [app]` prints the front window's frame — or the
focused window of the named app — as `x y width height` in AppKit coordinates, for checking where a
snap put it.

## Settings

Open 「設定…」 from the menu bar icon. Changes apply immediately.

- General: launch at login, Accessibility permission status
- Shortcuts: one table for maximize and one for the edges, one row per action. The cycle column holds
  the keys above. The 15 fixed sizes (whole, 64 pt and 24 pt margin for maximize; 1/2, 1/4 and 3/4
  for the edges) have no key by default. Below them, the two desktop moves
- Credits

Click a field, then press a key combination. ⎋ cancels, ⌫ removes the key.

The sizes are fixed: 1/2, 1/4 and 3/4 for the edges, and the whole screen or a 64 or 24 pt margin for
maximize. A size below the app's minimum window size is clamped to that minimum and kept against the
edge, so what each step does depends on the screen and the app.

## License

[GPL-3.0](LICENSE)
