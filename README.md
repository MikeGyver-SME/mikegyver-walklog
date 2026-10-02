# WalkLog v1.0.0

An iOS walk tracker for MikeGyver Studio. Tap **Start Walk**, and the app
silently records your GPS coordinates + directional bearing about every
10 seconds into your own Cloudflare Worker (SQLite Durable Object) — even with
the screen locked. Tap **Stop** and within seconds you get an inline map of
your route, total time, distance, average mph, and a shareable web map link.

## Layout

```
walklog/
├── worker/                  Cloudflare Worker + SQLite Durable Object API
│   ├── wrangler.toml        Worker config (walklog-api, WalkLogDO binding)
│   ├── package.json
│   └── src/index.js         Routes, auth, haversine summary, Leaflet map page
├── ios/                     SwiftUI iPhone app (XcodeGen project)
│   ├── project.yml          MARKETING_VERSION / CURRENT_PROJECT_VERSION live here
│   └── WalkLog/
│       ├── WalkLogApp.swift
│       ├── Models.swift         TrackPoint, WalkSummary, Geo helpers
│       ├── SettingsStore.swift  Worker URL + token (UserDefaults)
│       ├── ApiClient.swift      Worker REST client
│       ├── LocationTracker.swift CLLocationManager, background-capable
│       ├── WalkSession.swift    Walk state machine, ~10 s batched uploads
│       ├── ContentView.swift    Start / live stats / Stop UI
│       ├── SummaryView.swift    Inline MapKit route + stats + ShareLink
│       ├── SettingsView.swift   Worker URL/token entry + connection test
│       ├── Info.plist           Location usage strings, UIBackgroundModes
│       └── Assets.xcassets/     Navy/gold app icon set
├── .github/workflows/
│   └── testflight.yml       macos-26: XcodeGen → archive → IPA → fastlane pilot
├── docs/
│   └── POWERSHELL-SETUP.md  Detailed PowerShell runbook (start here)
└── scripts/
    └── push-walklog.ps1     Clone/copy/commit/push/tag helper for Windows
```

## Quickstart

Follow **`docs/POWERSHELL-SETUP.md`** — it covers every command:

1. **Part 1:** Node.js → `npm install` → `wrangler login` → generate API token →
   `wrangler secret put WALKLOG_TOKEN` → `wrangler deploy` → smoke-test script
2. **Part 2:** App Store Connect API key + Team ID + bundle ID + app record →
   create the GitHub repo → add 4 secrets → `git tag v1.0.0` → TestFlight

## API reference (Worker)

All routes except `/` and `/walks/:id/map` need
`Authorization: Bearer <WALKLOG_TOKEN>`.

| Method | Route | Purpose |
|---|---|---|
| POST | `/walks` | Create a walk → `{id, started_at}` |
| POST | `/walks/:id/points` | Upload batch `{points:[{ts,lat,lon,alt?,course?,speed?,accuracy?}]}` |
| POST | `/walks/:id/finish` | Close the walk → `{summary}` |
| GET | `/walks/:id` | Walk + summary + all points |
| GET | `/walks?limit=N` | Recent walks with summaries |
| GET | `/walks/:id/map` | Shareable Leaflet map page (public link) |
| GET | `/debug/count` | `{walks, points}` sanity check |

## Honest limitations

- iOS — not the app — decides GPS fix cadence, especially with the screen
  locked. The app records every good fix and uploads in batches about every
  10 seconds; spacing on the map may be slightly uneven.
- Background tracking needs **Always** location permission + Precise Location.
  iOS always shows the location arrow while tracking; no app can hide it.
- Battery use is roughly like running Maps navigation for the walk's duration.

## Versioning

- `ios/project.yml`: `MARKETING_VERSION` (user-visible) and
  `CURRENT_PROJECT_VERSION` (must increase for every TestFlight upload).
- Tag `v*` (e.g. `git tag v1.0.1; git push origin v1.0.1`) to build + upload.
