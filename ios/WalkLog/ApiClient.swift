import Foundation

struct ApiError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Thin client for the WalkLog Worker API.
final class ApiClient {
    let baseURL: URL
    let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    private func makeRequest(path: String, method: String, body: Any? = nil) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ApiError(message: "No response from server")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ApiError(message: "Server returned \(http.statusCode): \(text)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Creates a walk server-side; returns the walk id.
    func createWalk(device: String) async throws -> String {
        struct R: Decodable { let ok: Bool; let id: String }
        let req = try makeRequest(path: "walks", method: "POST", body: ["device": device])
        return try await send(req, as: R.self).id
    }

    /// Uploads a batch of points. The server dedupes by timestamp, so retries are safe.
    func uploadPoints(walkId: String, points: [TrackPoint]) async throws {
        struct R: Decodable { let ok: Bool; let stored: Int }
        let req = try makeRequest(path: "walks/\(walkId)/points", method: "POST",
                                  body: ["points": points.map(\.apiDictionary)])
        _ = try await send(req, as: R.self)
    }

    func finishWalk(walkId: String) async throws {
        struct R: Decodable { let ok: Bool }
        let req = try makeRequest(path: "walks/\(walkId)/finish", method: "POST", body: [:])
        _ = try await send(req, as: R.self)
    }

    /// Connectivity check used by the Settings screen.
    func ping() async throws {
        let (data, resp) = try await URLSession.shared.data(from: baseURL)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw ApiError(message: "Worker did not answer")
        }
        _ = data
    }
}
