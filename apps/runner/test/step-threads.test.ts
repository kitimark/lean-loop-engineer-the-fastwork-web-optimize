import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, afterEach, describe, expect, it, vi } from "vitest";
import { UsageError, stepCommand } from "../src/lib.ts";
import { renderQuestions, replyCommand, stepWithTopic, subjectOf, topicCommand, type Thread } from "../src/step-threads.ts";
import { collectFeedback } from "../src/watch-collect.ts";
import { check, coreCaller } from "../src/watch.ts";
import { pathsFor } from "../src/watch-collect.ts";

afterEach(() => vi.unstubAllGlobals());
const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const t = (flag: string, ids: string[]): Thread => ({ flag, open: ids.length, comments: ids.map((id) => ({ id, text: "q", at: 0, status: "open", reply: null })) });

describe("fw step topic and fw step post --topic", () => {
  it("topic is the step.topic command, lead by default", () => {
    expect(topicCommand(["--id", "smooth", "--title", "Smoothness", "--summary", "Hero exit first."], {})).toMatchObject({
      type: "step.topic", actor: "lead", topic: "smooth", title: "Smoothness", summary: "Hero exit first." });
  });
  it("takes the actor from FW_ACTOR or --as; a missing part is a usage error", () => {
    expect(topicCommand(["--id", "a", "--title", "T", "--summary", "S", "--as", "script"], { FW_ACTOR: "user" })).toMatchObject({ actor: "script" });
    expect(() => topicCommand(["--id", "a", "--title", "T"], {})).toThrow(UsageError);
    expect(() => topicCommand(["--title", "T", "--summary", "S"], {})).toThrow(UsageError);
    expect(() => topicCommand(["--id", "a", "--summary", "S"], {})).toThrow(UsageError);
  });
  it("step post carries --topic when given and nothing when not", () => {
    expect(stepWithTopic(["post", "s1", "--title", "x", "--topic", "smooth"], {})).toMatchObject({ type: "step.post", step: "s1", title: "x", topic: "smooth" });
    expect("topic" in stepWithTopic(["post", "s1", "--title", "x"], {})).toBe(false);
    expect(stepWithTopic(["start", "s1"], {})).toEqual(stepCommand(["start", "s1"], {}));
  });
});

describe("fw step usage", () => {
  it("the step usage error names the thread commands", () => {
    let msg = "";
    try { stepWithTopic([], {}); } catch (e) { msg = (e as Error).message; }
    expect(msg).toContain("fw step topic");
  });
});

describe("fw step reply (the lead answers a question)", () => {
  const threads = [t("step:a", ["fb-1"]), t("topic:smooth", ["fb-2"]), t("step:smooth", ["fb-3"]), t("topic:smooth2", ["fb-3"])];
  it("finds the subject that holds the comment", () => {
    expect(subjectOf(threads, "a", "fb-1")).toBe("step:a");
    expect(subjectOf(threads, "smooth", "fb-2")).toBe("topic:smooth");
  });
  it("an id that is both a step and a topic with the same comment id needs --kind", () => {
    const both = [t("step:x", ["fb-9"]), t("topic:x", ["fb-9"])];
    expect(() => subjectOf(both, "x", "fb-9")).toThrow(UsageError);
    expect(subjectOf(both, "x", "fb-9", "topic")).toBe("topic:x");
  });
  it("an unknown comment is a usage error", () => {
    expect(() => subjectOf(threads, "a", "fb-nope")).toThrow(UsageError);
    expect(() => subjectOf(threads, "a", "fb-2")).toThrow(UsageError);
  });
  it("is the review.feedback.reply command on that subject, read from console-api", async () => {
    vi.stubGlobal("fetch", async (url: string) => new Response(JSON.stringify({ ok: true, threads }), { headers: { "content-type": "application/json" } }));
    expect(await replyCommand(["--id", "a", "--to", "fb-1", "--text", "done"], {}, "http://x")).toEqual({
      type: "review.feedback.reply", key: "review-feedback-reply:fb-1", actor: "lead", flag: "step:a", to: "fb-1", text: "done" });
    await expect(replyCommand(["--id", "a", "--to", "fb-1"], {}, "http://x")).rejects.toThrow(UsageError);
    await expect(replyCommand(["--id", "a", "--to", "fb-1", "--text", "x", "--kind", "card"], {}, "http://x")).rejects.toThrow(UsageError);
  });
  it("a refusal from console-api is reported", async () => {
    vi.stubGlobal("fetch", async () => new Response(JSON.stringify({ ok: false, reason: "boom" })));
    await expect(replyCommand(["--id", "a", "--to", "fb-1", "--text", "x"], {}, "http://x")).rejects.toThrow("refused: boom");
  });
});

describe("fw step questions", () => {
  const th: Thread[] = [{ flag: "step:a", open: 1, comments: [
    { id: "fb-1", text: "one", at: 0, status: "answered", reply: { text: "ok", at: 1000 } },
    { id: "fb-2", text: "two\nlines", at: 2000, status: "open", reply: null }] }];
  it("prints the open questions only, and all of them with --all", () => {
    const open = renderQuestions(th, false);
    expect(open).toContain("step:a  fb-2");
    expect(open).not.toContain("fb-1");
    const all = renderQuestions(th, true);
    expect(all).toContain("fb-1");
    expect(all).toContain("reply (1970-01-01T00:00:01.000Z): ok");
  });
  it("says so when nothing is open", () => {
    expect(renderQuestions([], false)).toBe("no open questions");
    expect(renderQuestions([{ ...th[0]!, comments: [th[0]!.comments[0]!] }], false)).toBe("no open questions");
  });
});

describe("step.question alert (Lean Fw.Obs.Health, fed by the log through collectFeedback)", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
  const have = existsSync(bin);
  const core = coreCaller(have ? [bin] : []);
  const line = (o: object) => JSON.stringify(o);
  const post = (id: string, flag: string, ts: number) => line({ seq: ts, ts, type: "review.feedback", key: `k-${id}`, actor: "user", flag, id, text: `q ${id}` });
  const reply = (to: string, flag: string, ts: number) => line({ seq: ts, ts, type: "review.feedback.reply", key: `r-${to}`, actor: "lead", flag, to, text: "a" });
  const dirWith = (lines: string[]) => {
    const d = mkdtempSync(join(tmpdir(), "fwstep-")); dirs.push(d);
    writeFileSync(join(d, "events.jsonl"), lines.join("\n") + "\n");
    return pathsFor("/x/r", { FW_CONSOLE_DIR: d } as never);
  };
  const snap = (feedback: unknown[]) => ({
    now: 1_000_000, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null },
    system: { load1: 0, memPressure: "normal", diskFreeGB: 100, simLock: { holder: null, since: null }, docker: [], worktrees: 1, consolePids: [], ci: [], stale: [], feedback },
  }) as never;
  const codes = async (lines: string[]) => (await check(snap(collectFeedback(dirWith(lines))), core)).alerts.filter((a) => a.code === "step.question" || a.code === "review.feedback").map((a) => [a.code, a.subject]);

  it.skipIf(!have)("a question on a step or topic opens step.question, not review.feedback; the lead's reply closes it", async () => {
    expect(await codes([post("fb-1", "step:a", 1), post("fb-2", "topic:t", 2), post("fb-3", "nav:x", 3)])).toEqual([
      ["review.feedback", "nav:x"], ["step.question", "step:a"], ["step.question", "topic:t"]]);
    expect(await codes([post("fb-1", "step:a", 1), reply("fb-1", "step:a", 2)])).toEqual([]);
  });
});
