import { afterEach, describe, expect, it, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { ReviewCard, type ReviewItem } from "../src/Reviews";
import { FeedbackThreadView, makeCid, ReviewFeedback } from "../src/ReviewFeedback";

afterEach(() => vi.unstubAllGlobals());

const FLAG = "nav:earn-no-transition";
const item = (o: Partial<ReviewItem> = {}): ReviewItem => ({
  flag: FLAG, step: `review-${FLAG}`, state: "open", date: "2026-10-21", words: "pending", audience: "user",
  changed: null, material: null, link: null, preview: null, ...o,
});
const noop = () => undefined;
const card = (i: ReviewItem) => renderToStaticMarkup(<ReviewCard item={i} confirming={null} busy={false} error={null} onAsk={noop} onConfirm={noop} onCancel={noop} />);
const thread = { flag: FLAG, open: 1, comments: [
  { id: "fb-1", text: "look at the <b>font</b>", at: 1_700_000_000_000, status: "answered" as const, reply: { text: "done, see note", at: 1_700_000_060_000 } },
  { id: "fb-2", text: "and the colour", at: 1_700_000_120_000, status: "open" as const, reply: null }] };

describe("Feedback section of a review card", () => {
  it("has a textarea and a Send button, also with no comments yet", () => {
    const html = card(item());
    for (const w of ['data-testid="review-feedback"', "<textarea", 'data-testid="feedback-send"', ">Send<", "No comments yet."]) expect(html).toContain(w);
  });
  it("shows each comment with its time, a status chip and the lead's reply; the open count is in the heading", () => {
    const html = card(item({ feedback: thread }));
    expect(html).toContain("Feedback (1 open)");
    expect(html).toContain("2023-11-14 22:13");
    expect(html).toContain(">answered<");
    expect(html).toContain(">open<");
    expect(html).toContain("Lead replied 2023-11-14 22:14");
    expect(html).toContain("done, see note");
  });
  it("renders the text as plain text, never as HTML", () => {
    const html = renderToStaticMarkup(<FeedbackThreadView thread={thread} />);
    expect(html).toContain("&lt;b&gt;font&lt;/b&gt;");
    expect(html).not.toContain("<b>font</b>");
  });
  it("a decided card still shows its thread", () => {
    expect(card(item({ state: "keep", feedback: thread }))).toContain("and the colour");
  });
  it("the textarea and Send button are full width on a phone (block / w-full) and the button is a 44 px target", () => {
    const html = renderToStaticMarkup(<ReviewFeedback flag={FLAG} thread={null} />);
    expect(html).toMatch(/<textarea[^>]*class="[^"]*w-full/);
    expect(html).toMatch(/<button[^>]*class="[^"]*min-h-11[^"]*w-full/);
  });
});

describe("the client id on the plain-http LAN page", () => {
  it("is made without crypto.randomUUID and fits the server's pattern", () => {
    vi.stubGlobal("crypto", { getRandomValues: globalThis.crypto.getRandomValues.bind(globalThis.crypto) });
    const a = makeCid(); const b = makeCid();
    expect(a).toMatch(/^[A-Za-z0-9-]{8,60}$/);
    expect(a).not.toBe(b);
  });
});
