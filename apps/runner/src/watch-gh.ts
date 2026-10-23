// GitHub platform status for `fw watch` (task gh-status): one read of the public githubstatus summary per pass.
// Collection only: the Actions flag, the incident naming and the alert are fwcore's (Fw.Obs.GhStatus, obs.health).

export const GH_STATUS_URL = "https://www.githubstatus.com/api/v2/summary.json";
export const GH_TIMEOUT_MS = 10_000;
/** The components kept; the other components of the summary are not read. */
const KEPT = ["Actions", "Pages", "Webhooks"] as const;

export interface GhIncident {
  name: string; status: string; impact: string;
  /** ms since the epoch */
  createdAt: number; updatedAt: number;
  /** the first 200 characters of the newest update, tags removed */
  body: string;
  /** the incident touches the Actions component */
  actions: boolean;
}
/** Component states are the Statuspage names (operational, degraded_performance, partial_outage, major_outage,
 *  under_maintenance) or "unknown" (the fetch failed or the summary could not be read). `prevDegraded`: the previous
 *  pass left Actions flagged (Fw.Obs.GhStatus.ghOpenB keeps that on unknown). */
export interface GhSnap {
  actions: string; pages: string; webhooks: string; prevDegraded: boolean; incidents: GhIncident[];
}
export const GH_UNKNOWN: Omit<GhSnap, "prevDegraded"> = { actions: "unknown", pages: "unknown", webhooks: "unknown", incidents: [] };

const STATES = new Set(["operational", "degraded_performance", "partial_outage", "major_outage", "under_maintenance"]);
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const ms = (v: unknown): number => { const t = typeof v === "string" ? Date.parse(v) : NaN; return Number.isFinite(t) ? t : 0; };

/** Plain text of an update body: tags become spaces, runs of spaces collapse, first 200 characters (code points). */
export function bodyText(html: string): string {
  return [...html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim()].slice(0, 200).join("");
}

/** The kept part of a summary.json body. A missing component or an unknown state name reads as "unknown";
 *  open incidents are those of the summary (it lists only unresolved ones) that touch a kept component. */
export function parseGhSummary(json: unknown): Omit<GhSnap, "prevDegraded"> {
  if (!isObj(json) || !Array.isArray(json.components)) return { ...GH_UNKNOWN };
  const comps: unknown[] = json.components;
  const state = (name: string): string => {
    const c = comps.find((x): x is Record<string, unknown> => isObj(x) && x.name === name);
    return c && typeof c.status === "string" && STATES.has(c.status) ? c.status : "unknown";
  };
  const incidents: GhIncident[] = [];
  for (const i of Array.isArray(json.incidents) ? json.incidents : []) {
    if (!isObj(i) || typeof i.name !== "string") continue;
    if (typeof i.resolved_at === "string" || i.status === "resolved" || i.status === "postmortem") continue;
    const ups = (Array.isArray(i.incident_updates) ? i.incident_updates : []).filter(isObj);
    const newest = ups.reduce<Record<string, unknown> | null>((a, u) => (a === null || ms(u.created_at) > ms(a.created_at) ? u : a), null);
    const names = new Set<string>();
    for (const c of Array.isArray(i.components) ? i.components : []) if (isObj(c) && typeof c.name === "string") names.add(c.name);
    for (const u of ups) for (const c of Array.isArray(u.affected_components) ? u.affected_components : []) {
      if (isObj(c) && typeof c.name === "string") names.add(c.name);
    }
    if (!KEPT.some((k) => names.has(k))) continue;
    incidents.push({
      name: i.name, status: typeof i.status === "string" ? i.status : "", impact: typeof i.impact === "string" ? i.impact : "",
      createdAt: ms(i.created_at), updatedAt: Math.max(ms(i.updated_at), newest ? ms(newest.created_at) : 0),
      body: newest && typeof newest.body === "string" ? bodyText(newest.body) : "", actions: names.has("Actions"),
    });
  }
  return { actions: state("Actions"), pages: state("Pages"), webhooks: state("Webhooks"), incidents };
}

export type GhFetch = (url: string, timeoutMs: number) => Promise<unknown>;
const fetchJson: GhFetch = async (url, timeoutMs) => {
  const r = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
};

/** One read per call, no auth, no retry; any failure reads as unknown (never throws). */
export async function collectGh(prevDegraded: boolean, get: GhFetch = fetchJson): Promise<GhSnap> {
  try {
    return { ...parseGhSummary(await get(GH_STATUS_URL, GH_TIMEOUT_MS)), prevDegraded };
  } catch { return { ...GH_UNKNOWN, prevDegraded }; }
}

/** Whether the logged output of the previous pass carried the `sys.ghDegraded` alert. */
export function ghFlagged(out: { system?: { alerts?: string[] } } | null | undefined): boolean {
  return out?.system?.alerts?.includes("sys.ghDegraded") === true;
}

/** Whether the logged output of the previous pass carried the `sys.contended` alert (the hysteresis bit of Lean
 *  `Fw.Obs.Health.contendedNow`: open since the last check, it stays open down to `calmLoad`). */
export function contendedFlagged(out: { system?: { alerts?: string[] } } | null | undefined): boolean {
  return out?.system?.alerts?.includes("sys.contended") === true;
}
