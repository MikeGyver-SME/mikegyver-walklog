# WalkLog v1.0.0 — PowerShell Setup Runbook

Two parts, in order. Part 1 puts your Cloudflare Worker + SQLite database online
and proves it works. Part 2 builds the iPhone app in GitHub Actions and delivers
it to your phone through TestFlight.

**What you're building**

```
iPhone (WalkLog, SwiftUI)                      Cloudflare
┌─────────────────────────────┐                ┌──────────────────────────────┐
│ Start Walk → GPS + bearing  │  HTTPS + token │ Worker (src/index.js)        │
│ captures every fix; uploads │ ─────────────► │  ├─ POST /walks             │
│ in batches ~every 10 s      │                │  ├─ POST /walks/:id/points   │
│ Stop → inline MapKit route, │                │  ├─ POST /walks/:id/finish   │
│ total time, distance, mph   │                │  └─ GET  /walks/:id/map     │
│ + shareable web map link    │                │       (SQLite Durable Object)│
└─────────────────────────────┘                └──────────────────────────────┘
```

**Before you start:** the `walklog-v1.0.0.zip` from Wiggs, extracted somewhere
handy (these steps assume `~\Downloads\walklog-v1.0.0\walklog`). A Cloudflare
account (free plan is fine) and your paid Apple Developer membership.

---

## Part 1 — Cloudflare Worker, API token, and SQLite Durable Object

### 1.1 Install Node.js LTS

```powershell
winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
```

Close PowerShell and open a **new** one, then verify:

```powershell
node -v
npm -v
```

You should see version numbers (e.g. `v22.x.x` / `10.x.x`). If `winget` isn't
available, install Node LTS from https://nodejs.org and reopen PowerShell.

### 1.2 Install the Worker dependencies

```powershell
cd "$env:USERPROFILE\Downloads\walklog-v1.0.0\walklog\worker"
npm install
```

This pulls in `wrangler` locally (nothing is installed globally).

### 1.3 Log in to Cloudflare

```powershell
npx wrangler login
```

A browser window opens — approve the Cloudflare login. Back in PowerShell you
should see `Successfully logged in`.

### 1.4 Create the API token (do this before deploying)

The iPhone app authenticates with a bearer token you invent. Generate a strong
one, copy it to your clipboard, and **save it in your password manager** —
you'll paste it into the app later, and `wrangler` never shows it again.

```powershell
$Token = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 40 | ForEach-Object { [char]$_ })
$Token | Set-Clipboard
Write-Host "Token copied to clipboard — save it in your password manager NOW." -ForegroundColor Yellow
$Token
```

Store it in the Worker as an encrypted secret:

```powershell
npx wrangler secret put WALKLOG_TOKEN
```

When prompted, paste the token (right-click in the PowerShell window) and press
Enter. You should see `✨ Success! Uploaded secret WALKLOG_TOKEN`.

> Keep that PowerShell variable `$Token` alive for the smoke test below. If you
> close the window, grab the token from your password manager instead.

### 1.5 Deploy

```powershell
npx wrangler deploy
```

Wrangler prints something like:

```
✨ Success! Deployed walklog-api to https://walklog-api.<your-subdomain>.workers.dev
```

**Copy that URL** — it's your Worker URL. The SQLite Durable Object (`WalkLogDO`)
is created automatically on first request; there is nothing else to provision.

### 1.6 Smoke-test the whole API

Replace the first line with your real Worker URL, then run the block:

```powershell
$Worker  = "https://walklog-api.<your-subdomain>.workers.dev"
$Headers = @{ Authorization = "Bearer $Token" }

# 1. Create a walk
$walk = Invoke-RestMethod -Method Post -Uri "$Worker/walks" `
    -Headers $Headers -ContentType "application/json" `
    -Body '{"device":"powershell-smoke-test"}'
"Walk id: $($walk.id)"

# 2. Upload one GPS point (Tomball-ish coordinates)
$point = @{
    ts       = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    lat      = 30.0978
    lon      = -95.6253
    course   = 45
    speed    = 1.4
    accuracy = 8
}
$body = @{ points = @($point) } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post -Uri "$Worker/walks/$($walk.id)/points" `
    -Headers $Headers -ContentType "application/json" -Body $body

# 3. Finish the walk and see the summary
$done = Invoke-RestMethod -Method Post -Uri "$Worker/walks/$($walk.id)/finish" -Headers $Headers
$done.summary | Format-List

# 4. Confirm the Durable Object actually stored everything
Invoke-RestMethod -Uri "$Worker/debug/count" -Headers $Headers

# 5. Open the shareable map page in your browser
Start-Process "$Worker/walks/$($walk.id)/map"
```

Expected: `stored: 1`, a summary object, `walks: 1, points: 1`, and a map page
with one marker. **Part 1 is done** — your backend is live. Write down:

- Worker URL: `https://walklog-api.<your-subdomain>.workers.dev`
- API token: (in your password manager)

---

## Part 2 — GitHub repo, secrets, and TestFlight build

### 2.1 One-time Apple setup (about 5 minutes on the web)

1. **App Store Connect API key** — this is how GitHub Actions signs and uploads
   without your password:
   - Go to https://appstoreconnect.apple.com → **Users and Access** →
     **Integrations** → **App Store Connect API** → **Team Keys** → **+**
   - Name it `WalkLog CI`, Access: **Admin** (App Manager also works for uploads)
   - Click **Generate**, then note the **Key ID** (e.g. `A1B2C3D4E5`) and the
     **Issuer ID** (a UUID at the top of the page)
   - **Download the `.p8` file now** — Apple shows it exactly once. Save it to
     `~\Downloads\AuthKey_<KeyID>.p8`
2. **Team ID** — https://developer.apple.com/account → **Membership** → copy the
   **Team ID** (10 characters, e.g. `AB12CD34EF`)
3. **Register the bundle ID** (so the app record can reference it):
   - https://developer.apple.com/account → **Certificates, Identifiers & Profiles**
     → **Identifiers** → **+** → **App IDs** → **App**
   - Description: `WalkLog`, Bundle ID: **Explicit** → `studio.mikegyver.walklog`
   - No special capabilities needed (background location is an Info.plist mode,
     not a capability) → **Register**
4. **Create the app record**:
   - App Store Connect → **My Apps** → **+** → **New App** → platform **iOS**,
     Name `WalkLog`, Bundle ID `studio.mikegyver.walklog`, SKU `walklog-001`

### 2.2 Create the GitHub repo and push the code

On https://github.com/new (or under your `MikeGyver-SME` org): repository name
**`mikegyver-walklog`**, visibility **Private**, do **not** add a README
(the zip already has one).

Then in PowerShell:

```powershell
cd "$env:USERPROFILE\Downloads\walklog-v1.0.0\walklog"
git init -b main
git add -A
git commit -m "WalkLog v1.0.0"
git remote add origin https://github.com/MikeGyver-SME/mikegyver-walklog.git
git branch -M main
git push -u origin main
```

> Shortcut: `scripts\push-walklog.ps1` in this folder does the clone/copy/commit/
> push/tag cycle for you on later versions — see the script's header comments.

### 2.3 Add the four secrets to the repo

Either: repo page → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret** (four times), or in PowerShell with the GitHub CLI:

```powershell
$Repo = "MikeGyver-SME/mikegyver-walklog"

gh secret set ASC_KEY_ID    --body "A1B2C3D4E5"   --repo $Repo
gh secret set ASC_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" --repo $Repo
gh secret set TEAM_ID       --body "AB12CD34EF"   --repo $Repo

$P8 = Get-Content -Raw "$env:USERPROFILE\Downloads\AuthKey_A1B2C3D4E5.p8"
gh secret set ASC_KEY_P8 --body $P8 --repo $Repo
```

(`gh secret set` handles the multi-line `.p8` content correctly. Don't have the
`gh` CLI? `winget install GitHub.cli`, then `gh auth login`.)

### 2.4 Trigger the build

The workflow runs on version tags. Push one:

```powershell
cd "$env:USERPROFILE\Downloads\walklog-v1.0.0\walklog"
git tag v1.0.0
git push origin v1.0.0
```

Watch it: repo → **Actions** → **Build and upload WalkLog to TestFlight**.
It takes roughly 10–15 minutes: XcodeGen → archive with App Store signing →
export IPA → `fastlane pilot upload`. A copy of the IPA is also kept as a
workflow artifact for 14 days.

### 2.5 Install on your iPhone via TestFlight

1. App Store Connect → **My Apps** → **WalkLog** → **TestFlight** → the new
   build appears under **iOS Builds** (processing takes a few minutes)
2. **Internal Testing** → create a group (or use the default) → **+** → add
   yourself as a tester
3. On your iPhone: install **TestFlight** from the App Store, open the invite
   email (or redeem the public link), install **WalkLog**

### 2.6 First launch

1. Open WalkLog → tap the **gear** → paste your **Worker URL** and **API token**
   → **Test connection** (you should see "Connected — the Worker answered")
2. Back → **Start Walk**
   - iOS asks for location: tap **Allow While Using App**, then choose
     **Change to Always Allow** when it prompts (background tracking needs it)
   - Leave **Precise Location ON**
3. Walk. Lock the screen if you like — tracking continues (you'll see the
   location arrow; Apple doesn't let any app hide it)
4. **Stop** → within a second or two you get the inline map, total time,
   distance, and average mph, plus a **Share walk map** link

### 2.7 Shipping v1.0.1 and beyond

1. Bump versions in `ios/project.yml`: `MARKETING_VERSION` (what users see)
   and `CURRENT_PROJECT_VERSION` (must increase every TestFlight upload)
2. Commit, push, tag the new version:
   ```powershell
   git add -A; git commit -m "WalkLog v1.0.1"
   git push
   git tag v1.0.1; git push origin v1.0.1
   ```
3. TestFlight testers get the update automatically

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Test connection` → 401 | Token mismatch. Re-run `npx wrangler secret put WALKLOG_TOKEN` in `worker\` and re-paste the same token into the app |
| `Could not reach the Worker` on Start | Worker URL typo, or `http://` instead of `https://`. Re-run the Part 1 smoke test |
| No location prompt / tracking stops when locked | iPhone **Settings → WalkLog → Location → Always**; **Precise Location ON** |
| Workflow fails at Archive: signing/provisioning | API key needs **Admin** (or App Manager) access; check all four secrets are set |
| Export fails on `teamID` | `TEAM_ID` secret is wrong — copy it from developer.apple.com → Account → Membership |
| `pilot upload`: app not found | Do step 2.1(4): the App Store Connect app record must exist before the first upload |
| `fastlane` install takes minutes | Normal — it's a big gem; let it finish |
| Map page shows no route | The walk had < 2 accepted points (e.g. started indoors). iOS needs a real GPS fix |

**Notes worth knowing:** iOS decides how often GPS fixes arrive — the app records
every good fix and uploads in batches about every 10 seconds, so you may see
slightly uneven spacing on the map. That's the OS, not a bug. Battery impact is
roughly like running Apple Maps navigation for the length of the walk.
