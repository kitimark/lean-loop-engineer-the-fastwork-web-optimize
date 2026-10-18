import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ask } from "../hooks/spawn-guard.mjs";
import { message, modeOf, record, request, verdict } from "../hooks/wait-guard.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, "../hooks/wait-guard.mjs");
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const golden = join(here, "../../../packages/contracts/golden/ops/ops.wait.jsonl");
const bash = (command: string, extra: object = {}) => ({ hook_event_name: "PreToolUse", tool_name: "Bash", tool_use_id: "toolu_7", tool_input: { command }, ...extra });
const have = existsSync(bin);

describe("wait guard: request, mode, wording (no fwcore needed)", () => {
  it("builds ops.wait from the Bash command, nothing else", () => {
    expect(request(bash("echo hi") as never)).toEqual({ op: "ops.wait", cmd: "echo hi" });
    expect(request({ tool_name: "Bash", tool_input: {} })).toBeNull();
    expect(request({ tool_name: "Bash", tool_input: { command: 3 } })).toBeNull();
  });
  it("mode: shadow by default, env wins over the file, unknown = shadow", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-wg-"));
    expect(modeOf(d, {})).toBe("shadow");
    writeFileSync(join(d, "wait-guard.json"), JSON.stringify({ mode: "enforce" }));
    expect(modeOf(d, {})).toBe("enforce");
    expect(modeOf(d, { FW_WAIT_GUARD: "off" })).toBe("off");
    expect(modeOf(d, { FW_WAIT_GUARD: "bogus" })).toBe("shadow");
    expect(modeOf(null, {})).toBe("shadow");
  });
  it("verdict: only enforce + deny prints; the text names the reason and the fix", () => {
    const deny = { decision: "deny", reason: "bgLong", shape: "fwWatch" };
    expect(verdict("shadow", deny)).toBeNull();
    expect(verdict("off", deny)).toBeNull();
    expect(verdict("enforce", { decision: "allow", reason: null })).toBeNull();
    expect(verdict("enforce", null)).toBeNull();
    const out = verdict("enforce", deny)!.hookSpecificOutput;
    expect(out).toMatchObject({ hookEventName: "PreToolUse", permissionDecision: "deny" });
    expect(out.permissionDecisionReason).toContain("fwWatch");
    expect(out.permissionDecisionReason).toContain("run_in_background");
    expect(message({ reason: "unboundedLoop" })).toContain("timeout");
  });
  it("record: verb = decision:reason:shape, no command text, fits the 40-char verb limit", () => {
    const r = record(bash("secret &") as never, { decision: "deny", reason: "bgLong", shape: "longSleep" }, 5);
    expect(r).toMatchObject({ hook_event_name: "WaitGuard", tool_name: "Bash", verb: "deny:bgLong:longSleep", ts: 5, tool_use_id: "toolu_7" });
    expect(JSON.stringify(r)).not.toContain("secret");
    expect(record(bash("x") as never, null, 1).verb).toBe("unavailable");
    expect(record(bash("x") as never, { decision: "allow", reason: null }, 1).verb).toBe("allow");
  });
});

describe.skipIf(!have)("wait guard vs the Lean goldens (ops.wait.jsonl)", () => {
  const cases = readFileSync(golden, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { name: string; request: { cmd?: string; caps?: object }; response: Record<string, unknown> });
  it("the file has the documented shapes", () => {
    const shapes = new Set(cases.map((c) => c.response.shape));
    for (const s of ["fwWatch", "loop", "server", "tail", "longSleep"]) expect(shapes.has(s)).toBe(true);
    expect(cases.some((c) => c.response.reason === "unboundedLoop")).toBe(true);
  });
  it.each(cases.filter((c) => typeof c.request.cmd === "string").map((c) => [c.name, c] as const))("%s", (_n, c) => {
    const reply = ask(bin, { op: "ops.wait", cmd: c.request.cmd, ...(c.request.caps ? { caps: c.request.caps } : {}) });
    expect(reply).toMatchObject({ decision: c.response.decision, reason: c.response.reason, shape: c.response.shape });
  });
});

describe.skipIf(!have)("wait guard process", () => {
  const run = (command: string, env: Record<string, string>, extra: object = {}) => {
    const d = mkdtempSync(join(tmpdir(), "fw-wg-"));
    const r = spawnSync("node", [script], { input: JSON.stringify(bash(command, extra)), env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin, ...env }, encoding: "utf8" });
    const f = existsSync(join(d, "spool")) ? readdirSync(join(d, "spool")) : [];
    return { r, recs: f.flatMap((x) => readFileSync(join(d, "spool", x), "utf8").trim().split("\n").map((l) => JSON.parse(l))) };
  };
  it("default (shadow): logs the refusal, prints nothing, exits 0", () => {
    const { r, recs } = run("pnpm fw watch --until-alert &", {});
    expect([r.status, r.stdout, r.stderr]).toEqual([0, "", ""]);
    expect(recs).toHaveLength(1);
    expect(recs[0]).toMatchObject({ hook_event_name: "WaitGuard", tool_name: "Bash", verb: "deny:bgLong:fwWatch" });
  });
  it("enforce: prints a deny with the fix", () => {
    const { r } = run("pnpm fw watch &", { FW_WAIT_GUARD: "enforce" });
    expect(r.status).toBe(0);
    const out = JSON.parse(r.stdout);
    expect(out.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(out.hookSpecificOutput.permissionDecisionReason).toContain("run_in_background");
  });
  it("enforce, allowed command: no output, an allow line", () => {
    const { r, recs } = run("pnpm test", { FW_WAIT_GUARD: "enforce" });
    expect([r.status, r.stdout]).toEqual([0, ""]);
    expect(recs[0]).toMatchObject({ verb: "allow" });
  });
  it("off: nothing at all", () => {
    const { r, recs } = run("pnpm fw watch &", { FW_WAIT_GUARD: "off" });
    expect([r.status, r.stdout, recs.length]).toEqual([0, "", 0]);
  });
  it("missing fwcore: logged as unavailable, no output, exit 0 even in enforce", () => {
    const { r, recs } = run("pnpm fw watch &", { FW_CORE_BIN: "/nonexistent/fwcore", FW_WAIT_GUARD: "enforce" });
    expect([r.status, r.stdout]).toEqual([0, ""]);
    expect(recs[0].verb).toBe("unavailable");
  });
  it("other tools, no command, garbage input: no output, no spool", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-wg-"));
    for (const input of ["not json", JSON.stringify({ tool_name: "Agent" }), JSON.stringify({ tool_name: "Bash", tool_input: {} })]) {
      const r = spawnSync("node", [script], { input, env: { ...process.env, FW_CONSOLE_DIR: d, FW_CORE_BIN: bin }, encoding: "utf8" });
      expect([r.status, r.stdout]).toEqual([0, ""]);
    }
    expect(existsSync(join(d, "spool"))).toBe(false);
  });
});
