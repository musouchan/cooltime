import Foundation
import XCTest
@testable import CooltimeCore

final class FabricCopilotOperationUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountsDocumentedPublicCopilotOperationOnly() throws {
        let log = """
        {"type":"Microsoft.Fabric.CapacityOperationEvents.Operation","id":"1","data":{"operationName":"Copilot in Fabric","releaseType":"Public","capacityUnitMs":1500,"identityValue":"private"}}
        {"type":"Microsoft.Fabric.CapacityOperationEvents.Operation","id":"2","data":{"operationName":"Notebook Run","releaseType":"Public","capacityUnitMs":9000}}
        {"type":"Microsoft.Fabric.CapacityOperationEvents.Operation","id":"3","data":{"operationName":"Copilot in Fabric","releaseType":"Preview","capacityUnitMs":3000}}
        {"type":"Microsoft.Fabric.CapacityOperationEvents.Operation","id":"4","data":{"operationName":"Copilot in Fabric","releaseType":"Public","capacityUnitMs":2500}}
        {"type":"Microsoft.Fabric.CapacityOperationEvents.Operation","id":"1","data":{"operationName":"Copilot in Fabric","releaseType":"Public","capacityUnitMs":1500}}
        """
        let s = try FabricCopilotOperationUsage.parse(Data(log.utf8), fetchedAt: now)
        XCTAssertEqual(s.windows[0].reportedAmount, 4)
        XCTAssertEqual(s.windows[0].reportedUnit, "CU秒")
        XCTAssertNil(s.credit)
        XCTAssertNil(s.windows[0].remainingCount)
        XCTAssertNil(s.windows[0].resetsAt)
        XCTAssertFalse(String(describing: s).contains("private"))
    }

    func testRejectsInvalidAndUnmeasuredLogs() {
        for log in ["{}", "{broken", "{\"type\":\"Microsoft.Fabric.CapacityOperationEvents.Operation\",\"id\":\"1\",\"data\":{\"operationName\":\"Copilot in Fabric\",\"releaseType\":\"Public\",\"capacityUnitMs\":true}}",
                    "{\"type\":\"Microsoft.Fabric.CapacityOperationEvents.Operation\",\"id\":\"1\",\"data\":{\"operationName\":\"Copilot in Fabric\",\"releaseType\":\"Public\",\"capacityUnitMs\":-1}}",
                    "{\"type\":\"Microsoft.Fabric.CapacityOperationEvents.Operation\",\"id\":\"1\",\"data\":{\"operationName\":\"Notebook Run\",\"releaseType\":\"Public\",\"capacityUnitMs\":12}}"] {
            XCTAssertThrowsError(try FabricCopilotOperationUsage.parse(Data(log.utf8), fetchedAt: now))
        }
    }

    func testManualOptionRemains() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "fabric-copilot-operation-usage" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-181" })
    }
}
