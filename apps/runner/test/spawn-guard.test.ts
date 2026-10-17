import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CAPS, ask, request } from "../hooks/spawn-guard.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, "../hooks/spawn-guard.mjs");
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const call = (tool_input: object, extra: object = {}) => ({ hook_event_name: "PreToolUse", tool_name: "Agent", tool_use_id: "toolu_9", tool_input, ...extra });
const decide = (p: object) => ask(bin, request(p as never, 1000));

describe("spawn guard (shadow)", () => {
  it("asks Lean with unnamedReadOnly = true", () => {
    expect(CAPS).toEqual({ unnamedReadOnly: true });
    expect(request(call({ subagent_type: "Explore" }) as never, 5)).toMatchObject({ op: "ops.spawn", caps: { unnamedReadOnly: true }, now: 5, req: { role: "Explore", depth: 0, spawner: "lead" } });
  });
  it.each([
    ["unnamed read-only subagent: allow", { subagent_type: "Explore" }, "allow", null],
    ["named worktree role with isolation: allow", { subagent_type: "lean-prover", name: "lp", isolation: "worktree" }, "allow", null],
    ["worktree role without isolation becomes a teammate: deny", { subagent_type: "lean-prover", name: "lp" }, "deny", "kindMismatch"],
    ["unnamed editor: deny", { subagent_type: "lean-prover", isolation: "worktree" }, "deny", "unnamed"],
    ["unknown role: deny", { subagent_type: "nope", name: "x" }, "deny", "unknownRole"],
  ])("%s", (_n, input, decision, reason) => {
    expect(decide(call(input))).toMatchObject({ decision, reason });
  });
  it("process: writes one SpawnGuard line to the spool, prints nothing, exits 0 even when it would deny", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    const r = spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "lean-prover", name: "lp" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin }, encoding: "utf8" });
    expect(r.status).toBe(0);
    expect(r.stdout).toBe("");
    expect(r.stderr).toBe("");
    const [f] = readdirSync(join(d, "spool"));
    const rec = JSON.parse(readFileSync(join(d, "spool", f!), "utf8"));
    expect(rec).toMatchObject({ hook_event_name: "SpawnGuard", tool_name: "Agent", tool_use_id: "toolu_9", verb: "deny:kindMismatch" });
  });
  it("missing fwcore: logged as unavailable, still exit 0", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    const r = spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "Explore" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: "/nonexistent/fwcore" }, encoding: "utf8" });
    expect(r.status).toBe(0);
    const [f] = readdirSync(join(d, "spool"));
    expect(JSON.parse(readFileSync(join(d, "spool", f!), "utf8")).verb).toBe("unavailable");
  });
  it("other tools and garbage input: no output, no spool", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    for (const input of ["not json", JSON.stringify({ tool_name: "Bash" })]) {
      const r = spawnSync("node", [script], { input, env: { ...process.env, FW_CONSOLE_DIR: d }, encoding: "utf8" });
      expect([r.status, r.stdout]).toEqual([0, ""]);
    }
    expect(() => readdirSync(join(d, "spool"))).toThrow();
  });
});

describe("spawn guard: expected vs given kind is logged", () => {
  it("a kindMismatch record says why (want/got from the Lean ops.spawn reply)", async () => {
    const { kinds } = await import("../hooks/spawn-guard.mjs");
    const kindsOf = (input: object) => { const q = request(call(input) as never, 1); return kinds(q.req, ask(bin, q)); };
    expect(kindsOf({ subagent_type: "lean-prover", name: "lp" })).toMatchObject({ role: "lean-prover", want_kind: "worktree", got_kind: "teammate", has_name: true, isolation: false });
    expect(kindsOf({ subagent_type: "scout", isolation: "worktree" })).toMatchObject({ want_kind: "subagent", got_kind: "worktree" });
    expect(kindsOf({ subagent_type: "nope", name: "x" })).toMatchObject({ want_kind: null, got_kind: "teammate" });
  });
  it("fwcore unavailable: kinds are null, the request is still described", async () => {
    const { kinds } = await import("../hooks/spawn-guard.mjs");
    expect(kinds(request(call({ subagent_type: "lean-prover", name: "lp" }) as never, 1).req, null)).toEqual(
      { role: "lean-prover", want_kind: null, got_kind: null, has_name: true, isolation: false, depth: 0 });
  });
  it("the spool record of a kindMismatch carries want/got", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "lean-prover", name: "lp" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin }, encoding: "utf8" });
    const [f] = readdirSync(join(d, "spool"));
    expect(JSON.parse(readFileSync(join(d, "spool", f!), "utf8"))).toMatchObject({ want_kind: "worktree", got_kind: "teammate" });
  });
});
