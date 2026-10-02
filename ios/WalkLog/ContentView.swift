import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: WalkSession
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showSettings = false
    @State private var confirmStop = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                switch session.phase {
                case .idle: idleView
                case .acquiring: acquiringView
                case .tracking: trackingView
                case .finishing: finishingView
                case .done: doneView
                }
            }
            .padding()
            .navigationTitle("WalkLog")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("Stop this walk?", isPresented: $confirmStop,
                                titleVisibility: .visible) {
                Button("Stop walk", role: .destructive) { session.stop() }
                Button("Keep walking", role: .cancel) {}
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(Brand.navy, Brand.gold)
            Text("Ready when you are.")
                .font(.title2)
            if !settings.isConfigured {
                Text("Add your Worker URL and token in Settings to begin.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { showSettings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.navy)
            } else {
                Button {
                    session.start()
                } label: {
                    Text("Start Walk")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.navy)
                Text("GPS + bearing recorded about every 10 seconds, even with the screen locked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Acquiring

    private var acquiringView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(session.statusMessage.isEmpty ? "Acquiring GPS…" : session.statusMessage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Step outside or near a window for a faster fix.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) { session.cancel() }
                .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Tracking

    private var trackingView: some View {
        VStack(spacing: 20) {
            Spacer()
            liveStatRow(label: "Elapsed", value: WalkSummary.formatDuration(session.liveElapsed))
            liveStatRow(label: "Distance", value: String(format: "%.2f mi", session.liveDistanceMi))
            liveStatRow(label: "Speed", value: String(format: "%.1f mph", session.liveSpeedMph))
            Text("\(session.points.count) GPS points recorded")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) { confirmStop = true } label: {
                Text("Stop")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func liveStatRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.title, design: .monospaced))
                .bold()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Finishing

    private var finishingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(session.statusMessage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            if let summary = session.summary {
                SummaryView(points: session.points, summary: summary, mapURL: session.mapURL)
            }
            Button("New Walk") { session.reset() }
                .buttonStyle(.bordered)
        }
    }
}
