import Foundation
import CoreLocation
import SwiftUI

// MARK: - Brand

enum Brand {
    /// MikeGyver navy
    static let navy = Color(red: 10 / 255, green: 31 / 255, blue: 68 / 255)
    /// MikeGyver gold
    static let gold = Color(red: 232 / 255, green: 182 / 255, blue: 42 / 255)
}

// MARK: - TrackPoint

/// One GPS fix: coordinates + directional bearing (course) + speed.
struct TrackPoint: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    /// Directional bearing of travel in degrees true. nil when stationary/unknown.
    var course: Double?
    /// Speed in meters per second. nil when unknown.
    var speed: Double?
    /// Horizontal accuracy in meters. nil when unknown.
    var accuracy: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(from location: CLLocation) {
        timestamp = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        course = location.course >= 0 ? location.course : nil
        speed = location.speed >= 0 ? location.speed : nil
        accuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
    }

    /// Dictionary matching the Worker API schema: {ts, lat, lon, alt?, course?, speed?, accuracy?}
    var apiDictionary: [String: Any] {
        var d: [String: Any] = [
            "ts": Int(timestamp.timeIntervalSince1970 * 1000),
            "lat": latitude,
            "lon": longitude,
        ]
        if let v = altitude { d["alt"] = v }
        if let v = course { d["course"] = v }
        if let v = speed { d["speed"] = v }
        if let v = accuracy { d["accuracy"] = v }
        return d
    }
}

// MARK: - WalkSummary

struct WalkSummary: Codable {
    var walkId: String
    var pointCount: Int
    var durationSeconds: Double
    var distanceMeters: Double

    var distanceMiles: Double { distanceMeters / 1609.344 }
    var avgMph: Double {
        durationSeconds > 0 ? distanceMiles / (durationSeconds / 3600) : 0
    }

    static func compute(points: [TrackPoint], walkId: String) -> WalkSummary {
        let distance = Geo.totalDistanceMeters(points)
        let duration: Double
        if let first = points.first?.timestamp, let last = points.last?.timestamp {
            duration = max(0, last.timeIntervalSince(first))
        } else {
            duration = 0
        }
        return WalkSummary(walkId: walkId, pointCount: points.count,
                           durationSeconds: duration, distanceMeters: distance)
    }

    /// h:mm:ss
    static func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Geo

enum Geo {
    static func haversineMeters(from a: CLLocationCoordinate2D,
                                to b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let s = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(min(1, max(0, s))))
    }

    static func totalDistanceMeters(_ points: [TrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        // Use the same 3 m distance-only simplification as the Worker.
        // Keep every raw point for uploads and map rendering.
        var keep: Set<Int> = [0, points.count - 1]
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            var best = 3.0
            var index: Int?
            if b > a + 1 {
                for i in (a + 1)..<b {
                    let d = deviation(points[i].coordinate, points[a].coordinate, points[b].coordinate)
                    if d > best { best = d; index = i }
                }
            }
            if let i = index {
                keep.insert(i)
                stack.append((a, i)); stack.append((i, b))
            }
        }
        let indices = keep.sorted()
        var total = 0.0
        for i in 1..<indices.count {
            total += haversineMeters(from: points[indices[i - 1]].coordinate,
                                     to: points[indices[i]].coordinate)
        }
        return total
    }

    private static func deviation(_ p: CLLocationCoordinate2D,
                                  _ a: CLLocationCoordinate2D,
                                  _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0
        let scale = cos(a.latitude * .pi / 180)
        let x = (p.longitude - a.longitude) * .pi / 180 * r * scale
        let y = (p.latitude - a.latitude) * .pi / 180 * r
        let bx = (b.longitude - a.longitude) * .pi / 180 * r * scale
        let by = (b.latitude - a.latitude) * .pi / 180 * r
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared > 0 ? max(0, min(1, (x * bx + y * by) / lengthSquared)) : 0
        return hypot(x - t * bx, y - t * by)
    }
}
