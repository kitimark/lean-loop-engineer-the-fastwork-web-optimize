import { afterEach, describe, expect, it, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import type { Board, Step } from "@fw/contracts";
import { Steps } from "../src/App";
import { sendFeedback } from "../src/ReviewFeedback";
import { QuestionBox, TopicGroup, questionWords, type StepTopics } from "../src/StepThreads";

afterEach(() => vi.unstubAllGlobals());

const step = (id: string, o: Partial<Step> = {}): Step => ({
  id, card: null, title: `title ${id}`, kind: "action", options: null, status: "waiting", postedAt: 0, answer: null,
  audience: "user", body: "", ...o,
} as Step);
const board = (steps: Step[]): Board => ({ steps, cards: [], seq: 1, now: 1000 } as unknown as Board);
const thread = (flag: string, open: number) => ({ flag, open, comments: [
  { id: "fb-1", text: "why <b>this</b>?", at: 1_700_000_000_000, status: open > 0 ? "open" as const : "answered" as const,
    reply: open > 0 ? null : { text: "because", at: 1_700_000_060_000 } }] });
const group = (o: Partial<StepTopics["groups"][number]> = {}) => ({
  topic: "smooth", title: "Smoothness", summary: "Hero exit first.", updatedAt: 1_700_000_000_000, steps: ["a"], openQuestions: 0, activity: 0, thread: null, ...o });
const html = (steps: Step[], topics: StepTopics | null) => renderToStaticMarkup(<Steps board={board(steps)} act={async () => {}} now={1000} topics={topics} />);

describe("Your steps grouped by topic (Lean console.stepTopics order)", () => {
  const topics: StepTopics = { groups: [
    group({ openQuestions: 1, thread: thread("topic:smooth", 1), steps: ["a", "b"] }),
    group({ topic: null, title: "Other", summary: "", updatedAt: null, steps: ["c"] }),
    group({ topic: "quiet", title: "Quiet topic", summary: "Nothing open.", steps: [] }),
  ], threads: [thread("step:a", 1), thread("topic:smooth", 1)] };
  const out = html([step("a"), step("b"), step("c")], topics);
  it("shows each group with its title, the lead's summary, its time and the steps in the group", () => {
    expect(out).toContain("Your steps (3)");
    expect(out).toContain(">Smoothness<");
    expect(out).toContain("Hero exit first.");
    expect(out).toContain("updated 2023-11-14 22:13");
    expect(out.indexOf("title a")).toBeGreaterThan(out.indexOf(">Smoothness<"));
    expect(out.indexOf("title c")).toBeGreaterThan(out.indexOf(">Other<"));
  });
  it("keeps the groups in the order Lean gave and still shows a quiet topic", () => {
    expect(out.indexOf(">Smoothness<")).toBeLessThan(out.indexOf(">Other<"));
    expect(out.indexOf(">Other<")).toBeLessThan(out.indexOf(">Quiet topic<"));
  });
  it("counts the questions waiting on a topic and opens the thread of a step with one", () => {
    expect(out).toContain("1 question waiting");
    expect(out).toMatch(/data-testid="step-questions-a"[^>]*open/);
    expect(out).not.toMatch(/data-testid="step-questions-b"[^>]*open/);
    expect(out).toContain("1 waiting for the lead");
  });
  it("renders a question as plain text, never as HTML", () => {
    expect(out).toContain("why &lt;b&gt;this&lt;/b&gt;?");
    expect(out).not.toContain("why <b>this</b>?");
  });
  it("gives the Other group no topic thread, and each step and topic a question box", () => {
    expect(out).toContain('data-testid="topic-questions-smooth"');
    expect(out).not.toContain('data-testid="topic-questions-null"');
    for (const id of ["a", "b", "c"]) expect(out).toContain(`data-testid="step-questions-${id}"`);
  });
  it("falls back to the flat list before the groups are loaded", () => {
    const flat = html([step("a")], null);
    expect(flat).toContain("title a");
    expect(flat).not.toContain('data-testid="topic-group"');
    expect(flat).not.toContain("Ask a question");
  });
});

describe("a question box", () => {
  it("is a textarea and a Send button, and says Ask a question while there is no thread", () => {
    const h = renderToStaticMarkup(<QuestionBox kind="step" id="a" thread={null} />);
    for (const w of ["Ask a question", "<textarea", 'data-testid="feedback-send"', "Questions"]) expect(h).toContain(w);
  });
  it("a topic group shows an answered reply under its question", () => {
    const h = renderToStaticMarkup(<TopicGroup group={group({ thread: thread("topic:smooth", 0) })} renderStep={() => null} />);
    expect(h).toContain("Lead replied 2023-11-14 22:14");
    expect(h).toContain("because");
  });
});

describe("a closed step keeps its thread", () => {
  it("an answered step whose thread has a reply shows that reply", () => {
    const out = html([step("z", { status: "answered", answer: "yes" } as Partial<Step>)], { groups: [], threads: [thread("step:z", 0)] });
    expect(out).toContain("answered: title z (yes)");
    expect(out).toContain("because");
  });
});

describe("the send of a question", () => {
  const stub = (reply: unknown) => {
    const calls: { url: string; init: RequestInit }[] = [];
    vi.stubGlobal("crypto", { getRandomValues: globalThis.crypto.getRandomValues.bind(globalThis.crypto) });
    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => { calls.push({ url, init }); return new Response(JSON.stringify(reply), { headers: { "content-type": "application/json" } }); });
    return calls;
  };
  it("POSTs {text, cid} to the step's or topic's question route", async () => {
    const calls = stub({ ok: true });
    const w = questionWords("step", "a b");
    const r = await sendFeedback("step:a b", "why?", null, w.url);
    expect(r.error).toBeNull();
    expect(calls[0]!.url).toBe("/api/steps/step/a%20b/question");
    expect(calls[0]!.init.method).toBe("POST");
    expect(JSON.parse(String(calls[0]!.init.body))).toEqual({ text: "why?", cid: r.cid });
    expect(questionWords("topic", "t").url).toBe("/api/steps/topic/t/question");
  });
  it("shows why a question was not recorded", async () => {
    stub({ ok: false, reason: "text is empty" });
    expect((await sendFeedback("topic:t", " ", null, questionWords("topic", "t").url)).error).toBe("Refused: text is empty");
  });
});
