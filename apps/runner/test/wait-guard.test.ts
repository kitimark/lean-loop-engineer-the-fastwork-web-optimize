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

describe.skipIf(!have)("wait guard: shadow-log false positives are allowed, true positives stay refused (wait-guard-enforce)", () => {
  const verb = (cmd: string) => {
    const r = ask(bin, { op: "ops.wait", cmd }) as { decision: string; reason?: string | null; shape?: string | null } | null;
    return r ? [r.decision, r.reason, r.shape].filter((x) => typeof x === "string").join(":") : "unavailable";
  };
  // The 4 shadow-log denies that were false positives (paths replaced), then corpus shapes agents use.
  const allow = [
    "S=/tmp/s; cd \"${S:?}\" && find . -mindepth 1 -maxdepth 1 -type d -mmin +60 > \"$S/del.txt\"; while read -r d; do [ -n \"$d\" ] || continue; rm -rf -- \"${S:?}/${d:?}\"; done < \"$S/del.txt\"; df -h / | tail -1",
    "while IFS= read -r line; do case \"$line\" in pnpm*) t=$(echo \"$line\" | sed -E 's/x/y/'); echo \"== $t\"; eval \"$line\" 2>&1 | tail -2;; esac; done < /tmp/pending.txt; git log --oneline -6 main",
    "cat > /tmp/c.py <<'EOF'\nimport os\ns = 'x'\n      while (cmd[i + 1] === \">\") i++;\nwhile True:\n    break\nEOF\npython3 /tmp/c.py",
    "git ls-files | while read -r f; do wc -l \"$f\"; done | sort -n | tail -3",
    "while read -r a b; do echo $a; done <<< \"$pairs\"",
    "for i in $(seq 1 10); do sleep 1; done",
    "i=0; until gh run view 1 --exit-status || [ $i -ge 10 ]; do sleep 120; i=$((i+1)); done",
    "timeout 600 sh -c 'until gh run view 1 --exit-status; do sleep 120; done'",
    "pnpm fw ci wait 39086309620",
    "sh -c 'pnpm test &'",
    "git commit -m \"fix the while loop\"",
  ];
  const deny = [
    ["until [ \"$(gh run view 1 --json status -q .status)\" = completed ]; do sleep 150; done; gh run view 1", "deny:unboundedLoop"],
    ["while read l; do echo $l; done", "deny:unboundedLoop"],
    ["tail -f x.log | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["for f in a b; do while true; do sleep 1; done; done", "deny:unboundedLoop"],
    ["cat <<EOF > f\nx\nEOF\nwhile true; do sleep 1; done", "deny:unboundedLoop"],
    ["ls | while read f; do echo $f; done &", "deny:bgLong:loop"],
  ] as const;
  // Round-2 review (wait-guard-enforce): read conditions that never fail, denylisted-producer escapes, quoted <<.
  const review = [
    ["while read l || true; do sleep 1; done < f", "deny:unboundedLoop"],
    ["while read l || :; do sleep 1; done < f", "deny:unboundedLoop"],
    ["while read l; [ 1 ]; do sleep 1; done < f", "deny:unboundedLoop"],
    ["while read l && true; do sleep 1; done < f", "deny:unboundedLoop"],
    ["while read -u 3 l; do sleep 1; done < f 3< <(tail -f x)", "deny:unboundedLoop"],
    ["while read l < f; do echo $l; done < g", "deny:unboundedLoop"],
    ["ping x | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["tail -fn 10 log | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["tail --follow=name log | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["tail -n0 -F log | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["cat /dev/urandom | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["cat - | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["cat -u f | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["log stream | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["sleep infinity | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["gh run watch 1 | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["tail -f log | grep x | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["find . -exec tail -f {} \\; | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["jq -n 'repeat(1)' | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["seq inf | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["ls | while read l; do echo $l; done < /dev/zero", "deny:unboundedLoop"],
    ["while read l; do echo $l; done < <(ping x)", "deny:unboundedLoop"],
    ["echo \"<<EOF\"\nuntil false; do sleep 5; done", "deny:unboundedLoop"],
    ["echo '<<EOF'\nuntil false; do sleep 5; done", "deny:unboundedLoop"],
    ["echo \\<<EOF\nuntil false; do sleep 5; done", "deny:unboundedLoop"],
    ["node server.mjs & pid=$!; sleep 1; curl -s localhost:3000; kill $pid", "deny:bgLong:server"],
    ["while read -r f; do echo \"$f\"; done < <(git diff --name-only main)", "allow"],
    ["git ls-files | grep lean | while read -r f; do wc -l \"$f\"; done", "allow"],
    ["find . -name '*.lean' | while read f; do echo $f; done", "allow"],
    ["printf '%s\\n' a b | while read x; do echo $x; done", "allow"],
    ["gh run list --limit 5 | while read l; do echo $l; done", "allow"],
    ["cat f.txt | while read -r l; do echo $l; done", "allow"],
    ["while read l\ndo\n  echo $l\ndone < f.txt", "allow"],
    ["cat <<'EOF' > f\nuntil false; do sleep 5; done\nEOF\necho ok", "allow"],
  ] as const;
  it.each(review.map(([c, v]) => [c.slice(0, 60), c, v] as const))("review: %s", (_n, c, v) => expect(verb(c)).toBe(v));
  // Round-3 review: the bound comes from the loop condition only; finite filters; device paths; here-string $( ).
  const review3 = [
    ["tail -f log | while read l; do echo $((n+1)); done", "deny:unboundedLoop"],
    ["yes | while read l; do echo; date; done", "deny:unboundedLoop"],
    ["while true; do date; sleep 1; done", "deny:unboundedLoop"],
    ["until gh run view 1 --exit-status; do date; sleep 120; done", "deny:unboundedLoop"],
    ["until false; do sleep 1; echo deadline; done", "deny:unboundedLoop"],
    ["while [ \"$SECONDS\" ]; do sleep 1; done", "deny:unboundedLoop"],
    ["while [ 1 -lt 2 ]; do sleep 1; done", "deny:unboundedLoop"],
    ["while :; do [ $i -lt 5 ] || break; i=$((i+1)); done", "deny:unboundedLoop"],
    ["tail -f log | while read l && [ $i -lt 9 ]; do i=$((i+1)); done", "deny:unboundedLoop"],
    ["while [ $i -lt 9 ] || true; do sleep 1; done", "deny:unboundedLoop"],
    ["while read l; do echo $l; done < //dev/zero", "deny:unboundedLoop"],
    ["cat ./../../dev/zero | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["while read l; do echo $l; done <<< \"$(yes)\"", "deny:unboundedLoop"],
    ["pnpm -s fw list | while read l; do echo $l; done", "deny:unboundedLoop"],
    ["git log | awk '{while(1)print}' | while read h; do echo $h; done", "deny:unboundedLoop"],
    ["i=0; while [ ! -s \"$F\" ] && [ $i -lt 55 ]; do sleep 10; i=$((i+1)); done", "allow"],
    ["end=$((SECONDS+60)); while [ $SECONDS -lt $end ]; do sleep 5; done", "allow"],
    ["while (( i < 10 )); do i=$((i+1)); done", "allow"],
    ["git log --oneline | sed 's/a/b/' | awk '{print $1}' | while read h; do echo $h; done", "allow"],
    ["git ls-files | tr a b | cut -c1-3 | uniq | while read l; do echo $l; done", "allow"],
    ["ls | xargs -n 1 echo | while read l; do echo $l; done", "allow"],
    ["gh pr list --json number -q '.[].number' | while read n; do gh pr view $n; done", "allow"],
    ["git reflog show main | grep x | head -12 | while read h rest; do echo $h; done", "allow"],
    ["find . -name '*.json' -print0 | while IFS= read -r -d $'\\0' f; do echo \"$f\"; done", "allow"],
    ["node scripts/list.mjs | while read l; do echo $l; done", "allow"],
    ["while read -r f; do echo $f; done <<< \"$(git diff --name-only)\"", "allow"],
  ] as const;
  it.each(review3.map(([c, v]) => [c.slice(0, 60), c, v] as const))("review3: %s", (_n, c, v) => expect(verb(c)).toBe(v));
  it("deny messages name the read-loop shape, the producer allowlist and the smoke-test idiom", () => {
    const loop = message({ reason: "unboundedLoop" });
    for (const s of ["cmd | while read", "done < <(cmd)", "gh run list/view", "no `||`"]) expect(loop).toContain(s);
    for (const s of ["loop condition", "pnpm ... > f.txt", "timeout N bash -c"]) expect(loop).toContain(s);
    const bg = message({ reason: "bgLong", shape: "server" });
    for (const s of ["kill $pid", "run_in_background: true", "TaskStop"]) expect(bg).toContain(s);
  });
  it.each(allow.map((c) => [c.slice(0, 60), c] as const))("allow: %s", (_n, c) => expect(verb(c)).toBe("allow"));
  it.each(deny.map(([c, v]) => [c.slice(0, 60), c, v] as const))("deny: %s", (_n, c, v) => expect(verb(c)).toBe(v));
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
