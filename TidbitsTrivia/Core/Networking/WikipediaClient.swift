import Foundation

/// Read-only client for the open Wikipedia REST + Action APIs. No key, no
/// auth — so it deliberately bypasses APIClient's JWT path. `nonisolated`
/// so fetches run off the main actor (the app is MainActor by default).
nonisolated struct WikipediaClient: Sendable {
    static let shared = WikipediaClient()

    private let restBase = "https://en.wikipedia.org/api/rest_v1"
    private let actionBase = "https://en.wikipedia.org/w/api.php"

    // MARK: REST summary

    struct Summary: Decodable, Sendable {
        let title: String
        let description: String?
        let extract: String?
        let type: String?            // "standard" | "disambiguation" | ...
        let thumbnail: Thumb?
        let content_urls: URLs?
        struct Thumb: Decodable, Sendable { let source: String }
        struct URLs: Decodable, Sendable {
            let desktop: Page?
            struct Page: Decodable, Sendable { let page: String? }
        }
        var pageURL: URL? { content_urls?.desktop?.page.flatMap(URL.init(string:)) }
    }

    func summary(for title: String) async throws -> Summary {
        let path = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let url = URL(string: "\(restBase)/page/summary/\(path)")!
        var req = URLRequest(url: url)
        req.setValue("TidbitsTrivia/1.0 (learning trivia app)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Summary.self, from: data)
    }

    // MARK: Search (Action API)

    struct SearchResult: Decodable, Sendable {
        let query: Query?
        struct Query: Decodable, Sendable { let search: [Hit] }
        struct Hit: Decodable, Sendable { let title: String }
    }

    /// Returns candidate article titles for a free-text topic.
    func search(_ topic: String, limit: Int = 30) async throws -> [String] {
        var comp = URLComponents(string: actionBase)!
        comp.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "list", value: "search"),
            .init(name: "srsearch", value: topic),
            .init(name: "srlimit", value: String(limit)),
            .init(name: "srnamespace", value: "0"),
            .init(name: "format", value: "json"),
        ]
        var req = URLRequest(url: comp.url!)
        req.setValue("TidbitsTrivia/1.0 (learning trivia app)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SearchResult.self, from: data)
        return decoded.query?.search.map(\.title) ?? []
    }

    /// Fetch summaries for many titles concurrently, dropping failures.
    func summaries(for titles: [String]) async -> [Summary] {
        await withTaskGroup(of: Summary?.self) { group in
            for t in titles {
                group.addTask { try? await self.summary(for: t) }
            }
            var out: [Summary] = []
            for await s in group where s != nil { out.append(s!) }
            return out
        }
    }
}
