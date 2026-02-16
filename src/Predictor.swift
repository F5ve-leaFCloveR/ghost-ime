import Foundation

final class Predictor {
    private let words: [String]
    private var userCounts: [String: Int]
    private let countsURL: URL
    private let aiSuggester: AISuggester?

    init() {
        if let url = Bundle.main.url(forResource: "words", withExtension: "txt"),
           let data = try? String(contentsOf: url, encoding: .utf8) {
            words = data
                .split(whereSeparator: { $0.isWhitespace })
                .map { $0.lowercased() }
                .filter { $0.count >= 2 }
        } else {
            words = []
        }

        let appDir = Self.resolveAppDirectory()
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        countsURL = appDir.appendingPathComponent("user_counts.json")
        aiSuggester = AISuggester.loadDefault(appDirectory: appDir)

        if let data = try? Data(contentsOf: countsURL),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            userCounts = decoded
        } else {
            userCounts = [:]
        }
    }

    func suggest(for prefix: String) -> String? {
        let p = prefix.lowercased()
        guard p.count >= 1 else { return nil }

        var best: String?
        var bestScore = -1
        var bestLen = Int.max

        for w in words {
            guard w.hasPrefix(p), w.count > p.count else { continue }

            let score = userCounts[w, default: 0]
            if score > bestScore {
                best = w
                bestScore = score
                bestLen = w.count
                continue
            }

            if score == bestScore, w.count < bestLen {
                best = w
                bestLen = w.count
            }
        }

        return best
    }

    func requestNeuralSuggestion(for prefix: String, completion: @escaping (String?) -> Void) {
        guard let aiSuggester else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        aiSuggester.suggest(prefix: prefix, completion: completion)
    }

    func learn(word: String) {
        let w = word.lowercased()
        guard w.count >= 2 else { return }
        userCounts[w, default: 0] += 1
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(userCounts) else { return }
        try? data.write(to: countsURL, options: [.atomic])
    }

    private static func resolveAppDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("ghost-ime", isDirectory: true)
    }
}
