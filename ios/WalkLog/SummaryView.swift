import SwiftUI
import MapKit

/// Inline map of the finished walk + stats, rendered from local points —
/// instant, no waiting on the network.
struct SummaryView: View {
    let points: [TrackPoint]
    let summary: WalkSummary
    let mapURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if points.count >= 2 {
                    Map(position: .constant(.region(fitRegion))) {
                        MapPolyline(coordinates: points.map(\.coordinate))
                            .stroke(Brand.navy, lineWidth: 4)
                        Marker("Start", coordinate: points.first!.coordinate)
                            .tint(.green)
                        Marker("End", coordinate: points.last!.coordinate)
                            .tint(.red)
                    }
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ContentUnavailableView(
                        "No route",
                        systemImage: "mappin.slash",
                        description: Text("Not enough GPS points were recorded.")
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 12) {
                    statCard("Total time", WalkSummary.formatDuration(summary.durationSeconds))
                    statCard("Distance", String(format: "%.2f mi", summary.distanceMiles))
                    statCard("Avg pace", String(format: "%.1f mph", summary.avgMph))
                    statCard("Points", "\(summary.pointCount)")
                }

                if let mapURL {
                    ShareLink(item: mapURL) {
                        Label("Share walk map", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.navy)
                    Text("Opens a web map of this walk — no login needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Walk summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Region that fits the whole route with padding.
    private var fitRegion: MKCoordinateRegion {
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.002, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.002, (maxLon - minLon) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
