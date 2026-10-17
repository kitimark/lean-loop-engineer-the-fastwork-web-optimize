import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CAPS, ask, message, modeOf, request, verdict } from "../hooks/spawn-guard.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, "../hooks/spawn-guard.mjs");
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const call = (tool_input: object, extra: object = {}) => ({ hook_event_name: "PreToolUse", tool_name: "Agent", tool_use_id: "toolu_9", tool_input, ...extra });
const decide = (p: object) => ask(bin, request(p as never, 1000));

describe("spawn guard (shadow mode)", () => {
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
    const r = spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "lean-prover", name: "lp" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, FW_SPAWN_GUARD: "shadow" }, encoding: "utf8" });
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
    spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "lean-prover", name: "lp" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, FW_SPAWN_GUARD: "shadow" }, encoding: "utf8" });
    const [f] = readdirSync(join(d, "spool"));
    expect(JSON.parse(readFileSync(join(d, "spool", f!), "utf8"))).toMatchObject({ want_kind: "worktree", got_kind: "teammate" });
  });
});

const run = (input: object, env: Record<string, string>) => {
  const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
  const r = spawnSync("node", [script], { input: JSON.stringify(call(input)), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, ...env }, encoding: "utf8" });
  const out = r.stdout ? JSON.parse(r.stdout).hookSpecificOutput : null;
  return { status: r.status, out, pending: existsSync(join(d, "spawn-pending")) ? readdirSync(join(d, "spawn-pending")).length : 0 };
};
const refused = { permissionDecision: "deny" };

describe("spawn guard: enforce mode (default)", () => {
  // false-positive classes of the shadow log (Lean fp_classes_allowed): must pass silently
  it.each<[string, object, object?]>([
    ["class A: teammate role (plan-editor) with worktree isolation", { subagent_type: "plan-editor", name: "plan-rev11", isolation: "worktree" }],
    ["class A: teammate role (researcher) with worktree isolation", { subagent_type: "researcher", name: "sim-fix", isolation: "worktree" }],
    ["class A: named general-purpose worktree helper", { subagent_type: "general-purpose", name: "math-final", isolation: "worktree" }],
    ["class B: unnamed fork helper nested under an agent", { subagent_type: "fork" }, { agent_id: "a1", agent_type: "lean-prover" }],
    ["class B: unnamed workflow agent", { subagent_type: "workflow-subagent" }],
    ["class B: unnamed read-only helper without a task (checker)", { subagent_type: "checker" }],
    ["named worktree role with isolation", { subagent_type: "lean-prover", name: "lp", isolation: "worktree" }],
    ["named teammate role", { subagent_type: "researcher", name: "r1" }],
  ])("allowed, no output, spawn proceeds: %s", (_n, input, extra) => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    const r = spawnSync("node", [script], { input: JSON.stringify(call(input, extra ?? {})), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, FW_SPAWN_GUARD: "" }, encoding: "utf8" });
    expect([r.status, r.stdout]).toEqual([0, ""]);
    expect(readdirSync(join(d, "spawn-pending"))).toHaveLength(1);
  });
  // refusal classes: each names its reason
  it.each([
    ["worktree role without isolation (I-272 trap)", { subagent_type: "part-builder", name: "port-x" }, "kindMismatch", /wants worktree, this call gives teammate/],
    ["unnamed editor", { subagent_type: "lean-prover", isolation: "worktree" }, "unnamed", /unnamed/],
    ["unknown role", { subagent_type: "nope", name: "x" }, "unknownRole", /unknownRole/],
  ])("refused with its reason: %s", (_n, input, reason, re) => {
    const r = run(input, { FW_SPAWN_GUARD: "" });
    expect(r.status).toBe(0);
    expect(r.out).toMatchObject({ hookEventName: "PreToolUse", ...refused });
    expect(r.out.permissionDecisionReason).toMatch(re);
    expect(r.out.permissionDecisionReason).toContain(reason);
    expect(r.pending).toBe(0);
  });
  it("nested editor is refused with its reason", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    const r = spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "part-builder", name: "pb", isolation: "worktree" }, { agent_id: "a1", agent_type: "lean-prover" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, FW_SPAWN_GUARD: "" }, encoding: "utf8" });
    expect(JSON.parse(r.stdout).hookSpecificOutput).toMatchObject({ ...refused, permissionDecisionReason: expect.stringContaining("nestedEditor") });
  });
  it("an ask model needs approval: permissionDecision ask", () => {
    const r = run({ subagent_type: "lean-prover", name: "lp", isolation: "worktree", model: "claude-fable-5-1" }, { FW_SPAWN_GUARD: "" });
    expect(r.out).toMatchObject({ permissionDecision: "ask" });
  });
  it("shadow and off: a refused spawn prints nothing", () => {
    for (const mode of ["shadow", "off"]) expect(run({ subagent_type: "part-builder", name: "port-x" }, { FW_SPAWN_GUARD: mode }).out).toBeNull();
  });
  it("the refused spawn is still logged, enforce or shadow", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    spawnSync("node", [script], { input: JSON.stringify(call({ subagent_type: "part-builder", name: "port-x" })), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, FW_SPAWN_GUARD: "" }, encoding: "utf8" });
    const [f] = readdirSync(join(d, "spool"));
    expect(JSON.parse(readFileSync(join(d, "spool", f!), "utf8")).verb).toBe("deny:kindMismatch");
  });
  it("fwcore missing: fails open", () => {
    const r = run({ subagent_type: "part-builder", name: "port-x" }, { FW_SPAWN_GUARD: "", FW_CORE_BIN: "/nonexistent/fwcore" });
    expect([r.status, r.out, r.pending]).toEqual([0, null, 1]);
  });
  it("modeOf: default enforce; env wins over spawn-guard.json; unknown = enforce", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-sg-"));
    expect(modeOf(d, {})).toBe("enforce");
    writeFileSync(join(d, "spawn-guard.json"), JSON.stringify({ mode: "shadow" }));
    expect(modeOf(d, {})).toBe("shadow");
    expect(modeOf(d, { FW_SPAWN_GUARD: "off" })).toBe("off");
    expect(modeOf(d, { FW_SPAWN_GUARD: "bogus" })).toBe("enforce");
  });
  it("verdict/message: only enforce prints; every denial names a reason", () => {
    const q = request(call({ subagent_type: "x" }) as never, 1).req as { role: string };
    expect(verdict("shadow", q, { decision: "deny", reason: "unnamed" })).toBeNull();
    expect(verdict("enforce", q, { decision: "allow", reason: null })).toBeNull();
    expect(verdict("enforce", q, null)).toBeNull();
    expect(message(q, { decision: "deny", reason: "capRole", role: "lean-prover" })).toContain("capRole (lean-prover)");
  });
});
