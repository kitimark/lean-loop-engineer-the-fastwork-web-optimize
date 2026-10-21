// Renders the tables of research/notes/2026/10-21-warmup-costs.md from results.json (written by measure.mjs).
//   node render.mjs          rewrites the block between the GENERATED markers in the note
//   node render.mjs --check  exits 1 when the block in the note differs from the render (a hand edit or a stale table)
// The grace rule constants below are the INPUT proposed for Fw.Sup (docs in the note); the Lean rule is sup-model's.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const note = join(here, "..", "10-21-warmup-costs.md");
const res = JSON.parse(readFileSync(join(here, "results.json"), "utf8"));
const K = 10, GMIN_S = 60, GMAX_S = 1800; // grace = clamp(K x cold, GMIN, GMAX), seconds

const q = (v, p) => { const s = [...v].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)]; };
const sec = (ms) => (ms / 1000).toFixed(ms < 10000 ? 2 : 1);
const range = (v, f = (x) => x) => (v.length ? `${f(Math.min(...v))} to ${f(Math.max(...v))}` : "-");
const row = (...c) => `| ${c.join(" | ")} |`;
const tab = (head, rows) => [row(...head), row(...head.map(() => "---")), ...rows.map((r) => row(...r))].join("\n");
const day = (s) => s.slice(0, 10);
const K_ = res.kinds;
const loadFree = (s) => `${s.load1} / ${s.freeMB} / ${s.availMB}`;
const out = [];

// ---- per-kind sample tables ----
const cold = {}; // kind -> { label, ms (cold cost used), basis, footMB }
if (K_.lsp) {
  const L = K_.lsp, ok = L.samples.filter((s) => s.ok);
  out.push(`### lake serve to first diagnostics\n\nCommand: \`${L.command}\`. Measured ${day(L.samples[0].at)}, ${L.samples.length} fresh servers, \`${L.file}\` (${L.lines} lines).\n`);
  out.push(tab(["run", "initialize ms", "first diagnostics ms", "file done ms", "server tree footprint MB", "load1 / free MB / avail MB"],
    L.samples.map((s) => [s.n, s.initializeMs, s.firstDiagMs, s.fileDoneMs, s.footprintMB, loadFree(s)])));
  const fd = ok.map((s) => s.fileDoneMs);
  cold.lsp = { label: "lake serve (to file done)", ms: Math.max(...fd), basis: `max of ${ok.length} ok runs`, footMB: Math.max(...ok.map((s) => s.footprintMB)) };
}
if (K_.sim) {
  const S = K_.sim;
  out.push(`\n### Simulator boot and shutdown\n\nCommand: \`${S.command}\`. Measured ${day(S.samples[0].at)}, ${S.samples.length} devices created and deleted by the run (${S.leftoverDevices} left over), ${S.runtime}, ${S.device}.\n`);
  out.push(tab(["run", "create ms", "first boot ready ms", "shutdown ms", "reboot ready ms", "shutdown ms (2nd)", "delete ms", "sim tree footprint MB (1st / 2nd boot)", "load1 / free MB / avail MB"],
    S.samples.map((s) => [s.n, s.createMs, s.firstBootReadyMs, s.shutdownMs, s.rebootReadyMs, s.shutdown2Ms, s.deleteMs, `${s.firstBootFootprintMB} / ${s.rebootFootprintMB}`, loadFree(s)])));
  const rb = S.samples.map((s) => s.rebootReadyMs), sd = [...S.samples.map((s) => s.shutdownMs), ...S.samples.map((s) => s.shutdown2Ms)];
  cold.sim = { label: "Simulator (reboot ready + shutdown)", ms: Math.max(...rb) + Math.max(...sd), basis: `max reboot-to-ready + max shutdown of ${S.samples.length} runs`, footMB: Math.max(...S.samples.map((s) => Math.max(s.firstBootFootprintMB, s.rebootFootprintMB))) };
}
if (K_.fwcore) {
  const F = K_.fwcore, t = F.spawnSamples.map((s) => s.ms);
  out.push(`\n### fwcore start\n\nCommand: \`${F.command}\`. Measured ${day(F.spawnSamples[0].at)}, binary ${F.binaryMB} MB.\n`);
  out.push(tab(["run", "spawn to reply ms", "exit", "load1 / free MB / avail MB"], F.spawnSamples.map((s) => [s.n, s.ms, s.status, loadFree(s)])));
  out.push("\n" + tab(["run", "real ms (time -l)", "max RSS MB", "peak footprint MB", "load1 / free MB / avail MB"], F.rssSamples.map((s) => [s.n, s.realMs, s.maxRssMB, s.peakFootprintMB, loadFree(s)])));
  cold.fwcore = { label: "fwcore start", ms: Math.max(...t), basis: `max of ${t.length} runs`, footMB: Math.max(...F.rssSamples.map((s) => s.peakFootprintMB)) };
}
if (K_.vitest) {
  const V = K_.vitest;
  out.push(`\n### fwcore starts inside a test run\n\nCommand: \`${V.command}\`. Measured ${day(V.samples[0].at)}. The file runs ${V.testsPassed} tests and starts fwcore ${V.fwcoreStarts} times (counting wrapper, separate untimed run).\n`);
  out.push(tab(["run", "process wall ms", "vitest duration ms", "exit", "load1 / free MB / avail MB"], V.samples.map((s) => [s.n, s.wallMs, s.vitestDurationMs, s.status, loadFree(s)])));
}
if (K_.lakehist) {
  const H = K_.lakehist, f = H.series, qs = (x) => [x.n, sec(x.p50), sec(x.p90), sec(x.p99), sec(x.max)];
  out.push(`\n### longest lake build (history)\n\nSource: \`${H.command}\`. Window ${day(H.from)} to ${day(H.to)} (read ${day(H.at)}). Nearest-rank quantiles, seconds.\n`);
  out.push(tab(["series", "n", "p50 s", "p90 s", "p99 s", "max s"], [
    ["all `lake build` stages", ...qs(f.all)], ["exit 0", ...qs(f.exit0)], ["exit 0, load1 < 10", ...qs(f.exit0_load_lt10)], ["exit 0, load1 >= 10", ...qs(f.exit0_load_ge10)],
    ["exit 0, under 2 s (no module rebuilt)", ...qs(f.exit0_noop_lt2s)], ["exit 0, 2 s or more (a rebuild)", ...qs(f.exit0_real_ge2s)],
    ["bench: solo build, plain", ...qs(f.bench_solo_build_plain)], ["bench: clean fwcore-build, plain", ...qs(f.bench_clean_fwcore_build_plain)]]));
  cold.lakehist = { label: "lake build (rebuild, p99)", ms: f.exit0_real_ge2s.p99, basis: `p99 of ${f.exit0_real_ge2s.n} rebuilds of 2 s or more`, footMB: null };
}

// ---- summary and grace ----
const sum = [], grace = [];
for (const k of ["lsp", "sim", "fwcore", "lakehist"]) {
  const c = cold[k]; if (!c) continue;
  const g = Math.min(GMAX_S, Math.max(GMIN_S, Math.round((K * c.ms) / 1000)));
  sum.push([c.label, sec(c.ms), c.basis, c.footMB ?? "-"]);
  grace.push([c.label, sec(c.ms), `${K} x ${sec(c.ms)} = ${(K * c.ms / 1000).toFixed(0)}`, g]);
}
const head = [`## Tables (generated from results.json by render.mjs; do not edit)\n`,
  `### Cold-start cost per kind\n`, tab(["kind", "cold cost s", "basis", "footprint MB"], sum), `\n### Proposed idle grace per kind (rule: grace = clamp(${K} x cold, ${GMIN_S} s, ${GMAX_S} s))\n`,
  tab(["kind", "cold cost s", "k x cold s", "grace s"], grace), "\n"];
const body = [...head, ...out].join("\n");

const BEGIN = "<!-- GENERATED:tables -->", END = "<!-- /GENERATED:tables -->";
const txt = readFileSync(note, "utf8");
const a = txt.indexOf(BEGIN), b = txt.indexOf(END);
if (a < 0 || b < 0) { console.error("markers missing in the note"); process.exit(2); }
const next = txt.slice(0, a + BEGIN.length) + "\n" + body + "\n" + txt.slice(b);
if (process.argv.includes("--check")) { if (next !== txt) { console.error("render --check: the note's tables differ from results.json"); process.exit(1); } console.log("render --check: ok"); }
else { writeFileSync(note, next); console.log("render: wrote the tables"); }
