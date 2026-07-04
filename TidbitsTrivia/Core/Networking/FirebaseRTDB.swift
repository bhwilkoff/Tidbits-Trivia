import Foundation

/// Firebase Realtime Database over its REST + streaming API — the Apple twin of
/// `js/firebase.js` and `FirebaseNet.kt`, but with NO third-party SDK (URLSession
/// only, per the Apple no-packages rule). Anonymous auth via the Identity Toolkit
/// REST endpoint; reads/writes via the RTDB `.json` REST API; live updates via
/// Server-Sent Events (`text/event-stream`).
///
/// Shared by the Mac host (publishing a Tidbits Live room) and the iOS join
/// surface. Same project + non-secret config as the web/Android clients, so all
/// four platforms meet in ONE room (js/firebase-config.js). Access is gated by
/// Security Rules + the anon-auth requirement, not by hiding the config.
///
/// Verified end to end against the live project with curl (anon sign-up → PUT →
/// GET → PATCH → roster read → delete) before this client was written.
actor FirebaseRTDB {
    struct Config: Sendable {
        let apiKey: String
        let databaseURL: String   // https://<project>-default-rtdb.firebaseio.com
    }

    /// The committed non-secret web config (same project as js/firebase-config.js).
    static let shared = FirebaseRTDB(config: .init(
        apiKey: "AIzaSyCns8iba6zVqkddEUY_gqoc4eVxz-3BGaA",
        databaseURL: "https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com"))

    let config: Config
    private let session: URLSession
    private var idToken: String?
    private var refreshToken: String?
    private var expiry: Date = .distantPast
    private(set) var uid: String?

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    enum RTDBError: Error, Equatable { case http(Int), noToken, badResponse, alreadyLinked }

    /// Outcome of a federated sign-in: the provider account's uid + its verified email
    /// (identity keys the shared profile by the email, not the uid).
    struct FederatedResult: Sendable { let uid: String; let email: String? }

    // MARK: - Auth (anonymous)

    /// Ensure a live anonymous session; returns the uid. Signs up on first use,
    /// refreshes when the hour-long token nears expiry.
    @discardableResult
    func ensureAuth() async throws -> String {
        if let uid, Date() < expiry.addingTimeInterval(-300) { return uid }
        if refreshToken == nil { refreshToken = Keychain.get(Self.refreshKey) }   // restore persisted session
        if refreshToken != nil {
            do { try await refreshSession() }
            catch { refreshToken = nil; Keychain.delete(Self.refreshKey); try await signUpAnonymous() }
        } else {
            try await signUpAnonymous()
        }
        guard let uid else { throw RTDBError.noToken }
        return uid
    }

    private struct SignUpResponse: Decodable {
        let idToken: String; let refreshToken: String; let expiresIn: String; let localId: String
    }
    private func signUpAnonymous() async throws {
        var req = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(config.apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        let r = try JSONDecoder().decode(SignUpResponse.self, from: data)
        apply(idToken: r.idToken, refreshToken: r.refreshToken, expiresIn: r.expiresIn, uid: r.localId)
    }

    private struct RefreshResponse: Decodable {
        let id_token: String; let refresh_token: String; let expires_in: String; let user_id: String
    }
    private func refreshSession() async throws {
        guard let refreshToken else { try await signUpAnonymous(); return }
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(config.apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        let r = try JSONDecoder().decode(RefreshResponse.self, from: data)
        apply(idToken: r.id_token, refreshToken: r.refresh_token, expiresIn: r.expires_in, uid: r.user_id)
    }

    private struct IdpResponse: Decodable {
        let idToken: String; let refreshToken: String; let expiresIn: String; let localId: String
        let email: String?
    }

    /// Sign in with Apple → the Apple Firebase account (its own uid; allowDuplicateEmails
    /// lets it coexist with a Google account for the same email). Identity keys the shared
    /// profile by the verified email so both providers land on the same records.
    func signInWithApple(identityToken: String, rawNonce: String) async throws -> FederatedResult {
        let post = "id_token=\(identityToken)&providerId=apple.com&nonce=\(rawNonce)"
        let r = try await signInWithIdp(postBody: post, linkTo: nil)
        apply(idToken: r.idToken, refreshToken: r.refreshToken, expiresIn: r.expiresIn, uid: r.localId)
        return FederatedResult(uid: r.localId, email: r.email)
    }

    /// The verified email of the current federated session, decoded from the Firebase ID
    /// token payload (nil for anonymous). Lets the profile re-key by email after relaunch.
    func currentEmail() -> String? {
        guard let token = idToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    /// Sign out of the federated account and return to a FRESH anonymous session (new
    /// uid). The account's records stay in players/{accountUid}; signing back in restores.
    func signOut() async throws -> String {
        Keychain.delete(Self.refreshKey)
        idToken = nil; refreshToken = nil; uid = nil; expiry = .distantPast
        try await signUpAnonymous()
        return uid ?? ""
    }

    private func signInWithIdp(postBody: String, linkTo idToken: String?) async throws -> IdpResponse {
        var body: [String: Any] = ["postBody": postBody, "requestUri": "http://localhost",
                                   "returnSecureToken": true, "returnIdpCredential": true]
        if let idToken { body["idToken"] = idToken }
        var req = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(config.apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            if msg.contains("FEDERATED_USER_ID_ALREADY_LINKED") || msg.contains("EMAIL_EXISTS") { throw RTDBError.alreadyLinked }
            throw RTDBError.http(http.statusCode)
        }
        return try JSONDecoder().decode(IdpResponse.self, from: data)
    }

    /// Keychain key for the anonymous refresh token — persisting it keeps the `uid`
    /// (hence the portable player profile) stable across relaunches.
    static let refreshKey = "tidbits.fb.anonRefresh"

    private func apply(idToken: String, refreshToken: String, expiresIn: String, uid: String) {
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.uid = uid
        self.expiry = Date().addingTimeInterval(TimeInterval(expiresIn) ?? 3600)
        Keychain.set(refreshToken, for: Self.refreshKey)
    }

    private func validToken() async throws -> String {
        try await ensureAuth()
        guard let idToken else { throw RTDBError.noToken }
        return idToken
    }

    // MARK: - REST read/write

    /// Overwrite the value at `path` (RTDB PUT).
    func put<T: Encodable>(_ path: String, _ value: T) async throws {
        try await write(path, value, method: "PUT")
    }
    /// Merge children at `path` (RTDB PATCH).
    func patch<T: Encodable>(_ path: String, _ value: T) async throws {
        try await write(path, value, method: "PATCH")
    }
    func delete(_ path: String) async throws {
        let token = try await validToken()
        var req = URLRequest(url: restURL(path, token: token))
        req.httpMethod = "DELETE"
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }
    /// True if a value exists (non-null) at `path`. A cheap presence check that
    /// decodes nothing — so it can probe a node keyed by a @MainActor-isolated
    /// Codable type (e.g. `live/{code}/meta`) without tripping Swift 6's
    /// isolated-conformance rule inside this actor. Used by the unified "Join a
    /// game" front to tell a hosted Tidbits Live room from a LAN Trivia Night.
    func exists(_ path: String) async throws -> Bool {
        let token = try await validToken()
        let (data, resp) = try await session.data(from: restURL(path, token: token))
        try Self.check(resp)
        guard let s = String(data: data, encoding: .utf8) else { return false }
        return !data.isEmpty && s != "null"
    }

    /// Read + decode the value at `path` (nil if the node is absent → JSON null).
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T? {
        let token = try await validToken()
        let (data, resp) = try await session.data(from: restURL(path, token: token))
        try Self.check(resp)
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ path: String, _ value: T, method: String) async throws {
        try await writeJSON(path, JSONEncoder().encode(value), method: method)
    }

    /// Write pre-encoded JSON. Callers on another actor (e.g. the @MainActor host)
    /// encode their own value first, so a MainActor-isolated Codable conformance
    /// never has to run inside this actor (Swift 6 isolated-conformances).
    func putJSON(_ path: String, _ json: Data) async throws { try await writeJSON(path, json, method: "PUT") }
    func patchJSON(_ path: String, _ json: Data) async throws { try await writeJSON(path, json, method: "PATCH") }

    private func writeJSON(_ path: String, _ json: Data, method: String) async throws {
        let token = try await validToken()
        var req = URLRequest(url: restURL(path, token: token))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }

    // MARK: - Live streaming (Server-Sent Events)

    struct StreamEvent: Sendable {
        let event: String     // "put" | "patch" | "keep-alive" | "cancel" | "auth_revoked"
        let path: String      // relative to the streamed node, e.g. "/" or "/teams/uid"
        let dataJSON: Data?    // the SSE `data` value re-encoded as JSON (nil when null)
    }

    /// Stream live updates at `path` as SSE. The stream cancels its underlying
    /// request when the consumer's task is cancelled.
    func stream(_ path: String) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let token = try await validToken()
        var req = URLRequest(url: restURL(path, token: token))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 3600
        return Self.makeStream(req: req, session: session)
    }

    /// nonisolated so the AsyncThrowingStream build closure captures only Sendable
    /// values (URLRequest, URLSession) — never actor-isolated state (Swift 6).
    nonisolated static func makeStream(req: URLRequest, session: URLSession) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    try check(resp)
                    var currentEvent = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            if let ev = parse(event: currentEvent, payload: String(line.dropFirst(6))) { continuation.yield(ev) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parse an RTDB SSE frame: `data: {"path":"/x","data":<value>}`.
    nonisolated static func parse(event: String, payload: String) -> StreamEvent? {
        guard event != "keep-alive" else { return nil }
        guard let d = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return StreamEvent(event: event, path: "/", dataJSON: nil)
        }
        let path = obj["path"] as? String ?? "/"
        var dataJSON: Data?
        if let value = obj["data"], !(value is NSNull) {
            dataJSON = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        return StreamEvent(event: event, path: path, dataJSON: dataJSON)
    }

    // MARK: - Helpers

    private func restURL(_ path: String, token: String) -> URL {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(config.databaseURL)/\(clean).json?auth=\(token)")!
    }

    nonisolated static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw RTDBError.badResponse }
        guard (200...299).contains(http.statusCode) else { throw RTDBError.http(http.statusCode) }
    }

    /// A short human-shareable room code (Crockford-ish, no confusable chars) —
    /// the same alphabet as js/firebase.js so codes read identically everywhere.
    static func newRoomCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }
}
