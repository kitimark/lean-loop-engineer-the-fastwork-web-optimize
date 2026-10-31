import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { parseSamples } from "../../../../apps/runner/src/watch-collect.ts";
const [fwcore, timings] = process.argv.slice(2);
const lines = readFileSync(timings, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const FAM = [["fw land", "dry total"], ["fw", "land dry"], ["fw", "slot run land pnpm fw land dry"]];
const famOf = (o) => (o.host === "local" ? FAM.findIndex(([t, s]) => o.tool === t && o.step.startsWith(s)) : -1);
const unknown = new Set();
const idOf = (step) => {
  const s = step.replace(/^dry /, "");
  if (s.includes("land-inputs.test.ts")) return "reads-scan";
  if (s.includes("scripts/ci-paths.mjs")) return "lint:ciPaths";
  if (s.includes("part-footprint")) return "lint:footprint";
  if (s.includes("axiom-check.sh")) return "lint:axioms";
  if (s.includes("fwcore-build.sh")) return "fwcore-build";
  if (s.includes("check-workflows.sh")) return "workflow-lint";
  if (s.includes("compose.test.ts")) return "console-api:compose";
  if (s.includes("land-overflow-widths")) return "runner:overflow-widths";
  if (s.includes("ledger-merge.test.ts")) return "runner:ledger-notes";
  if (s === "claims lint") return null;
  unknown.add(s);
  return "other:" + s;
};
const totals = lines.filter((o) => o.host === "local" && o.tool === "fw land" && o.step.startsWith("dry total"));
const kids = lines.filter((o) => o.host === "local" && o.tool === "fw land" && o.step.startsWith("dry ") && !o.step.startsWith("dry total"));
const kidsByCommit = new Map();
for (const k of kids) {
  if (!kidsByCommit.has(k.commit)) kidsByCommit.set(k.commit, []);
  kidsByCommit.get(k.commit).push(k);
}
const setOfTotal = (t) => (kidsByCommit.get(t.commit) ?? []).filter((k) => k.startMs >= t.startMs - 5 && k.startMs <= t.startMs + t.durMs + 50).map((k) => idOf(k.step)).filter((x) => x !== null);
const rows = lines.filter((o) => famOf(o) >= 0);
const before = [], after = [];
let noTotal = 0;
for (const o of rows) {
  before.push(JSON.stringify(o));
  const t = o.tool === "fw land" ? o : totals.find((x) => x.commit === o.commit && x.startMs >= o.startMs - 3000 && x.startMs <= o.startMs + o.durMs);
  if (!t) { noTotal++; after.push(JSON.stringify(o)); continue; }
  after.push(JSON.stringify({ ...o, set: setOfTotal(t) }));
}
const run = (texts) => {
  const samples = parseSamples(texts.join("\n"), 1e9);
  const r = spawnSync(fwcore, [], { input: JSON.stringify({ id: 0, op: "obs.timing", samples }) + "\n", encoding: "utf8", maxBuffer: 1 << 30 });
  const vs = JSON.parse(r.stdout.split("\n")[0]).verdicts.filter((v) => v.kind === "sample");
  return { samples, vs };
};
const B = run(before), A = run(after);
const famV = (v) => famOf({ host: "local", tool: v.tool, step: v.step });
const count = (R, f) => R.vs.filter((v) => v.code === "slow" && famV(v) === f).length;
const codes = (R) => { const m = {}; for (const v of R.vs) m[v.code] = (m[v.code] ?? 0) + 1; return m; };
console.log("rows", rows.length, "withoutTotal", noTotal, "unknown child steps", [...unknown]);
for (let f = 0; f < 3; f++) console.log("family", FAM[f].join("/"), "slow before", count(B, f), "after", count(A, f), "samples", B.vs.filter((v) => famV(v) === f).length);
console.log("slow all before", B.vs.filter((v) => v.code === "slow").length, "after", A.vs.filter((v) => v.code === "slow").length);
console.log("codes before", JSON.stringify(codes(B)), "after", JSON.stringify(codes(A)));
const pick = (R, startMs) => R.vs.filter((v) => R.samples[v.idx].startMs === startMs).map((v) => `${v.tool}|${v.step}|${v.code} n=${v.n} base=${v.baseline} dur=${v.durMs}`);
for (const [c, s] of [["0180811", 1793431500999], ["0058ef3", 1793436388545], ["001d247", 1793478536258]]) {
  console.log(c, s, "\n  before", pick(B, s), "\n  after ", pick(A, s));
}
const wk = A.samples.find((x) => x.startMs === 1793478536258 && x.step === "dry total lake");
console.log("work of 001d247 after:", JSON.stringify(wk?.work));

const day = (R) => { const m = {}; for (const v of R.vs) if (v.code === "slow" && famV(v) === 0) { const d = new Date(R.samples[v.idx].startMs).toISOString().slice(5, 10); m[d] = (m[d] ?? 0) + 1; } return JSON.stringify(m); };
console.log("fam0 slow per day before", day(B), "\nfam0 slow per day after ", day(A));
const durs = (R) => R.vs.filter((v) => v.code === "slow" && famV(v) === 0).map((v) => v.durMs).sort((a, b) => a - b);
const q = (a, p) => a[Math.floor((a.length - 1) * p)];
console.log("fam0 slow dur p10/p50/p90 before", q(durs(B), 0.1), q(durs(B), 0.5), q(durs(B), 0.9), "after", q(durs(A), 0.1), q(durs(A), 0.5), q(durs(A), 0.9));
console.log("fam0 slow with built>0 (mods != 0) before/after", B.vs.filter((v) => v.code === "slow" && famV(v) === 0 && B.samples[v.idx].work?.mods !== "0").length, A.vs.filter((v) => v.code === "slow" && famV(v) === 0 && A.samples[v.idx].work?.mods !== "0").length);
// Live-like replay: the watch judges the last SAMPLE_CAP (3000) rows of the whole file; reproduce that for each alert sample.
const withSet = (o) => {
  if (famOf(o) < 0) return JSON.stringify(o);
  const t = o.tool === "fw land" ? o : totals.find((x) => x.commit === o.commit && x.startMs >= o.startMs - 3000 && x.startMs <= o.startMs + o.durMs);
  return JSON.stringify(t ? { ...o, set: setOfTotal(t) } : o);
};
for (const [c, s] of [["0180811", 1793431500999], ["0058ef3", 1793436388545], ["001d247", 1793478536258]]) {
  const i = lines.findIndex((o) => o.startMs === s && o.tool === "fw land" && o.step.startsWith("dry total"));
  const slice = lines.slice(Math.max(0, i - 2999), i + 1);
  const rb = run(slice.map((o) => JSON.stringify(o))), ra = run(slice.map(withSet));
  console.log("live-like", c, "line", i + 1, "before", pick(rb, s), "after", pick(ra, s));
}
