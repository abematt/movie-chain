// Stores a finished run in `results`. The app posts one per game over (and
// resends any it couldn't deliver), so this must be safe to receive twice.
//
//   POST /functions/v1/results     body: see `Run` below
//   Authorization: Bearer <the player's access token>
//
// The run belongs to the user in the token (an anonymous user until 0.9.0),
// never to an id in the body: a forged run needs a real session per player,
// and anonymous sign-ins are rate limited per IP.
//
// Checks the run's shape — not its truth: links aren't re-checked against TMDB,
// and points can't be (speed is measured on the phone). A daily's start must
// match the published one when the day is published.
//
//   201 stored · 200 a daily already stored for this player · 401 no app key or
//   no valid session · 422 not a valid run
//
// Secrets: APP_KEY (the app's publishable key, checked against `apikey`).

import { createClient } from "npm:@supabase/supabase-js@2";

/** The local date of daily #1 (`DailyStart.firstDay` in the app). */
const FIRST_DAY = Date.UTC(2026, 9, 26);
const DAY_MS = 24 * 60 * 60 * 1000;
/** `Scoring` in the app: 10 base, up to 30 for speed and 30 for obscurity. */
const MIN_POINTS_PER_LINK = 10;
const MAX_POINTS_PER_LINK = 70;
const MAX_LINKS = 1000;
const MAX_BODY = 64 * 1024;

type Kind = "actor" | "movie";
type Node = { kind: Kind; id: number; seconds?: number };
type Run = {
  mode: "endless" | "daily_start";
  number: number | null;
  chain: Node[];
  links: number;
  points: number;
  ended_by_quit: boolean;
  app_version: string;
};

const appKey = Deno.env.get("APP_KEY") ?? "";
const db = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return text(405, "POST only");
  if (!appKey || req.headers.get("apikey") !== appKey) return text(401, "Unknown app");
  const player = await caller(req);
  if (!player) return text(401, "Not signed in");

  const raw = await req.text();
  if (raw.length > MAX_BODY) return text(413, "Too large");
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return text(422, "Not JSON");
  }
  const checked = check(body);
  if (typeof checked === "string") return text(422, checked);
  const run = checked;

  if (run.mode === "daily_start") {
    const start = await publishedStart(run.number!);
    if (start && (start.kind !== run.chain[0].kind || start.id !== run.chain[0].id)) {
      return text(422, "Not the day's start");
    }
  }

  const { error } = await db.from("results").insert({ player_id: player, ...run });
  if (error?.code === "23505") return text(200, "Already stored");
  if (error) {
    console.error("insert failed", error.message);
    return text(500, "Not stored");
  }
  return text(201, "Stored");
});

/** The run, normalised, or why it isn't one. */
function check(body: unknown): Run | string {
  if (!isObject(body)) return "Not an object";
  // Older apps also send a `device_id`; it's ignored.
  const { mode, number, chain, links, points, ended_by_quit, app_version } = body;

  if (mode !== "endless" && mode !== "daily_start") return "Bad mode";
  if (mode === "endless" && number !== null && number !== undefined) return "Number on an endless run";
  if (mode === "daily_start") {
    // Day n starts on the player's local date; the earliest time zone is UTC+14.
    const latest = Math.floor((Date.now() + 14 * 60 * 60 * 1000 - FIRST_DAY) / DAY_MS) + 1;
    if (!isInt(number) || number < 1 || number > latest) return "Bad number";
  }
  if (typeof ended_by_quit !== "boolean") return "Bad ended_by_quit";
  if (typeof app_version !== "string" || app_version.length === 0 || app_version.length > 32) {
    return "Bad app_version";
  }

  if (!Array.isArray(chain) || chain.length < 1 || chain.length > MAX_LINKS + 1) return "Bad chain";
  const nodes: Node[] = [];
  const seen = new Set<string>();
  for (const [i, item] of chain.entries()) {
    if (!isObject(item)) return `Bad link ${i}`;
    const { kind, id, seconds } = item;
    if (kind !== "actor" && kind !== "movie") return `Bad kind at ${i}`;
    if (i > 0 && kind === nodes[i - 1].kind) return `Kinds don't alternate at ${i}`;
    if (!isInt(id) || id < 1 || id > 1e9) return `Bad id at ${i}`;
    if (seen.has(`${kind}${id}`)) return `Repeat at ${i}`;
    seen.add(`${kind}${id}`);
    const node: Node = { kind, id };
    if (i > 0) {
      if (typeof seconds !== "number" || !(seconds >= 0 && seconds <= 600)) return `Bad seconds at ${i}`;
      node.seconds = Math.round(seconds * 10) / 10;
    }
    nodes.push(node);
  }

  if (!isInt(links) || links !== nodes.length - 1) return "links doesn't match the chain";
  if (!isInt(points) || points < links * MIN_POINTS_PER_LINK || points > links * MAX_POINTS_PER_LINK) {
    return "Points out of range";
  }

  return {
    mode,
    number: mode === "daily_start" ? number as number : null,
    chain: nodes,
    links,
    points,
    ended_by_quit,
    app_version,
  };
}

/** The user id in the request's bearer token, when the token is a live session. */
async function caller(req: Request): Promise<string | null> {
  const token = req.headers.get("authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token) return null;
  const { data, error } = await db.auth.getUser(token);
  return error ? null : data.user?.id ?? null;
}

/** The day's start as published (highest revision), or null when it isn't. */
async function publishedStart(number: number): Promise<{ kind: string; id: number } | null> {
  const { data, error } = await db
    .from("puzzles")
    .select("data")
    .eq("mode", "daily_start")
    .eq("number", number)
    .order("revision", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) console.error("puzzle read failed", number, error.message);
  return data?.data ?? null;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isInt(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value);
}

function text(status: number, message: string): Response {
  return new Response(message, { status, headers: { "Content-Type": "text/plain" } });
}
