import XCTest
@testable import CooltimeCore

final class DevinEnterpriseUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var cycleData: Data {
        jsonData(#"{"items":[{"after":1799000000,"before":1801000000}],"has_next_page":false}"#)
    }
    private var budgetData: Data {
        jsonData(#"{"items":[{"budget_id":"root","parent_budget_id":null,"status":"active","cycle_acu_limit":500,"temporary_cycle_acu_limit":null}],"has_next_page":false}"#)
    }
    private func jsonData(_ value: String) -> Data { value.data(using: .utf8)! }

    func testParsesCurrentEnterpriseBudgetRemainingAndReset() throws {
        let snapshot = try DevinEnterpriseUsage.parse(
            cyclesData: cycleData, budgetsData: budgetData,
            consumptionData: jsonData(#"{"total_acus":125,"consumption_by_date":[]}"#),
            now: now, fetchedAt: now
        )
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.label, "Enterprise ACU予算")
        XCTAssertEqual(window.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(window.remainingCount, 375)
        XCTAssertEqual(window.resetsAt, Date(timeIntervalSince1970: 1_801_000_000))
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testUsesExplicitTemporaryLimitAndNeverShowsNegativeRemaining() throws {
        let budgets = jsonData(#"{"items":[{"budget_id":"root","parent_budget_id":null,"status":"active","cycle_acu_limit":500,"temporary_cycle_acu_limit":1000}],"has_next_page":false}"#)
        let snapshot = try DevinEnterpriseUsage.parse(
            cyclesData: cycleData, budgetsData: budgets,
            consumptionData: jsonData(#"{"total_acus":1200}"#),
            now: now, fetchedAt: now
        )
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 120)
        XCTAssertEqual(snapshot.windows.first?.remainingCount, 0)
    }

    func testRejectsMissingCycleUnlimitedBudgetMalformedAndNegativeUsage() {
        XCTAssertThrowsError(try DevinEnterpriseUsage.currentCycle(in: jsonData(#"{"items":[]}"#), now: now))
        XCTAssertThrowsError(try DevinEnterpriseUsage.rootBudgetLimit(in: jsonData(#"{"items":[{"budget_id":"root","parent_budget_id":null,"status":"active","cycle_acu_limit":null,"temporary_cycle_acu_limit":null}]}"#)))
        XCTAssertThrowsError(try DevinEnterpriseUsage.rootBudgetLimit(in: jsonData(#"{"items":[{"budget_id":"root","parent_budget_id":null,"status":"active","cycle_acu_limit":500}],"has_next_page":true}"#)))
        XCTAssertThrowsError(try DevinEnterpriseUsage.parse(cyclesData: cycleData, budgetsData: budgetData,
                                                             consumptionData: jsonData(#"{"total_acus":-1}"#),
                                                             now: now, fetchedAt: now))
        XCTAssertThrowsError(try DevinEnterpriseUsage.parse(cyclesData: jsonData("not json"),
                                                             budgetsData: budgetData,
                                                             consumptionData: jsonData(#"{"total_acus":0}"#),
                                                             now: now, fetchedAt: now))
    }
}
