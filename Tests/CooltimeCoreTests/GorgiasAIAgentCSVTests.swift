import Foundation
import XCTest
@testable import CooltimeCore

final class GorgiasAIAgentCSVTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadsOneExplicitAIInteractionCount() throws {
        let csv = "Metric,Value\nAutomated interactions,\"1,234\"\nTime saved,20\n"
        let result = try GorgiasAIAgentCSV.parse(Data(csv.utf8), fetchedAt: now)
        XCTAssertEqual(result.windows.single?.reportedAmount, 1234)
        XCTAssertEqual(result.windows.single?.reportedUnit, "interactions")
        XCTAssertNil(result.windows.single?.remainingCount)
        XCTAssertNil(result.windows.single?.resetsAt)
        XCTAssertNil(result.credit)
    }

    func testReadsWideKeyMetricCardExport() throws {
        let csv = "AI Agent automation rate,Automated interactions,Time saved\n50%,42,4h\n"
        XCTAssertEqual(try GorgiasAIAgentCSV.parse(Data(csv.utf8), fetchedAt: now)
            .windows.single?.reportedAmount, 42)
    }

    func testRejectsTotalsWithoutAIAgentMetricAndBreakdowns() {
        for csv in ["Metric,Value\nTotal tickets,12\n",
                    "Metric,Value\nAutomated interactions,12\nAutomated interactions,2\n",
                    "Automated interactions,Channel\n12,email\n2,chat\n",
                    "Metric,Value\nAutomated interactions,12.5\n",
                    "Metric,Value\nAutomated interactions,50%\n"] {
            XCTAssertThrowsError(try GorgiasAIAgentCSV.parse(Data(csv.utf8), fetchedAt: now))
        }
    }

    func testManualServiceRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "gorgias-ai-agent-csv" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-131" })
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
