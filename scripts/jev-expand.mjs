#!/usr/bin/env node
// Glue of the D1 file-context ablation (research/notes/2026/10-2x-jev-file-context-ablation.md). Lean decides
// (fwcore oracle.expandPaths, oracle.expand, oracle.paired, oracle.adopt); this file reads git blobs and the answer
// files and writes the datasets and results.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { datasetsDir, logPathFor, pickedRows, redactNames } from "../apps/runner/src/oracle.ts";
import { armAnswers, jevAnswers } from "../apps/runner/src/oracle-score.ts";
import { fwcoreCall } from "../packages/gh-budget/src/index.ts";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const SRC = "ecdc0787";
export const BLOB_MAX = 3e6;
export const OUT = join(REPO, "results", "jev-file-context-ablation");

export const readJsonl = (f) => readFileSync(f, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l));
const writeJsonl = (f, rows) => writeFileSync(f, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");

function gitOut(args) {
  try { return execFileSync("git", ["-C", REPO, ...args], { maxBuffer: 1 << 28, stdio: ["ignore", "pipe", "ignore"] }); }
  catch { return null; }
}

/** The text of `path` at `sha`, or null when it is no blob, too large or binary; with its blob id. */
export function blobAt(git, sha, path) {
  const id = git(["rev-parse", "--verify", "-q", `${sha}:${path}`])?.toString().trim() || null;
  if (!id || git(["cat-file", "-t", id])?.toString().trim() !== "blob") return { id: null, text: null };
  if (Number(git(["cat-file", "-s", id])) > BLOB_MAX) return { id, text: null };
  const buf = git(["cat-file", "blob", id]);
  if (!buf || buf.subarray(0, 8000).includes(0)) return { id, text: null };
  return { id, text: buf.toString("utf8") };
}

/** The last commit of `src` before the incident time `at` (committer date). */
export const pinOf = (git, src, at) => git(["rev-list", "-1", `--before=${at}`, src])?.toString().trim() || null;

/** The row of a dataset file with the expansion's `files` text; any other result leaves the row as it was. */
export function withFiles(row, result) {
  return result?.result === "expanded" ? { ...row, files: result.filesText } : row;
}

/** The texts and blob ids at `sha` of the paths `cfg` allows. */
function blobsOf(core, git, sha, cfg, row) {
  const blobs = {}, ids = {};
  for (const p of core({ op: "oracle.expandPaths", cfg, row }).paths.filter((x) => x.allowed)) {
    const b = blobAt(git, sha, p.path);
    blobs[p.path] = b.text;
    ids[p.path] = b.id;
  }
  return { blobs, ids };
}

/** One D1 row and each config's result: the safe config reads the files at the row's pin, the naive one at the dataset
commit `src`, as a reader who opens today's files would. */
export function expandOne(core, git, src, at, row) {
  const pick = { title: row.title, symptom: row.symptom, cause: row.cause };
  const pin = at ? pinOf(git, src, at) : null;
  const run = (cfg, sha) => {
    if (!sha) return { result: "same", files: [], ids: {} };
    const { blobs, ids } = blobsOf(core, git, sha, cfg, pick);
    return { ...core({ op: "oracle.expand", cfg, rowId: row.id, row: pick, blobs }), ids };
  };
  return { id: row.id, label: row.label, at: at ?? null, pin, src, safe: run("safe", pin), naive: run("naive", pin ? src : null) };
}

/** The committed record of one row: no file text, only paths, verdicts, sizes and blob ids. */
export function recordOf(x) {
  const strip = (r) => ({ result: r.result, ...(r.esc !== undefined ? { esc: r.esc } : {}),
    files: r.files.map((f) => ({ ...f, blob: r.ids[f.path] ?? null })) });
  return { id: x.id, label: x.label, at: x.at, pin: x.pin, safe: strip(x.safe), naive: strip(x.naive) };
}

/** The datasets: `d1-expand` gets the safe files on its expanded rows; `d1-naive` gets the naive files on the same rows. */
export function datasets(rows, results) {
  const by = new Map(results.map((x) => [x.id, x]));
  const expanded = (id) => by.get(id)?.safe.result === "expanded";
  return {
    expand: rows.map((r) => withFiles(r, by.get(r.id)?.safe)),
    naive: rows.map((r) => (expanded(r.id) ? withFiles(r, by.get(r.id).naive) : r)),
    ids: rows.filter((r) => expanded(r.id)).map((r) => r.id),
  };
}

function build(f) {
  const core = fwcoreCall(REPO);
  const dir = f.dir ?? datasetsDir(REPO);
  const src = f.src ?? SRC;
  const git = gitOut;
  const ledger = JSON.parse(git(["show", `${src}:docs/team/incidents/ledger.json`]).toString()).incidents;
  const at = new Map(ledger.map((i) => [i.id, i.at]));
  const rows = readJsonl(join(dir, "d1.jsonl"));
  const results = rows.map((r) => expandOne(core, git, src, at.get(r.id), r));
  const d = datasets(rows, results);
  writeJsonl(join(dir, "d1-expand.jsonl"), d.expand);
  writeJsonl(join(dir, "d1-naive.jsonl"), d.naive);
  const count = (k, v) => results.filter((x) => x[k].result === v).length;
  const summary = { src, rows: rows.length, pinned: results.filter((x) => x.pin).length,
    safe: { expanded: count("safe", "expanded"), refused: count("safe", "refused"), same: count("safe", "same") },
    naive: { expanded: d.ids.filter((i) => results.find((x) => x.id === i).naive.result === "expanded").length,
      refused: d.ids.filter((i) => results.find((x) => x.id === i).naive.result === "refused").length },
    dropped: droppedIds(results), expandedIds: d.ids };
  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, "inputs.json"), JSON.stringify({ ...summary, rows: results.map(recordOf) }, null, 1) + "\n");
  console.log(`jev-expand build: ${JSON.stringify({ ...summary, dropped: summary.dropped.length, expandedIds: d.ids.length })}`);
}

/** The expanded rows where a file was dropped for a vocabulary word. */
export const droppedIds = (results) => results.filter((x) => x.safe.result === "expanded" && x.safe.files.some((f) => f.verdict === "vocab"))
  .map((x) => x.id);

/** The paired requests of one arm: base and arm answers on the expanded rows, in both modes. */
export function pairedOf(core, question, replay, base, arm) {
  return Object.fromEntries(["strict", "renorm"].map((mode) =>
    [mode, core({ op: "oracle.paired", name: question, mode, replay, base, arm })]));
}

function paired(f) {
  const core = fwcoreCall(REPO);
  const dir = f.dir ?? datasetsDir(REPO);
  const inputs = JSON.parse(readFileSync(join(OUT, "inputs.json"), "utf8"));
  const ids = new Set(inputs.expandedIds);
  const names = redactNames(REPO);
  const mainLog = logPathFor(REPO);
  const pick = (set) => { const p = pickedRows(core, set, dir); if (typeof p === "string") throw new Error(p); return p; };
  const base = pick("d1"), x = pick("d1x"), n = pick("d1n");
  const replay = base.rows.filter((r) => ids.has(r.id)).map((r) => ({ id: r.id, label: r.label }));
  const only = (l) => l.filter((a) => ids.has(a.id));
  const jev = (p) => only(jevAnswers(core, p.question, names, p.rows, mainLog));
  const clean = (arm) => only(armAnswers(join(REPO, "results", "jev-arms-clean", `d1-${arm}.answers.jsonl`)));
  const mine = (arm) => { const file = join(OUT, `d1x-${arm}.answers.jsonl`); return existsSync(file) ? only(armAnswers(file)) : null; };
  const arms = { jev: [jev(base), jev(x)], "jev-naive": [jev(base), jev(n)] };
  for (const a of ["haiku", "sonnet"]) { const m = mine(a); if (m) arms[a] = [clean(a), m]; }
  const out = { question: base.question, rows: replay.length, answered: {}, arms: {} };
  for (const [a, [b, m]] of Object.entries(arms)) {
    out.answered[a] = { base: b.length, arm: m.length };
    out.arms[a] = pairedOf(core, base.question, replay, b, m);
  }
  const traced = existsSync(join(OUT, "traced.json")) ? JSON.parse(readFileSync(join(OUT, "traced.json"), "utf8")) : { rows: [] };
  const adoptArms = Object.entries(out.arms).filter(([a]) => a !== "jev-naive")
    .flatMap(([a, m]) => ["strict", "renorm"].map((mode) => ({ arm: `${a}/${mode}`, pairs: m[mode].pairs })));
  out.adopt = core({ op: "oracle.adopt", arms: adoptArms, dropped: inputs.dropped, traced: traced.rows.map((r) => r.id) });
  writeFileSync(join(OUT, "paired.json"), JSON.stringify(out, null, 1) + "\n");
  for (const [a, m] of Object.entries(out.arms)) for (const mode of ["strict", "renorm"]) {
    const r = m[mode];
    console.log(`${a} ${mode}: base ${r.baseRight}/${r.rows}, arm ${r.armRight}/${r.rows}, +${r.gains.length} -${r.losses.length} ` +
      `net ${r.net}, p ${r.p.num}/${r.p.den}`);
  }
  console.log(`adopt: ${out.adopt.adopt} (${out.adopt.reasons.length} reasons)`);
}

/** Per replay set: its rows and how many the answer log already answers, so the sends a run needs are known first. */
function status(f) {
  const core = fwcoreCall(REPO);
  const dir = f.dir ?? datasetsDir(REPO);
  const names = redactNames(REPO);
  for (const set of ["d1", "d1x", "d1n"]) {
    const p = pickedRows(core, set, dir);
    if (typeof p === "string") { console.log(`${set}: ${p}`); continue; }
    const a = jevAnswers(core, p.question, names, p.rows, logPathFor(REPO));
    console.log(`${set}: ${p.rows.length} rows, ${a.length} in the answer log, ${p.rows.length - a.length} to send`);
  }
}

/** The prompts of the expanded rows only, for scripts/jev-arms-clean.mjs. */
function prompts(f) {
  const ids = new Set(JSON.parse(readFileSync(join(OUT, "inputs.json"), "utf8")).expandedIds);
  const kept = readJsonl(f.in).filter((p) => ids.has(p.id));
  writeJsonl(f.out, kept);
  console.log(`jev-expand prompts: ${kept.length} of the expanded rows in ${f.out}`);
}

function flags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i += 2) o[argv[i].replace(/^--/, "")] = argv[i + 1];
  return o;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [sub, ...rest] = process.argv.slice(2);
  const f = flags(rest);
  if (sub === "build") build(f);
  else if (sub === "paired") paired(f);
  else if (sub === "status") status(f);
  else if (sub === "prompts" && f.in && f.out) prompts(f);
  else { console.error("usage: jev-expand.mjs build [--dir d] [--src sha] | paired [--dir d] | status [--dir d] | prompts --in <all.jsonl> --out <expanded.jsonl>"); process.exitCode = 64; }
}
