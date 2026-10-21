// TS STAND-IN for Fw.Sup.Adapt (lean/Fw/Sup/Adapt.lean, proved there): every function mirrors the Lean definition of
// the same name; test/slot.test.ts replays packages/contracts/golden/sup/adapt.jsonl against them. Replace by fwcore
// once it serves `sup.adapt`.

export type Kind = "check" | "test" | "land" | "sim" | "other";
export const KINDS: readonly Kind[] = ["check", "test", "land", "sim", "other"];
export const kindOf = (s: string): Kind | null => (KINDS as readonly string[]).includes(s) ? (s as Kind) : null;

export type Params = {
  nMin: number; nMax: number; targetCenti: number; highCenti: number; floorMB: number; headroomMB: number; cmprsPct: number;
  swapRiseMBPerMin: number; holdS: number; leanProcMB: number; testMB: number; landMB: number; simMB: number; otherMB: number;
  warmS: number; ageS: number; maxWaitS: number; leaseS: number; leaseMaxS: number; simIdleS: number; graceMs: number;
  simPollS: number; buildMB: number; agentsMax: number; agentsAgeS: number;
};

/** Equal to `Fw.Sup.Adapt.Params` defaults (golden case "default parameters"). */
export const DEFAULT_PARAMS: Params = {
  nMin: 1, nMax: 4, targetCenti: 800, highCenti: 1600, floorMB: 1024, headroomMB: 2048, cmprsPct: 40, swapRiseMBPerMin: 512,
  holdS: 30, leanProcMB: 700, testMB: 1600, landMB: 1500, simMB: 2800, otherMB: 1000, warmS: 60, ageS: 300, maxWaitS: 1800,
  leaseS: 60, leaseMaxS: 3600, simIdleS: 600, graceMs: 5000, simPollS: 30, buildMB: 2100, agentsMax: 8, agentsAgeS: 900,
};

export type Sample = { time: number; loadCenti: number; freeMB: number; ramMB: number; compressorMB: number; swapUsedMB: number; cores: number };
export type Prev = { time: number; swapUsedMB: number } | null;
export type Ctl = { n: number; lastChange: number; prev: Prev };
export type Signal = "overload" | "under" | "hold";

const sub = (a: number, b: number): number => Math.max(0, a - b);
const div = (a: number, b: number): number => (b === 0 ? 0 : Math.floor(a / b));

export const loadHigh = (p: Params, s: Sample): boolean => p.highCenti <= s.loadCenti;
export const memLow = (p: Params, s: Sample): boolean => s.freeMB < p.floorMB;
export const cmprsHigh = (p: Params, s: Sample): boolean => s.ramMB > 0 && p.cmprsPct * s.ramMB <= 100 * s.compressorMB;
export const swapRising = (p: Params, prev: Prev, s: Sample): boolean =>
  prev !== null && prev.time < s.time && p.swapRiseMBPerMin * (s.time - prev.time) <= 60 * sub(s.swapUsedMB, prev.swapUsedMB);
export const overloaded = (p: Params, prev: Prev, s: Sample): boolean =>
  loadHigh(p, s) || memLow(p, s) || cmprsHigh(p, s) || swapRising(p, prev, s);
export const roomy = (p: Params, s: Sample): boolean => s.loadCenti < p.targetCenti && p.floorMB + p.headroomMB <= s.freeMB;
export const signal = (p: Params, prev: Prev, s: Sample): Signal => (overloaded(p, prev, s) ? "overload" : roomy(p, s) ? "under" : "hold");
export const clamp = (p: Params, x: number): number => Math.max(p.nMin, Math.min(p.nMax, x));
export const target = (n: number, g: Signal): number => (g === "overload" ? div(n, 2) : g === "under" ? n + 1 : n);
export const nextN = (p: Params, c: Ctl, s: Sample): number => clamp(p, target(c.n, signal(p, c.prev, s)));

export function step(p: Params, c: Ctl, s: Sample): Ctl {
  const prev = { time: s.time, swapUsedMB: s.swapUsedMB };
  const m = nextN(p, c, s);
  return c.lastChange + p.holdS <= s.time && m !== c.n ? { n: m, lastChange: s.time, prev } : { ...c, prev };
}

export const init = (p: Params): Ctl => ({ n: clamp(p, 2), lastChange: 0, prev: null });

/** A queue ticket or a slot holder; no process id. `leaseS` is the granted lease length (s). */
export type Entry = { owner: string; token: string; kind: Kind; since: number; till: number; foot: number; leaseS: number };

export const live = (now: number, e: Entry): boolean => now < e.till;
export const prune = (now: number, es: Entry[]): Entry[] => es.filter((e) => live(now, e));
export const expired = (now: number, es: Entry[]): Entry[] => es.filter((e) => !live(now, e));
export const same = (owner: string, token: string, e: Entry): boolean => e.owner === owner && e.token === token;
export const grantUntil = (p: Params, now: number, lease: number): number => now + Math.min(lease, p.leaseMaxS);
export const grant = (p: Params, me: Entry, now: number, lease: number, foot: number): Entry =>
  ({ ...me, since: now, till: grantUntil(p, now, lease), foot, leaseS: Math.min(lease, p.leaseMaxS) });
export const lenOf = (p: Params, lease: number | null, e: Entry): number => (lease === null ? e.leaseS : Math.min(lease, p.leaseMaxS));

export function renew(p: Params, now: number, owner: string, token: string, lease: number | null, es: Entry[]): Entry[] | null {
  if (!es.some((e) => same(owner, token, e) && live(now, e))) return null;
  return es.map((e) => (same(owner, token, e) ? { ...e, till: now + lenOf(p, lease, e), leaseS: lenOf(p, lease, e) } : e));
}

export const leaseOr = (stored: number | null, since: number, till: number): number => stored ?? Math.max(0, till - since);

export const release = (owner: string, token: string, es: Entry[]): Entry[] => es.filter((e) => !same(owner, token, e));

export const leanThreads = (p: Params, cores: number, roomMB: number): number => Math.max(1, Math.min(cores, div(roomMB, p.leanProcMB)));

export function foot(p: Params, threads: number, k: Kind): number {
  switch (k) {
    case "check": return threads * p.leanProcMB;
    case "test": return p.testMB;
    case "land": return p.landMB;
    case "sim": return p.simMB;
    case "other": return p.otherMB;
  }
}

export const charged = (p: Params, now: number, hs: Entry[]): number =>
  prune(now, hs).filter((h) => now < h.since + p.warmS).reduce((a, h) => a + h.foot, 0);
export const room = (p: Params, s: Sample, hs: Entry[]): number => sub(sub(s.freeMB, p.floorMB), charged(p, s.time, hs));
export const threadsFor = (p: Params, s: Sample, hs: Entry[]): number => leanThreads(p, s.cores, room(p, s, hs));
export const need = (p: Params, s: Sample, hs: Entry[], k: Kind): number => foot(p, threadsFor(p, s, hs), k);

export type Why =
  | { why: "queued"; ahead: number }
  | { why: "older" }
  | { why: "full"; running: number; limit: number }
  | { why: "simBusy" }
  | { why: "drain"; others: number }
  | { why: "memory"; needMB: number; roomMB: number }
  | { why: "simFirst" };
export type Verdict = { verdict: "admit"; threads: number; footMB: number } | ({ verdict: "wait" | "timeout" } & Why);

const waitOr = (p: Params, waited: number, w: Why): Verdict => ({ verdict: p.maxWaitS <= waited ? "timeout" : "wait", ...w });

export function before(q: Entry[], me: Entry): Entry[] {
  const i = q.findIndex((e) => e.token === me.token);
  return i < 0 ? q : q.slice(0, i);
}

export const aheadSame = (q: Entry[], me: Entry): number => before(q, me).filter((e) => e.kind === me.kind).length;
export const simHeld = (now: number, hs: Entry[]): boolean => prune(now, hs).some((h) => h.kind === "sim");
export const heldOf = (now: number, hs: Entry[], k: Kind): boolean => prune(now, hs).some((h) => h.kind === k);
export const others = (now: number, hs: Entry[]): number => prune(now, hs).filter((h) => h.kind !== "sim").length;
export const simPending = (now: number, hs: Entry[], q: Entry[]): boolean => q.some((e) => e.kind === "sim") && !simHeld(now, hs);
export const starved = (p: Params, now: number, hs: Entry[], q: Entry[], me: Entry): boolean =>
  before(q, me).some((e) => e.kind !== me.kind && e.since + p.ageS <= now && !(e.kind === "sim" && simHeld(now, hs)));

export function yieldsToSim(p: Params, n: number, s: Sample, hs: Entry[], q: Entry[], me: Entry): boolean {
  if (me.kind === "sim") return false;
  const o = others(s.time, hs);
  if (simHeld(s.time, hs) && 0 < o) return true;
  return (
    simPending(s.time, hs, q) &&
    (0 < o || n < prune(s.time, hs).length + 2 || s.freeMB < need(p, s, hs, me.kind) + p.floorMB + charged(p, s.time, hs) + p.simMB)
  );
}

export function verdict(p: Params, n: number, s: Sample, hs: Entry[], q: Entry[], me: Entry, waited: number): Verdict {
  const running = prune(s.time, hs).length;
  const ahead = aheadSame(q, me);
  if (ahead > 0) return waitOr(p, waited, { why: "queued", ahead });
  if (me.kind !== "sim" && starved(p, s.time, hs, q, me)) return waitOr(p, waited, { why: "older" });
  if (n <= running) return waitOr(p, waited, { why: "full", running, limit: n });
  if (me.kind === "sim" && simHeld(s.time, hs)) return waitOr(p, waited, { why: "simBusy" });
  if (me.kind === "sim" && 1 < others(s.time, hs)) return waitOr(p, waited, { why: "drain", others: others(s.time, hs) });
  const needMB = need(p, s, hs, me.kind);
  if (s.freeMB < needMB + p.floorMB + charged(p, s.time, hs)) return waitOr(p, waited, { why: "memory", needMB, roomMB: room(p, s, hs) });
  if (yieldsToSim(p, n, s, hs, q, me)) return waitOr(p, waited, { why: "simFirst" });
  return { verdict: "admit", threads: threadsFor(p, s, hs), footMB: needMB };
}

export const legacyEntry = (now: number): Entry => ({ owner: "sim-lock", token: "sim-lock", kind: "sim", since: 0, till: now + 1, foot: 0, leaseS: 0 });
export const withLegacy = (now: number, legacy: boolean, hs: Entry[]): Entry[] => (legacy ? [...hs, legacyEntry(now)] : hs);

export const simBoot = (now: number, owner: string, token: string, hs: Entry[]): boolean =>
  hs.some((h) => h.kind === "sim" && same(owner, token, h) && live(now, h));

export type SimAct = "none" | "keep" | "shutdown";
export const simIdleNext = (now: number, held: boolean, booted: boolean, prev: number | null): number | null =>
  booted && !held ? (prev ?? now) : null;
export function simAction(p: Params, now: number, hs: Entry[], booted: boolean, legacyHeld: boolean, idleSince: number | null): SimAct {
  if (!booted) return "none";
  if (legacyHeld || simHeld(now, hs)) return "keep";
  if (idleSince === null) return "keep";
  return idleSince + p.simIdleS <= now ? "shutdown" : "keep";
}
export const simDue = (p: Params, now: number, last: number): boolean => last + p.simPollS <= now;

export type BuildWhy =
  | { why: "simWaits" }
  | { why: "agentsUnknown" }
  | { why: "agents"; live: number; max: number }
  | { why: "memory"; freeMB: number; needMB: number };
export type BuildVerdict = { verdict: "admit" } | ({ verdict: "wait" } & BuildWhy);
export const simQueued = (now: number, q: Entry[]): boolean => prune(now, q).some((e) => e.kind === "sim");
export const agentsSeen = (p: Params, now: number, reading: { time: number; live: number } | null): number | null =>
  reading !== null && now <= reading.time + p.agentsAgeS ? reading.live : null;
export function admitBuild(p: Params, simWaits: boolean, freeMB: number, agents: number | null): BuildVerdict {
  if (simWaits) return { verdict: "wait", why: "simWaits" };
  if (agents === null) return { verdict: "wait", why: "agentsUnknown" };
  if (p.agentsMax <= agents) return { verdict: "wait", why: "agents", live: agents, max: p.agentsMax };
  if (freeMB < p.floorMB + p.buildMB) return { verdict: "wait", why: "memory", freeMB, needMB: p.floorMB + p.buildMB };
  return { verdict: "admit" };
}

export type StopAct = "term" | "wait" | "kill" | "done";
export function stopAct(p: Params, alive: boolean, sameStart: boolean, termAt: number | null, nowMs: number): StopAct {
  if (!alive || !sameStart) return "done";
  if (termAt === null) return "term";
  return termAt + p.graceMs <= nowMs ? "kill" : "wait";
}

export type CacheKey = { kind: Kind; argv: string[]; tree: string; base: string };
export const keyOf = (kind: Kind, argv: string[], tree: string, mainSha: string, clean: boolean): CacheKey | null =>
  clean ? { kind, argv, tree, base: kind === "land" ? mainSha : "" } : null;
const sameKey = (a: CacheKey, b: CacheKey): boolean =>
  a.kind === b.kind && a.tree === b.tree && a.base === b.base && a.argv.length === b.argv.length && a.argv.every((x, i) => x === b.argv[i]);
export const cacheHit = (recorded: CacheKey, exit: number, k: CacheKey | null): boolean => k !== null && sameKey(recorded, k) && exit === 0;
export const cacheable = (exit: number): boolean => exit === 0;
