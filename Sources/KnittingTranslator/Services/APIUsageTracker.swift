import Foundation

final class APIUsageTracker {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    private let countKey = "gemini_daily_request_count"
    private let dateKey  = "gemini_daily_request_date"

    let freeierLimit = 500

    var usedToday: Int {
        resetIfNewDay()
        return defaults.integer(forKey: countKey)
    }

    func recordUsage(_ count: Int) {
        resetIfNewDay()
        defaults.set(defaults.integer(forKey: countKey) + count, forKey: countKey)
    }

    /// 翻訳後に残り10%未満になるか
    func wouldTriggerWarning(adding count: Int) -> Bool {
        return usedToday + count > Int(Double(freeierLimit) * 0.90)
    }

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let stored = defaults.object(forKey: dateKey) as? Date ?? .distantPast
        guard !Calendar.current.isDate(today, inSameDayAs: stored) else { return }
        defaults.set(0,     forKey: countKey)
        defaults.set(today, forKey: dateKey)
    }
}
