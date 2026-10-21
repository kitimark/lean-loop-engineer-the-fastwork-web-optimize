// The facts of the land overflow and the real CircleCI dependencies (task land-lane-circleci). The rule is Lean `Fw.Ci.Overflow`
// (fwcore ops `ci.overflow`, `ci.overflowCombine`; golden packages/contracts/golden/ci/overflow.jsonl): GitHub Actions first, CircleCI
// for the legs GitHub has no free job slot for. This file reads facts (gh, the status pages, the CircleCI API through
// scripts/circleci.mjs, a ledger file) and hands them to fwcore; it decides nothing, except that it asks for the CircleCI facts only
// when fwcore's first answer names legs to move (the CircleCI facts do not change which legs those are: Lean `overflow_only_when_full`).
//
// Freshness of what is read (the limits the decision lives with):
//  - the GitHub slot count is one `gh run list --limit 100` call, cached on disk for SLOT_TTL_S (120 s, the gh poll floor), so it is up to
//    that old, and it sees only the newest 100 runs (an older run still going is not counted: an under-count);
//  - the CircleCI status is the console's `/api/ci-status` (at most 120 s old by its own poll, and stale after 6 min: Lean `usable`);
//  - credits and storage are read from the ledger of pipelines this Mac fetched.
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { collectGh } from "./watch-gh.ts";
import type { CircleDeps, CircleFetch, CircleLane, OverflowPlan, Pusher } from "./land-remote.ts";
import type { FwCall, Gh } from "./run.ts";

/** How long one `gh run list` answer serves later decisions. */
export const SLOT_TTL_S = 120;
/** The `status` values of a run that holds or waits for a runner (the rest is `completed`). */
export const ACTIVE_STATUS = new Set(["queued", "in_progress", "waiting", "pending", "requested"]);
export const SLOT_FIELDS = "status,workflowName,databaseId";

export type Slots = { /** names of the active workflow runs, null: not readable */ active: string[] | null; /** seconds since the list was read */ ageS: number };

/** One `gh run list` for the whole repo (the newest 100 runs), served from `cacheFile` while it is younger than SLOT_TTL_S. No retry: a
 *  refused call (403, budget) reads as unknown, and unknown means GitHub first. */
export async function readSlots(gh: Gh, nowMs: () => number, cacheFile?: string): Promise<Slots> {
  const t = nowMs();
  if (cacheFile && existsSync(cacheFile)) {
    try {
      const c = JSON.parse(readFileSync(cacheFile, "utf8")) as { at: number; active: string[] };
      if (Array.isArray(c.active) && t - c.at >= 0 && t - c.at < SLOT_TTL_S * 1000) return { active: c.active, ageS: Math.round((t - c.at) / 1000) };
    } catch { /* an unreadable cache is no cache */ }
  }
  try {
    const rows = JSON.parse(await gh(["run", "list", "--limit", "100", "--json", SLOT_FIELDS], { deadline: Math.ceil(t / 1000) + 60 })) as { status: string; workflowName: string }[];
    const active = rows.filter((r) => ACTIVE_STATUS.has(r.status)).map((r) => r.workflowName);
    if (cacheFile) {
      mkdirSync(dirname(cacheFile), { recursive: true });
      writeFileSync(`${cacheFile}.tmp`, JSON.stringify({ at: t, active }));
      renameSync(`${cacheFile}.tmp`, cacheFile);
    }
    return { active, ageS: 0 };
  } catch { return { active: null, ageS: 0 }; }
}

export type OverflowDeps = {
  call: FwCall;
  /** the legs of the lane, in matrix order (lean/land-legs.txt) */
  legs: string[];
  now: () => number;
  slots: () => Promise<Slots>;
  /** githubstatus Actions component and the last flag */
  ghStatus: () => Promise<{ actions: string; prevDegraded: boolean }>;
  /** the console's CircleCI arm verdict and when it was read */
  ccStatus: () => Promise<{ arm: string; readAt: number | null }>;
  /** the checkout key list and the newest clone result (scripts/circleci.mjs `keyCheck`) */
  keys: () => Promise<{ keys: number | null; checkout: boolean | null }>;
  /** credits spent and storage used, from the ledger */
  budget: () => { spent: number; storage: number };
  /** test flag: GitHub counts as full (env FW_LAND_FORCE_FULL=1) */
  forceFull: boolean;
};
export type OverflowReply = { gh: string[]; cc: string[]; reason: string; ghFree: number; ghDegraded: boolean; ccReady: boolean };

/** fwcore `ci.overflow` over the facts of this moment. Never throws: any failure to gather is the all-GitHub plan, reported in `note`. */
export async function planOverflow(d: OverflowDeps): Promise<{ gh: string[]; cc: string[]; reason: string; note?: string } | null> {
  const safe = async <T>(f: () => Promise<T>, dflt: T): Promise<T> => { try { return await f(); } catch { return dflt; } };
  const [slots, gh] = await Promise.all([safe(d.slots, { active: null, ageS: 0 } as Slots), safe(d.ghStatus, { actions: "unknown", prevDegraded: false })]);
  const now = d.now();
  const gathered = { legs: d.legs, ghActive: slots.active, ghActions: gh.actions, ghPrev: gh.prevDegraded, now, forceFull: d.forceFull };
  const ask = (cc: { ccArm: string; ccReadAt: number | null; spent: number; storage: number; keys: number | null; checkout: boolean | null }) =>
    d.call({ op: "ci.overflow", ...gathered, ...cc }) as OverflowReply;
  // Fwcore's first answer, with no CircleCI fact: the legs to move do not depend on those facts.
  let r = ask({ ccArm: "unknown", ccReadAt: null, spent: 0, storage: 0, keys: null, checkout: null });
  let cc = "CircleCI not asked";
  if (r.reason !== "github-first") {
    const [st, k] = await Promise.all([safe(d.ccStatus, { arm: "unknown", readAt: null as number | null }), safe(d.keys, { keys: null as number | null, checkout: null as boolean | null })]);
    const b = await safe(async () => d.budget(), { spent: 0, storage: 0 });
    r = ask({ ccArm: st.arm, ccReadAt: st.readAt, spent: b.spent, storage: b.storage, keys: k.keys, checkout: k.checkout });
    cc = `CircleCI ${st.arm}`;
  }
  const count = slots.active === null ? "GitHub slot count unreadable" : `GitHub slots free ${r.ghFree}, count ${slots.ageS} s old`;
  return { gh: r.gh, cc: r.cc, reason: r.reason, note: `${count}; ${cc}${d.forceFull ? "; forced full" : ""}` };
}

/** The overflow plan a land passes to `runTiered`: the legs, and the plan made once, when the remote tier starts. */
export function overflowFor(d: OverflowDeps): OverflowPlan {
  return { legs: d.legs, plan: () => planOverflow(d) };
}

// ---- the real CircleCI dependencies ------------------------------------------------------------------------------------------
type Cci = {
  loadGolden: () => unknown;
  loadConfig: (root: string) => { slug: string; definitionId: string };
  keychainToken: () => string;
  triggerRequest: (a: Record<string, unknown>) => { method: string; url: string; body: unknown };
  keyCheck: (ctx: unknown, a: { slug: string }) => Promise<{ proceed: boolean; verdict: string; keys: number | null; checkout: boolean | null }>;
  call: (ctx: unknown, method: string, url: string, body?: unknown) => Promise<{ id: string }>;
  waitPipeline: (ctx: unknown, a: { slug: string; pipelineId: string; timeoutS: number; intervalS: number }) => Promise<{ code: number }>;
  fetchPipeline: (ctx: unknown, a: { slug: string; pipelineId: string; out: string }) => Promise<{ sha: string; lanes: CircleLane[]; runs: { queueMs: number; durMs: number }[] }>;
  storageSoFar: (ctx: unknown) => number;
  creditsSoFar: (ctx: unknown, now?: number) => number;
};

/** scripts/circleci.mjs loaded at run time from `root`, so the typechecker never resolves it (it is plain JS). */
export async function loadCircleci(root: string): Promise<Cci> {
  return (await import(pathToFileURL(join(root, "scripts", "circleci.mjs")).href)) as Cci;
}

export type RealCircle = {
  deps: (call: FwCall, push: Pusher) => CircleDeps;
  /** `OverflowDeps.keys` */
  keys: OverflowDeps["keys"];
  /** `OverflowDeps.budget` */
  budget: OverflowDeps["budget"];
};

/** The CircleCI adapter's dependencies over scripts/circleci.mjs. The token is read from the Keychain (service fw-circleci-token) inside
 *  each request there: it is never printed, never in an argument list or a file. `outDir` is where fetched artifacts go. */
export async function realCircle(root: string, outDir: string, log: (l: string) => void = () => {}): Promise<RealCircle> {
  const m = await loadCircleci(root);
  const cfg = m.loadConfig(root);
  const golden = m.loadGolden();
  const ledgerPath = join(root, ".local", "circleci-ledger.json");
  const mkCtx = (extra: Record<string, unknown> = {}) => ({ golden, fetchFn: fetch, getToken: m.keychainToken, sleep: (s: number) => new Promise((r) => setTimeout(r, s * 1000)), now: Date.now, log, ledgerPath, ...extra });
  return {
    deps: (call, push) => ({
      call, push,
      trigger: async (branch, legs) => {
        if (!cfg.slug || !cfg.definitionId) throw new Error("CircleCI is not configured on this machine (.local/circleci.json)");
        const ctx = mkCtx();
        const k = await m.keyCheck(ctx, { slug: cfg.slug });
        if (!k.proceed) throw new Error(`CircleCI key check: ${k.verdict}`);
        const req = m.triggerRequest({ slug: cfg.slug, definitionId: cfg.definitionId, branch, lane: "land", legs });
        return (await m.call(ctx, req.method, req.url, req.body)).id;
      },
      wait: async (pipelineId, timeoutS, signal) => {
        // The wait polls at 120 s or slower; the abort ends it at its next sleep.
        const sleep = (s: number) => new Promise<void>((res, rej) => {
          const t = setTimeout(() => { if (signal?.aborted) rej(new Error("aborted")); else res(); }, s * 1000);
          signal?.addEventListener("abort", () => { clearTimeout(t); rej(new Error("aborted")); }, { once: true });
        });
        try { return (await m.waitPipeline(mkCtx({ sleep }), { slug: cfg.slug, pipelineId, timeoutS, intervalS: 120 })).code; }
        catch (e) { if (signal?.aborted) return 3; throw e; }
      },
      fetch: async (pipelineId): Promise<CircleFetch> => {
        const doc = await m.fetchPipeline(mkCtx(), { slug: cfg.slug, pipelineId, out: join(outDir, pipelineId) });
        const queueMs = Math.max(0, ...doc.runs.map((r) => r.queueMs)), laneMs = Math.max(0, ...doc.runs.map((r) => r.durMs));
        return { sha: doc.sha, lanes: doc.lanes ?? [], times: { queueMs, laneMs } };
      },
    }),
    keys: async () => {
      if (!cfg.slug) return { keys: null, checkout: null };
      const r = await m.keyCheck(mkCtx(), { slug: cfg.slug });
      return { keys: r.keys, checkout: r.checkout };
    },
    budget: () => ({ spent: m.creditsSoFar({ ledgerPath }), storage: m.storageSoFar({ ledgerPath }) }),
  };
}

/** The Actions component of githubstatus and the last flag; `collectGh` reads once and never throws. */
export const ghStatusOnce = async (prevDegraded = false): Promise<{ actions: string; prevDegraded: boolean }> => {
  const s = await collectGh(prevDegraded);
  return { actions: s.actions, prevDegraded: s.prevDegraded };
};

/** The console's `GET /api/ci-status`: the CircleCI arm verdict (Lean Fw.Obs.CiStatus, in the console) and the time of its last read. */
export async function ccStatusFrom(get: (path: string) => Promise<{ status: number; body: unknown }>): Promise<{ arm: string; readAt: number | null }> {
  const r = await get("/api/ci-status");
  const b = r.body as { readAt?: unknown; arm?: { verdict?: unknown } };
  if (r.status !== 200) return { arm: "unknown", readAt: null };
  return { arm: typeof b.arm?.verdict === "string" ? b.arm.verdict : "unknown", readAt: typeof b.readAt === "number" ? b.readAt : null };
}

export const forceFullFromEnv = (env: Record<string, string | undefined> = process.env): boolean => env.FW_LAND_FORCE_FULL === "1";
