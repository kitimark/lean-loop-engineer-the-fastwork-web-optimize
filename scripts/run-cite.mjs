#!/usr/bin/env node
// Run-citation check (task run-cite-check): does each cited CI run carry the flag it is cited for?
//   node scripts/run-cite.mjs [--ledger <findings ledger.json>] [--note <file>]... [--json] [--refresh <run id>]...
// Docs: docs/team/tools/run-cite.md. The verdict is Lean's (`fwcore` op gate.runCite, lean/Fw/Gate/RunCite.lean).
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const top = join(dirname(fileURLToPath(import.meta.url)), "..");

export const PATTERNS = ["trajectory-chromium", "trajectory-playwright-webkit", "trajectory-apple", "chromium-counts-*",
  "gate-chromium-j0", "gate-playwright-webkit-j0", "webkit-sim-*"];

export const NO_ARTIFACT = "no trajectory, count, gate or webkit-sim artifact: expired, not finished, or not a gate run";
export const NOT_FOUND = "run not found";

const RUN_ID = /\b\d{10,12}\b/g;
const NOTE_CITE = /\b(\d{10,12})\s+([A-Za-z][A-Za-z0-9.]*:[A-Za-z0-9_@-]+)/g;

/** Citations of the ledger rows that name a flag: every run id in the row's evidence, cited for that flag. */
export function ledgerCites(ledger) {
  const out = [];
  for (const row of ledger.findings ?? []) {
    if (typeof row.flag !== "string" || typeof row.evidence !== "string") continue;
    for (const run of new Set(row.evidence.match(RUN_ID) ?? [])) out.push({ run, flag: row.flag, source: `ledger:${row.id ?? row.n}` });
  }
  return out;
}

/** Citations written `<run id> <part:variant>` in a note or handoff. */
export function noteCites(text, source) {
  const seen = new Set();
  const out = [];
  for (const m of text.matchAll(NOTE_CITE)) {
    const k = `${m[1]} ${m[2]}`;
    if (!seen.has(k)) { seen.add(k); out.push({ run: m[1], flag: m[2], source }); }
  }
  return out;
}

const readJson = (f) => JSON.parse(readFileSync(f, "utf8"));
const filesOf = (d, re) => readdirSync(d).filter((n) => re.test(n)).sort().map((n) => join(d, n));

/** The arms of one downloaded artifact directory: `{artifact, file, search}` per arm. */
export function armsOf(name, dir) {
  const arm = (file, search) => ({ artifact: name, file: file.slice(dir.length + 1), search });
  if (name.startsWith("trajectory-")) {
    return filesOf(dir, /^raw-.*\.json$/).flatMap((f) => (readJson(f).runs ?? []).map((r) => arm(f, r.search ?? "")));
  }
  if (name.startsWith("chromium-counts-")) {
    return filesOf(dir, /^counts\.json$/).map((f) => arm(f, readJson(f).meta?.search ?? ""));
  }
  if (name.startsWith("gate-")) {
    return filesOf(dir, /\.json$/).flatMap((f) => {
      const s = readJson(f).header?.flags?.search;
      return typeof s === "string" ? [arm(f, s)] : [];
    });
  }
  if (name.startsWith("webkit-sim-")) {
    return filesOf(dir, /-session-\d+\.json$/).map((f) => arm(f, readJson(f).site?.search ?? ""));
  }
  return [];
}

/** `gh run download` of the arm-bearing artifacts into `dir`: `{ok}` or `{status, stderr}`. */
export function ghDownload(run, dir) {
  const r = spawnSync("gh", ["run", "download", run, ...PATTERNS.flatMap((p) => ["-p", p]), "-D", dir], { encoding: "utf8" });
  return r.status === 0 ? { ok: true } : { ok: false, status: r.status ?? r.signal, stderr: r.stderr ?? "" };
}

/** The facts of one run from a fresh download; throws on a gh failure that is not a missing artifact or run. */
export function fetchFacts(run, download = ghDownload) {
  const dir = mkdtempSync(join(tmpdir(), "run-cite-"));
  try {
    const r = download(run, dir);
    if (!r.ok) {
      if (/no valid artifacts found/i.test(r.stderr)) return { run, missing: NO_ARTIFACT };
      if (/HTTP 404|could not find any workflow run|not found/i.test(r.stderr)) return { run, missing: NOT_FOUND };
      throw new Error(`gh run download ${run} failed (${r.status}), not retried: ${r.stderr.trim()}`);
    }
    const arms = readdirSync(dir).sort().flatMap((n) => armsOf(n, join(dir, n)));
    return arms.length ? { run, arms } : { run, missing: NO_ARTIFACT };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export const defaultCache = () => process.env.FW_RUN_CITE_CACHE ?? join(top, ".cache/run-cite/runs.json");

export function loadCache(file) {
  return existsSync(file) ? readJson(file) : {};
}

export function saveCache(file, cache) {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(cache, null, 1) + "\n");
}

/** Facts for every run, from the cache or one download each (saved after each one, so an abort keeps what was read). */
export function gatherFacts(runs, cacheFile, { download = ghDownload, refresh = [] } = {}) {
  const cache = loadCache(cacheFile);
  for (const r of refresh) delete cache[r];
  let fetched = 0;
  for (const run of runs) {
    if (cache[run]) continue;
    cache[run] = fetchFacts(run, download);
    fetched++;
    saveCache(cacheFile, cache);
  }
  return { facts: runs.map((r) => cache[r]), fetched };
}

/** The fwcore request of `gate.runCite`. */
export function request(facts, cites) {
  return {
    op: "gate.runCite",
    runs: facts.map((f) => (f.arms ? { run: f.run, arms: f.arms.map((a) => a.search) } : { run: f.run, missing: f.missing })),
    cites: cites.map(({ run, flag }) => ({ run, flag })),
  };
}

/** One request to fwcore, one reply; an `error` reply or a failed run throws. */
export function coreCall(bin) {
  if (!existsSync(bin)) throw new Error(`fwcore not built: cd lean && lake build (${bin})`);
  return (req) => {
    const r = spawnSync(bin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", encoding: "utf8", maxBuffer: 1 << 30 });
    if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${r.stderr}`);
    const { id: _id, ...rest } = JSON.parse(r.stdout.split("\n")[0]);
    if (typeof rest.error === "string") throw new Error(`fwcore ${req.op}: ${rest.error}`);
    return rest;
  };
}

/** The verdict line of one citation. */
export function lineOf(cite, v) {
  const tail = v.verdict === "mismatch" ? `carried: ${v.carried.length ? v.carried.join(", ") : "(no flag)"}` : v.verdict === "unknown" ? v.why : "";
  return `${v.verdict.padEnd(8)} ${cite.run} ${cite.flag}  [${cite.source}]${tail ? `  ${tail}` : ""}`;
}

/** Exit 0: no mismatch; 1: a mismatch; 2: usage or a failure. */
export function cli(argv, { core, cacheFile = defaultCache(), download = ghDownload, log = console.log } = {}) {
  let ledger = null;
  const notes = [];
  const refresh = [];
  let json = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--ledger") ledger = argv[++i];
    else if (a === "--note") notes.push(argv[++i]);
    else if (a === "--refresh") refresh.push(argv[++i]);
    else if (a === "--json") json = true;
    else { console.error(`run-cite: unknown argument ${a}`); return 2; }
  }
  if (!ledger && !notes.length) ledger = join(top, "research/findings/ledger.json");
  const cites = [
    ...(ledger ? ledgerCites(readJson(ledger)) : []),
    ...notes.flatMap((n) => noteCites(readFileSync(n, "utf8"), n)),
  ];
  const runs = [...new Set(cites.map((c) => c.run))];
  const { facts, fetched } = gatherFacts(runs, cacheFile, { download, refresh });
  const { verdicts } = core(request(facts, cites));
  const rows = cites.map((c, i) => ({ ...c, ...verdicts[i] }));
  if (json) log(JSON.stringify(rows));
  else {
    for (const [i, c] of cites.entries()) log(lineOf(c, verdicts[i]));
    const n = (k) => rows.filter((r) => r.verdict === k).length;
    log(`run-cite: ${cites.length} citations of ${runs.length} runs (${fetched} downloaded): match ${n("match")}, mismatch ${n("mismatch")}, unknown ${n("unknown")}`);
  }
  return rows.some((r) => r.verdict === "mismatch") ? 1 : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = cli(process.argv.slice(2), { core: coreCall(process.env.FW_CORE_BIN ?? join(top, "lean/.lake/build/bin/fwcore")) });
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    process.exitCode = 2;
  }
}
