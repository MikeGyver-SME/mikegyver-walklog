import Foundation
import Combine

/// Worker URL + API token, persisted in UserDefaults. Entered once in Settings.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var workerURL: String {
        didSet { UserDefaults.standard.set(workerURL, forKey: Self.urlKey) }
    }
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: Self.tokenKey) }
    }

    private static let urlKey = "walklog.workerURL"
    private static let tokenKey = "walklog.token"

    private init() {
        workerURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        token = UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
    }

    var isConfigured: Bool {
        let u = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.lowercased().hasPrefix("http") && !t.isEmpty
    }

    var normalizedBaseURL: URL? {
        var u = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        return URL(string: u)
    }

    var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
