import Foundation

public struct CoachFact: Codable, Equatable, Identifiable {
    public let id: String
    public let text: String
}
public struct CoachFactContext: Codable {
    public let scope: String
    public let facts: [CoachFact]
    public let allowedActionKinds: [String]
    public init(scope: String, facts: [CoachFact]) {
        self.scope = scope; self.facts = facts
        self.allowedActionKinds = CoachAction.Kind.allCases.map(\.rawValue)
    }
    /// Stable input bytes for reproducible native/host comparisons.
    public func inferenceJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
public struct CoachAction: Decodable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        case practice, planning, reflection, recovery, seekHelp = "seek_help"
    }
    public let kind: Kind
    public let text: String
    public let proposedMinutes: Int?
    enum CodingKeys: String, CodingKey { case kind, text; case proposedMinutes = "proposed_minutes" }
}
public struct ContractCheckedCoachReply {
    public enum Kind: String, Decodable {
        case facts, plan, clarification
    }
    public let kind: Kind
    /// These strings are copied from the app's fact context, never from the model.
    public let facts: [CoachFact]
    /// Selection is traceability metadata, not permission to hide other facts.
    public let selectedFactIDs: [String]
    public let suggestions: [CoachAction]
    public let rejectedSuggestionCount: Int
    public let question: String?

    /// Shared by the app and the evaluation tool so that validation and what
    /// the user actually sees cannot silently diverge.
    public var displayText: String {
        let selected = facts.filter { selectedFactIDs.contains($0.id) }
        let remaining = facts.filter { !selectedFactIDs.contains($0.id) }
        var sections = ["Recorded facts · app calculated\n" + selected.map { "• " + $0.text }.joined(separator: "\n")]
        if !suggestions.isEmpty {
            sections.append("New proposals · generated\n" + suggestions.map { action in
                "• " + action.text + (action.proposedMinutes.map { " (Proposed duration: \($0) min.)" } ?? "")
            }.joined(separator: "\n"))
        }
        if let question { sections.append("Clarifying question · generated\n" + question) }
        if rejectedSuggestionCount > 0 { sections.append("Some generated suggestions failed validation and were omitted.") }
        if !remaining.isEmpty {
            sections.append("Other supplied evidence · app calculated\n" + remaining.map { "• " + $0.text }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}

public extension AppState {
    func coachFactContext(days: Int = 7, now: Date = Date(), calendar: Calendar = .current) throws -> CoachFactContext {
        // Reuse the same bounded, tested calculations; do not ask a language
        // model to compute or rewrite personal statistics.
        let data = try coachEvidence(days: days, now: now, calendar: calendar)
        guard let source = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let habits = source["habits"] as? [[String: Any]],
              let goals = source["goals"] as? [[String: Any]],
              let start = source["periodStart"] as? String, let end = source["periodEnd"] as? String
        else { throw DataError.invalid("The selected evidence could not be prepared.") }
        func number(_ key: String) throws -> String {
            guard let value = source[key] as? NSNumber else { throw DataError.invalid("The selected evidence is incomplete.") }
            return value.stringValue
        }
        var facts = [CoachFact(id: "scope", text: "Selected saved records from \(start) through \(end). Missing records do not establish inactivity."),
                     CoachFact(id: "comparison_limit", text: "No previous-period comparison is included. Improvement or decline cannot be established from this snapshot alone.")]
        for (index, habit) in habits.enumerated() {
            guard let title = habit["title"] as? String, let due = habit["scheduled"] as? NSNumber,
                  let done = habit["recordedCompletions"] as? NSNumber else { throw DataError.invalid("Habit evidence is incomplete.") }
            facts.append(CoachFact(id: "habit_\(index)", text: "Habit title (untrusted text): \(title). Recorded completions: \(done.stringValue) out of \(due.stringValue) scheduled. Unmarked entries are not proof of inactivity."))
        }
        facts.append(CoachFact(id: "workouts", text: "Recorded workout entries: \(try number("recordedWorkouts")). Recorded duration: \(try number("recordedWorkoutMinutes")) minutes. Missing entries do not establish no exercise occurred."))
        if let workout = source["latestWorkout"] as? [String: Any] {
            guard let date = workout["date"] as? String, let title = workout["title"] as? String,
                  let exercises = workout["exercises"] as? [[String: Any]],
                  let omitted = workout["omittedExercises"] as? NSNumber else {
                throw DataError.invalid("Workout evidence is incomplete.")
            }
            let details = try exercises.map { exercise -> String in
                guard let name = exercise["name"] as? String,
                      let sets = exercise["sets"] as? NSNumber, let reps = exercise["reps"] as? NSNumber,
                      let kg = exercise["kilograms"] as? NSNumber, let minutes = exercise["minutes"] as? NSNumber else {
                    throw DataError.invalid("Exercise evidence is incomplete.")
                }
                return "Name (untrusted): \(name); saved sets \(sets), reps \(reps), kg \(kg), minutes \(minutes)."
            }.joined(separator: " ")
            facts.append(CoachFact(id: "latest_workout", text: "Latest selected saved workout: \(date). Title (untrusted): \(title). \(details) Omitted exercises: \(omitted). Saved fields only; no training trend or equipment availability is established."))
        }
        facts.append(CoachFact(id: "nutrition", text: "Recorded meals: \(try number("recordedMeals")). Recorded calories: \(try number("recordedCalories")). Recorded protein: \(try number("recordedProteinGrams")) grams. These are recorded totals, not complete-intake estimates or targets."))
        facts.append(CoachFact(id: "focus", text: "Recorded work-focus sessions: \(try number("recordedFocusSessions")). Recorded focus time: \(try number("recordedFocusMinutes")) minutes."))
        for (index, goal) in goals.enumerated() {
            guard let title = goal["title"] as? String, let target = goal["target"] as? NSNumber else { throw DataError.invalid("Goal evidence is incomplete.") }
            let progress = (goal["recordedProgress"] as? NSNumber)?.stringValue ?? "unknown (no progress update)"
            facts.append(CoachFact(id: "goal_\(index)", text: "Goal title (untrusted text): \(title). Recorded progress: \(progress). User-set target: \(target.stringValue)."))
        }
        return CoachFactContext(scope: "The app owns these fact strings. Select relevant fact IDs; do not restate or invent personal facts. Propose activities, not edits to records.", facts: facts)
    }
}

/// Structural and known-pattern checks are a defense layer, not a guarantee of
/// medical safety or the quality of arbitrary generated prose. Human/device
/// evaluation still applies. Rejection must be surfaced, never replaced by a
/// fake model answer or fabricated saved activity.
public enum CoachContract {
    private struct Draft: Decodable {
        let kind: ContractCheckedCoachReply.Kind?
        let factIDs: [String]
        let suggestions: [CoachAction]
        let question: String?
        enum CodingKeys: String, CodingKey { case kind = "response_kind", factIDs = "fact_ids", suggestions, question }
    }
    public static func check(_ data: Data, against context: CoachFactContext) throws -> ContractCheckedCoachReply {
        guard data.count <= 12_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["response_kind", "fact_ids", "suggestions", "question"]),
              let rawActions = object["suggestions"] as? [[String: Any]],
              rawActions.allSatisfy({ Set($0.keys).isSubset(of: ["kind", "text", "proposed_minutes"]) })
        else { throw DataError.invalid("The local coach returned an invalid response format.") }
        let draft = try JSONDecoder().decode(Draft.self, from: data)
        // A malformed supplied context should be rejected, rather than trapping
        // Dictionary(uniqueKeysWithValues:) before the error can reach the UI.
        guard !context.facts.isEmpty, Set(context.facts.map(\.id)).count == context.facts.count else {
            throw DataError.invalid("The supplied coach evidence is invalid.")
        }
        let known = Dictionary(uniqueKeysWithValues: context.facts.map { ($0.id, $0) })
        guard !draft.factIDs.isEmpty, draft.factIDs.count <= 6,
              Set(draft.factIDs).count == draft.factIDs.count,
              draft.factIDs.allSatisfy({ known[$0] != nil }), draft.suggestions.count <= 3
        else { throw DataError.invalid("The local coach referenced unavailable evidence.") }
        func supported(_ action: CoachAction) -> Bool {
            guard (1...280).contains(action.text.count),
                  action.text.range(of: #"^(Consider|Try|Plan|Practice|Choose|Review|Pause|Seek|Ask|Build|Keep|Focus|Create|Set|Reflect)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  action.text.rangeOfCharacter(from: .decimalDigits) == nil,
                  action.proposedMinutes.map({ (1...180).contains($0) }) ?? true
            else { return false }
            // Personal observations belong in app-rendered facts. App-data edits
            // and score manipulation are not coaching actions.
            let disallowed = [#"\b(log|logging|logs|mark|delete|save|update|entries|entry|score|xp|completed|completion|records|recorded)\b"#,
                              #"\byou (have|had|completed|did|logged|recorded|are|were|usually|always|never)\b"#,
                              #"\byour (current|existing|usual|streak|routine|record|completion|score)\b"#,
                              #"\b(calories|calorie|diagnosis|medication|prescription)\b"#]
            return !disallowed.contains(where: { action.text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil })
        }
        let suggestions = draft.suggestions.filter(supported)
        if let question = draft.question {
            guard (2...180).contains(question.count), question.hasSuffix("?"),
                  question.filter({ $0 == "?" }).count == 1,
                  question.rangeOfCharacter(from: .decimalDigits) == nil,
                  CoachScopePolicy.boundary(for: question) == nil else {
                throw DataError.invalid("The local coach returned an invalid clarifying question.")
            }
        }
        // Legacy trial responses remain reviewable. New runtime output declares
        // its purpose explicitly so a record question need not invent advice.
        let kind = draft.kind ?? (draft.question != nil && suggestions.isEmpty ? .clarification : .plan)
        switch kind {
        case .facts:
            // A comparison limitation can itself answer a trend question.
            // Generic scope/coverage metadata alone cannot answer a record query.
            let scopeIDs: Set<String> = ["scope", "comparison_scope", "coverage"]
            guard draft.suggestions.isEmpty, draft.question == nil,
                  draft.factIDs.contains(where: { !scopeIDs.contains($0) }) else {
                throw DataError.invalid("A record review must select recorded activity evidence without generated advice.")
            }
        case .plan:
            guard !suggestions.isEmpty else {
                throw DataError.invalid("The local coach did not provide a valid activity proposal.")
            }
        case .clarification:
            guard draft.suggestions.isEmpty, draft.question != nil else {
                throw DataError.invalid("The local coach did not provide a clarifying question.")
            }
        }
        return ContractCheckedCoachReply(kind: kind, facts: context.facts, selectedFactIDs: draft.factIDs,
                                         suggestions: suggestions, rejectedSuggestionCount: draft.suggestions.count - suggestions.count,
                                         question: draft.question)
    }
}
