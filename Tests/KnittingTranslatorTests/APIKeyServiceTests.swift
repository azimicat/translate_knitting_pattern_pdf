import XCTest
@testable import KnittingTranslator

/// テスト用の UserDefaults を注入して実際の設定を汚染しない
@MainActor
final class APIKeyServiceTests: XCTestCase {

    private var sut: APIKeyService!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName    = "KnittingTranslatorTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        sut          = APIKeyService(defaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        sut = nil
    }

    // MARK: - 初期状態

    func testInit_noKey_hasKeyIsFalse() {
        XCTAssertFalse(sut.hasKey)
        XCTAssertNil(sut.apiKey())
    }

    // MARK: - save / apiKey

    func testSave_setsHasKeyTrue() {
        sut.save("AIzaSyTestKey123")
        XCTAssertTrue(sut.hasKey)
    }

    func testSave_canRetrieveKey() {
        sut.save("AIzaSyTestKey123")
        XCTAssertEqual(sut.apiKey(), "AIzaSyTestKey123")
    }

    func testSave_overwritesPreviousKey() {
        sut.save("AIzaSyOldKey")
        sut.save("AIzaSyNewKey")
        XCTAssertEqual(sut.apiKey(), "AIzaSyNewKey")
    }

    // MARK: - delete

    func testDelete_clearsKey() {
        sut.save("AIzaSyTestKey123")
        sut.delete()
        XCTAssertFalse(sut.hasKey)
        XCTAssertNil(sut.apiKey())
    }

    // MARK: - エッジケース

    func testSave_emptyString_treatedAsNoKey() {
        sut.save("")
        // 空文字列は「未設定」として扱う
        XCTAssertNil(sut.apiKey())
    }

    func testInit_existingKey_hasKeyIsTrue() {
        // 既にキーが保存されている状態で初期化すると hasKey が true になる
        testDefaults.set("AIzaSyExistingKey", forKey: "google_ai_api_key")
        let newService = APIKeyService(defaults: testDefaults)
        XCTAssertTrue(newService.hasKey)
        XCTAssertEqual(newService.apiKey(), "AIzaSyExistingKey")
    }
}
