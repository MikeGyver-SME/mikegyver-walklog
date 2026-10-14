import Foundation
import CoreLocation
func p(_ x: Double, _ y: Double) -> TrackPoint {
    TrackPoint(from: CLLocation(latitude: 30 + y / 111194.92664455874,
                               longitude: -95 + x / (111194.92664455874 * cos(.pi / 6))))
}
func check(_ points: [TrackPoint], _ expected: Double) {
    let actual = Geo.totalDistanceMeters(points)
    precondition(abs(actual - expected) < 0.2, "\(actual) vs \(expected)")
}
check([], 0)
check([p(0,0)], 0)
var noisyStraight: [TrackPoint] = []
for i in 0...200 {
    let x: Double = Double(i) * 5.0
    let y: Double
    if i == 0 || i == 200 {
        y = 0.0
    } else if i % 2 == 1 {
        y = 2.0
    } else {
        y = -2.0
    }
    noisyStraight.append(p(x, y))
}
check(noisyStraight, 1000.0)
check([p(0,0),p(50,0),p(100,0),p(100,50),p(100,100)], 200)
check([p(0,0),p(50,0),p(100,0),p(50,0),p(0,0)], 200)
check([p(0,0),p(100,0),p(100,100),p(0,100),p(0,0)], 400)
check([p(0,0),p(1,1),p(-1,-1),p(0,0)], 0)
check([p(0,0),p(1,0)], 1)
print("Swift distance regressions passed")
