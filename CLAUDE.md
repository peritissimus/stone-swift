# Stone (Swift) — project rules

**Scope: a note taker, nothing more.** It captures to today's journal and lets you look back through notes
read-only. It never edits, renames, moves, or deletes a note — those belong to Stone desktop. A
change that makes it write anything other than an appended capture needs an explicit ask.

Stone desktop's hexagonal architecture (see `../stone/CLAUDE.md`), expressed in Swift. The package
graph enforces the dependency rule; `Scripts/lint-architecture.sh` enforces the rest.

## Layers

| Target | May import | Holds |
| --- | --- | --- |
| `StoneDomain` | Foundation | Entities (`NoteEntity`), value objects (`NotePath`, `JournalDate`, `AppConfig`…), pure services (`JournalComposer`, `NoteSearchScorer`…), errors, ports |
| `StoneApplication` | StoneDomain | Per-action `XxxUseCase` classes, a `XxxUseCases` facade implementing the in-port, and a `createXxxUseCases` factory |
| `StoneAdaptersOut` | StoneDomain | Out-port implementations: filesystem, Stone config (read-only), clock |
| `StoneUI` | StoneDomain, AppKit, SwiftUI | The capture panel. It sees in-port facades only, bundled in `StoneServices` |
| `Stone/Infrastructure` | everything | `AppContainer` is the only place concrete adapters are constructed |

- **The domain decides and never does.** No clock, randomness, filesystem or `async`. Anything like that is injected through a port (`IClock`), and domain tests use no fakes.
- **Ports are protocols with an `I` prefix.** In-ports live in `Ports/In`, out-ports in `Ports/Out`. They are `Sendable` and `async throws` wherever I/O sits behind them.
- **Use cases:** one class per action. Shared helpers go in a camelCase module beside them (`noteLoading.swift`).
- **File homogeneity:** a PascalCase file declares exactly one type named after the file. A camelCase file declares none.
- **UI mirrors the renderer rules:** views read `@Observable` stores (`CaptureStore`, `BrowseStore`, `PanelStore`), and stores call in-ports. `StoneShell` is the coordinator: it maps the panel's key intents to screens and actions.
- **Captures are serialized and byte-preserving:** each save waits for the one before it, and the use case appends to the file's exact text — never re-compose a note's header.
- **Config is Stone desktop's `~/.config/stone/config.json`, read-only.** Stone owns and normalizes
  that file (it drops unknown keys), so this app never writes it.
- **Storage format is Stone desktop's**: journal seeds `# YYYY-MM-DD\n\n`, captures append `\n\n[HH:MM] text`, dot-folders ignored.

## Done means

`./Scripts/test.sh` passes: swift tests, the architecture lint, and a warning-free Xcode build.
`Stone.xcodeproj` is generated from `project.yml` by XcodeGen, so never hand-edit it.
