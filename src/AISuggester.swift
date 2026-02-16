import Foundation

final class AISuggester {
    struct Config {
        let endpoint: URL
        let model: String
        let temperature: Double
        let maxTokens: Int
        let timeoutSeconds: TimeInterval
        let minPrefixLength: Int
        let cacheTTLSeconds: TimeInterval
    }

    private struct CacheEntry {
        let value: String?
        let createdAt: Date
    }

    private let config: Config
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "ghost-ime.ai-suggester")
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: [(String?) -> Void]] = [:]

    init(config: Config) {
        self.config = config

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        sessionConfig.timeoutIntervalForResource = config.timeoutSeconds + 2
        session = URLSession(configuration: sessionConfig)
    }

    static func loadDefault(appDirectory: URL) -> AISuggester? {
        let env = ProcessInfo.processInfo.environment
        let fileURL = appDirectory.appendingPathComponent("ai_config.json")
        let fileValues = loadValues(from: fileURL)

        let enabled = parseBool(env["GHOST_IME_AI_ENABLED"])
            ?? (fileValues["enabled"] as? Bool)
            ?? true
        guard enabled else { return nil }

        let endpointString = env["GHOST_IME_AI_ENDPOINT"]
            ?? (fileValues["endpoint"] as? String)
            ?? "http://127.0.0.1:11434/api/generate"
        guard let endpoint = URL(string: endpointString) else {
            NSLog("ghost-ime: invalid AI endpoint: %@", endpointString)
            return nil
        }

        let model = env["GHOST_IME_AI_MODEL"]
            ?? (fileValues["model"] as? String)
            ?? "llama3.2:1b"

        let temperature = parseDouble(env["GHOST_IME_AI_TEMPERATURE"])
            ?? (fileValues["temperature"] as? Double)
            ?? 0.2

        let maxTokens = parseInt(env["GHOST_IME_AI_MAX_TOKENS"])
            ?? (fileValues["maxTokens"] as? Int)
            ?? 8

        let timeoutSeconds = parseDouble(env["GHOST_IME_AI_TIMEOUT"])
            ?? (fileValues["timeoutSeconds"] as? Double)
            ?? 3.0

        let minPrefixLength = parseInt(env["GHOST_IME_AI_MIN_PREFIX"])
            ?? (fileValues["minPrefixLength"] as? Int)
            ?? 2

        let cacheTTLSeconds = parseDouble(env["GHOST_IME_AI_CACHE_TTL"])
            ?? (fileValues["cacheTTLSeconds"] as? Double)
            ?? 300

        let config = Config(
            endpoint: endpoint,
            model: model,
            temperature: max(0.0, temperature),
            maxTokens: max(1, maxTokens),
            timeoutSeconds: max(1.0, timeoutSeconds),
            minPrefixLength: max(1, minPrefixLength),
            cacheTTLSeconds: max(10.0, cacheTTLSeconds)
        )

        return AISuggester(config: config)
    }

    func suggest(prefix: String, completion: @escaping (String?) -> Void) {
        let normalized = prefix.lowercased()
        guard normalized.count >= config.minPrefixLength else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        stateQueue.async {
            let now = Date()
            if let entry = self.cache[normalized],
               now.timeIntervalSince(entry.createdAt) <= self.config.cacheTTLSeconds {
                DispatchQueue.main.async { completion(entry.value) }
                return
            }

            self.inFlight[normalized, default: []].append(completion)
            guard self.inFlight[normalized]?.count == 1 else {
                return
            }

            self.fetchSuggestion(prefix: normalized)
        }
    }

    private func fetchSuggestion(prefix: String) {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = makePayload(prefix: prefix)
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            finish(prefix: prefix, value: nil)
            return
        }
        request.httpBody = body

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            guard error == nil else {
                self.finish(prefix: prefix, value: nil)
                return
            }

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data else {
                self.finish(prefix: prefix, value: nil)
                return
            }

            let suggestion = self.parseSuggestion(from: data, prefix: prefix)
            self.finish(prefix: prefix, value: suggestion)
        }
        task.resume()
    }

    private func finish(prefix: String, value: String?) {
        stateQueue.async {
            self.cache[prefix] = CacheEntry(value: value, createdAt: Date())
            let callbacks = self.inFlight.removeValue(forKey: prefix) ?? []
            DispatchQueue.main.async {
                for callback in callbacks {
                    callback(value)
                }
            }
        }
    }

    private func makePayload(prefix: String) -> [String: Any] {
        return [
            "model": config.model,
            "prompt": "Continue exactly one English word for this prefix: '\(prefix)'. Return only the completed word that starts with the prefix. No punctuation and no explanation.",
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "num_predict": config.maxTokens
            ]
        ]
    }

    private func parseSuggestion(from data: Data, prefix: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = json as? [String: Any],
              let response = root["response"] as? String else {
            return nil
        }

        return normalize(raw: response, prefix: prefix)
    }

    private func normalize(raw: String, prefix: String) -> String? {
        let token = firstWord(in: raw).lowercased()
        guard token.isEmpty == false else { return nil }

        var candidate = token
        if candidate.hasPrefix(prefix) == false {
            candidate = prefix + candidate
        }

        guard candidate.hasPrefix(prefix), candidate.count > prefix.count else {
            return nil
        }

        return candidate
    }

    private func firstWord(in text: String) -> String {
        var result = ""
        var started = false

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || scalar.value == 0x27 {
                result.append(String(scalar))
                started = true
                continue
            }

            if started {
                break
            }
        }

        return result
    }

    private static func loadValues(from fileURL: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else {
            return [:]
        }

        return dict
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func parseDouble(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value)
    }

    private static func parseInt(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value)
    }
}
