// The first-day tables of the resource baseline (task sup-baseline): reduces <console dir>/sup-samples.jsonl (the 20 s sampler,
// watch-collect.ts `sampleOnce`) and <console dir>/locks.jsonl (acquire/release events of heavy-lock.mjs, lake-slot-lib.sh and
// sim-lock.sh) into research/notes/2026/10-2x-sup-baseline.md.
//   node apps/runner/src/sup-report.ts --dir <console dir> --out <note file> [--check]
// TS STAND-IN (reducer and renderer, no decision logic: the verdict of a sample is Lean's, Fw.Obs.Health.Res). The raw files are
// local-only (.fw-console/ is gitignored); the note keeps only the reduced tables, no command, path or other user's name.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { KindUse, ProcKind, SupSample } from "./watch-collect.ts";

export const KINDS: readonly ProcKind[] = ["lean", "fwcore", "node", "pnpm", "chromium", "simulator", "webkit", "other"];
export interface LockEv { ts: number; lock: string; ev: string; kind: string; pid: number; start: number; slot?: number; waitMs?: number; holdMs?: number }

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
 *  a release with no acquire (it began before the collection) is counted in `orphans`. */
export function pairHolds(evs: LockEv[]): { holds: Hold[]; orphans: number } {
  const open = new Map<string, Hold[]>();
  const holds: Hold[] = [];
  let orphans = 0;
  for (const e of [...evs].sort((a, b) => a.ts - b.ts)) {
    const key = `${e.lock}/${e.pid}/${e.start}`;
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

export interface Report {
  samples: number; dropped: number; from: number; to: number; partial: number; maxGapS: number; gaps60: number; costMs: { p50: number; p90: number; max: number };
  verdicts: Record<"quiet" | "busy" | "pressured" | "unknown", number>;
  kinds: Record<ProcKind, { n: ReturnType<typeof dist>; memMB: ReturnType<typeof dist>; cmprsMB: ReturnType<typeof dist>; present: number }>;
  sum: { memMB: ReturnType<typeof dist> };
  sys: { swapUsedMB: ReturnType<typeof dist>; swapPct: ReturnType<typeof dist>; compressorMB: ReturnType<typeof dist>; freePct: ReturnType<typeof dist>; load: ReturnType<typeof dist> };
  ramMB: number; swapTotalMB: number;
  sim: { samples: number; idleSamples: number; gbHours: number; idleGbHours: number };
  locks: { lock: string; kind: string; acquires: number; refuses: number; open: number; wait: ReturnType<typeof dist>; waited: number; hold: ReturnType<typeof dist>; maxConc: number }[];
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
  const kinds = Object.fromEntries(KINDS.map((k) => {
    const u = (s: SupSample): KindUse => s.kinds[k];
    return [k, { n: dist(kept.map((s) => u(s).n)), memMB: dist(kept.map((s) => u(s).memMB)), cmprsMB: dist(kept.map((s) => u(s).cmprsMB)), present: kept.filter((s) => u(s).n > 0).length }];
  })) as Report["kinds"];
  const { holds, orphans } = pairHolds(evs);
  const simHolds = holds.filter((h) => h.lock === "sim");
  const heldAt = (t: number): boolean => simHolds.some((h) => h.from <= t && t <= (h.to ?? to));
  const weight = (i: number): number => Math.min((kept[i + 1]?.ts ?? kept[i]!.ts + 20_000) - kept[i]!.ts, 60_000) / 3_600_000;
  let simSamples = 0; let idleSamples = 0; let gbH = 0; let idleGbH = 0;
  kept.forEach((s, i) => {
    if (s.kinds.simulator.n === 0) return;
    simSamples++;
    const g = (s.kinds.simulator.memMB / 1024) * weight(i);
    gbH += g;
    if (!heldAt(s.ts)) { idleSamples++; idleGbH += g; }
  });
  const keys = [...new Set(evs.map((e) => `${e.lock}/${e.kind}`))].sort();
  const locks = keys.map((key) => {
    const [lock, kind] = key.split("/") as [string, string];
    const mine = evs.filter((e) => e.lock === lock && e.kind === kind);
    const hs = holds.filter((h) => h.lock === lock && h.kind === kind);
    const waits = mine.filter((e) => e.ev === "acquire").map((e) => e.waitMs ?? 0);
    return {
      lock, kind, acquires: waits.length, refuses: mine.filter((e) => e.ev === "refuse").length, open: hs.filter((h) => h.to === null).length,
      wait: dist(waits), waited: waits.filter((w) => w >= 1000).length, hold: dist(mine.filter((e) => e.ev === "release").map((e) => e.holdMs ?? 0)),
      maxConc: maxConcurrent(hs, evs.length ? Math.max(...evs.map((e) => e.ts)) : 0),
    };
  });
  return {
    samples: kept.length, dropped, from, to, partial: kept.filter((s) => s.partial.length > 0).length,
    maxGapS: gaps.length ? Math.max(...gaps) : 0, gaps60: gaps.filter((g) => g > 60).length, costMs: dist(kept.map((s) => s.costMs)), verdicts, kinds,
    sum: { memMB: dist(kept.map((s) => KINDS.reduce((a, k) => a + s.kinds[k].memMB, 0))) },
    sys: {
      swapUsedMB: dist(col((s) => s.swapUsedMB)), compressorMB: dist(col((s) => s.compressorMB)), freePct: dist(col((s) => s.freePct)), load: dist(col((s) => s.loadCenti / 100)),
      swapPct: dist(col((s) => (s.swapUsedMB !== null && s.swapTotalMB ? (100 * s.swapUsedMB) / s.swapTotalMB : null))),
    },
    ramMB: kept[0]?.ramMB ?? 0, swapTotalMB: kept.find((s) => s.swapTotalMB)?.swapTotalMB ?? 0,
    sim: { samples: simSamples, idleSamples, gbHours: gbH, idleGbHours: idleGbH },
    locks, orphans, lockFrom: evs.length ? Math.min(...evs.map((e) => e.ts)) : null, lockTo: evs.length ? Math.max(...evs.map((e) => e.ts)) : null,
  };
}

const row = (cells: (string | number)[]): string => `| ${cells.join(" | ")} |`;
const table = (head: string[], rows: (string | number)[][]): string =>
  [row(head), row(head.map((h, i) => (i === 0 ? "---" : "---:"))), ...rows.map(row)].join("\n");
const f1 = (x: number): string => x.toFixed(1);
const sec = (ms: number): string => (ms / 1000).toFixed(ms >= 10_000 ? 0 : 1);

export function render(r: Report): string {
  const date = r.samples ? day(r.from) : "no data";
  const share = (n: number): string => (r.samples ? `${((100 * n) / r.samples).toFixed(1)} %` : "0 %");
  const lines: string[] = [];
  lines.push(
    "# Resource baseline of the dev Mac, first-day tables (task sup-baseline)", "",
    `Status: MEASURED ${date} on the dev Mac (macOS, ${gb(r.ramMB)} GB RAM, ${gb(r.swapTotalMB)} GB swap); ${r.samples} samples, ${r.samples ? stamp(r.from) : "-"} to ${r.samples ? stamp(r.to) : "-"}.`,
    "These are FIRST-DAY numbers. The 3-day collection continues in the running watch process; its full tables and the conclusions (which jobs to move, which limits to set) are follow-ups, not claimed here.",
    "Every table below is generated from the local-only files `.fw-console/sup-samples.jsonl` and `.fw-console/locks.jsonl` by `apps/runner/src/sup-report.ts` (a TS stand-in; the verdict of each sample is Lean's); edit the generator, not this file.", "",
    "## What is measured", "",
    "- CONFIRMED (apps/runner/src/watch-collect.ts `sampleOnce`): every 20 s one `top -l 1 -stats pid,mem,cmprs`, `ps -A -o pid=,comm=`, `sysctl -n vm.swapusage` and `memory_pressure -Q` are read and reduced to one line: per kind the process count, the footprint and its compressed part, plus swap used, compressor size, free memory, 1-min load, the cost of the sample and the Lean verdict. No command line, path or user name is stored.",
    "- CONFIRMED (lean/Fw/Obs/Health.lean, namespace `Res`): the kind of a process comes from the basename of its executable against a fixed allowlist (`kindTable`; every unlisted name is `other`); the verdict is `pressured` when swap use, the compressor or free memory trips its limit, else `busy` when a heavy kind (lean, chromium, simulator, webkit) runs or the 1-min load is at least 2.00, else `quiet`. Theorems: the verdict never lowers as pressure grows (`verdict_rank_mono`), and a quiet sample has no process of a heavy kind (`quiet_no_heavy`). The limits (swap 90 %, compressor 50 % of RAM, free 15 %, load 2.00) are first guesses, revisable after the 3 days.",
    "- CONFIRMED (scripts/heavy-lock.mjs, scripts/lake-slot-lib.sh, scripts/sim-lock.sh): each lock appends an acquire and a release line (heavy-lock also a refuse line) with the time, kind, the holder's pid and start time, the wait or the hold in ms; no path, no argument, no owner name.", "",
    "Footprint is the `top` MEM column per process. It counts the process's own compressed pages (CMPRS is the part of MEM that is compressed), so it does not under-report idle processes the way `ps` RSS does. It is per process: pages shared between processes (frameworks, the Lean runtime) are counted in each, so a sum over processes can exceed the machine's real use. Read the per-kind figures as upper bounds of that kind's share, and the rows as comparable between kinds, not as additive.", "",
    "## Samples", "",
    table(["measure", "value"], [
      ["samples kept", r.samples], ["dropped (another watcher sampled within 10 s)", r.dropped], ["samples with a missing reading (no verdict)", r.partial],
      ["longest gap between samples (s)", f1(r.maxGapS)], ["gaps over 60 s", r.gaps60],
      ["cost of one sample, p50 / p90 / max (s)", `${sec(r.costMs.p50)} / ${sec(r.costMs.p90)} / ${sec(r.costMs.max)}`]]), "",
    "## Verdict share", "",
    table(["verdict", "samples", "share"], (["quiet", "busy", "pressured", "unknown"] as const).map((v) => [v, r.verdicts[v], share(r.verdicts[v])])), "",
    "`unknown` is a sample with a missing reading. `quiet` is the share of time a measurement on this Mac would not have been disturbed by our own heavy work; any other share is the machine as it was, including everything else the user runs.", "",
    "## Footprint per kind", "",
    table(["kind", "samples present", "procs p50", "procs p90", "procs max", "footprint MB p50", "p90", "max", "of which compressed MB p50"],
      KINDS.map((k) => { const x = r.kinds[k]; return [k, `${x.present} (${share(x.present)})`, x.n.p50, x.n.p90, x.n.max, x.memMB.p50, x.memMB.p90, x.memMB.max, x.cmprsMB.p50]; })), "",
    `All kinds together: footprint ${r.sum.memMB.p50} MB p50, ${r.sum.memMB.p90} MB p90, ${r.sum.memMB.max} MB max (a sum of per-process figures; see the shared-page limit above).` +
      (r.ramMB > 0 && r.sum.memMB.max > r.ramMB ? ` The largest sum (${gb(r.sum.memMB.max)} GB) exceeds the ${gb(r.ramMB)} GB of RAM, which shows the double counting: only the per-kind rows and their changes are meaningful, not their total.` : ""), "",
    "## Machine", "",
    table(["measure", "p50", "p90", "max"], [
      ["swap used (MB)", r.sys.swapUsedMB.p50, r.sys.swapUsedMB.p90, r.sys.swapUsedMB.max],
      ["swap used (% of total)", f1(r.sys.swapPct.p50), f1(r.sys.swapPct.p90), f1(r.sys.swapPct.max)],
      ["compressor (MB)", r.sys.compressorMB.p50, r.sys.compressorMB.p90, r.sys.compressorMB.max],
      ["free memory (%)", r.sys.freePct.p50, r.sys.freePct.p90, r.sys.freePct.max],
      ["load, 1 min", f1(r.sys.load.p50), f1(r.sys.load.p90), f1(r.sys.load.max)]]), "",
    "Free memory is `memory_pressure`'s system-wide free percentage, so its p90 is the best and its p50 the typical case; the pressure limit trips at the low end.", "",
    "## Simulator", "",
    table(["measure", "value"], [
      ["samples with a simulator-kind process", r.sim.samples], ["of which with no sim-lock held", r.sim.idleSamples],
      ["simulator footprint, GB-hours", r.sim.gbHours.toFixed(2)], ["of which with no sim-lock held (idle), GB-hours", r.sim.idleGbHours.toFixed(2)]]), "",
    "The simulator kind includes `MobileSafari`, `SpringBoard` and the CoreSimulator service. The Simulator's WebKit helpers carry the same names as Safari's (`com.apple.WebKit.*`), so they count under `webkit`, and a Safari the user opens counts there too: `webkit` cannot tell the two apart. A booted Simulator is idle when the sim-lock is free.", "",
    "## Locks", "",
    r.locks.length
      ? table(["lock", "kind", "acquires", "refused", "still open", "waited >= 1 s", "wait ms p50", "p90", "max", "hold ms p50", "p90", "max", "most at once"],
        r.locks.map((l) => [l.lock, l.kind, l.acquires, l.refuses, l.open, l.waited, l.wait.p50, l.wait.p90, l.wait.max, l.hold.p50, l.hold.p90, l.hold.max, l.maxConc]))
      : "No lock event was logged in this window.",
    "", r.lockFrom !== null ? `Lock events span ${stamp(r.lockFrom)} to ${stamp(r.lockTo ?? r.lockFrom)}; ${r.orphans} release(s) had no acquire in the window (the job began before logging).` : "",
    "`lake-slot` and `sim-lock` time stamps are whole seconds (macOS `date` has no `%N`), so their waits and holds are rounded to seconds and a release and an acquire in one second may count as overlapping or not; \"most at once\" is a lower bound. `heavy` is in ms. The lake-slot pid is the calling shell's (`$$`), also inside a subshell, so two holders in one shell share a pid. With events on, `lake_slot` runs its command as a child instead of `exec`-ing it, so the shell stays alive for the build's duration; a wrapper killed by a signal logs no release (the hold shows as \"still open\") while its child keeps the slot.", "",
    "## Limits", "",
    "- First-day data only: one day of one person's use of one Mac. Do not generalize to other days or machines; the 3 days decide.",
    "- Local-only lane: this Mac's resources cannot be measured on CI; the raw files stay under `.fw-console/` (gitignored).",
    "- The 20 s cadence misses anything shorter (a 5 s lake build can fall between two samples); `top` itself costs the time in the cost row, and a sample under heavy load may be late (see the gap rows).",
    "- Kinds are by program name, so a `node` that is our watcher and a `node` that is someone's dev server both count as `node`.", "");
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
