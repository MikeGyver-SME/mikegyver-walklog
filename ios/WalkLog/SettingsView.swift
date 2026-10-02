import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloudflare Worker") {
                    TextField("https://walklog-api.<you>.workers.dev",
                              text: $settings.workerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API token", text: $settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(testing ? "Testing…" : "Test connection") { test() }
                        .disabled(testing || !settings.isConfigured)
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("The token is the value you stored with `wrangler secret put WALKLOG_TOKEN`.")
                }

                Section("About") {
                    Text("WalkLog records GPS coordinates + bearing about every 10 seconds and stores your route in your own Cloudflare Worker (SQLite Durable Object).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func test() {
        testing = true
        testResult = ""
        Task {
            do {
                guard let base = settings.normalizedBaseURL else {
                    throw ApiError(message: "That URL does not look valid.")
                }
                let client = ApiClient(baseURL: base, token: settings.trimmedToken)
                try await client.ping()
                testResult = "Connected — the Worker answered."
            } catch {
                testResult = "Failed: \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
