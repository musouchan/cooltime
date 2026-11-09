import XCTest
@testable import CooltimeCore

final class ServiceCategoryTests: XCTestCase {
    func testEveryCatalogEntryAppearsExactlyOnceInTheTableOfContents() {
        let sections = ServiceCategory.sections(from: Catalog.all)
        let ids = sections.flatMap(\.services).map(\.id)
        XCTAssertEqual(ids.count, Catalog.all.count)
        XCTAssertEqual(Set(ids), Set(Catalog.all.map(\.id)))
        XCTAssertEqual(sections.map(\.category), ServiceCategory.allCases.filter {
            category in Catalog.all.contains { ServiceCategory.category(for: $0) == category }
        })
        XCTAssertFalse(sections.contains { $0.category == .other })
    }

    func testAutomaticAndManualVariantsShareTheSamePurposeCategory() {
        let pairs = [
            ("aider-local-usage", "sheet-24", ServiceCategory.coding),
            ("openart-cli-balance", "sheet-45", .image),
            ("kling-api-package-usage", "sheet-49", .videoAudio),
            ("microsoft365-copilot-report", "sheet-118", .work),
            ("vertex-token-monitoring", "sheet-101", .api),
        ]
        for (automaticID, manualID, expected) in pairs {
            XCTAssertEqual(ServiceCategory.category(for: Catalog.all.first { $0.id == automaticID }!), expected)
            XCTAssertEqual(ServiceCategory.category(for: Catalog.all.first { $0.id == manualID }!), expected)
        }
    }

    func testSearchAcrossCategoriesAndSelectedCategory() {
        let all = ServiceCategory.sections(from: Catalog.all, search: "  gemini  ")
        XCTAssertTrue(all.flatMap(\.services).contains { $0.id == "sheet-68" })
        XCTAssertTrue(all.flatMap(\.services).contains { $0.id == "gemini-cli-local-usage" })

        let coding = ServiceCategory.sections(from: Catalog.all, search: "gemini", selected: .coding)
        XCTAssertEqual(coding.map(\.category), [.coding])
        XCTAssertTrue(coding[0].services.allSatisfy { ServiceCategory.category(for: $0) == .coding })
        XCTAssertEqual(ServiceCategory.sections(from: Catalog.all, search: "no-such-service").count, 0)
    }
}
