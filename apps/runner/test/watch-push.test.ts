import { appendFileSync, existsSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { coreCaller } from "../src/watch.ts";
import { LineTail, pushLine, startPush } from "../src/watch-push.ts";

const here = dirname(fileURLToPath(import.meta.url));
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const have = existsSync(bin);
const core = coreCaller(have ? [bin] : []);
const dirs: string[] = [];
afterAll(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); });
const setup = () => { const d = mkdtempSync(join(tmpdir(), "fwpush-")); dirs.push(d); const f = join(d, "events.jsonl"); writeFileSync(f, '{"type":"agent.spawn","actor":"hook"}\n'); return { d, f }; };
const ev = (o: object) => JSON.stringify(o) + "\n";
const until = async (ok: () => boolean, ms: number) => { const t0 = Date.now(); while (!ok() && Date.now() - t0 < ms) await new Promise((r) => setTimeout(r, 10)); return Date.now() - t0; };
const user = { type: "review.feedback", actor: "user", flag: "step:s1", id: "fb-1", text: "why  is it\nslow?" };

describe("pushLine", () => {
  it("one line, subject and text", () => expect(pushLine(user)).toBe("USER review.feedback step:s1 why is it slow?"));
  it("step events show the step", () => expect(pushLine({ type: "step.done", actor: "user", step: "ask-x" })).toBe("USER step.done ask-x"));
});

describe("LineTail", () => {
  it("starts at the end, waits for a newline, restarts after rotation", () => {
    const { d, f } = setup();
    const t = new LineTail(f);
    expect(t.read()).toEqual([]);
    appendFileSync(f, '{"a":');
    expect(t.read()).toEqual([]);
    appendFileSync(f, '1}\n{"b":2}\n');
    expect(t.read()).toEqual(['{"a":1}', '{"b":2}']);
    renameSync(f, join(d, "events.old"));
    writeFileSync(f, '{"c":3}\n');
    expect(t.read()).toEqual(['{"c":3}']);
  });
});

describe.skipIf(!have)("obs.push golden", () => {
  it("fwcore answers every row of golden/obs/push.jsonl", async () => {
    const g = readFileSync(join(here, "../../../packages/contracts/golden/obs/push.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(g.length).toBeGreaterThan(5);
    for (const row of g) {
      const r = await core(row.request);
      expect({ push: r.push }, row.name).toEqual(row.response);
    }
  });
});

describe.skipIf(!have)("startPush", () => {
  it("prints a user question within the deadline", async () => {
    const { f } = setup();
    const out: string[] = [];
    const stop = startPush(f, core, (s) => out.push(s));
    appendFileSync(f, ev(user));
    const ms = await until(() => out.length > 0, 2000);
    stop();
    expect(out).toEqual(["USER review.feedback step:s1 why is it slow?"]);
    expect(ms).toBeLessThan(2000);
  });
  it("prints nothing for hook, script, lead or user step.start events", async () => {
    const { f } = setup();
    const out: string[] = [];
    const stop = startPush(f, core, (s) => out.push(s));
    appendFileSync(f, ev({ type: "agent.spawn", actor: "hook" }) + ev({ type: "step.done", actor: "script", step: "x" }) + ev({ type: "step.start", actor: "user", step: "y" }) + ev({ type: "review.feedback", actor: "lead", flag: "f", text: "t" }));
    appendFileSync(f, ev({ type: "step.done", actor: "user", step: "marker" }));
    await until(() => out.length > 0, 2000);
    stop();
    expect(out).toEqual(["USER step.done marker"]);
  });
  it("a partial line waits for its newline", async () => {
    const { f } = setup();
    const out: string[] = [];
    const stop = startPush(f, core, (s) => out.push(s));
    const full = ev(user);
    appendFileSync(f, full.slice(0, 30));
    await new Promise((r) => setTimeout(r, 1300));
    expect(out).toEqual([]);
    appendFileSync(f, full.slice(30));
    await until(() => out.length > 0, 2000);
    stop();
    expect(out.length).toBe(1);
  });
});
