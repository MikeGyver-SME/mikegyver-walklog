// WalkLog API — Cloudflare Worker backed by a SQLite Durable Object.
//
// Routes (all JSON except /map, which returns HTML):
//   POST /walks                 {device?, note?}            -> {ok, id, started_at}
//   POST /walks/:id/points      {points:[{ts,lat,lon,...}]}  -> {ok, stored}
//   POST /walks/:id/finish      {}                           -> {ok, summary}
//   GET  /walks/:id             -> {ok, walk, summary, points}
//   GET  /walks?limit=N         -> {ok, walks:[...]}  (newest first, with summaries)
//   GET  /walks/:id/map         -> shareable Leaflet HTML page (no auth; id is unguessable)
//   GET  /debug/count           -> {ok, walks, points}  (auth required)
//   GET  /                      -> status text
//
// Auth: every route except "/" and "/walks/:id/map" requires
//   Authorization: Bearer <WALKLOG_TOKEN>

const EARTH_R_M = 6371000;

function toRad(d) { return (d * Math.PI) / 180; }

function haversineMeters(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_R_M * Math.asin(Math.sqrt(s));
}

function authorized(request, env) {
  const h = request.headers.get("Authorization") || "";
  const m = /^Bearer\s+(.+)$/.exec(h);
  return !!m && m[1] === env.WALKLOG_TOKEN;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    },
  });
}

function err(message, status = 400) {
  return json({ ok: false, error: message }, status);
}

export class WalkLogDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.state.blockConcurrencyWhile(async () => {
      const sql = this.state.storage.sql;
      sql.exec(`CREATE TABLE IF NOT EXISTS walks (
        id TEXT PRIMARY KEY,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        device TEXT,
        note TEXT
      )`);
      // WITHOUT ROWID: (walk_id, ts) is the natural key and dedupes re-uploads.
      sql.exec(`CREATE TABLE IF NOT EXISTS points (
        walk_id TEXT NOT NULL,
        ts INTEGER NOT NULL,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        alt REAL,
        course REAL,
        speed REAL,
        accuracy REAL,
        PRIMARY KEY (walk_id, ts)
      ) WITHOUT ROWID`);
      sql.exec(`CREATE INDEX IF NOT EXISTS idx_points_walk_ts ON points (walk_id, ts)`);
    });
  }

  createWalk(device, note) {
    const id = crypto.randomUUID().replace(/-/g, "");
    const startedAt = Date.now();
    this.state.storage.sql.exec(
      `INSERT INTO walks (id, started_at, device, note) VALUES (?, ?, ?, ?)`,
      id, startedAt, device || null, note || null
    );
    return { id, started_at: startedAt };
  }

  addPoints(id, points) {
    const sql = this.state.storage.sql;
    const walk = firstRow(sql.exec(`SELECT id FROM walks WHERE id = ?`, id));
    if (!walk) return null;
    // Note: SqlStorage has no .prepare() (that's the D1 API) — one exec per row.
    let stored = 0;
    for (const p of points) {
      if (typeof p.lat !== "number" || typeof p.lon !== "number") continue;
      const ts = Math.floor(Number(p.ts) || Date.now());
      const r = sql.exec(
        `INSERT OR IGNORE INTO points
         (walk_id, ts, lat, lon, alt, course, speed, accuracy)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        id, ts, p.lat, p.lon,
        numOrNull(p.alt), numOrNull(p.course), numOrNull(p.speed), numOrNull(p.accuracy)
      );
      stored += r.rowsWritten;
    }
    return stored;
  }

  finishWalk(id) {
    const sql = this.state.storage.sql;
    const walk = firstRow(sql.exec(`SELECT * FROM walks WHERE id = ?`, id));
    if (!walk) return null;
    const endedAt = Date.now();
    sql.exec(`UPDATE walks SET ended_at = ? WHERE id = ?`, endedAt, id);
    return this.summarize(id);
  }

  getPoints(id) {
    return this.state.storage.sql
      .exec(`SELECT ts, lat, lon, alt, course, speed, accuracy
             FROM points WHERE walk_id = ? ORDER BY ts ASC`, id)
      .toArray();
  }

  summarize(id) {
    const sql = this.state.storage.sql;
    const walk = firstRow(sql.exec(`SELECT * FROM walks WHERE id = ?`, id));
    if (!walk) return null;
    const pts = this.getPoints(id);
    let distanceM = 0;
    for (let i = 1; i < pts.length; i++) {
      distanceM += haversineMeters(
        { lat: pts[i - 1].lat, lon: pts[i - 1].lon },
        { lat: pts[i].lat, lon: pts[i].lon }
      );
    }
    const startTs = pts.length ? pts[0].ts : walk.started_at;
    const endTs = pts.length ? pts[pts.length - 1].ts : (walk.ended_at || walk.started_at);
    const durationS = Math.max(0, (endTs - startTs) / 1000);
    const distanceMi = distanceM / 1609.344;
    const avgMph = durationS > 0 ? distanceMi / (durationS / 3600) : 0;
    return {
      walk_id: id,
      point_count: pts.length,
      started_at: walk.started_at,
      ended_at: walk.ended_at,
      duration_s: Math.round(durationS),
      distance_m: Math.round(distanceM * 10) / 10,
      distance_mi: Math.round(distanceMi * 1000) / 1000,
      avg_mph: Math.round(avgMph * 100) / 100,
      start: pts.length ? { lat: pts[0].lat, lon: pts[0].lon } : null,
      end: pts.length ? { lat: pts[pts.length - 1].lat, lon: pts[pts.length - 1].lon } : null,
    };
  }

  listWalks(limit) {
    const rows = this.state.storage.sql
      .exec(`SELECT id, started_at, ended_at, device, note
             FROM walks ORDER BY started_at DESC LIMIT ?`, limit)
      .toArray();
    return rows.map((w) => ({ ...w, summary: this.summarize(w.id) }));
  }

  counts() {
    const sql = this.state.storage.sql;
    const w = firstRow(sql.exec(`SELECT COUNT(*) AS n FROM walks`));
    const p = firstRow(sql.exec(`SELECT COUNT(*) AS n FROM points`));
    return { walks: w.n, points: p.n };
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "OPTIONS") return json({ ok: true });

    // Public share page: the walk id is a 128-bit random token.
    const mapMatch = /^\/walks\/([0-9a-f]{32})\/map$/.exec(path);
    if (mapMatch && request.method === "GET") {
      const summary = this.summarize(mapMatch[1]);
      if (!summary) return err("walk not found", 404);
      const pts = this.getPoints(mapMatch[1]);
      return mapPage(summary, pts);
    }

    if (!authorized(request, this.env)) {
      return err("unauthorized: bad or missing bearer token", 401);
    }

    if (path === "/debug/count" && request.method === "GET") {
      return json({ ok: true, ...this.counts() });
    }

    if (path === "/walks" && request.method === "POST") {
      const body = await safeJson(request);
      const { id, started_at } = this.createWalk(body.device, body.note);
      return json({ ok: true, id, started_at });
    }

    if (path === "/walks" && request.method === "GET") {
      const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get("limit") || "20", 10) || 20));
      return json({ ok: true, walks: this.listWalks(limit) });
    }

    const walkMatch = /^\/walks\/([0-9a-f]{32})$/.exec(path);
    if (walkMatch && request.method === "GET") {
      const summary = this.summarize(walkMatch[1]);
      if (!summary) return err("walk not found", 404);
      const walk = firstRow(this.state.storage.sql
        .exec(`SELECT id, started_at, ended_at, device, note FROM walks WHERE id = ?`, walkMatch[1]));
      return json({ ok: true, walk, summary, points: this.getPoints(walkMatch[1]) });
    }

    const ptsMatch = /^\/walks\/([0-9a-f]{32})\/points$/.exec(path);
    if (ptsMatch && request.method === "POST") {
      const body = await safeJson(request);
      if (!Array.isArray(body.points)) return err("body.points must be an array");
      if (body.points.length > 2000) return err("too many points in one batch (max 2000)");
      const stored = this.addPoints(ptsMatch[1], body.points);
      if (stored === null) return err("walk not found", 404);
      return json({ ok: true, stored });
    }

    const finMatch = /^\/walks\/([0-9a-f]{32})\/finish$/.exec(path);
    if (finMatch && request.method === "POST") {
      const summary = this.finishWalk(finMatch[1]);
      if (!summary) return err("walk not found", 404);
      return json({ ok: true, summary });
    }

    return err("not found", 404);
  }
}

function firstRow(cursor) {
  const rows = cursor.toArray();
  return rows.length ? rows[0] : undefined;
}

function numOrNull(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

async function safeJson(request) {
  try { return await request.json(); }
  catch { return {}; }
}

// ---- Shareable map page -------------------------------------------------

function mapPage(summary, pts) {
  // Points are numbers written by our own API; JSON.stringify is safe to inline.
  const coords = JSON.stringify(pts.map((p) => [p.lat, p.lon]));
  const mins = Math.floor(summary.duration_s / 60);
  const secs = String(summary.duration_s % 60).padStart(2, "0");
  const title = `WalkLog — ${summary.distance_mi} mi in ${mins}:${secs} (${summary.avg_mph} mph avg)`;
  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>html,body{margin:0;height:100%;font-family:-apple-system,Helvetica,Arial,sans-serif}
#map{height:100%} .banner{position:absolute;top:10px;left:50%;transform:translateX(-50%);z-index:1000;
background:rgba(10,31,68,.92);color:#fff;padding:10px 16px;border-radius:12px;font-size:14px;text-align:center;
box-shadow:0 2px 8px rgba(0,0,0,.3)} .banner b{color:#e8b62a}</style></head>
<body><div id="map"></div>
<div class="banner"><b>WalkLog</b> &nbsp;${summary.distance_mi} mi &nbsp;•&nbsp; ${mins}:${secs} &nbsp;•&nbsp; ${summary.avg_mph} mph avg &nbsp;•&nbsp; ${summary.point_count} points</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const coords = ${coords};
const map = L.map('map');
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap'}).addTo(map);
if (coords.length) {
  const line = L.polyline(coords, {color:'#0a1f44', weight:5}).addTo(map);
  L.marker(coords[0], {title:'Start'}).addTo(map).bindPopup('Start');
  L.marker(coords[coords.length-1], {title:'End'}).addTo(map).bindPopup('End');
  map.fitBounds(line.getBounds().pad(0.2));
} else { map.setView([29.76,-95.36], 11); }
</script></body></html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/") {
      return new Response("WalkLog API — POST /walks to begin. See README.\n", {
        headers: { "Content-Type": "text/plain" },
      });
    }
    const id = env.WALKLOG.idFromName("walklog-main");
    const stub = env.WALKLOG.get(id);
    return stub.fetch(request);
  },
};
