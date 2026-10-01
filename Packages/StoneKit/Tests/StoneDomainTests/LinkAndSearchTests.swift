import Foundation
import Testing
@testable import StoneDomain

struct SearchScorerTests {
    @Test func everyTermMustMatch() {
        #expect(NoteSearchScorer.score(query: "wallet leak", title: "Notes", body: "the wallet") == nil)
        #expect(NoteSearchScorer.score(query: "wallet leak", title: "Notes", body: "wallet leak") != nil)
    }

    @Test func titleOutranksBody() {
        let title = NoteSearchScorer.score(query: "wallet", title: "Wallet release", body: "")!
        let body = NoteSearchScorer.score(query: "wallet", title: "Other", body: "wallet")!
        #expect(title.score > body.score)
    }

    @Test func snippetCentresOnTheMatch() {
        let body = String(repeating: "x ", count: 200) + "needle here"
        let hit = NoteSearchScorer.score(query: "needle", title: "", body: body)!
        #expect(hit.snippet.hasPrefix("…"))
        #expect(hit.snippet.contains("needle here"))
    }
}

struct JournalTests {
    @Test func captureAppendsStampedParagraph() {
        let date = try! JournalDate(year: 2026, month: 9, day: 29)
        let seeded = JournalComposer.seed(for: date)
        #expect(seeded == "# 2026-09-29\n\n")
        let first = JournalComposer.append("fix leak", at: ClockTime(hour: 9, minute: 5), to: seeded)
        #expect(first == "# 2026-09-29\n\n[09:05] fix leak")
        let second = JournalComposer.append("ship", at: ClockTime(hour: 19, minute: 42), to: first + "\n")
        #expect(second == "# 2026-09-29\n\n[09:05] fix leak\n\n[19:42] ship")
        #expect(JournalComposer.append("   ", at: ClockTime(hour: 1, minute: 1), to: first) == first)
    }

    @Test func journalDateParsesOnlyStrictDays() {
        #expect(JournalDate(parsing: "2026-02-28")?.description == "2026-02-28")
        #expect(JournalDate(parsing: "2026-02-30") == nil)
        #expect(JournalDate(parsing: "20260228") == nil)
    }

    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .hebrew, .islamicUmmAlQura, .gregorian])
    func journalDayIsGregorianWhateverTheUsersCalendar(_ identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let instant = Date(timeIntervalSince1970: 1_790_812_800)  // 2026-10-01 00:00 UTC
        #expect(JournalDate(date: instant, calendar: calendar).description == "2026-10-01")
    }

    @Test func journalDayFollowsTheCalendarsTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let instant = Date(timeIntervalSince1970: 1_790_812_800)  // still 30 Sep in California
        #expect(JournalDate(date: instant, calendar: calendar).description == "2026-09-30")
    }

    @Test func journalFileIsNamedByDay() throws {
        #expect(NoteFileNaming.journalFileName(for: try JournalDate(year: 2026, month: 4, day: 8)) == "2026-04-08.md")
    }
}
