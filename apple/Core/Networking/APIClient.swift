import Foundation

/// Shared API client — ALL network calls go through this singleton.
/// Views never call URLSession directly. Same architectural rule as
/// `js/api.js` (web) and `ApiClient.kt` (Android).
///
/// `refreshIfNeeded()` is the cross-platform contract: every call
/// that hits a Cloudflare Worker, Supabase Storage, or any
/// Edge Function MUST refresh the JWT first. Auth-SDK auto-refresh
/// only covers the SDK's own HTTP path; external endpoints bypass it.
/// Symptom of skipping: 401s — or worse, 400s with "exp claim" in the
/// body — on Worker calls that look like generic backend bugs.
actor APIClient {
    static let shared = APIClient()

    // FILL IN: Your API base URL
    private let baseURL = ""

    private func authHeaders() -> [String: String] {
        // FILL IN: Return auth headers
        [:]
    }

    /// Call BEFORE any request to a Worker / Storage / Edge Function.
    /// Implementation depends on your auth manager — typically:
    ///   if let exp = session.expiresAt, exp < Date().addingTimeInterval(60) {
    ///       try await AuthManager.shared.refresh()
    ///   }
    func refreshIfNeeded() async throws {
        // FILL IN
    }

    func get<T: Decodable>(_ endpoint: String, params: [String: String] = [:]) async throws -> T {
        try await refreshIfNeeded()
        var components = URLComponents(string: baseURL + endpoint)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        for (k, v) in authHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await refreshIfNeeded()
        var request = URLRequest(url: URL(string: baseURL + endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in authHeaders() { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
