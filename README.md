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

## Search

The Swift app searches Stone desktop's existing database at
`~/.config/stone/stone-data/notes.db`, scoped to the configured workspace. It reuses desktop's FTS5
chunks and stored BGE embeddings. The workspace must already be registered in Stone desktop; desktop
owns database creation and migrations.

Captures commit Markdown first, queue a transactional text-index update, and generate embeddings in
the background. A startup scan and scans every 30 seconds reconcile external additions and edits.
Unchanged content keeps its existing vectors. Removing a file removes its derived search rows;
desktop note IDs, favorites, pins, notebook assignments, tags, and deletion state are preserved.
The only additional table is `stone_swift_index_state`, in the same database, for file timestamps and
content fingerprints. The desktop importer also uses atomic path-based creation so both apps can
adopt the same note identity when they discover a new file concurrently.

Semantic search uses the same `Xenova/bge-small-en-v1.5` model and 384-dimensional Float32 vectors as
desktop. Search merges keyword and semantic candidates and reranks up to 30 notes with desktop's
`Xenova/ms-marco-MiniLM-L-6-v2` cross-encoder. Reranking is query-dependent; embeddings are generated
when notes change. Native chunking and content hashes follow the desktop format.

The Swift interface starts a small Node helper on demand, which runs Stone's existing model worker
without opening Electron. It reuses `~/.config/stone/ml-cache`, releases the process after idle time,
and needs no API key. Node must be installed and the desktop worker and its dependencies must be
available (either the installed desktop app or a built Stone checkout). On this development layout,
`~/projects/stone/dist/main/workers/embedding.worker.cjs` is found automatically. The worker may
download its public model weights if they are missing from the cache.

| Override | Purpose |
| --- | --- |
| `STONE_DATABASE_PATH` | Path to an existing desktop database |
| `STONE_EMBEDDING_WORKER` | Absolute path to desktop's built `embedding.worker.cjs` |
| `STONE_NODE_PATH` | Node executable; otherwise discovered through PATH and standard Homebrew locations |
| `STONE_ML_CACHE` | Model cache directory, default `~/.config/stone/ml-cache` |

If the model process is unavailable, SQLite keyword search and deterministic ranking continue.
If the database is unavailable or the workspace is unregistered, search falls back to Markdown.
A successfully saved capture remains successful if indexing fails; later scans retry it. Tests use
isolated desktop-schema fixtures rather than modifying the real database.

## Run the dev build

```sh
cd ~/projects/stone-swift
./Scripts/test.sh                                   # tests + architecture lint + Debug build
open --env STONE_WORKSPACE=/tmp/stone-test "build/Build/Products/Debug/Stone Dev.app"   # sandbox
open "build/Build/Products/Debug/Stone Dev.app"      # your real workspace
pkill -f "Stone Dev"                                 # quit (or menu bar → Quit)
```

You can also run `xcodegen generate && open Stone.xcodeproj`, then press ⌘R. Requires Xcode 16+ and macOS 15+. The Swift package uses system SQLite; semantic search also uses the desktop model runtime described above.

## Architecture

The code is hexagonal, and each layer is its own SwiftPM target, so a forbidden import won't compile.

```
Packages/StoneKit/Sources/
  StoneDomain/        NoteEntity, JournalDate, LocationPolicy, AppConfig, JournalComposer, NoteSearchScorer, ports   → Foundation only
  StoneApplication/   CaptureToJournal, GetTodayJournal, ListNotes, OpenNote, SearchNotes (+ facades/factories)      → StoneDomain
  StoneAdaptersOut/   Filesystem, shared SQLite search, desktop model process, read-only config, clock               → StoneDomain
  StoneUI/            the panel, CaptureStore, BrowseStore, hotkey, HUD                                              → StoneDomain in-ports
Stone/Infrastructure/ AppContainer (composition root), @main, AppDelegate
```
