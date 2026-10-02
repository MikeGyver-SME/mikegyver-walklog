import Foundation
import CoreLocation
import UIKit

enum WalkPhase: Equatable {
    case idle
    case acquiring   // waiting for the first good GPS fixes
    case tracking
    case finishing   // flushing final points + closing the walk server-side
    case done
}

/// Owns one walk: GPS capture, ~10 s batched uploads, local backup, summary.
@MainActor
final class WalkSession: ObservableObject {
    @Published var phase: WalkPhase = .idle
    @Published var points: [TrackPoint] = []
    @Published var statusMessage = ""
    @Published var summary: WalkSummary?
    @Published var mapURL: URL?

    // Live readouts while tracking
    @Published var liveElapsed: TimeInterval = 0
    @Published var liveDistanceMi: Double = 0
    @Published var liveSpeedMph: Double = 0

    private let tracker = LocationTracker()
    private var api: ApiClient?
    private var walkId: String?
    private var startTime: Date?
    private var lastUpload = Date.distantPast
    private var sentCount = 0
    private var uploading = false
    private var tickTimer: Timer?

    var settings: SettingsStore { SettingsStore.shared }

    // MARK: - Control

    func start() {
        guard phase == .idle else { return }
        guard settings.isConfigured, let base = settings.normalizedBaseURL else {
            statusMessage = "Enter your Worker URL and token in Settings first."
            return
        }
        api = ApiClient(baseURL: base, token: settings.trimmedToken)
        points = []
        sentCount = 0
        summary = nil
        mapURL = nil
        startTime = nil
        liveElapsed = 0; liveDistanceMi = 0; liveSpeedMph = 0
        phase = .acquiring
        statusMessage = "Acquiring GPS…"
        tracker.onLocation = { [weak self] loc in self?.handleLocation(loc) }
        tracker.requestAlwaysIfNeeded()
        tracker.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { await createWalkOnServer() }
    }

    func stop() {
        guard phase == .tracking || phase == .acquiring else { return }
        phase = .finishing
        statusMessage = "Uploading final points…"
        tracker.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        Task { await finish() }
    }

    func reset() {
        tracker.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        phase = .idle
        points = []
        summary = nil
        mapURL = nil
        walkId = nil
        api = nil
        sentCount = 0
        statusMessage = ""
        clearLocalBackup()
    }

    func cancel() { reset() }

    // MARK: - Internals

    private func createWalkOnServer() async {
        do {
            let id = try await api!.createWalk(device: UIDevice.current.name)
            walkId = id
            lastUpload = Date()
            saveLocalBackup()
        } catch {
            statusMessage = "Could not reach the Worker: \(error.localizedDescription)"
            tracker.stop()
            tickTimer?.invalidate()
            tickTimer = nil
            phase = .idle
        }
    }

    private func handleLocation(_ loc: CLLocation) {
        guard phase == .acquiring || phase == .tracking else { return }
        let p = TrackPoint(from: loc)
        points.append(p)
        if phase == .acquiring, points.count >= 3 {
            phase = .tracking
            startTime = points.first?.timestamp
            statusMessage = ""
        }
        saveLocalBackup()
        updateLiveStats()
        // Upload at most every 10 s; the server dedupes, so retries are safe.
        if Date().timeIntervalSince(lastUpload) >= 10 {
            uploadPending()
        }
    }

    private func tick() {
        guard phase == .tracking else { return }
        updateLiveStats()
    }

    private func updateLiveStats() {
        if let t0 = startTime {
            liveElapsed = Date().timeIntervalSince(t0)
        }
        liveDistanceMi = Geo.totalDistanceMeters(points) / 1609.344
        if let speed = points.last?.speed, speed > 0 {
            liveSpeedMph = speed * 2.23694
        }
    }

    private func uploadPending() {
        guard !uploading, let api, let walkId, sentCount < points.count else { return }
        uploading = true
        lastUpload = Date()
        let batch = Array(points[sentCount...])
        Task {
            do {
                try await api.uploadPoints(walkId: walkId, points: batch)
                self.sentCount = self.points.count
            } catch {
                // Points stay local; the next cycle retries.
            }
            self.uploading = false
        }
    }

    private func finish() async {
        if let api, let walkId, sentCount < points.count {
            try? await api.uploadPoints(walkId: walkId, points: Array(points[sentCount...]))
            sentCount = points.count
        }
        if let api, let walkId {
            _ = try? await api.finishWalk(walkId: walkId)
            mapURL = api.baseURL.appendingPathComponent("walks/\(walkId)/map")
        }
        summary = WalkSummary.compute(points: points, walkId: walkId ?? "local")
        clearLocalBackup()
        phase = .done
    }

    // MARK: - Local backup (survives app kill / cellular dead zones)

    private var backupURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("walklog_pending.json")
    }

    private func saveLocalBackup() {
        struct Backup: Codable {
            var walkId: String?
            var points: [TrackPoint]
        }
        let backup = Backup(walkId: walkId, points: points)
        try? JSONEncoder().encode(backup).write(to: backupURL, options: .atomic)
    }

    private func clearLocalBackup() {
        try? FileManager.default.removeItem(at: backupURL)
    }
}
