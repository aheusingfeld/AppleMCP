import Foundation
import Observation
import XCTest
@testable import M3MCPApp

final class AppModelObservationTests: XCTestCase {
    @MainActor
    func testConsentChangeDoesNotInvalidateServerStatus() async throws {
        let suite = "M3MCP.ObservationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: preferences)
        let unrelatedChange = expectation(description: "Server status stays unchanged")
        unrelatedChange.isInverted = true
        withObservationTracking {
            _ = model.serverState
        } onChange: {
            unrelatedChange.fulfill()
        }

        model.acceptUsageRisk()
        XCTAssertTrue(model.usageRiskAccepted)
        await fulfillment(of: [unrelatedChange], timeout: 0.05)
    }

    @MainActor
    func testConsentChangeInvalidatesConsentDependentView() async throws {
        let suite = "M3MCP.ObservationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: preferences)
        let consentChange = expectation(description: "Consent-dependent view updates")
        withObservationTracking {
            _ = model.usageRiskAccepted
        } onChange: {
            consentChange.fulfill()
        }

        model.acceptUsageRisk()
        await fulfillment(of: [consentChange], timeout: 1)
    }
}
