export type Kind = "check" | "test" | "land" | "sim" | "other" | "measure";
export const KINDS: readonly Kind[] = ["check", "test", "land", "sim", "other", "measure"];
export const kindOf = (s: string): Kind | null => (KINDS as readonly string[]).includes(s) ? (s as Kind) : null;

export type Params = {
  nMin: number; nMax: number; targetCenti: number; highCenti: number; floorMB: number; headroomMB: number; cmprsPct: number;
  swapRiseMBPerMin: number; holdS: number; leanProcMB: number; testMB: number; landMB: number; simMB: number; otherMB: number;
  warmS: number; ageS: number; maxWaitS: number; leaseS: number; leaseMaxS: number; simIdleS: number; graceMs: number;
  simPollS: number; buildMB: number; agentsMax: number; agentsAgeS: number; swapOutMBPerMinMax: number; comprMBPerMinMax: number;
  rateMinS: number; rateMaxS: number; measureMB: number;
};

export const DEFAULT_PARAMS: Params = {
  nMin: 1, nMax: 4, targetCenti: 800, highCenti: 1600, floorMB: 1024, headroomMB: 2048, cmprsPct: 40, swapRiseMBPerMin: 512,
  holdS: 30, leanProcMB: 700, testMB: 1600, landMB: 1500, simMB: 2800, otherMB: 1000, warmS: 60, ageS: 300, maxWaitS: 1800,
  leaseS: 60, leaseMaxS: 3600, simIdleS: 600, graceMs: 5000, simPollS: 30, buildMB: 2100, agentsMax: 8, agentsAgeS: 900,
  swapOutMBPerMinMax: 64, comprMBPerMinMax: 1500, rateMinS: 5, rateMaxS: 600, measureMB: 2800,
};

export type Mem = {
  freeMB: number; specMB: number; purgMB: number; fileMB: number; fileMinMB: number; swapUsedMB: number; swapTotalMB: number;
  press: number; comprMBPerMin: number; swapOutMBPerMin: number;
};
export type Sample = { time: number; loadCenti: number; mem: Mem; ramMB: number; compressorMB: number; cores: number };
export type Prev = { time: number; swapUsedMB: number } | null;
export type Ctl = { n: number; lastChange: number; prev: Prev };
export type Signal = "overload" | "under" | "hold";

const sub = (a: number, b: number): number => Math.max(0, a - b);
const div = (a: number, b: number): number => (b === 0 ? 0 : Math.floor(a / b));

export const availMB = (m: Mem): number => m.freeMB + m.specMB + m.purgMB + sub(m.fileMB, m.fileMinMB);
export const avail = (s: Sample): number => availMB(s.mem);
export const swapActive = (p: Params, m: Mem): boolean => p.swapOutMBPerMinMax <= m.swapOutMBPerMin;
export const thrash = (p: Params, m: Mem): boolean => p.comprMBPerMinMax <= m.comprMBPerMin;
export const memLow = (p: Params, m: Mem): boolean => availMB(m) < p.floorMB || m.press !== 1 || swapActive(p, m) || thrash(p, m);

export type VmMark = { time: number; count: number; rate: number; swapCount: number; swapRate: number };
export const mbPerMin = (dt: number, c0: number, c1: number, pageB: number): number =>
  (c0 <= c1 ? div((c1 - c0) * pageB * 60, dt * 1048576) : 0);
export function vmNext(p: Params, prev: VmMark | null, now: number, count: number, swapCount: number, pageB: number): VmMark {
  if (prev === null) return { time: now, count, rate: 0, swapCount, swapRate: 0 };
  if (now < prev.time + p.rateMinS) return prev;
  if (now <= prev.time + p.rateMaxS) {
    const dt = now - prev.time;
    return { time: now, count, rate: mbPerMin(dt, prev.count, count, pageB), swapCount, swapRate: mbPerMin(dt, prev.swapCount, swapCount, pageB) };
  }
  return { time: now, count, rate: 0, swapCount, swapRate: 0 };
}

export const loadHigh = (p: Params, s: Sample): boolean => p.highCenti <= s.loadCenti;
export const cmprsHigh = (p: Params, s: Sample): boolean => s.ramMB > 0 && p.cmprsPct * s.ramMB <= 100 * s.compressorMB;
export const swapRising = (p: Params, prev: Prev, s: Sample): boolean =>
  prev !== null && prev.time < s.time && p.swapRiseMBPerMin * (s.time - prev.time) <= 60 * sub(s.mem.swapUsedMB, prev.swapUsedMB);
export const overloaded = (p: Params, prev: Prev, s: Sample): boolean =>
  loadHigh(p, s) || memLow(p, s.mem) || cmprsHigh(p, s) || swapRising(p, prev, s);
export const roomy = (p: Params, s: Sample): boolean => s.loadCenti < p.targetCenti && p.floorMB + p.headroomMB <= avail(s);
export const signal = (p: Params, prev: Prev, s: Sample): Signal => (overloaded(p, prev, s) ? "overload" : roomy(p, s) ? "under" : "hold");
export const clamp = (p: Params, x: number): number => Math.max(p.nMin, Math.min(p.nMax, x));
export const target = (n: number, g: Signal): number => (g === "overload" ? div(n, 2) : g === "under" ? n + 1 : n);
export const nextN = (p: Params, c: Ctl, s: Sample): number => clamp(p, target(c.n, signal(p, c.prev, s)));

export function step(p: Params, c: Ctl, s: Sample): Ctl {
  const prev = { time: s.time, swapUsedMB: s.mem.swapUsedMB };
  const m = nextN(p, c, s);
  return c.lastChange + p.holdS <= s.time && m !== c.n ? { n: m, lastChange: s.time, prev } : { ...c, prev };
}

export const init = (p: Params): Ctl => ({ n: clamp(p, 2), lastChange: 0, prev: null });

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
    case "measure": return p.measureMB;
  }
}

export const charged = (p: Params, now: number, hs: Entry[]): number =>
  prune(now, hs).filter((h) => now < h.since + p.warmS).reduce((a, h) => a + h.foot, 0);
export const room = (p: Params, s: Sample, hs: Entry[]): number => sub(sub(avail(s), p.floorMB), charged(p, s.time, hs));
export const threadsFor = (p: Params, s: Sample, hs: Entry[]): number => leanThreads(p, s.cores, room(p, s, hs));
export const need = (p: Params, s: Sample, hs: Entry[], k: Kind): number => foot(p, threadsFor(p, s, hs), k);

export type Why =
  | { why: "queued"; ahead: number }
  | { why: "older" }
  | { why: "full"; running: number; limit: number }
  | { why: "simBusy" }
  | { why: "drain"; others: number }
  | { why: "memory"; needMB: number; roomMB: number }
  | { why: "memLow"; availMB: number }
  | { why: "simFirst" }
  | { why: "pass" }
  | { why: "gap"; needS: number; leftS: number }
  | { why: "unknown" }
  | { why: "measureBusy" };
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
    (0 < o || n < prune(s.time, hs).length + 2 || avail(s) < need(p, s, hs, me.kind) + p.floorMB + charged(p, s.time, hs) + p.simMB)
  );
}

export const idleHead = (p: Params, s: Sample, hs: Entry[]): boolean =>
  prune(s.time, hs).length === 0 && s.mem.press === 1 && !thrash(p, s.mem) && !swapActive(p, s.mem);

export function verdictWith(idle: boolean, p: Params, n: number, s: Sample, hs: Entry[], q: Entry[], me: Entry, waited: number): Verdict {
  const running = prune(s.time, hs).length;
  const ahead = aheadSame(q, me);
  if (ahead > 0) return waitOr(p, waited, { why: "queued", ahead });
  if (me.kind !== "sim" && starved(p, s.time, hs, q, me)) return waitOr(p, waited, { why: "older" });
  if (n <= running) return waitOr(p, waited, { why: "full", running, limit: n });
  if (me.kind === "sim" && simHeld(s.time, hs)) return waitOr(p, waited, { why: "simBusy" });
  if (me.kind === "sim" && 1 < others(s.time, hs)) return waitOr(p, waited, { why: "drain", others: others(s.time, hs) });
  if (memLow(p, s.mem) && !idle) return waitOr(p, waited, { why: "memLow", availMB: avail(s) });
  const needMB = need(p, s, hs, me.kind);
  if (avail(s) < needMB + p.floorMB + charged(p, s.time, hs) && !idle) return waitOr(p, waited, { why: "memory", needMB, roomMB: room(p, s, hs) });
  if (yieldsToSim(p, n, s, hs, q, me)) return waitOr(p, waited, { why: "simFirst" });
  return { verdict: "admit", threads: threadsFor(p, s, hs), footMB: needMB };
}

export const verdict = (p: Params, n: number, s: Sample, hs: Entry[], q: Entry[], me: Entry, waited: number): Verdict =>
  verdictWith(idleHead(p, s, hs), p, n, s, hs, q, me, waited);

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
  | { why: "memory"; availMB: number; needMB: number };
export type BuildVerdict = { verdict: "admit" } | ({ verdict: "wait" } & BuildWhy);
export const simQueued = (now: number, q: Entry[]): boolean => prune(now, q).some((e) => e.kind === "sim");
export const agentsSeen = (p: Params, now: number, reading: { time: number; live: number } | null): number | null =>
  reading !== null && now <= reading.time + p.agentsAgeS ? reading.live : null;
export function admitBuild(p: Params, simWaits: boolean, availMB: number, agents: number | null): BuildVerdict {
  if (simWaits) return { verdict: "wait", why: "simWaits" };
  if (agents === null) return { verdict: "wait", why: "agentsUnknown" };
  if (p.agentsMax <= agents) return { verdict: "wait", why: "agents", live: agents, max: p.agentsMax };
  if (availMB < p.floorMB + p.buildMB) return { verdict: "wait", why: "memory", availMB, needMB: p.floorMB + p.buildMB };
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

export type WParams = { measureMaxS: number; passMaxS: number; settleS: number; histMin: number; histN: number };
export const DEFAULT_WPARAMS: WParams = { measureMaxS: 5400, passMaxS: 1200, settleS: 30, histMin: 3, histN: 20 };
export type Window = { owner: string; token: string; deadline: number; passTill: number | null; next: number };

export const openAt = (wp: WParams, owner: string, token: string, now: number, gapS: number): Window =>
  ({ owner, token, deadline: now + wp.measureMaxS, passTill: null, next: now + gapS });
export const active = (now: number, w: Window): boolean => now < w.deadline;
export const heldWindow = (now: number, hs: Entry[], w: Window): boolean =>
  prune(now, hs).some((h) => h.kind === "measure" && h.token === w.token && h.owner === w.owner);
export const current = (now: number, hs: Entry[], w: Window | null): Window | null =>
  w !== null && active(now, w) && heldWindow(now, hs, w) ? w : null;
export const passLive = (now: number, w: Window): boolean => w.passTill !== null && now < w.passTill;
export const fits = (wp: WParams, now: number, next: number, d: number): boolean => now + d + wp.settleS <= next;

export function gate(wp: WParams, w: Window, pred: number | null, p: Params, now: number, waited: number, me: Entry, base: Verdict): Verdict {
  if (passLive(now, w)) return waitOr(p, waited, { why: "pass" });
  if (me.kind === "measure") return waitOr(p, waited, { why: "measureBusy" });
  if (base.verdict !== "admit") return base;
  if (pred === null) return waitOr(p, waited, { why: "unknown" });
  return fits(wp, now, w.next, pred) ? base : waitOr(p, waited, { why: "gap", needS: pred + wp.settleS, leftS: sub(w.next, now) });
}

export function wverdict(wp: WParams, w: Window | null, pred: number | null, p: Params, n: number, s: Sample, hs: Entry[], q: Entry[], me: Entry, waited: number): Verdict {
  const cur = current(s.time, hs, w);
  const base = verdict(p, n, s, hs, q, me, waited);
  return cur === null ? base : gate(wp, cur, pred, p, s.time, waited, me, base);
}

export type Row = { step: string; durMs: number; exit: number | null; host: string };
export const runStepOf = (k: Kind): string => `slot run ${k}`;
export const counts = (k: Kind, r: Row): boolean =>
  r.host === "local" && r.exit === 0 && !r.step.endsWith(" cached") && (r.step === runStepOf(k) || r.step.startsWith(`${runStepOf(k)} `));
export const durs = (wp: WParams, k: Kind, rows: Row[]): number[] => rows.filter((r) => counts(k, r)).map((r) => r.durMs).reverse().slice(0, wp.histN);
export const rank90 = (n: number): number => Math.floor((9 * n + 9) / 10);
export const p90 = (xs: number[]): number => (xs.length === 0 ? 0 : [...xs].sort((a, b) => a - b)[rank90(xs.length) - 1]!);
export function predict(wp: WParams, k: Kind, rows: Row[]): number | null {
  const xs = durs(wp, k, rows);
  return wp.histMin <= xs.length ? Math.floor((p90(xs) + 999) / 1000) : null;
}

export type PassVerdict = { pass: "start"; till: number } | { pass: "wait"; others: number } | { pass: "gone" };
export const othersOf = (now: number, hs: Entry[], token: string): number => prune(now, hs).filter((h) => h.token !== token).length;
export function passStart(wp: WParams, w: Window | null, now: number, hs: Entry[], owner: string, token: string, forS: number): PassVerdict {
  const cur = current(now, hs, w);
  if (cur === null || cur.token !== token || cur.owner !== owner) return { pass: "gone" };
  const o = othersOf(now, hs, token);
  if (0 < o) return { pass: "wait", others: o };
  return { pass: "start", till: Math.min(now + Math.min(forS, wp.passMaxS), cur.deadline) };
}

export const beginPass = (w: Window, till: number): Window => ({ ...w, passTill: till });
export const want = (w: Window, now: number): Window => ({ ...w, next: Math.min(w.next, now) });
export const stopPass = (w: Window, now: number, gapS: number): Window => ({ ...w, passTill: null, next: now + gapS });
export const capLease = (w: Window, now: number, lease: number): number => Math.min(lease, sub(w.deadline, now));
