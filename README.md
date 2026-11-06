# noot

Tiny, ephemeral note windows for macOS. Press a shortcut, get a little monospaced
text pane, type, close it — and it's gone forever. Nothing is ever saved.

## Install

Requires the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/danew/noot.git
cd noot
./build.sh --install
open /Applications/noot.app
```

Add it to **System Settings → General → Login Items** to start it at login.

## Usage

| Action | How |
| --- | --- |
| New note (anywhere) | `⌃⌥N` |
| New note (when noot is active) | `⌘N` |
| Close note (gone forever) | `⌘W` |
| Move | drag the dot at the top centre |
| Resize | drag a corner (both axes) or a side (one axis) |
| Pin on top (dot fills) | double-click the dot, or `⌘T` |
| Quit | menu bar icon → Quit |

Shortcut, padding, font size and window size are constants at the top of
`Sources/main.swift`.
