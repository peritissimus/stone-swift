import Foundation
import Synchronization
import Testing
import StoneDomain
@testable import StoneUI

/// Records captures in order; can be told to fail or to stall the first save.
final class FakeJournal: IJournalUseCases {
    let captured = Mutex<[String]>([])
    let stamps = Mutex<[Date]>([])
    let failNext = Mutex(false)
    let failAll = Mutex(false)
    let stallFirst = Mutex(false)

    func capture(_ text: String, writtenAt: Date) async throws -> NoteEntity {
        if stallFirst.withLock({ let stall = $0; $0 = false; return stall }) {
            try? await Task.sleep(for: .milliseconds(80))
        }
        if failAll.withLock({ $0 }) || failNext.withLock({ let fail = $0; $0 = false; return fail }) {
            throw CocoaError(.fileWriteUnknown)
        }
        captured.withLock { $0.append(text) }
        stamps.withLock { $0.append(writtenAt) }
        return NoteEntity(
            path: try NotePath("Journal/2026-10-01.md"), source: "# 2026-10-01\n\n\(text)",
            modifiedAt: .now, policy: .standard)
    }

    func today() async throws -> NoteEntity? { nil }
}

@MainActor
struct CaptureStoreTests {
    let defaults = UserDefaults(suiteName: "stone-tests-\(UUID().uuidString)")!

    @Test func submitClearsDraftAtOnceAndSavesTrimmedText() async throws {
        let journal = FakeJournal()
        let store = CaptureStore(journal: journal, defaults: defaults)
        store.draft = "  fix the leak \n"
        let save = try #require(store.submit())
        #expect(store.draft.isEmpty)
        _ = await save.value
        #expect(journal.captured.withLock { $0 } == ["fix the leak"])
    }

    @Test func blankDraftSubmitsNothing() {
        let store = CaptureStore(journal: FakeJournal(), defaults: defaults)
        store.draft = " \n\t"
        #expect(store.submit() == nil)
    }

    @Test func failedSaveRestoresTheDraft() async throws {
        let journal = FakeJournal()
        journal.failNext.withLock { $0 = true }
        let store = CaptureStore(journal: journal, defaults: defaults)
        store.draft = "important"
        let result = await (try #require(store.submit())).value
        guard case .failure = result else { Issue.record("expected failure"); return }
        #expect(store.draft == "important")
    }

    @Test func rapidCapturesLandInOrder() async throws {
        let journal = FakeJournal()
        journal.stallFirst.withLock { $0 = true }
        let store = CaptureStore(journal: journal, defaults: defaults)
        store.draft = "first"
        _ = store.submit()
        store.draft = "second"
        let last = try #require(store.submit())
        _ = await last.value
        #expect(journal.captured.withLock { $0 } == ["first", "second"])
    }

    @Test func stampIsTakenWhenReturnIsPressed() async throws {
        let journal = FakeJournal()
        let pressed = Date(timeIntervalSince1970: 1_000)
        let store = CaptureStore(journal: journal, defaults: defaults, now: { pressed })
        store.draft = "note"
        _ = await (try #require(store.submit())).value
        #expect(journal.stamps.withLock { $0 } == [pressed])
    }

    @Test func queuedFailuresComeBackInTheOrderWritten() async throws {
        let journal = FakeJournal()
        journal.failAll.withLock { $0 = true }
        journal.stallFirst.withLock { $0 = true }
        let store = CaptureStore(journal: journal, defaults: defaults)
        store.draft = "A"
        _ = store.submit()
        store.draft = "B"
        let last = try #require(store.submit())
        store.draft = "C"
        _ = await last.value
        #expect(store.draft == "A\n\nB\n\nC")
    }

    @Test func closeWaitsForEveryQueuedSaveAndRefusesNewOnes() async throws {
        let journal = FakeJournal()
        journal.stallFirst.withLock { $0 = true }
        let store = CaptureStore(journal: journal, defaults: defaults)
        store.draft = "one"
        _ = store.submit()
        store.draft = "two"
        _ = store.submit()
        await store.close()
        #expect(journal.captured.withLock { $0 } == ["one", "two"])
        store.draft = "after quit"
        #expect(store.submit() == nil)
        #expect(store.draft == "after quit")
    }

    @Test func aNoteSubmittedButNeverWrittenReturnsOnRelaunch() {
        defaults.set(["lost in a crash"], forKey: CaptureStore.pendingKey)
        defaults.set("still typing", forKey: CaptureStore.draftKey)
        let store = CaptureStore(journal: FakeJournal(), defaults: defaults)
        #expect(store.draft == "lost in a crash\n\nstill typing")
        #expect(defaults.stringArray(forKey: CaptureStore.pendingKey) == nil)
    }

    @Test func aWrittenNoteLeavesNoPendingRecord() async throws {
        let store = CaptureStore(journal: FakeJournal(), defaults: defaults)
        store.draft = "saved"
        _ = await (try #require(store.submit())).value
        #expect(defaults.stringArray(forKey: CaptureStore.pendingKey) == nil)
    }

    @Test func draftSurvivesARelaunch() {
        let store = CaptureStore(journal: FakeJournal(), defaults: defaults)
        store.draft = "half a thought"
        #expect(CaptureStore(journal: FakeJournal(), defaults: defaults).draft == "half a thought")
        store.draft = ""
        #expect(defaults.string(forKey: CaptureStore.draftKey) == nil)
    }
}

struct KeyShortcutTests {
    @Test func readsStoneAcceleratorSpellings() {
        #expect(KeyShortcut(parsing: "Alt+Space")?.display == "⌥Space")
        #expect(KeyShortcut(parsing: "CommandOrControl+Shift+N")?.display == "⌘⇧N")
        #expect(KeyShortcut(parsing: "Option+Space") == KeyShortcut(parsing: "Alt+Space"))
        #expect(KeyShortcut(parsing: "F5") != nil)
        #expect(KeyShortcut(parsing: "F13") != nil)
    }

    @Test(arguments: ["Alt+Up", "Control+.", "CommandOrControl+Shift+/", "Alt+Backspace", "Shift+Delete",
                      "Control+`", "Alt+[", "CommandOrControl+Alt+\\", "Alt+-", "Control+'"])
    func acceptsEveryKeyStonesRecorderWrites(_ text: String) {
        #expect(KeyShortcut(parsing: text) != nil)
    }

    @Test(arguments: ["Space", "F", "Shift+Hyper+Space", "Alt+Space+K", "Alt+", "", "Alt+Plus", "F24"])
    func rejectsAnythingItCannotReadExactly(_ text: String) {
        #expect(KeyShortcut(parsing: text) == nil)
    }
}
