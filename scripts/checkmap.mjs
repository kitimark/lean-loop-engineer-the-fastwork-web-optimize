#!/usr/bin/env node
// Check map runner (task check-map-lean, mistake class c-late-check): run the static check of every changed file before
// commit or land. Which file gets which command, and what the exit codes mean, are Lean (`fwcore` ops.checkMap and
// ops.checkVerdict; rules and proofs in lean/Fw/Ops/CheckMap.lean, golden packages/contracts/golden/ops/checkmap.jsonl).
// This file only lists paths, asks Lean, runs the argv it gets and reports.
//
//   node scripts/checkmap.mjs --staged        the staged files (scripts/hooks/pre-commit)
//                                             --staged also sends the staged deletions; a deleted generator input runs the preset check.
//   node scripts/checkmap.mjs [--base <ref>]  files changed against <ref> (default: merge-base with main), committed,
//                                             staged, unstaged or untracked (scripts/check.sh)
//   node scripts/checkmap.mjs --all           every tracked file
//   node scripts/checkmap.mjs --tracked       every tracked file is mapped to a kind (no command runs)
//   node scripts/checkmap.mjs --paths a b ..  these paths
//   --strict: a missing tool (exit 127) or a missing fwcore fails instead of being skipped.
//   node scripts/checkmap.mjs file <json|jsonl|ts|graph|ledger|preset|tsc|workflow> <args..>   our own checks (argv emitted by Lean).
//                                             With --staged, modes json, jsonl, ts and graph read each file's index blob
//                                             (`:path`), and mode preset exports the index inputs of Fw.Preset.Gen into a
//                                             temp tree and runs its --check there. Mode tsc and the tools Lean names
//                                             directly (node --check, sh -n, lake, ruby, python3, swiftc) read the working tree.
// Exit 0 when the run passes (Lean runOk), 1 otherwise.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const git = (cwd, args) => {
  const r = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 64 << 20 });
  if (r.status !== 0) throw new Error(`git ${args.join(" ")}: ${(r.stderr ?? "").trim()}`);
  return r.stdout;
};
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const z = (s) => s.split("\0").filter(Boolean);

/** Ask Lean one op; the reply, or null when fwcore is missing, too old or refuses. */
export function askCore(bin, op, req) {
  if (!existsSync(bin)) return null;
  const r = spawnSync(bin, [], { input: JSON.stringify({ id: 1, op, ...req }) + "\n", encoding: "utf8", timeout: 60_000, maxBuffer: 64 << 20 });
  try {
    const m = JSON.parse((r.stdout ?? "").split("\n")[0] ?? "");
    return m && m.id === 1 && !m.error ? m : null;
  } catch { return null; }
}

/** The staged deletions (Lean decides which of them matter: ops.checkMap `deleted`). */
function listDeleted(top, args) {
  return args.includes("--staged") ? z(git(top, ["diff", "--cached", "--no-renames", "--name-only", "-z", "--diff-filter=D"])) : [];
}

/** The changed paths of a mode. */
function listPaths(top, args) {
  if (args.includes("--staged")) return z(git(top, ["diff", "--cached", "--no-renames", "--name-only", "-z", "--diff-filter=ACMR"]));
  if (args.includes("--all") || args.includes("--tracked")) return z(git(top, ["ls-files", "-z"]));
  const i = args.indexOf("--paths");
  if (i >= 0) return args.slice(i + 1).filter((a) => !a.startsWith("--"));
  const j = args.indexOf("--base");
  let base = j >= 0 ? args[j + 1] : null;
  if (!base) {
    const mb = spawnSync("git", ["merge-base", "HEAD", "main"], { cwd: top, encoding: "utf8" });
    base = mb.status === 0 ? mb.stdout.trim() : "HEAD";
  }
  const changed = z(git(top, ["diff", "--name-only", "-z", "--diff-filter=ACMR", base]));
  const untracked = z(git(top, ["ls-files", "--others", "--exclude-standard", "-z"]));
  return [...new Set([...changed, ...untracked])];
}

/** Run one command; its exit code (127 when the tool is not installed, as a shell reports it). */
function run(top, cmd, staged) {
  const t0 = Date.now();
  const env = staged ? { ...process.env, FW_CHECKMAP_STAGED: "1" } : process.env;
  const r = spawnSync(cmd.argv[0], cmd.argv.slice(1), { cwd: join(top, cmd.cwd), encoding: "utf8", maxBuffer: 64 << 20, env });
  const code = r.error?.code === "ENOENT" ? 127 : r.error ? 1 : r.status ?? 1;
  return { code, ms: Date.now() - t0, out: `${r.stdout ?? ""}${r.stderr ?? ""}${r.error && code !== 127 ? String(r.error) : ""}` };
}

function main(args) {
  const strict = args.includes("--strict");
  const top = git(process.cwd(), ["rev-parse", "--show-toplevel"]).trim();
  const bin = process.env.FW_CORE_BIN ?? join(top, "lean/.lake/build/bin/fwcore");
  const listed = listPaths(top, args);
  const staged = args.includes("--staged");
  // --staged judges the index: a staged path gone from the working tree is sent as a deletion (Lean keeps the generator inputs).
  const paths = listed.filter((p) => existsSync(join(top, p)));
  const gone = staged ? listed.filter((p) => !existsSync(join(top, p))) : [];
  const m = askCore(bin, "ops.checkMap", { paths, deleted: [...listDeleted(top, args), ...gone] });
  if (!m) {
    console.error(`checkmap: ${bin} is missing or does not know ops.checkMap (cd lean && lake build); checks ${strict ? "FAILED (--strict)" : "skipped"}`);
    return strict ? 1 : 0;
  }
  for (const p of m.unmapped) console.error(`checkmap: UNMAPPED ${p}: no kind in lean/Fw/Ops/CheckMap.lean (add a rule and its check)`);
  const cmds = args.includes("--tracked") ? [] : m.cmds;
  const codes = [];
  for (const c of cmds) {
    const r = run(top, c, args.includes("--staged"));
    codes.push(r.code);
    const what = c.files.length === 1 ? c.files[0] : `${c.files.length} files`;
    const tag = r.code === 0 ? "ok" : r.code === 127 ? "MISSING TOOL" : "FAIL";
    if (r.code !== 0 || args.includes("--verbose")) console.error(`checkmap: ${tag} ${c.check} ${what}: ${c.argv[0]} (${r.ms} ms)`);
    if (r.code !== 0 && r.code !== 127) console.error(r.out.trimEnd().split("\n").slice(-20).map((l) => `  ${l}`).join("\n"));
  }
  const v = askCore(bin, "ops.checkVerdict", { codes, strict, unmapped: m.unmapped.length });
  if (!v) { console.error("checkmap: fwcore refused ops.checkVerdict"); return 1; }
  console.error(`checkmap: ${v.ok ? "ok" : "FAILED"}: ${paths.length} paths, ${cmds.length} commands, ${v.failed.length} failed, ${v.unavailable.length} tool missing, ${m.unmapped.length} unmapped`);
  return v.ok ? 0 : 1;
}

/** The text a `file` check judges: the index blob when FW_CHECKMAP_STAGED is set (set by `--staged`), else the file. */
function source(top, f) {
  if (process.env.FW_CHECKMAP_STAGED !== "1") return readFileSync(resolve(top, f), "utf8");
  return git(top, ["show", `:${f}`]);
}

/** The preset generator's inputs among the tracked files (the same places as `presetInput` in lean/Fw/Ops/CheckMap.lean). */
const PRESET_INPUTS = ["research/findings/ledger.json", "packages/contracts/golden/preset", "apps/site/src/registry/presets/v2-proved.json", "apps/site/src/registry/presets/shipped.json", "apps/site/src/parts"];

/** `Fw.Preset.Gen.run --check` over the working tree, or with FW_CHECKMAP_STAGED over the index: the generator's inputs
 * are exported from the index into a temp tree whose `lean/` links to this checkout's built `lean/` (the generator reads
 * `../<input>` from `lean/`). The generator code itself is the built one. */
function presetMode(top) {
  const staged = process.env.FW_CHECKMAP_STAGED === "1";
  const script = 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run ["--check"]\n';
  let root = top;
  let tmp = null;
  if (staged) {
    tmp = mkdtempSync(join(tmpdir(), "checkmap-preset-"));
    root = tmp;
    const files = z(git(top, ["ls-files", "-z", "--", ...PRESET_INPUTS])).filter((f) => !f.startsWith("apps/site/src/parts/") || f.endsWith("/part.json"));
    for (let i = 0; i < files.length; i += 200) git(top, ["checkout-index", `--prefix=${tmp}/`, "--", ...files.slice(i, i + 200)]);
    mkdirSync(join(tmp, "lean"));
    for (const e of readdirSync(join(top, "lean"))) symlinkSync(join(top, "lean", e), join(tmp, "lean", e));
  }
  try {
    const r = spawnSync("lake", ["env", "lean", "--stdin"], { cwd: join(root, "lean"), input: script, encoding: "utf8", maxBuffer: 64 << 20 });
    if (r.error?.code === "ENOENT") { console.error("lake missing"); return 127; }
    const out = `${r.stdout ?? ""}${r.stderr ?? ""}`.trimEnd();
    if (r.status !== 0) console.error(out.replaceAll(tmp ?? "\0", "<index>"));
    return r.status === 0 ? 0 : 1;
  } finally {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  }
}

/** `file <mode>`: our own parse checks. Exit 0 parsed, 1 a file does not parse, 127 the tool is missing. */
async function fileMode([mode, ...files]) {
  const top = git(process.cwd(), ["rev-parse", "--show-toplevel"]).trim();
  let bad = 0;
  const fail = (f, e) => { bad++; console.error(`${f}: ${String(e?.message ?? e).split("\n")[0]}`); };
  if (mode === "preset") return presetMode(top);
  if (mode === "tsc") {
    const tsc = join(top, files[0], "node_modules/.bin/tsc");
    if (!existsSync(tsc)) { console.error(`${tsc} missing (pnpm install)`); return 127; }
    const r = spawnSync(tsc, ["--noEmit", "-p", files[0]], { cwd: top, stdio: "inherit" });
    return r.status ?? 1;
  }
  if (mode === "ts") {
    const mod = await import("node:module");
    if (typeof mod.stripTypeScriptTypes !== "function") { console.error("node has no stripTypeScriptTypes"); return 127; }
    const warn = process.emitWarning;
    process.emitWarning = () => {};  // the API is marked experimental; its warning is noise here
    for (const f of files) {
      try { mod.stripTypeScriptTypes(source(top, f), { mode: "transform" }); } catch (e) { fail(f, e); }
    }
    process.emitWarning = warn;
    return bad ? 1 : 0;
  }
  if (mode === "graph") {  // the work graph's schema (Lean routes docs/team/work-graph.json here; plan.test runs the same conversion)
    const { checkGraph } = await import("../apps/runner/src/plan-check.ts");
    for (const f of files) {
      let text;
      try { text = source(top, f); } catch (e) { fail(f, e); continue; }
      for (const p of checkGraph(text)) fail(`${f} task`, p);
    }
    return bad ? 1 : 0;
  }
  if (mode === "ledger") {
    const { noteShapeProblems } = await import("../apps/runner/src/land-notes.ts");
    for (const f of files) {
      let text;
      try { text = source(top, f); } catch (e) { fail(f, e); continue; }
      for (const p of noteShapeProblems(text)) fail(f, p);
    }
    return bad ? 1 : 0;
  }
  if (mode === "workflow") {  // a workflow body (top-level return and await), not a module: parse it as an AsyncFunction, as build-review.test.mjs loads it
    for (const f of files) {
      try {
        const body = source(top, f).replace(/^export const meta = /m, "const meta = ");
        new AsyncFunction("agent", "args", body);  // construction parses; nothing runs
      } catch (e) { fail(f, e); }
    }
    return bad ? 1 : 0;
  }
  if (mode === "json" || mode === "jsonl") {
    for (const f of files) {
      const text = source(top, f);
      if (mode === "json") {
        try { JSON.parse(text); } catch (e) { fail(f, e); continue; }
        continue;
      }
      text.split("\n").forEach((l, i) => { if (l.trim()) try { JSON.parse(l); } catch (e) { fail(`${f}:${i + 1}`, e); } });
    }
    return bad ? 1 : 0;
  }
  console.error(`checkmap file: unknown mode ${mode}`);
  return 2;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {  // run, not imported
  const argv = process.argv.slice(2);
  process.exitCode = argv[0] === "file" ? await fileMode(argv.slice(1)) : main(argv);
}
