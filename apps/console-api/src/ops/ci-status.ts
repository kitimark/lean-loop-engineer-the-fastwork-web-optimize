// CircleCI platform status (task circleci-status): one read of the public Statuspage summary, no token.
// https://status.circleci.com/api/v2/summary.json (the page documents no rate limit and sends cache-control max-age=10;
// this poller reads it at most once per POLL_MS, and not before a 429's Retry-After).
//
// TS STAND-IN, marked for Lean replacement: `verdictOf`, `fresh` and `usable` copy Fw.Obs.CiStatus (lean/Fw/Obs/CiStatus.lean)
// and are checked against its golden packages/contracts/golden/obs/ci-status.jsonl by test/ci-status.test.ts. The fetch,
// the parse and the cache are glue and hold no decision. The Lean module is not an fwcore op yet (Fw/Wire is outside this task).

export const CIRCLECI_STATUS_URL = "https://status.circleci.com/api/v2/summary.json";
export const CIRCLECI_STATUS_PAGE = "https://status.circleci.com";
/** Lean Fw.Obs.CiStatus.pollMs / maxAgeMs (the test asserts both against the golden's constants line). */
export const POLL_MS = 120_000;
export const MAX_AGE_MS = 360_000;
export const FETCH_TIMEOUT_MS = 10_000;

export type Comp = "operational" | "degraded_performance" | "partial_outage" | "major_outage" | "under_maintenance" | "unknown";
export type Verdict = "healthy" | "degraded" | "unknown";

const COMPS = new Set<string>(["operational", "degraded_performance", "partial_outage", "major_outage", "under_maintenance"]);
/** The page's component names the verdict reads (Fw.Obs.CiStatus: armComps, macComps). */
export const NAMES = { docker: "Docker Jobs", machine: "Machine Jobs", pipelines: "Pipelines & Workflows", api: "CircleCI API", macos: "macOS Jobs" } as const;
export type Key = keyof typeof NAMES;
export type States = Record<Key, Comp>;
export const ALL_UNKNOWN: States = { docker: "unknown", machine: "unknown", pipelines: "unknown", api: "unknown", macos: "unknown" };

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const ms = (v: unknown): number => { const t = typeof v === "string" ? Date.parse(v) : NaN; return Number.isFinite(t) ? t : 0; };

export interface Incident { name: string; status: string; impact: string; createdAt: number; updatedAt: number; components: string[] }

/** The kept part of a summary.json body: five component states (a missing component or an unknown status reads as
 *  "unknown") and the unresolved incidents that touch one of them. */
export function parseSummary(json: unknown): { states: States; incidents: Incident[] } {
  if (!isObj(json) || !Array.isArray(json.components)) return { states: { ...ALL_UNKNOWN }, incidents: [] };
  const comps: unknown[] = json.components;
  const state = (name: string): Comp => {
    const c = comps.find((x): x is Record<string, unknown> => isObj(x) && x.name === name);
    return c && typeof c.status === "string" && COMPS.has(c.status) ? (c.status as Comp) : "unknown";
  };
  const states = Object.fromEntries((Object.keys(NAMES) as Key[]).map((k) => [k, state(NAMES[k])])) as States;
  const kept = new Set<string>(Object.values(NAMES));
  const incidents: Incident[] = [];
  for (const i of Array.isArray(json.incidents) ? json.incidents : []) {
    if (!isObj(i) || typeof i.name !== "string") continue;
    if (typeof i.resolved_at === "string" || i.status === "resolved" || i.status === "postmortem") continue;
    const names = (Array.isArray(i.components) ? i.components : []).flatMap((c) => (isObj(c) && typeof c.name === "string" ? [c.name] : []));
    const touched = names.filter((n) => kept.has(n));
    if (touched.length === 0) continue;
    incidents.push({
      name: i.name, status: typeof i.status === "string" ? i.status : "", impact: typeof i.impact === "string" ? i.impact : "",
      createdAt: ms(i.created_at), updatedAt: ms(i.updated_at), components: touched,
    });
  }
  return { states, incidents };
}

// ---- stand-in for Fw.Obs.CiStatus (golden-checked) ----
const bad = (c: Comp): boolean => c !== "operational" && c !== "unknown";
export function verdictOf(prev: Verdict, cs: Comp[]): Verdict {
  if (cs.some(bad)) return "degraded";
  if (cs.some((c) => c === "unknown")) return prev === "degraded" ? "degraded" : "unknown";
  return "healthy";
}
export const fresh = (readAt: number | null, now: number): boolean => readAt !== null && now - readAt <= MAX_AGE_MS;
export const usable = (v: Verdict, readAt: number | null, now: number): boolean => v === "healthy" && fresh(readAt, now);

export interface Reading extends States { prevArm: Verdict; prevMac: Verdict; readAt: number | null; now: number }
export interface Lane { verdict: Verdict; usable: boolean }
export function decide(r: Reading): { arm: Lane; macos: Lane; fresh: boolean } {
  const arm = verdictOf(r.prevArm, [r.docker, r.machine, r.pipelines, r.api]);
  const mac = verdictOf(r.prevMac, [r.macos, r.pipelines, r.api]);
  return { arm: { verdict: arm, usable: usable(arm, r.readAt, r.now) }, macos: { verdict: mac, usable: usable(mac, r.readAt, r.now) },
    fresh: fresh(r.readAt, r.now) };
}

/** What `GET /api/ci-status` returns and the land router reads: `arm.usable` is true only for a healthy, fresh reading. */
export interface CiStatusView {
  /** ms of the last successful read, or null before the first */
  readAt: number | null;
  now: number;
  fresh: boolean;
  states: States;
  arm: Lane;
  macos: Lane;
  incidents: Incident[];
  /** the last failed attempt's reason, or null */
  error: string | null;
  url: string;
}

export type StatusFetch = (url: string, timeoutMs: number) => Promise<{ status: number; retryAfterS: number | null; json: () => Promise<unknown> }>;
const realFetch: StatusFetch = async (url, timeoutMs) => {
  const r = await fetch(url, { signal: AbortSignal.timeout(timeoutMs), headers: { accept: "application/json" } });
  const ra = Number(r.headers.get("retry-after"));
  return { status: r.status, retryAfterS: Number.isFinite(ra) && ra > 0 ? ra : null, json: () => r.json() };
};

/** Poll-on-demand cache: a request reads the page only when the last attempt is POLL_MS old (and any Retry-After has
 *  passed); the first request waits for the read, later ones get the cache and start a refresh in the background. No
 *  timer, no background work while nobody asks. `now` and the fetch are injected so tests run without a clock or network. */
export class CiStatusPoller {
  private states: States = { ...ALL_UNKNOWN };
  private incidents: Incident[] = [];
  private readAt: number | null = null;
  private prevArm: Verdict = "unknown";
  private prevMac: Verdict = "unknown";
  private attemptAt: number | null = null;
  private notBefore = 0;
  private error: string | null = null;
  private inflight: Promise<void> | null = null;
  private readonly get: StatusFetch;
  private readonly clock: () => number;
  constructor(get: StatusFetch = realFetch, clock: () => number = Date.now) { this.get = get; this.clock = clock; }

  private due(now: number): boolean {
    return now >= this.notBefore && (this.attemptAt === null || now - this.attemptAt >= POLL_MS);
  }

  private async read(): Promise<void> {
    const t = this.clock();
    this.attemptAt = t;
    try {
      const r = await this.get(CIRCLECI_STATUS_URL, FETCH_TIMEOUT_MS);
      if (r.status === 429 || r.status === 503) {
        this.notBefore = t + Math.max(POLL_MS, (r.retryAfterS ?? 0) * 1000);
        throw new Error(`HTTP ${r.status}`);
      }
      if (r.status < 200 || r.status >= 300) throw new Error(`HTTP ${r.status}`);
      const p = parseSummary(await r.json());
      this.states = p.states;
      this.incidents = p.incidents;
      this.error = null;
      if (Object.values(p.states).some((s) => s !== "unknown")) this.readAt = t; // a body with no known component is not a reading
      else this.error = "summary has none of the components";
    } catch (e) {
      this.error = (e as Error).message;
      this.states = { ...ALL_UNKNOWN };
    }
    const d = decide({ ...this.states, prevArm: this.prevArm, prevMac: this.prevMac, readAt: this.readAt, now: this.clock() });
    this.prevArm = d.arm.verdict;
    this.prevMac = d.macos.verdict;
  }

  /** The current view; starts a read when one is due. */
  async view(): Promise<CiStatusView> {
    const now = this.clock();
    if (this.due(now) && !this.inflight) {
      this.inflight = this.read().finally(() => { this.inflight = null; });
    }
    if (this.inflight && this.readAt === null) await this.inflight; // until the first reading, callers wait for it
    const n = this.clock();
    const d = decide({ ...this.states, prevArm: this.prevArm, prevMac: this.prevMac, readAt: this.readAt, now: n });
    return { readAt: this.readAt, now: n, fresh: d.fresh, states: this.states, arm: d.arm, macos: d.macos,
      incidents: this.incidents, error: this.error, url: CIRCLECI_STATUS_PAGE };
  }
}
