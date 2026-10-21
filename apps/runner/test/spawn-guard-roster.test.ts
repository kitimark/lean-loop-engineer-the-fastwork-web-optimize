// Every agent file in .claude/agents is a role of the Lean spawn-guard roster (`Fw.Ops.SpawnGuard.prodRoles`, fwcore op
// `plan.roster`), its `edits` bit matches the file's Edit/Write tools, and the hook's ROLES table equals the roster.
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ROLES } from "../hooks/spawn-guard.mjs";
import { coreCandidates } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../..");
const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root, encoding: "utf8" }).trim();
const bin = coreCandidates(root, join(common, "..")).find((b) => {
  try { return execFileSync(b, ["--ops"], { encoding: "utf8" }).includes("plan.roster"); } catch { return false; }
});
type Role = { name: string; runsAs: string; edits: boolean };
const roster = (): Role[] => JSON.parse(spawnSync(bin!, [], { input: '{"op":"plan.roster"}\n', encoding: "utf8" }).stdout).roles;

const agentsDir = join(root, ".claude/agents");
const front = (f: string) => {
  const head = readFileSync(join(agentsDir, f), "utf8").split("\n---")[0]!;
  const field = (k: string) => head.match(new RegExp(`^${k}:\\s*(.*)$`, "m"))?.[1]?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  return { file: f, name: field("name")[0], tools: field("tools"), denied: field("disallowedTools") };
};
const agents = readdirSync(agentsDir).filter((f) => f.endsWith(".md")).sort().map(front);

describe("agent files against the Lean roster (plan.roster)", () => {
  it("fwcore with plan.roster is built (cd lean && lake build)", () => expect(bin).toBeTruthy());

  it("every agent file names a roster role, and its file name is that name", () => {
    const names = new Set(roster().map((r) => r.name));
    for (const a of agents) {
      expect(a.name, a.file).toBe(a.file.replace(/\.md$/, ""));
      expect(names.has(a.name!), `${a.file}: role ${a.name} is not in Fw.Ops.SpawnGuard.prodRoles`).toBe(true);
    }
  });

  it("a role edits in Lean exactly when its file grants Edit or Write", () => {
    const byName = new Map(roster().map((r) => [r.name, r]));
    for (const a of agents) {
      const writes = ["Edit", "Write"].some((t) => a.tools.includes(t) && !a.denied.includes(t));
      expect(writes, `${a.file}: Edit/Write tools vs Lean edits`).toBe(byName.get(a.name!)!.edits);
    }
  });

  it("the hook's ROLES table is the Lean roster", () => expect(ROLES).toEqual(roster()));
});
