import Foundation

public enum CoachScopeBoundary: String {
    case health, crisis, externalAction, appAction
    public var explanation: String {
        switch self {
        case .health: return "This activity coach cannot assess symptoms, injuries, treatment or restrictive diet targets. Please consult a qualified professional for those decisions. No model answer was generated."
        case .crisis: return "This activity coach cannot provide crisis support. If you may harm yourself or someone else, contact local emergency services or a trusted person now. No model answer was generated."
        case .externalAction: return "This coach runs on this device. It cannot upload your activity to a server or send messages. No data was sent and no model answer was generated."
        case .appAction: return "The coach cannot change or delete saved records. Use the app's own editing, export or reset controls for those actions. No records were changed and no model answer was generated."
        }
    }
}
public enum CoachScopePolicy {
    /// A conservative scope boundary, not a diagnostic or comprehensive crisis
    /// classifier. Check before invoking the model; never present this as AI
    /// analysis. Human review of ordinary coaching suggestions still applies.
    public static func boundary(for question: String) -> CoachScopeBoundary? {
        func matches(_ pattern: String) -> Bool {
            question.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if matches(#"\b(suicid(?:e|al)|kill myself|harm myself|self[- ]harm|hurt myself|kill someone)\b"#) { return .crisis }
        if matches(#"\b(pain|hurts?|hurting|injur(?:y|ies|ed)|swollen|swelling|bleeding|fainting|dizziness|numbness|diagnos(?:e|is)|medication|dosage|prescri(?:be|ption)|insulin)\b"#) { return .health }
        if matches(#"\b(calorie|calories)\b.*\b(target|limit|deficit|prescription)\b|\b(target|limit|deficit)\b.*\b(calorie|calories)\b"#)
            || matches(#"\b(strict|restrictive|aggressive|extreme|crash)\b.*\b(diet|weight[- ]loss|weight loss)\b"#) { return .health }
        if matches(#"\b(send|upload|transmit|share)\b.*\b(server|cloud|internet|api|email|message)\b"#) { return .externalAction }
        if matches(#"\b(delete|erase|reset|remove)\b.*\b(history|records|logs|data|everything)\b"#) { return .appAction }
        return nil
    }
    public static func requireSupported(_ question: String) throws {
        if let boundary = boundary(for: question) { throw DataError.invalid(boundary.explanation) }
    }
}
