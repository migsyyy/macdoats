# MacDoats

Menu bar companion for Dota 2 on macOS. Click the MacDoats icon (a ⌘ tome) next to the battery; right-click for About / Quit.

- Blocks macOS shortcuts (⌘Q, ⌘W, ⌘H, … ) while Dota is frontmost — one toggle; **Customize…** opens
  the advanced window to edit/record the list
- Alt-Tab / ⌘Tab switches apps (on by default); Alt is whichever key you mapped to ⌥
- Customize… window lists each blocked shortcut with what it does, including screenshot / ⌘⇧+number hotkeys (restored on leave/quit/relaunch)
- Locks the cursor inside the Dota window (panic toggle: ⌃⌥⌘L, works anywhere)
- Remaps fn / ⌃ / ⌥ / ⌘ by dragging the four key squares; presets: Mac, Windows (Ctrl · Fn · Win · Alt)
- Shows whether the 🌐 fn key still opens the emoji picker, with a shortcut to Keyboard settings to turn it off

## Build & run

    ./build.sh && open build/MacDoats.app

The app icon comes from `design/logo/kit/export/MacDoats.icns`, which `build.sh` copies into the bundle.

Needs **Accessibility** (System Settings → Privacy & Security). The build is ad-hoc signed, so every
rebuild invalidates the grant: remove MacDoats from the list and re-add it.

Test without Dota: `defaults write dev.macdoats.app targetBundleIDs -array com.apple.TextEdit`
(undo with `defaults delete dev.macdoats.app targetBundleIDs`). Logic check: `swift run MacDoats --selftest`.
