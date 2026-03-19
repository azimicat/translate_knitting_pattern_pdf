import Foundation

/// Google AI API キーの保存・読み込みを管理する。
/// テスト時は `UserDefaults(suiteName:)` を注入することで実際のストレージを汚染しない。
@MainActor
@Observable
final class APIKeyService {

    private(set) var hasKey: Bool = false

    private let defaults: UserDefaults
    private let defaultsKey = "google_ai_api_key"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasKey = loadKey() != nil
    }

    func save(_ key: String) {
        defaults.set(key, forKey: defaultsKey)
        hasKey = true
    }

    func apiKey() -> String? {
        loadKey()
    }

    func delete() {
        defaults.removeObject(forKey: defaultsKey)
        hasKey = false
    }

    // MARK: - Private

    private func loadKey() -> String? {
        let key = defaults.string(forKey: defaultsKey)
        return key.flatMap { $0.isEmpty ? nil : $0 }
    }
}
