// The TMDB proxy. The app asks this function instead of api.themoviedb.org, so
// the TMDB token stays on the server and every player shares one cache.
//
//   GET /functions/v1/tmdb/<tmdb path>?<query>     e.g. /tmdb/movie/603/credits
//
// Only the paths the app uses are forwarded. A fresh cached copy is served
// without touching TMDB; on a miss the response is fetched, cached for its
// route's lifetime and returned. If TMDB fails and an expired copy exists, the
// expired copy is served — an old cast beats a frozen turn.
//
// Secrets (`supabase secrets set`): TMDB_TOKEN (the v4 read token) and
// APP_KEY (the app's publishable key, checked against the `apikey` header).

import { createClient } from "npm:@supabase/supabase-js@2";

const TMDB = "https://api.themoviedb.org/3";
const DAY = 24 * 60 * 60;

/** The paths the app uses, and how long each response is kept. */
const ROUTES: { pattern: RegExp; ttl: number }[] = [
  { pattern: /^search\/(person|movie)$/, ttl: 1 * DAY },
  { pattern: /^discover\/movie$/, ttl: 7 * DAY },
  { pattern: /^movie\/\d+\/credits$/, ttl: 30 * DAY },
  // Filmographies grow as films are announced.
  { pattern: /^person\/\d+\/movie_credits$/, ttl: 7 * DAY },
];

const MAX_QUERY_LENGTH = 300;

const token = Deno.env.get("TMDB_TOKEN") ?? "";
const appKey = Deno.env.get("APP_KEY") ?? "";
const db = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  if (req.method !== "GET") return text(405, "GET only");
  // A light gate, not security: the key ships in the app. It keeps the
  // endpoint from being an open TMDB mirror for anyone who finds the URL.
  if (!appKey || req.headers.get("apikey") !== appKey) return text(401, "Unknown app");
  if (!token) return text(500, "TMDB_TOKEN is not set");

  const url = new URL(req.url);
  // The platform passes the path with the function's name in front.
  const path = url.pathname.replace(/^\/(functions\/v1\/)?tmdb\/?/, "");
  const route = ROUTES.find((r) => r.pattern.test(path));
  if (!route) return text(404, "Not a proxied path");

  const params = [...url.searchParams].filter(([name]) => name !== "api_key");
  params.sort(([a], [b]) => a.localeCompare(b));
  const query = new URLSearchParams(params).toString();
  if (query.length > MAX_QUERY_LENGTH) return text(414, "Query too long");
  const key = query ? `${path}?${query}` : path;

  // A cache fault is logged and treated as a miss: the player still gets TMDB.
  const { data: cached, error: readError } = await db
    .from("tmdb_cache")
    .select("body, expires_at")
    .eq("key", key)
    .maybeSingle();
  if (readError) console.error("cache read failed", key, readError.message);
  if (cached && new Date(cached.expires_at) > new Date()) {
    return json(cached.body, route.ttl, "hit");
  }

  let upstream: Response;
  try {
    upstream = await fetch(`${TMDB}/${key}`, {
      headers: { Authorization: `Bearer ${token}`, accept: "application/json" },
    });
  } catch {
    return cached ? json(cached.body, 0, "stale") : text(502, "TMDB unreachable");
  }
  if (!upstream.ok) {
    if (cached) return json(cached.body, 0, "stale");
    return text(upstream.status, `TMDB answered ${upstream.status}`);
  }

  const body = await upstream.text();
  const write = db.from("tmdb_cache").upsert({
    key,
    body,
    fetched_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + route.ttl * 1000).toISOString(),
  }).then(({ error }) => {
    if (error) console.error("cache write failed", key, error.message);
  });
  // Answer now; finish the cache write after the response has gone.
  // @ts-ignore: EdgeRuntime is a Supabase global.
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(write);
  else await write;
  return json(body, route.ttl, "miss");
});

function json(body: string, maxAge: number, cache: "hit" | "miss" | "stale"): Response {
  return new Response(body, {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": `public, max-age=${maxAge}`,
      "X-Cache": cache,
    },
  });
}

function text(status: number, message: string): Response {
  return new Response(message, { status, headers: { "Content-Type": "text/plain" } });
}
