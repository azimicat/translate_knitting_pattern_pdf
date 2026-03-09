import Foundation

enum EnvLoader {
    static func load() -> [String: String] {
        let paths: [String] = [
            // バンドル内 (make_app.sh で .app に埋め込まれた .env)
            Bundle.main.resourceURL?.appendingPathComponent(".env").path,
            Bundle.main.path(forResource: ".env", ofType: nil),
            // カレントディレクトリ（swift run 実行時はプロジェクト直下）
            FileManager.default.currentDirectoryPath + "/.env",
        ].compactMap { $0 }

        for path in paths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            return content.components(separatedBy: "\n").reduce(into: [:]) { dict, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), !trimmed.isEmpty,
                      let eq = trimmed.firstIndex(of: "=") else { return }
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                dict[key] = val
            }
        }
        return [:]
    }

    static func googleAIAPIKey() -> String? {
        load()["GOOGLE_AI_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
    }
}
