# Stone (Swift)

A native macOS **note taker** for your Stone workspace. It does one job: you press one key, write a
thought, press ↩, and it's in today's journal. It shares the workspace and the config with Stone desktop
(`~/.config/stone/config.json`), so what it writes is exactly what Stone's own quick capture writes.

It's not a note editor or a note organiser. Use Stone desktop for those.

## Using it

| Where | Key | Does |
| --- | --- | --- |
| anywhere | Stone's `quickCapture.shortcut` (⌥Space) | open / close the quick note |
| quick note | ↩ | save to `Journal/YYYY-MM-DD.md` as `[HH:MM] text`, close |
| | ⇧↩ | new line |
| | esc | close. The draft is kept, even across relaunches |
| | ⌥O | notes: search previous notes, with a read-only preview |
| | ⌘J | today's journal (read-only) |
| notes | ↑↓ · type | select · search every note |
| | ↩ | copy the previewed note |
| | esc / ⌥O | back to the quick note |

The menu-bar icon has the same commands, which helps if the hotkey is taken. Stone desktop claims the same
key, so quit it, or clear `quickCapture` in desktop and run only this app. If the key can't be registered,
a message says so on launch.

## Config

It only reads Stone desktop's `~/.config/stone/config.json` and never writes it.

- `workspace.defaultWorkspacePath`: an absolute path, `~/…`, or a path relative to home (`NoteBook` becomes `~/NoteBook`).
- `notes.locationPolicy.journalFolder`: where journals go (`Journal`).
- `quickCapture.shortcut`: the global key, in Electron spelling (`Alt+Space`, `CommandOrControl+Shift+N`). Leave it empty for no hotkey.

`STONE_WORKSPACE=/some/dir` points a single run at another folder.

## Run the dev build

```sh
cd ~/projects/stone-swift
./Scripts/test.sh                                   # tests + architecture lint + Debug build
open --env STONE_WORKSPACE=/tmp/stone-test "build/Build/Products/Debug/Stone Dev.app"   # sandbox
open "build/Build/Products/Debug/Stone Dev.app"      # your real workspace
pkill -f "Stone Dev"                                 # quit (or menu bar → Quit)
```

You can also run `xcodegen generate && open Stone.xcodeproj`, then press ⌘R. Requires Xcode 16+ and macOS 15+. No dependencies.

## Architecture

The code is hexagonal, and each layer is its own SwiftPM target, so a forbidden import won't compile.

```
Packages/StoneKit/Sources/
  StoneDomain/        NoteEntity, JournalDate, LocationPolicy, AppConfig, JournalComposer, NoteSearchScorer, ports   → Foundation only
  StoneApplication/   CaptureToJournal, GetTodayJournal, ListNotes, OpenNote, SearchNotes (+ facades/factories)      → StoneDomain
  StoneAdaptersOut/   FileSystemNoteRepository, AppConfigRepository (read-only), SystemClock                        → StoneDomain
  StoneUI/            the panel, CaptureStore, BrowseStore, hotkey, HUD                                              → StoneDomain in-ports
Stone/Infrastructure/ AppContainer (composition root), @main, AppDelegate
```
