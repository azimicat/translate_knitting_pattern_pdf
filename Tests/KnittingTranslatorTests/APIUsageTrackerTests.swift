import XCTest
@testable import KnittingTranslator

final class APIUsageTrackerTests: XCTestCase {

    private var sut: APIUsageTracker!
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName    = "APIUsageTrackerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        sut          = APIUsageTracker(defaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        sut = nil
    }

    // MARK: - 初期状態

    func testUsedToday_initial_isZero() {
        XCTAssertEqual(sut.usedToday, 0)
    }

    // MARK: - recordUsage

    func testRecordUsage_incrementsCount() {
        sut.recordUsage(10)
        XCTAssertEqual(sut.usedToday, 10)
    }

    func testRecordUsage_accumulates() {
        sut.recordUsage(10)
        sut.recordUsage(5)
        XCTAssertEqual(sut.usedToday, 15)
    }

    // MARK: - wouldTriggerWarning

    func testWouldTriggerWarning_belowThreshold_returnsFalse() {
        // usedToday=0, adding=450 → 合計450 = 500*0.90 → 超えない
        XCTAssertFalse(sut.wouldTriggerWarning(adding: 450))
    }

    func testWouldTriggerWarning_aboveThreshold_returnsTrue() {
        // usedToday=0, adding=451 → 合計451 > 450 → 警告
        XCTAssertTrue(sut.wouldTriggerWarning(adding: 451))
    }

    func testWouldTriggerWarning_withExistingUsage_belowThreshold_returnsFalse() {
        // usedToday=440, adding=10 → 合計450 = 450 → 超えない
        sut.recordUsage(440)
        XCTAssertFalse(sut.wouldTriggerWarning(adding: 10))
    }

    func testWouldTriggerWarning_withExistingUsage_aboveThreshold_returnsTrue() {
        // usedToday=440, adding=11 → 合計451 > 450 → 警告
        sut.recordUsage(440)
        XCTAssertTrue(sut.wouldTriggerWarning(adding: 11))
    }

    func testWouldTriggerWarning_atLimit_returnsTrue() {
        // usedToday=450, adding=1 → 合計451 > 450 → 警告
        sut.recordUsage(450)
        XCTAssertTrue(sut.wouldTriggerWarning(adding: 1))
    }

    func testWouldTriggerWarning_alreadyAtFreeierLimit_returnsTrue() {
        // 全枠使い切った状態でも1ページでも警告
        sut.recordUsage(500)
        XCTAssertTrue(sut.wouldTriggerWarning(adding: 1))
    }

    // MARK: - 日付リセット

    func testResetIfNewDay_resetsCountForNewDay() {
        // 昨日の日付を記録しておく
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)
        testDefaults.set(99, forKey: "gemini_daily_request_count")
        testDefaults.set(yesterdayStart, forKey: "gemini_daily_request_date")

        // 新しい日のインスタンスで usedToday を参照するとリセットされる
        let freshSut = APIUsageTracker(defaults: testDefaults)
        XCTAssertEqual(freshSut.usedToday, 0)
    }

    func testResetIfNewDay_sameDay_doesNotReset() {
        sut.recordUsage(99)
        // 同じインスタンスで再度アクセスしてもリセットされない
        XCTAssertEqual(sut.usedToday, 99)
    }

    // MARK: - freeierLimit

    func testFreeierLimit_is500() {
        XCTAssertEqual(sut.freeierLimit, 500)
    }
}
