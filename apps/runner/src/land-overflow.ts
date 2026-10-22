import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { collectGh } from "./watch-gh.ts";
import type { CircleDeps, CircleFetch, CircleLane, OverflowPlan, Pusher } from "./land-remote.ts";
import type { FwCall, Gh } from "./run.ts";

export const SLOT_TTL_S = 120;
export const ACTIVE_STATUS = new Set(["queued", "in_progress", "waiting", "pending", "requested"]);
export const SLOT_FIELDS = "status,workflowName,databaseId";

export type Slots = { active: string[] | null; ageS: number };

export async function readSlots(gh: Gh, nowMs: () => number, cacheFile?: string): Promise<Slots> {
  const t = nowMs();
  if (cacheFile && existsSync(cacheFile)) {
    try {
      const c = JSON.parse(readFileSync(cacheFile, "utf8")) as { at: number; active: string[] };
      if (Array.isArray(c.active) && t - c.at >= 0 && t - c.at < SLOT_TTL_S * 1000) return { active: c.active, ageS: Math.round((t - c.at) / 1000) };
    } catch {}
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
  legs: string[];
  now: () => number;
  slots: () => Promise<Slots>;
  ghStatus: () => Promise<{ actions: string; prevDegraded: boolean }>;
  ccStatus: () => Promise<{ arm: string; readAt: number | null }>;
  keys: () => Promise<{ keys: number | null; checkout: boolean | null }>;
  budget: () => { spent: number; storage: number };
  forceFull: boolean;
};
export type OverflowReply = { gh: string[]; cc: string[]; reason: string; ghFree: number; ghDegraded: boolean; ccReady: boolean };

export async function planOverflow(d: OverflowDeps): Promise<{ gh: string[]; cc: string[]; reason: string; note?: string } | null> {
  const safe = async <T>(f: () => Promise<T>, dflt: T): Promise<T> => { try { return await f(); } catch { return dflt; } };
  const [slots, gh] = await Promise.all([safe(d.slots, { active: null, ageS: 0 } as Slots), safe(d.ghStatus, { actions: "unknown", prevDegraded: false })]);
  const now = d.now();
  const gathered = { legs: d.legs, ghActive: slots.active, ghActions: gh.actions, ghPrev: gh.prevDegraded, now, forceFull: d.forceFull };
  const ask = (cc: { ccArm: string; ccReadAt: number | null; spent: number; storage: number; keys: number | null; checkout: boolean | null }) =>
    d.call({ op: "ci.overflow", ...gathered, ...cc }) as OverflowReply;
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

export function overflowFor(d: OverflowDeps): OverflowPlan {
  return { legs: d.legs, plan: () => planOverflow(d) };
}

type Cci = {
  loadGolden: () => unknown;
  loadConfig: (root: string) => { slug: string; definitionId: string };
  keychainToken: () => string;
  triggerRequest: (a: Record<string, unknown>) => { method: string; url: string; body: unknown };
  keyCheck: (ctx: unknown, a: { slug: string }) => Promise<{ proceed: boolean; verdict: string; keys: number | null; checkout: boolean | null }>;
  call: (ctx: unknown, method: string, url: string, body?: unknown) => Promise<{ id: string }>;
  waitPipeline: (ctx: unknown, a: { slug: string; pipelineId: string; timeoutS: number; intervalS: number }) => Promise<{ code: number }>;
  fetchPipeline: (ctx: unknown, a: { slug: string; pipelineId: string; out: string }) => Promise<{ sha: string; lanes: CircleLane[]; runs: { queueMs: number; durMs: number }[] }>;
  storageSoFar: (ctx: unknown, exceptId?: string, now?: number) => number;
  creditsSoFar: (ctx: unknown, now?: number) => number;
};

export async function loadCircleci(root: string): Promise<Cci> {
  return (await import(pathToFileURL(join(root, "scripts", "circleci.mjs")).href)) as Cci;
}

export type RealCircle = {
  deps: (call: FwCall, push: Pusher) => CircleDeps;
  keys: OverflowDeps["keys"];
  budget: OverflowDeps["budget"];
};

export async function realCircle(root: string, outDir: string, log: (l: string) => void = () => {}, over: Record<string, unknown> = {}): Promise<RealCircle> {
  const m = await loadCircleci(root);
  const cfg = m.loadConfig(root);
  const golden = m.loadGolden();
  const ledgerPath = join(root, ".local", "circleci-ledger.json");
  const mkCtx = (extra: Record<string, unknown> = {}) => ({ golden, fetchFn: fetch, getToken: m.keychainToken, sleep: (s: number) => new Promise((r) => setTimeout(r, s * 1000)), now: Date.now, log, ledgerPath, ...over, ...extra });
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
        const sleep = (s: number) => new Promise<void>((res, rej) => {
          const t = setTimeout(() => { if (signal?.aborted) rej(new Error("aborted")); else res(); }, s * 1000);
          signal?.addEventListener("abort", () => { clearTimeout(t); rej(new Error("aborted")); }, { once: true });
        });
        try { return (await m.waitPipeline(mkCtx({ sleep, storageStop: false }), { slug: cfg.slug, pipelineId, timeoutS, intervalS: 120 })).code; }
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
    budget: () => {
      const now = Date.now();
      return { spent: m.creditsSoFar({ ledgerPath }, now), storage: m.storageSoFar({ ledgerPath, golden }, "", now) };
    },
  };
}

export const ghStatusOnce = async (prevDegraded = false): Promise<{ actions: string; prevDegraded: boolean }> => {
  const s = await collectGh(prevDegraded);
  return { actions: s.actions, prevDegraded: s.prevDegraded };
};

export async function ccStatusFrom(get: (path: string) => Promise<{ status: number; body: unknown }>): Promise<{ arm: string; readAt: number | null }> {
  const r = await get("/api/ci-status");
  const b = r.body as { readAt?: unknown; arm?: { verdict?: unknown } };
  if (r.status !== 200) return { arm: "unknown", readAt: null };
  return { arm: typeof b.arm?.verdict === "string" ? b.arm.verdict : "unknown", readAt: typeof b.readAt === "number" ? b.readAt : null };
}

export const forceFullFromEnv = (env: Record<string, string | undefined> = process.env): boolean => env.FW_LAND_FORCE_FULL === "1";
