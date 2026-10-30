import XCTest
@testable import RecoveryCore

private struct FakeSource: UsageSource {
    func fetch(entry: CatalogEntry, config: ServiceConfig, context: SourceContext) async throws -> SourceResult {
        SourceResult(credit: CreditBalance(amount: 1, currency: "USD"))
    }
}

private struct NoSecrets: SecretStore {
    func secret(for configID: String) -> String? { nil }
}

final class SourceRegistryTests: XCTestCase {
    func testStandardRegistryHasOfficialSources() {
        let r = SourceRegistry.standard
        XCTAssertNotNil(r.source(for: .claudeStatusline))
        XCTAssertNotNil(r.source(for: .codexAppServer))
        XCTAssertNotNil(r.source(for: .apiKey))
    }

    func testEmptyRegistryReturnsNilInsteadOfInventingData() {
        XCTAssertNil(SourceRegistry([:]).source(for: .apiKey))
    }

    func testCustomSourceCanBeRegisteredWithoutTouchingTheRest() async throws {
        let registry = SourceRegistry([.apiKey: FakeSource()])
        let entry = Catalog.entry("openrouter")!
        let config = ServiceConfig(catalogID: entry.id)
        let ctx = SourceContext(http: URLSessionClient(), secrets: NoSecrets())
        let result = try await registry.source(for: .apiKey)!.fetch(entry: entry, config: config, context: ctx)
        XCTAssertEqual(result.credit?.amount, 1)
    }

    func testAllCurrentCatalogEntriesAreOfficial() {
        XCTAssertTrue(Catalog.all.allSatisfy { $0.tier == .official })
    }

    func testAPIKeyAdapterWithoutKeyFailsClearly() async {
        let entry = Catalog.entry("deepseek")!
        let config = ServiceConfig(catalogID: entry.id)
        let ctx = SourceContext(http: URLSessionClient(), secrets: NoSecrets())
        do {
            _ = try await APIKeyAdapter().fetch(entry: entry, config: config, context: ctx)
            XCTFail("キーが無いのに成功した")
        } catch {
            XCTAssertEqual(error as? SourceError, .notAvailable("APIキーが未設定です"))
        }
    }
}
