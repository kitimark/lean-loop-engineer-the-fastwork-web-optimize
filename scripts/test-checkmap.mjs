#!/usr/bin/env node
// test-checkmap.mjs (task check-map-lean): (1) every line of packages/contracts/golden/ops/checkmap.jsonl, replayed through
// the built fwcore, gets the golden reply; (2) in a throwaway git repo with scripts/checkmap.mjs and the pre-commit hook,
// a tracked .mjs with a syntax error fails the check (and the commit), a fixed one passes, a broken .json and an
// unmapped file fail. Needs lean/.lake/build/bin/fwcore (cd lean && lake build) or FW_CORE_BIN.
//   node scripts/test-checkmap.mjs
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

rmSync(dir, { recursive: true, force: true });
console.log(bad ? `test-checkmap: ${bad} FAILED` : "test-checkmap: all passed");
process.exit(bad ? 1 : 0);
