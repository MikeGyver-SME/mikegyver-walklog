# WalkLog 1.1 — distance smoothing field-test release

The previous iPhone and Worker calculations summed every consecutive GPS segment. Small sideways position errors can inflate distance without an obvious jump on the map. This is a plausible contributor to the October 13 discrepancy, not proof of the true distance or of Apple Watch accuracy.

## Changes

- Same 3-meter Ramer–Douglas–Peucker distance-only simplification on iOS and the Worker. It retains endpoints and deviations exceeding 3 meters; corners, reversals and loops are regression tested. Tight curves and turns below the tolerance can still lose distance. This is an estimate requiring field validation, not a calibrated correction.
- Every original accepted GPS point remains in the upload, database and map. No percentage correction and no every-Nth-point shortcut.
- API summaries include `raw_distance_m` and `distance_method: rdp-3m-v1` so the treatment can be compared with the raw total.
- iOS ignores duplicate/out-of-order fixes. Upload completion advances only to the end of the batch actually sent; stopping waits for an in-flight batch before flushing the remaining points.
- App marketing version 1.1.0, build 3. If build 3 has already been used in App Store Connect, raise CURRENT_PROJECT_VERSION before uploading.

## Measured replay

October 13 public map, 1,779 coordinates:
- Old/raw: 6.348528 miles.
- New distance estimate: 6.240658 miles.
- Apple Watch screenshot: 6.08 miles.
- Residual difference from watch: about 0.161 mile (2.6%).

The public map supplied coordinates only, so this replay cannot assess accuracy readings, speed or fix timing. The 3-meter tolerance was chosen as a conservative noise tolerance, not tuned to make the result match the watch. GPS spikes beyond the tolerance are still retained by this distance simplifier; this release does not claim to solve large jumps or all stationary drift.

## Install both parts

1. Copy this project's changed and new files into your existing checkout, retaining its own .git directory and repository settings. No credentials or signing changes are required.
2. From `worker`, run `npm install`, `npm test`, then `npm run deploy` using your existing Cloudflare setup. No database migration is needed.
3. Commit the iOS updates and test workflow, then use your existing TestFlight workflow. Install the resulting TestFlight build on the phone.
4. Update both pieces before comparing app and map distances. A newly deployed Worker recomputes summaries for existing walks too; stored raw points remain unchanged. Old on-phone summaries/screenshots do not update retroactively.

## Validation

Eight Node regression tests passed locally; Worker JavaScript syntax checked. Native Swift tests are provided in ios/Tests/main.swift and a macOS CI workflow compiles Models.swift and executes them. This Linux environment has no Swift/Xcode, so the native tests and full iOS build were not run here. They must pass on macOS before installation.

For the next field test, start both devices close together and compare the app summary, map summary and watch. Include straight sections, turns, a loop and a brief stationary stop. A precisely measured course is a stronger accuracy reference than agreement with another tracker. The live estimate can revise slightly as additional points change which small deviations are simplified.
