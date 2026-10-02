import Foundation
import CoreLocation
import Combine

/// Wraps CLLocationManager for background-capable walk tracking.
///
/// iOS reality check: the OS — not the app — decides how often fixes arrive,
/// especially with the screen locked. So this tracker records every accepted
/// fix and lets WalkSession batch uploads about every 10 seconds, rather than
/// pretending a timer fires in the background.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var latestLocation: CLLocation?

    /// Called on the main actor for every accepted fix.
    var onLocation: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5 // meters
        manager.activityType = .fitness
        // Background survival:
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    /// "Always" is required for tracking with the screen locked.
    func requestAlwaysIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last else { return }
        // Drop invalid or very coarse fixes (indoors / urban canyon).
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 65 else { return }
        // Drop stale cached fixes delivered right after start.
        guard abs(fix.timestamp.timeIntervalSinceNow) < 10 else { return }
        Task { @MainActor in
            self.latestLocation = fix
            self.onLocation?(fix)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        // GPS gaps (tunnels, buildings) are normal; the session keeps going and
        // resumes recording when fixes return.
    }
}
