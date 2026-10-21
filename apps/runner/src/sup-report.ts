// The tables of the resource baseline (task sup-baseline): reduces <console dir>/sup-samples.jsonl (the 20 s sampler,
// watch-collect.ts `sampleOnce`) and <console dir>/locks.jsonl (acquire/release events of heavy-lock.mjs, lake-slot-lib.sh and
// sim-lock.sh) into research/notes/2026/10-2x-sup-baseline.md.
//   node apps/runner/src/sup-report.ts --dir <console dir> --out <note file> [--check]
// TS STAND-IN (reducer and renderer, no decision logic: the verdict of a sample is the TS mirror of Fw.Obs.Health.Res, golden-checked). The raw files are
// local-only (.fw-console/ is gitignored); the note keeps only the reduced tables, no command, path or other user's name.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { PROC_KINDS, RES_PARAMS, footMB, trippedBy, type KindUse, type ProcKind, type SupSample } from "./watch-collect.ts";

export const KINDS: readonly ProcKind[] = PROC_KINDS;
export interface LockEv { ts: number; lock: string; ev: string; kind: string; pid: number; start: number; slot?: number; waitMs?: number; holdMs?: number; exec?: number }

const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
function isSample(o: unknown): o is SupSample {
  const s = o as SupSample;
  return typeof o === "object" && o !== null && isNum(s.ts) && isNum(s.loadCenti) && isNum(s.ramMB) && isNum(s.costMs) && Array.isArray(s.partial) &&
    typeof s.kinds === "object" && s.kinds !== null && KINDS.every((k) => isNum(s.kinds[k]?.n) && isNum(s.kinds[k]?.memMB) && isNum(s.kinds[k]?.cmprsMB));
}
function isLockEv(o: unknown): o is LockEv {
  const e = o as LockEv;
  return typeof o === "object" && o !== null && isNum(e.ts) && typeof e.lock === "string" && typeof e.ev === "string" && typeof e.kind === "string" && isNum(e.pid) && isNum(e.start);
}
export function parseJsonl<T>(text: string, ok: (o: unknown) => o is T): T[] {
  const out: T[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try { const o: unknown = JSON.parse(line); if (ok(o)) out.push(o); } catch { /* a half-written last line */ }
  }
  return out;
}

/** Nearest-rank percentile (q in 0..1) of unsorted values; 0 for none. */
export function pct(xs: number[], q: number): number {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.max(0, Math.ceil(q * s.length) - 1))]!;
}
const dist = (xs: number[]) => ({ p50: pct(xs, 0.5), p90: pct(xs, 0.9), max: xs.length ? Math.max(...xs) : 0 });
const gb = (mb: number): string => (mb / 1024).toFixed(1);
const day = (ts: number): string => new Date(ts).toISOString().slice(0, 10);
const stamp = (ts: number): string => `${new Date(ts).toISOString().slice(0, 16).replace("T", " ")} UTC`;

/** Samples in time order, a sample within `minGapMs` of the previous kept one dropped (two watcher processes sampling at once). */
export function dedupe(samples: SupSample[], minGapMs = 10_000): { kept: SupSample[]; dropped: number } {
  const kept: SupSample[] = [];
  for (const s of [...samples].sort((a, b) => a.ts - b.ts)) {
    if (kept.length === 0 || s.ts - kept[kept.length - 1]!.ts >= minGapMs) kept.push(s);
  }
  return { kept, dropped: samples.length - kept.length };
}

export interface Hold { lock: string; kind: string; pid: number; start: number; from: number; to: number | null }
/** Pairs each release with the latest open acquire of the same lock, pid and start; an acquire never released is open (`to` null),
 *  an acquire marked `exec` (the lake-slot form that execs its command and so logs no release) makes no hold,
 *  a release with no acquire (it began before the collection) is counted in `orphans`. */
export function pairHolds(evs: LockEv[]): { holds: Hold[]; orphans: number } {
  const open = new Map<string, Hold[]>();
  const holds: Hold[] = [];
  let orphans = 0;
  for (const e of [...evs].sort((a, b) => a.ts - b.ts)) {
    const key = `${e.lock}/${e.pid}/${e.start}`;
    if (e.ev === "acquire" && e.exec === 1) continue;
    if (e.ev === "acquire") {
      const h: Hold = { lock: e.lock, kind: e.kind, pid: e.pid, start: e.start, from: e.ts, to: null };
      holds.push(h);
      open.set(key, [...(open.get(key) ?? []), h]);
    } else if (e.ev === "release") {
      const h = open.get(key)?.pop();
      if (h) h.to = e.ts; else orphans++;
    }
  }
  return { holds, orphans };
}
/** The most holds open at once (a release at the same millisecond as an acquire counts first, so this is a lower bound). */
export function maxConcurrent(holds: Hold[], end: number): number {
  const pts = holds.flatMap((h) => [{ t: h.from, d: 1 }, { t: h.to ?? end, d: -1 }]).sort((a, b) => a.t - b.t || a.d - b.d);
  let cur = 0; let best = 0;
  for (const p of pts) { cur += p.d; best = Math.max(best, cur); }
  return best;
}

type Dist = ReturnType<typeof dist>;
export interface Report {
  samples: number; dropped: number; from: number; to: number; partial: number; maxGapS: number; gaps60: number; costMs: { p50: number; p90: number; max: number };
  verdicts: Record<"quiet" | "busy" | "pressured" | "unknown", number>;
  /** Which pressure condition tripped, over the samples that have every reading (`n`); `swapOnly` is pressure by swap and nothing else. */
  pressure: { n: number; swap: number; cmprs: number; free: number; swapOnly: number; cmprsOrFree: number };
  kinds: Record<ProcKind, { n: Dist; memMB: Dist; cmprsMB: Dist; footMB: Dist; present: number }>;
  sys: { swapUsedMB: Dist; swapPct: Dist; compressorMB: Dist; freePct: Dist; load: Dist };
  ramMB: number; swapTotalMB: number;
  sim: { samples: number; idleSamples: number; gbHours: number; idleGbHours: number };
  serveMBh: number;
  /** Samples taken while a heavy-lock hold was open: how many, and the largest footprint per kind among them. */
  heavyHeld: { samples: number; peakFootMB: Record<ProcKind, number> };
  locks: { lock: string; kind: string; acquires: number; exec: number; refuses: number; open: number; wait: Dist; waited: number; released: number; hold: Dist; maxConc: number }[];
  simAcquires: number; lockDays: number;
  orphans: number; lockFrom: number | null; lockTo: number | null;
}

export function reduce(rawSamples: SupSample[], evs: LockEv[]): Report {
  const { kept, dropped } = dedupe(rawSamples);
  const col = (f: (s: SupSample) => number | null): number[] => kept.map(f).filter((x): x is number => x !== null);
  const from = kept[0]?.ts ?? 0;
  const to = kept[kept.length - 1]?.ts ?? 0;
  const gaps = kept.slice(1).map((s, i) => (s.ts - kept[i]!.ts) / 1000);
  const verdicts = { quiet: 0, busy: 0, pressured: 0, unknown: 0 };
  for (const s of kept) verdicts[s.verdict ?? "unknown"]++;
  const pressure = { n: 0, swap: 0, cmprs: 0, free: 0, swapOnly: 0, cmprsOrFree: 0 };
  for (const s of kept) {
    if (s.swapUsedMB === null || s.swapTotalMB === null || s.compressorMB === null || s.freePct === null) continue;
    const t = trippedBy(RES_PARAMS, { procs: [], loadCenti: s.loadCenti, swapUsedMB: s.swapUsedMB, swapTotalMB: s.swapTotalMB, compressorMB: s.compressorMB, ramMB: s.ramMB, freePct: s.freePct });
    pressure.n++;
    if (t.swap) pressure.swap++;
    if (t.cmprs) pressure.cmprs++;
    if (t.free) pressure.free++;
    if (t.swap && !t.cmprs && !t.free) pressure.swapOnly++;
    if (t.cmprs || t.free) pressure.cmprsOrFree++;
  }
  const kinds = Object.fromEntries(KINDS.map((k) => {
    const u = (s: SupSample): KindUse => s.kinds[k];
    return [k, { n: dist(kept.map((s) => u(s).n)), memMB: dist(kept.map((s) => u(s).memMB)), cmprsMB: dist(kept.map((s) => u(s).cmprsMB)), footMB: dist(kept.map((s) => footMB(u(s)))), present: kept.filter((s) => u(s).n > 0).length }];
  })) as Report["kinds"];
  const { holds, orphans } = pairHolds(evs);
  const heldAt = (lock: string, t: number): boolean => holds.some((h) => h.lock === lock && h.from <= t && t <= (h.to ?? to));
  const weight = (i: number): number => Math.min((kept[i + 1]?.ts ?? kept[i]!.ts + 20_000) - kept[i]!.ts, 60_000) / 3_600_000;
  let simSamples = 0; let idleSamples = 0; let gbH = 0; let idleGbH = 0; let serveMBh = 0;
  const heavyHeld = { samples: 0, peakFootMB: Object.fromEntries(KINDS.map((k) => [k, 0])) as Record<ProcKind, number> };
  kept.forEach((s, i) => {
    serveMBh += footMB(s.kinds.leanServe) * weight(i);
    if (heldAt("heavy", s.ts)) {
      heavyHeld.samples++;
      for (const k of KINDS) heavyHeld.peakFootMB[k] = Math.max(heavyHeld.peakFootMB[k], footMB(s.kinds[k]));
    }
    if (s.kinds.simulator.n === 0) return;
    simSamples++;
    const g = (footMB(s.kinds.simulator) / 1024) * weight(i);
    gbH += g;
    if (!heldAt("sim", s.ts)) { idleSamples++; idleGbH += g; }
  });
  const keys = [...new Set(evs.map((e) => `${e.lock}/${e.kind}`))].sort();
  const lockEnd = evs.length ? Math.max(...evs.map((e) => e.ts)) : 0;
  const locks = keys.map((key) => {
    const [lock, kind] = key.split("/") as [string, string];
    const mine = evs.filter((e) => e.lock === lock && e.kind === kind);
    const hs = holds.filter((h) => h.lock === lock && h.kind === kind);
    const acq = mine.filter((e) => e.ev === "acquire");
    const rel = mine.filter((e) => e.ev === "release");
    return {
      lock, kind, acquires: acq.length, exec: acq.filter((e) => e.exec === 1).length, refuses: mine.filter((e) => e.ev === "refuse").length, open: hs.filter((h) => h.to === null).length,
      wait: dist(acq.map((e) => e.waitMs ?? 0)), waited: acq.filter((e) => (e.waitMs ?? 0) >= 1000).length, released: rel.length, hold: dist(rel.map((e) => e.holdMs ?? 0)),
      maxConc: maxConcurrent(hs, lockEnd),
    };
  });
  const lockDays = evs.length ? Math.max(1 / 24, (lockEnd - Math.min(...evs.map((e) => e.ts))) / 86_400_000) : 0;
  return {
    samples: kept.length, dropped, from, to, partial: kept.filter((s) => s.partial.length > 0).length,
    maxGapS: gaps.length ? Math.max(...gaps) : 0, gaps60: gaps.filter((g) => g > 60).length, costMs: dist(kept.map((s) => s.costMs)), verdicts, pressure, kinds,
    sys: {
      swapUsedMB: dist(col((s) => s.swapUsedMB)), compressorMB: dist(col((s) => s.compressorMB)), freePct: dist(col((s) => s.freePct)), load: dist(col((s) => s.loadCenti / 100)),
      swapPct: dist(col((s) => (s.swapUsedMB !== null && s.swapTotalMB ? (100 * s.swapUsedMB) / s.swapTotalMB : null))),
    },
    ramMB: kept[0]?.ramMB ?? 0, swapTotalMB: kept.find((s) => s.swapTotalMB)?.swapTotalMB ?? 0,
    sim: { samples: simSamples, idleSamples, gbHours: gbH, idleGbHours: idleGbH }, serveMBh, heavyHeld,
    locks, simAcquires: evs.filter((e) => e.lock === "sim" && e.ev === "acquire").length, lockDays, orphans,
    lockFrom: evs.length ? Math.min(...evs.map((e) => e.ts)) : null, lockTo: evs.length ? lockEnd : null,
  };
}

const row = (cells: (string | number)[]): string => `| ${cells.join(" | ")} |`;
const table = (head: string[], rows: (string | number)[][]): string =>
  [row(head), row(head.map((h, i) => (i === 0 ? "---" : "---:"))), ...rows.map(row)].join("\n");
const f1 = (x: number): string => x.toFixed(1);
const sec = (ms: number): string => (ms / 1000).toFixed(ms >= 10_000 ? 0 : 1);
/** Window under which the note is a smoke sample (minutes): the 6 h that the limits section already uses. */
export const SMOKE_MIN = 360;

/** The design's section 5 (stage-0 measurements per stage): one row per metric with the value this window gives, or why none. */
function section5(r: Report, share: (n: number) => string): string {
  const k = r.kinds;
  const lake = r.locks.filter((l) => l.lock === "lake-slot");
  const lakeAcq = lake.reduce((a, l) => a + l.acquires, 0);
  const heavy = r.locks.filter((l) => l.lock === "heavy").reduce((a, l) => a + l.acquires, 0);
  const NC = "not collected";
  const rows: string[][] = [
    ["0", "Predicted peak charge, idle MB-hours reclaimable, requests that would be refused, replayed on the logs", NC, "-", "needs the replay of 3.5 days of logs; a follow-up of this task"],
    ["1a", "fwcore starts per day", NC, `fwcore processes present in ${k.fwcore.present} samples (${share(k.fwcore.present)}), p50 ${k.fwcore.n.p50}`, "a snapshot count, not a start count; starts need the spawn log"],
    ["1a", "`op` p50 latency against the 40 ms spawn", NC, "-", "needs the daemon (stage 1a) to time its calls"],
    ["1b", "Peak summed footprint of lean children", "sampler", `leanBuild ${k.leanBuild.footMB.max} MB max, ${k.leanBuild.n.max} processes max`, "per kind only, the leanServe servers are a separate row"],
    ["1b", "Lake builds outside a lease", "lake-slot events", `${lakeAcq} lake-slot acquire(s); leanBuild present in ${k.leanBuild.present} samples (${share(k.leanBuild.present)})`, "the exec form logs no hold interval, so a build outside a lease is not separated here"],
    ["1b", "Lake serve MB-hours idle", "sampler", `leanServe ${r.serveMBh.toFixed(1)} MB-hours in total`, "the idle split is not collected"],
    ["2", "Long-lived Node processes", "sampler", `node processes p50 ${k.node.n.p50}, p90 ${k.node.n.p90}, max ${k.node.n.max}`, "no process age is read, so \"long-lived\" is not separated"],
    ["2", "Hook start footprint", NC, "-", "needs a per-hook sample"],
    ["2", "Watch re-arm cold passes", NC, "-", "needs the watch log"],
    ["3", "Peak footprint during lands", "sampler and heavy-lock events", r.heavyHeld.samples ? `${r.heavyHeld.samples} sample(s) under a heavy-lock hold; peaks in the table below` : "no sample under a heavy-lock hold in this window", `${heavy} heavy-lock acquire(s)`],
    ["3", "Load p90", "sampler", `${f1(r.sys.load.p90)} (p50 ${f1(r.sys.load.p50)}, max ${f1(r.sys.load.max)})`, "1-minute load"],
    ["3", "`inc-land-load-flake` recurrences", NC, "-", "an incident count, not a machine reading"],
    ["4", "Idle Simulator GB-hours", "sampler and sim-lock events", `${r.sim.idleGbHours.toFixed(3)} idle of ${r.sim.gbHours.toFixed(3)} in total`, "the simulator kind is the launchd_sim subtree of a booted fw-* device; idle means no sim-lock held"],
    ["4", "Boots per day times boot time", "sim-lock events", `${r.simAcquires} sim-lock acquire(s) in ${r.lockDays.toFixed(2)} day(s)`, "boot time is not measured"],
    ["4", "Serena/MCP processes counted, idle alert", NC, "-", "these processes fall into `other`; no separate count"],
  ];
  return table(["stage", "design section 5 metric", "source", "value in this window", "note"], rows);
}

export function render(r: Report): string {
  const date = r.samples ? day(r.from) : "no data";
  const share = (n: number): string => (r.samples ? `${((100 * n) / r.samples).toFixed(1)} %` : "0 %");
  const pshare = (n: number): string => (r.pressure.n ? `${((100 * n) / r.pressure.n).toFixed(1)} %` : "0 %");
  const spanMin = r.samples ? (r.to - r.from) / 60_000 : 0;
  const smoke = spanMin < SMOKE_MIN;
  const span = spanMin.toFixed(spanMin < 10 ? 1 : 0);
  const lines: string[] = [];
  lines.push(
    smoke ? "# Resource baseline of the dev Mac, smoke sample (task sup-baseline)" : "# Resource baseline of the dev Mac (task sup-baseline)", "",
    `Status: MEASURED ${date} on the dev Mac (macOS, ${gb(r.ramMB)} GB RAM, ${gb(r.swapTotalMB)} GB swap); ${r.samples} samples, ${r.samples ? stamp(r.from) : "-"} to ${r.samples ? stamp(r.to) : "-"} (a span of ${span} min).`,
    smoke
      ? `This is a SMOKE SAMPLE, not first-day data: the span is ${span} min, under 6 h. It was taken by running the sampler (\`sampleOnce\`) by hand for a few minutes, to show that the sampler, the verdict and this generator work end to end. Its shares describe those minutes, which include this task's own checks and tests. The first-day tables are a follow-up.`
      : "These are the tables of the sampler's collection window. The conclusions (which jobs to move, which limits to set) are follow-ups, not claimed here.",
    "Collection starts when the watch process restarts on the landed code (the post-land routine): the watch that ran before the land has no sampler, so no sample before that restart exists.",
    "Every table below is generated from the local-only files `.fw-console/sup-samples.jsonl` and `.fw-console/locks.jsonl` by `apps/runner/src/sup-report.ts` (a TS stand-in; the verdict of each sample is the TS mirror of Lean's verdict (`resVerdict`), golden-checked); edit the generator, not this file.", "",
    "## What is measured", "",
    "- CONFIRMED (apps/runner/src/watch-collect.ts `sampleOnce`): every 20 s one `top -l 1 -stats pid,mem,cmprs`, `ps -A -o pid=,ppid=,comm=`, `sysctl -n vm.swapusage` and `memory_pressure -Q` are read and reduced to one line: per kind the process count and the footprint (MEM plus CMPRS) with its compressed part, plus swap used, compressor size, free memory, 1-min load, the cost of the sample and the verdict. The command line (`ps -o command`) is read only for the `lake`, `lean` and `launchd_sim` processes, to tell a build from a server and to find the Simulator device; it is not stored. No path or user name is stored.",
    "- CONFIRMED (lean/Fw/Obs/Health.lean, namespace `Res`): the kind of a process is decided by identity, not by name alone: the program name from a fixed table (`kindTable`), the first argument for `lake` (a `serve` is `leanServe`, anything else is `leanBuild`), the ancestry (a process under a booted `launchd_sim` of one of our `fw-*` Simulator devices is `simulator`; a Safari is `safari`-kind only under a `safaridriver` we started, and its WebKit helpers follow it) and the Simulator device name from its `device.plist`. Everything else is `other`, and `CoreSimulatorService`, system WebKit helpers and a Safari the user opened are `system` or `other`, not heavy. Heavy kinds are `leanBuild`, `chromium`, `simulator` and `webkit`. The verdict is `pressured` when swap use, the compressor or free memory trips its limit, else `busy` when a heavy kind runs or the 1-min load is at least 2.00, else `quiet`. Theorems: the verdict never lowers as pressure grows (`verdict_rank_mono`), `quiet` implies no heavy kind and a low load (`quiet_no_heavy`, `quiet_low_load`), and the background processes alone give `quiet` (`quiet_with_background`). The limits (swap 90 %, compressor 50 % of RAM, free 15 %, load 2.00) are first guesses, revised after the first day.",
    "- CONFIRMED (scripts/heavy-lock.mjs, scripts/lake-slot-lib.sh, scripts/sim-lock.sh): each lock appends an acquire line and a release line (heavy-lock also a refuse line) with the time, kind, the holder's pid and start time, the wait or the hold in ms; no path, no argument, no owner name. The exec form of `lake_slot` replaces the shell with its command and so can log the acquire only; its row has no hold (see Locks).", "",
    `Footprint is the \`top\` MEM column plus the CMPRS column per process (MEASURED: CMPRS is not a part of MEM; 6 of 620 rows of one \`top\` run had CMPRS above MEM, e.g. MEM 13 MB with CMPRS 73 MB). It is per process, so pages shared between processes (frameworks, the Lean runtime) can be counted in each. For that reason the tables give per-kind rows only and no total over kinds; read the rows as upper bounds of each kind's share and as comparable between kinds, not as additive.`, "",
    "## Samples", "",
    table(["measure", "value"], [
      ["samples kept", r.samples], ["dropped (another watcher sampled within 10 s)", r.dropped], ["samples with a missing reading (no verdict)", r.partial],
      ["longest gap between samples (s)", f1(r.maxGapS)], ["gaps over 60 s", r.gaps60],
      ["cost of one sample, p50 / p90 / max (s)", `${sec(r.costMs.p50)} / ${sec(r.costMs.p90)} / ${sec(r.costMs.max)}`]]), "",
    "## Verdict share", "",
    table(["verdict", "samples", "share"], (["quiet", "busy", "pressured", "unknown"] as const).map((v) => [v, r.verdicts[v], share(r.verdicts[v])])), "",
    "`unknown` is a sample with a missing reading. `quiet` is the share of time a measurement on this Mac would not have been disturbed by our own heavy work; any other share is the machine as it was, including everything else the user runs.", "",
    "### Which condition tripped `pressured`", "",
    table(["condition", "limit now", "samples tripped", `share of ${r.pressure.n} samples with every reading`], [
      ["swap used / swap total", `at least ${RES_PARAMS.swapPct} %`, r.pressure.swap, pshare(r.pressure.swap)],
      ["compressor / RAM", `at least ${RES_PARAMS.cmprsPct} %`, r.pressure.cmprs, pshare(r.pressure.cmprs)],
      ["free memory (`memory_pressure`)", `at most ${RES_PARAMS.freePct} %`, r.pressure.free, pshare(r.pressure.free)],
      ["pressured by swap alone", "-", r.pressure.swapOnly, pshare(r.pressure.swapOnly)],
      ["pressured by the compressor or free memory", "-", r.pressure.cmprsOrFree, pshare(r.pressure.cmprsOrFree)]]), "",
    "The swap ratio is of DYNAMIC swap: macOS adds swap files on demand, so used over total tends to sit near a fixed high ratio whatever the pressure, and `swapPct` is flagged for revision after the first day. `memory_pressure`'s system-wide free percentage is the pressure input to prefer; a row \"by swap alone\" above zero shows how much of `pressured` rests on the swap ratio only. The limits are the current `RES_PARAMS` (first guesses).", "",
    "## Footprint per kind", "",
    table(["kind", "samples present", "procs p50", "procs p90", "procs max", "footprint MB p50", "p90", "max", "of which compressed MB p50"],
      KINDS.map((k) => { const x = r.kinds[k]; return [k, `${x.present} (${share(x.present)})`, x.n.p50, x.n.p90, x.n.max, x.footMB.p50, x.footMB.p90, x.footMB.max, x.cmprsMB.p50]; })), "",
    "Footprint is MEM plus CMPRS; the last column is the CMPRS part. There is no total over kinds (shared pages can be counted twice).", "",
    "## Machine", "",
    table(["measure", "p50", "p90", "max"], [
      ["swap used (MB)", r.sys.swapUsedMB.p50, r.sys.swapUsedMB.p90, r.sys.swapUsedMB.max],
      ["swap used (% of total, dynamic swap)", f1(r.sys.swapPct.p50), f1(r.sys.swapPct.p90), f1(r.sys.swapPct.max)],
      ["compressor (MB)", r.sys.compressorMB.p50, r.sys.compressorMB.p90, r.sys.compressorMB.max],
      ["free memory (%)", r.sys.freePct.p50, r.sys.freePct.p90, r.sys.freePct.max],
      ["load, 1 min", f1(r.sys.load.p50), f1(r.sys.load.p90), f1(r.sys.load.max)]]), "",
    "Free memory is `memory_pressure`'s system-wide free percentage, so its p90 is the best and its p50 the typical case; the pressure limit trips at the low end.", "",
    "## Simulator", "",
    table(["measure", "value"], [
      ["samples with a simulator-kind process", r.sim.samples], ["of which with no sim-lock held", r.sim.idleSamples],
      ["simulator footprint, GB-hours", r.sim.gbHours.toFixed(3)], ["of which with no sim-lock held (idle), GB-hours", r.sim.idleGbHours.toFixed(3)]]), "",
    "The simulator kind is the whole `launchd_sim` subtree of a booted Simulator device of ours (named `fw-*`): the device's daemons, SpringBoard, MobileSafari and its WebKit helpers all count there. `CoreSimulatorService` and the system WebKit helpers that run for any app are `system`, not heavy, and a Safari the user opened is `other`. A booted Simulator is idle when the sim-lock is free.", "",
    "## Heavy-lock holds", "",
    r.heavyHeld.samples
      ? `${r.heavyHeld.samples} sample(s) fell inside a heavy-lock hold (a land, a check or a build). Largest footprint per kind among them:\n\n${table(["kind", "peak footprint MB"], KINDS.map((k) => [k, r.heavyHeld.peakFootMB[k]]))}`
      : "No sample fell inside a heavy-lock hold in this window.", "",
    "## Locks", "",
    r.locks.length
      ? table(["lock", "kind", "acquires", "of which exec (no release logged)", "refused", "still open", "waited >= 1 s", "wait ms p50", "p90", "max", "hold ms p50", "p90", "max", "most at once"],
        r.locks.map((l) => [l.lock, l.kind, l.acquires, l.exec, l.refuses, l.open, l.waited, l.wait.p50, l.wait.p90, l.wait.max,
          ...(l.released > 0 ? [l.hold.p50, l.hold.p90, l.hold.max] : ["not logged", "-", "-"]), l.maxConc > 0 ? l.maxConc : "-"]))
      : "No lock event was logged in this window.",
    "", r.lockFrom !== null ? `Lock events span ${stamp(r.lockFrom)} to ${stamp(r.lockTo ?? r.lockFrom)}; ${r.orphans} release(s) had no acquire in the window (the job began before logging).` : "",
    "`heavy` and `lake-slot` time stamps are in ms where the shell's `date` has `%N` (this Mac's does) and whole seconds otherwise; a `sim-lock` wait is counted in whole seconds (its poll loop sleeps 1 s). A release and an acquire at the same instant are counted as not overlapping, so \"most at once\" is a lower bound. The lake-slot pid is the calling shell's (`$$`), also inside a subshell, so two holders in one shell share a pid. `lake_slot` keeps `exec`: the shell becomes the command, so there is no point at which a release could be written. With events on it logs the acquire only (marked `exec`), and the row has no hold, no \"still open\" and no \"most at once\": the hold is not derived from the next acquire, because that gap includes idle time. The group form (`lake_slot_hold` and `lake_slot_release`) logs both lines.", "",
    "## Design section 5 mapping", "",
    "One row per metric of the design's section 5 (stage 0 measurements): the value this window gives, or why it gives none.", "",
    section5(r, share), "",
    "## Limits", "",
    smoke
      ? `- Smoke sample: ${span} min on one Mac, mostly this task's own work. Read it as a demonstration of the tables, not as a picture of a normal day or of the 3-day collection.`
      : "- One person's use of one Mac over the window above. Do not generalize to other days or machines.",
    "- Local-only lane: this Mac's resources cannot be measured on CI; the raw files stay under `.fw-console/` (gitignored).",
    "- The 20 s cadence misses anything shorter (a 5 s lake build can fall between two samples); `top` itself costs the time in the cost row, and a sample under heavy load may be late (see the gap rows).",
    "- Footprint per process can count shared pages twice, so only per-kind rows are given.",
    "- The pressure limits are first guesses and `swapPct` is on dynamic swap; both are revised after the first day.",
    "- A Safari counts only under a `safaridriver` we started; the WebKit helpers of a Safari the user opened are excluded by ancestry.",
    "- `node` processes are all `node`: a watcher of ours and someone's dev server both count there.", "");
  return lines.filter((l, i, a) => !(l === "" && a[i - 1] === "")).join("\n");
}

function arg(argv: string[], name: string): string | null {
  const i = argv.indexOf(name);
  return i >= 0 ? (argv[i + 1] ?? null) : null;
}
export function reportMain(argv: string[]): number {
  const dir = arg(argv, "--dir");
  const out = arg(argv, "--out");
  if (!dir || !out) { console.error("usage: sup-report.ts --dir <console dir> --out <note file> [--check]"); return 2; }
  const read = (f: string): string => (existsSync(join(dir, f)) ? readFileSync(join(dir, f), "utf8") : "");
  const text = render(reduce(parseJsonl(read("sup-samples.jsonl"), isSample), parseJsonl(read("locks.jsonl"), isLockEv)));
  if (argv.includes("--check")) {
    const same = existsSync(out) && readFileSync(out, "utf8") === text;
    console.error(same ? "sup-report: the note matches its data" : "sup-report: the note differs from what its data renders");
    return same ? 0 : 1;
  }
  writeFileSync(out, text);
  return 0;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(reportMain(process.argv.slice(2)));
