#!/usr/bin/env node
// Sends each agent-read file's path, size and lines to fwcore `lint.context` and prints the verdicts.
// Spec: lean/Fw/Lint/Context.lean; usage and flags: docs/team/tools/context-lint.md.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const top = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const flag = (f) => args.includes(f);

const ls = (dir, keep) => (existsSync(join(top, dir)) ? readdirSync(join(top, dir)).filter(keep).sort().map((n) => `${dir}/${n}`) : []);
const md = (n) => n.endsWith(".md");

export function defaultPaths() {
  const skills = ls(".claude/skills", () => true).map((d) => `${d}/SKILL.md`).filter((p) => existsSync(join(top, p)));
  return ["CLAUDE.md", ...ls(".claude/agents", md), ...skills, "docs/team/token-policy.md", ...ls("docs/team/tools", md),
    ...ls("docs/team/handoffs", md)].filter((p) => existsSync(join(top, p)));
}

export function fileOf(path) {
  const text = readFileSync(join(top, path), "utf8");
  const lines = text.split("\n");
  if (lines.at(-1) === "") lines.pop();
  return { path, bytes: statSync(join(top, path)).size, lines };
}

const paths = args.filter((a) => !a.startsWith("--"));
const req = { id: 1, op: "lint.context", files: (paths.length ? paths : defaultPaths()).map(fileOf) };
const bin = process.env.FW_CORE_BIN ?? join(top, "lean/.lake/build/bin/fwcore");
const r = existsSync(bin) ? spawnSync(bin, [], { input: JSON.stringify(req) + "\n", encoding: "utf8", maxBuffer: 64 << 20, timeout: 60_000 }) : null;
let reply = null;
try { reply = JSON.parse((r?.stdout ?? "").split("\n")[0]); } catch { reply = null; }
if (!reply || reply.error || !Array.isArray(reply.files)) {
  console.log(`context-lint: WARN no verdict (fwcore ${existsSync(bin) ? (reply?.error ?? "unreadable reply") : "missing"})`);
  process.exit(flag("--strict") ? 1 : 0);
}
if (flag("--json")) { console.log(JSON.stringify(reply)); process.exit(0); }

const bad = reply.files.filter((f) => f.verdict !== "ok");
const show = flag("--all") ? bad : bad.slice(0, 12);
for (const f of show) {
  const why = f.verdict === "overBudget" ? `${f.measure} ${f.value} > ${f.budget}` : `${f.slop} at line ${f.line}`;
  console.log(`context-lint: ${f.verdict} ${f.path} (${why})`);
}
if (show.length < bad.length) console.log(`context-lint: ... ${bad.length - show.length} more (--all)`);
const c = reply.counts;
console.log(`context-lint: ${reply.files.length} files: ${c.ok} ok, ${c.overBudget} over budget, ${c.slop} slop${flag("--strict") ? "" : " (warn-only)"}`);
process.exit(flag("--strict") && bad.length ? 1 : 0);
