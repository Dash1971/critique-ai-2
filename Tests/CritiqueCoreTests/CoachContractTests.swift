import XCTest
@testable import CritiqueCore

final class CoachContractTests: XCTestCase {
    let context = CoachFactContext(scope: "Saved evidence only", facts: [CoachFact(id: "habit_0", text: "Recorded completions: 2 out of 7 scheduled.")])
    func data(_ text: String) -> Data { Data(text.utf8) }
    func testFactsAreRenderedFromAppNotGeneratedNumbers() throws {
        let reply = try CoachContract.check(data(#"{"fact_ids":["habit_0"],"suggestions":[{"kind":"practice","text":"Try a short reading session.","proposed_minutes":10}]}"#), against: context)
        XCTAssertEqual(reply.facts[0].text, "Recorded completions: 2 out of 7 scheduled.")
        XCTAssertEqual(reply.suggestions[0].proposedMinutes, 10)
    }
    func testInventedEvidenceIsRejected() {
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["seven_of_seven"],"suggestions":[{"kind":"practice","text":"Try reading."}]}"#), against: context))
    }
    func testSelectingOnlyScopeCannotHideActualCompletionCounts() throws {
        let facts = CoachFactContext(scope: "App evidence", facts: [CoachFact(id: "scope", text: "Selected records"),
            CoachFact(id: "habit_0", text: "Recorded completions: 2 out of 7 scheduled.")])
        let reply = try CoachContract.check(data(#"{"fact_ids":["scope"],"suggestions":[{"kind":"planning","text":"Plan a short reading session."}]}"#), against: facts)
        XCTAssertEqual(reply.selectedFactIDs, ["scope"])
        XCTAssertEqual(reply.facts, facts.facts)
    }
    func testRejectedActionIsNotDisplayedOrReplacedWithAFakeSuggestion() throws {
        let payload = #"{"fact_ids":["habit_0"],"suggestions":[{"kind":"practice","text":"Try a short reading session."},{"kind":"planning","text":"Consider adding entries to improve the score."}]}"#
        let reply = try CoachContract.check(data(payload), against: context)
        XCTAssertEqual(reply.suggestions.map(\.text), ["Try a short reading session."])
        XCTAssertEqual(reply.rejectedSuggestionCount, 1)
        XCTAssertEqual(reply.facts, context.facts)
    }
    func testGeneratedObservationAndWriteFieldsAreRejected() {
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["habit_0"],"observations":"All seven completed","suggestions":[{"kind":"practice","text":"Try reading."}]}"#), against: context))
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["habit_0"],"suggestions":[{"kind":"practice","text":"Try reading.","save":true}]}"#), against: context))
    }
    func testScoreManipulationAndFalsePersonalClaimsAreRejected() {
        for text in ["Try marking the remaining activities completed.", "Consider adding entries to improve the score.", "Try a break because you have completed everything.", "Consider maintaining your streak."] {
            let payload: [String: Any] = ["fact_ids": ["habit_0"], "suggestions": [["kind": "practice", "text": text]]]
            XCTAssertThrowsError(try CoachContract.check(JSONSerialization.data(withJSONObject: payload), against: context))
        }
    }
    func testProposedDurationIsSeparateFromPersonalFacts() {
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["habit_0"],"suggestions":[{"kind":"practice","text":"Try reading for 10 minutes."}]}"#), against: context))
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["habit_0"],"suggestions":[{"kind":"practice","text":"Try reading.","proposed_minutes":-1}]}"#), against: context))
    }
    func testUnknownActionKindAndEmptyResponseAreRejected() {
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["habit_0"],"suggestions":[{"kind":"edit_records","text":"Try reading."}]}"#), against: context))
        XCTAssertThrowsError(try CoachContract.check(data(#"{"fact_ids":["habit_0"],"suggestions":[]}"#), against: context))
    }
    func testFactsUseRealEvidenceAndExcludeProfile() throws {
        var state = AppState(); state.profile.username = "PrivateName"
        var habit = Habit(title: "Read"); habit.created = Date().addingTimeInterval(-6 * 86400)
        state.habits = [habit]
        let facts = try state.coachFactContext()
        XCTAssertTrue(facts.facts.contains { $0.id == "habit_0" && $0.text.contains("Recorded completions: 0") })
        XCTAssertFalse(facts.facts.contains { $0.text.contains("PrivateName") })
        XCTAssertTrue(facts.facts.contains { $0.id == "comparison_limit" })
    }
}
