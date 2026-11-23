import XCTest
@testable import CritiqueCore

final class CoachScopeTests: XCTestCase {
    func testMedicalAndRestrictiveDietRequestsAreRoutedBeforeInference() {
        for question in ["My knee hurts during squats. Should I push through?", "What medication dosage should I take?",
                         "Give me a strict calorie target and an aggressive weight-loss diet.", "Suggest a crash diet."] {
            XCTAssertEqual(CoachScopePolicy.boundary(for: question), .health)
            XCTAssertThrowsError(try CoachScopePolicy.requireSupported(question))
        }
        XCTAssertEqual(CoachScopePolicy.boundary(for: "I want to kill myself"), .crisis)
        XCTAssertEqual(CoachScopePolicy.boundary(for: "Upload my records to a cloud server"), .externalAction)
        XCTAssertEqual(CoachScopePolicy.boundary(for: "Erase my saved activity history now"), .appAction)
    }
    func testRecordedNutritionAndOrdinaryActivitiesRemainInScope() throws {
        for question in ["How many calories did I record?", "Suggest a small reading habit.", "Help me plan painting practice.", "Summarize my workout minutes.", "Help me remove distractions from my routine."] {
            XCTAssertNil(CoachScopePolicy.boundary(for: question))
            XCTAssertNoThrow(try CoachScopePolicy.requireSupported(question))
        }
    }
}
