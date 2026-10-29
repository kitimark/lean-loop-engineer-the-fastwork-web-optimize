#!/usr/bin/env node
// test-checkmap.mjs (task check-map-lean): (1) every line of packages/contracts/golden/ops/checkmap.jsonl, replayed through
// the built fwcore, gets the golden reply; (2) in a throwaway git repo with scripts/checkmap.mjs and the pre-commit hook,
// a tracked .mjs with a syntax error fails the check (and the commit), a fixed one passes, a broken .json and an
// unmapped file fail. Needs lean/.lake/build/bin/fwcore (cd lean && lake build) or FW_CORE_BIN.
//   node scripts/test-checkmap.mjs
import { spawnSync } from "node:child_process";
import { copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { askCore } from "./checkmap.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");
const bin = process.env.FW_CORE_BIN ?? join(repo, "lean/.lake/build/bin/fwcore");
if (!existsSync(bin)) { console.error(`test-checkmap: ${bin} missing (cd lean && lake build)`); process.exit(1); }
let bad = 0;
const expect = (name, ok) => { if (!ok) bad++; console.log(`${ok ? "ok  " : "FAIL"} ${name}`); };

// (1) golden replay
const sortKeys = (v) => Array.isArray(v) ? v.map(sortKeys)
  : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])])) : v;
for (const line of readFileSync(join(repo, "packages/contracts/golden/ops/checkmap.jsonl"), "utf8").split("\n").filter(Boolean)) {
  const c = JSON.parse(line);
  const { op, ...req } = c.request;
  const r = spawnSync(bin, [], { input: JSON.stringify({ id: 1, op, ...req }) + "\n", encoding: "utf8" });
  const { id, ...got } = JSON.parse(r.stdout.split("\n")[0]);
  expect(`golden: ${c.name}`, JSON.stringify(sortKeys(got)) === JSON.stringify(sortKeys(c.response)));
}
expect("askCore returns null for an unknown op", askCore(bin, "ops.noSuchOp", {}) === null);

// (2) a throwaway repo
const dir = mkdtempSync(join(tmpdir(), "checkmap-test-"));
const env = { ...process.env, FW_CORE_BIN: bin, FW_LAND_TOKEN: "" };
const git = (...a) => spawnSync("git", a, { cwd: dir, encoding: "utf8", env });
git("init", "-q");
git("config", "user.name", "test");
git("config", "user.email", ["test", "example.invalid"].join(String.fromCharCode(64)));
mkdirSync(join(dir, "scripts/hooks"), { recursive: true });
copyFileSync(join(here, "checkmap.mjs"), join(dir, "scripts/checkmap.mjs"));
copyFileSync(join(here, "scrub.mjs"), join(dir, "scripts/scrub.mjs"));
copyFileSync(join(here, "hooks/pre-commit"), join(dir, "scripts/hooks/pre-commit"));
git("config", "core.hooksPath", "scripts/hooks");
const check = (...a) => spawnSync("node", ["scripts/checkmap.mjs", ...a], { cwd: dir, encoding: "utf8", env });

writeFileSync(join(dir, "broken.mjs"), "const pageDiff = 1; 0 (scrollHeight is a whole number: 1 px slack)\n");
git("add", "--", "broken.mjs");
let r = check("--staged");
expect("a staged .mjs with a syntax error fails the check (exit 1)", r.status === 1 && /FAIL nodeCheck broken\.mjs/.test(r.stderr));
r = git("commit", "-q", "-m", "broken");
expect("... and the pre-commit hook refuses the commit", r.status !== 0 && /FAIL nodeCheck broken\.mjs/.test(r.stderr));
expect("... so nothing was committed", git("rev-parse", "--verify", "-q", "HEAD").status !== 0);

writeFileSync(join(dir, "broken.mjs"), "const pageDiff = 1; // 0 (scrollHeight is a whole number: 1 px slack)\n");
git("add", "--", "broken.mjs");
r = check("--staged");
expect("the fixed .mjs passes (exit 0)", r.status === 0);
r = git("commit", "-q", "-m", "fixed");
expect("... and commits", r.status === 0);

writeFileSync(join(dir, "broken.mjs"), "export const a = (;\n");
r = check("--all");
expect("--all: a tracked .mjs with a syntax error in the working tree fails", r.status === 1 && /FAIL nodeCheck broken\.mjs/.test(r.stderr));
r = check("--tracked");
expect("--tracked runs no command (passes on a mapped tree)", r.status === 0 && /0 commands/.test(r.stderr));
git("checkout", "--", "broken.mjs");

writeFileSync(join(dir, "data.json"), "{\"a\": 1,}\n");
writeFileSync(join(dir, "rows.jsonl"), "{\"a\":1}\n{oops\n");
r = check("--paths", "data.json", "rows.jsonl");
expect("a broken .json and .jsonl fail", r.status === 1 && /FAIL jsonParse data\.json/.test(r.stderr) && /rows\.jsonl:2/.test(r.stderr));

writeFileSync(join(dir, "notes.unknownext"), "x\n");
r = check("--paths", "notes.unknownext");
expect("an unmapped file fails the run", r.status === 1 && /UNMAPPED notes\.unknownext/.test(r.stderr));

r = spawnSync("node", ["scripts/checkmap.mjs", "--paths", "broken.mjs"], { cwd: dir, encoding: "utf8", env: { ...env, FW_CORE_BIN: join(dir, "nope") } });
expect("without fwcore the checks are skipped with a warning (exit 0)", r.status === 0 && /skipped/.test(r.stderr));
r = spawnSync("node", ["scripts/checkmap.mjs", "--strict", "--paths", "broken.mjs"], { cwd: dir, encoding: "utf8", env: { ...env, FW_CORE_BIN: join(dir, "nope") } });
expect("... and fail with --strict", r.status === 1);

// (3) the preset check judges the index, runs when any input is staged
if (!existsSync(join(repo, "lean/.lake/build/lib/lean/Fw/Preset/Gen.olean"))) { console.error("test-checkmap: lean/.lake/build lacks Fw.Preset.Gen (cd lean && lake build)"); bad++; }
const pdir = mkdtempSync(join(tmpdir(), "checkmap-preset-test-"));
const pgit = (...a) => spawnSync("git", a, { cwd: pdir, encoding: "utf8", env });
pgit("init", "-q");
pgit("config", "user.name", "test");
pgit("config", "user.email", ["test", "example.invalid"].join(String.fromCharCode(64)));
mkdirSync(join(pdir, "scripts"), { recursive: true });
copyFileSync(join(here, "checkmap.mjs"), join(pdir, "scripts/checkmap.mjs"));
for (const f of ["research/findings/ledger.json", "apps/site/src/registry/presets/v2-proved.json"]) {
  mkdirSync(dirname(join(pdir, f)), { recursive: true });
  copyFileSync(join(repo, f), join(pdir, f));
}
mkdirSync(join(pdir, "apps/runner/src"), { recursive: true });
copyFileSync(join(repo, "apps/runner/src/land-notes.ts"), join(pdir, "apps/runner/src/land-notes.ts"));
cpSync(join(repo, "packages/contracts/golden/preset"), join(pdir, "packages/contracts/golden/preset"), { recursive: true });
for (const d of readdirSync(join(repo, "apps/site/src/parts"))) {
  const src = join(repo, "apps/site/src/parts", d, "part.json");
  if (!existsSync(src)) continue;
  mkdirSync(join(pdir, "apps/site/src/parts", d), { recursive: true });
  copyFileSync(src, join(pdir, "apps/site/src/parts", d, "part.json"));
}
mkdirSync(join(pdir, "lean"));  // untracked: links to the built lean/ (the working-tree mode runs there)
for (const e of readdirSync(join(repo, "lean"))) symlinkSync(join(repo, "lean", e), join(pdir, "lean", e));
pgit("add", "--", "research", "apps", "packages", "scripts");
pgit("commit", "-q", "--no-verify", "-m", "base");
const pcheck = (...a) => spawnSync("node", ["scripts/checkmap.mjs", "--verbose", ...a], { cwd: pdir, encoding: "utf8", env });
const timing = (r) => (/presetCheck[^\n]*\((\d+) ms\)/.exec(r.stderr) ?? [])[1];
const ledger = join(pdir, "research/findings/ledger.json");
const goodLedger = readFileSync(ledger, "utf8");
const badLedger = '{"findings": "stale"}\n';
writeFileSync(ledger, badLedger);
pgit("add", "--", "research/findings/ledger.json");
writeFileSync(ledger, goodLedger);  // the working tree is fixed, the index is stale
let pr = pcheck("--staged");
expect(`preset: stale staged ledger + fixed working tree is refused (${timing(pr)} ms)`, pr.status === 1 && /FAIL presetCheck/.test(pr.stderr));
writeFileSync(ledger, goodLedger + "\n");  // a changed but valid ledger (same rows)
pgit("add", "--", "research/findings/ledger.json");  // now the index is fixed
writeFileSync(ledger, badLedger);  // the working tree is stale
pr = pcheck("--staged");
expect(`preset: fixed staged ledger + stale working tree passes (${timing(pr)} ms)`, pr.status === 0 && /ok presetCheck/.test(pr.stderr));
pr = pcheck("--paths", "research/findings/ledger.json");
expect("preset: without --staged the working tree is judged (stale refused)", pr.status === 1 && /FAIL presetCheck/.test(pr.stderr));
writeFileSync(ledger, goodLedger);
pgit("add", "--", "research/findings/ledger.json");  // back to the committed bytes: nothing staged
const gold = join(pdir, "packages/contracts/golden/preset/v2-proved.json");
const goodGold = readFileSync(gold, "utf8");
writeFileSync(gold, '{"name":"v2-proved","extends":"original","fw":{}}\n');
pgit("add", "--", "packages/contracts/golden/preset/v2-proved.json");
writeFileSync(gold, goodGold);
pr = pcheck("--staged");
expect("preset: a staged stale golden preset file alone runs the check and is refused", pr.status === 1 && /FAIL presetCheck/.test(pr.stderr));
pgit("add", "--", "packages/contracts/golden/preset/v2-proved.json");
const part = readdirSync(join(pdir, "apps/site/src/parts"))[0];
const partJson = join(pdir, "apps/site/src/parts", part, "part.json");
writeFileSync(partJson, readFileSync(partJson, "utf8").replace("{", '{"zz":1,'));
pgit("add", "--", `apps/site/src/parts/${part}/part.json`);
pr = pcheck("--staged");
expect("preset: a staged part.json alone runs the check", /(ok|FAIL) presetCheck/.test(pr.stderr));
pgit("reset", "-q");
pgit("checkout", "--", ".");
// deletions: a staged delete of any generator input runs the check (the tree without the file is judged)
const delCase = (name, rel) => {
  pgit("rm", "-q", "--", rel);
  const d = pcheck("--staged");
  expect(`preset: staged deletion of ${name} runs the check`, /(ok|FAIL) presetCheck/.test(d.stderr));
  pgit("reset", "-q", "--", rel);
  pgit("checkout", "--", rel);
};
delCase("the ledger", "research/findings/ledger.json");
delCase("a golden preset file", "packages/contracts/golden/preset/v2-proved.json");
delCase("a part.json", `apps/site/src/parts/${part}/part.json`);
delCase("the site preset", "apps/site/src/registry/presets/v2-proved.json");
// renames: git detects them, the old path must still count as a deletion
const renCase = (name, rel, to) => {
  pgit("mv", rel, to);
  const d = pcheck("--staged");
  expect(`preset: staged rename of ${name} away runs the check`, /(ok|FAIL) presetCheck/.test(d.stderr));
  pgit("reset", "-q");
  pgit("checkout", "--", ".");
  rmSync(join(pdir, to), { force: true });
};
renCase("the ledger", "research/findings/ledger.json", "research/findings/ledger-old.json");
renCase("a golden preset file", "packages/contracts/golden/preset/v2-proved.json", "packages/contracts/golden/preset/v2-proved-old.json");
// a staged change to an input that is then deleted from the working tree still runs the check
writeFileSync(ledger, badLedger);
pgit("add", "--", "research/findings/ledger.json");
rmSync(ledger);
pr = pcheck("--staged");
expect("preset: staged ledger change deleted from the working tree still runs the check", /(ok|FAIL) presetCheck/.test(pr.stderr));
pgit("reset", "-q");
pgit("checkout", "--", ".");
{
  const doc = JSON.parse(goodLedger);
  const f0 = doc.findings[0];
  const note = { entry: f0.candidate, task: "fixture", field: "mechanism", text: "a fixture note" };
  const stageNote = (n) => {
    writeFileSync(ledger, JSON.stringify({ ...doc, notes: [...(doc.notes ?? []), n] }, null, 1) + "\n");
    pgit("add", "--", "research/findings/ledger.json");
    writeFileSync(ledger, goodLedger);
    const r = pcheck("--staged");
    pgit("reset", "-q");
    pgit("checkout", "--", ".");
    return r;
  };
  let nr = stageNote(note);
  expect("ledger notes: a staged note naming a candidate and a findings field passes and the check ran", nr.status === 0 && /ok ledgerNotes/.test(nr.stderr));
  nr = stageNote({ ...note, entry: "free text that is not a candidate" });
  expect("ledger notes: a staged note whose entry is free text (cols-probe) is refused", nr.status === 1 && /FAIL ledgerNotes/.test(nr.stderr) && /not the candidate of a finding/.test(nr.stderr));
  nr = stageNote({ ...note, field: "gate" });
  expect("ledger notes: a staged note whose field is not a findings field (hero-exit-gate-clear) is refused", nr.status === 1 && /FAIL ledgerNotes/.test(nr.stderr) && /not a findings field/.test(nr.stderr));
  nr = stageNote({ ...note, text: "" });
  expect("ledger notes: a staged note with an empty text is refused", nr.status === 1 && /FAIL ledgerNotes/.test(nr.stderr));
  const plain = spawnSync("node", ["scripts/checkmap.mjs", "--verbose", "--paths", "docs/x.md"], { cwd: pdir, encoding: "utf8", env });
  expect("ledger notes: a change that leaves the ledger alone plans no ledger check", !/ledgerNotes/.test(plain.stderr));
}

pgit("rm", "-q", "--cached", "--", "scripts/checkmap.mjs");  // an unrelated deletion runs nothing
expect("preset: a staged deletion of a non-input runs no preset check", !/presetCheck/.test(pcheck("--staged").stderr));
pgit("reset", "-q", "--", "scripts/checkmap.mjs");
rmSync(pdir, { recursive: true, force: true });

// (4) every Lean module Fw.Preset.Gen imports (transitively) is a generator input in Lean
{
  const seen = new Set();
  const walk = (mod) => {
    if (seen.has(mod) || !mod.startsWith("Fw.")) return;
    seen.add(mod);
    for (const l of readFileSync(join(repo, "lean", mod.replaceAll(".", "/") + ".lean"), "utf8").split("\n")) {
      const m = /^import\s+(\S+)/.exec(l);
      if (m) walk(m[1]);
    }
  };
  walk("Fw.Preset.Gen");
  const files = [...seen].map((m) => `lean/${m.replaceAll(".", "/")}.lean`);
  const got = askCore(bin, "ops.checkMap", { paths: files })?.cmds.find((c) => c.check === "presetCheck")?.files ?? [];
  expect(`preset: all ${files.length} modules of Gen's import closure are inputs (${files.join(", ")})`, files.every((f) => got.includes(f)));
  const del = askCore(bin, "ops.checkMap", { paths: [], deleted: ["apps/site/src/parts/hero/part.json", "x.mjs"] });
  expect("preset: ops.checkMap deleted: a deleted part.json plans the preset check and nothing else", del?.cmds.length === 1 && del.cmds[0].check === "presetCheck");
}

rmSync(dir, { recursive: true, force: true });
console.log(bad ? `test-checkmap: ${bad} FAILED` : "test-checkmap: all passed");
process.exit(bad ? 1 : 0);
