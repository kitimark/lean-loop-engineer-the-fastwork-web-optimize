import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { PartCard, type CPart } from "../src/Compose";
import { StripCard, stripUrl, ReviewCard, ReviewsPanel, ReviewsTabLabel, openFlags, type ReviewItem, type ReviewsData } from "../src/Reviews";
import { landingOf } from "../src/App";

const FLAG = "nav:earn-no-transition";
const item = (o: Partial<ReviewItem> = {}): ReviewItem => ({
  flag: FLAG, step: `review-${FLAG}`, state: "open", date: "2026-10-21", words: "accepted, pending user visual review", audience: "user",
  changed: { id: "nav.earn.noTransition", candidate: "the earn button transitions are off while the nav morphs", visual: "not equal mid-transition", chromium: "win on the open push", webkit: "unknown" },
  material: { chromium: { state: "ready", run: "39473950464", artifact: "frames-chromium", expires: "2026-11-19" }, webkit: { state: "pending", task: "earn-look-review-webkit" } },
  link: null, ...o,
});
const data = (items: ReviewItem[]): ReviewsData => ({ ok: true, open: items.filter((i) => i.state === "open").length, options: ["keep", "reject"], items });
const noop = () => undefined;
const panel = (d: ReviewsData, over: Partial<Parameters<typeof ReviewsPanel>[0]> = {}) => renderToStaticMarkup(
  <ReviewsPanel data={d} confirm={null} busy={false} error={null} onAsk={noop} onConfirm={noop} onCancel={noop} {...over} />);

describe("Your reviews panel", () => {
  it("an open item shows what changed, the material state and Keep / Reject; no link shows the run id and artifact name", () => {
    const html = panel(data([item()]));
    for (const w of ["Your reviews", FLAG, "look change, review pending", "the earn button transitions are off while the nav morphs", "not equal mid-transition",
      "39473950464", "frames-chromium", "expires 2026-11-19", "pending (task earn-look-review-webkit)", ">Keep<", ">Reject<", 'data-testid="no-link"']) expect(html).toContain(w);
    expect(html).not.toContain('data-testid="review-link"');
    expect(html).not.toContain('data-testid="confirm"');
  });
  it("a link from .local/reviews.json becomes the review page link", () => {
    const html = panel(data([item({ link: "https://example.test/r" })]));
    expect(html).toContain('href="https://example.test/r"');
    expect(html).not.toContain('data-testid="no-link"');
  });
  it("Keep or Reject asks in the page first: the confirm step names the choice and has Cancel, no window.confirm", () => {
    const keep = panel(data([item()]), { confirm: { flag: FLAG, word: "keep" } });
    expect(keep).toContain('data-testid="confirm"');
    expect(keep).toContain("Keep this look change?");
    expect(keep).toContain("Yes, keep");
    expect(keep).toContain(">Cancel<");
    expect(keep).not.toContain(">Reject<");
    const reject = panel(data([item()]), { confirm: { flag: FLAG, word: "reject" } });
    expect(reject).toContain("Reject this look change?");
    expect(reject).toContain("Yes, reject");
    const src = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../src/Reviews.tsx"), "utf8");
    expect(src).not.toMatch(/window\.confirm|[^.\w]confirm\(/);
  });
  it("a decided item shows the decision and no buttons", () => {
    const kept = panel(data([item({ state: "keep" })]));
    expect(kept).toContain("You kept it.");
    expect(kept).not.toContain(">Keep<");
    expect(kept).not.toContain("look change, review pending");
    expect(panel(data([item({ state: "reject" })]))).toContain("You rejected it.");
  });
  it("a refusal from Lean is shown on its item", () => {
    expect(panel(data([item()]), { error: { flag: FLAG, text: "Refused: this review is already decided" } })).toContain("Refused: this review is already decided");
  });
  it("no items: an empty note", () => {
    expect(panel(data([]))).toContain('data-testid="no-reviews"');
  });
  it("open items are listed before decided ones", () => {
    const html = panel(data([item({ flag: "a:done", state: "keep" }), item({ flag: "b:open" })]));
    expect(html.indexOf("b:open")).toBeLessThan(html.indexOf("a:done"));
  });
  it("a card fits a 390 px screen: wrapping text and buttons at touch height, no fixed widths", () => {
    const html = renderToStaticMarkup(<ReviewCard item={item()} confirming={null} busy={false} error={null} onAsk={noop} onConfirm={noop} onCancel={noop} />);
    expect(html).toContain("min-h-11");
    expect(html).toContain("flex-wrap");
    expect(html).toContain("break-words");
    expect(html).not.toMatch(/\bw-\[\d+px\]/);
  });
});

describe("nav badge and Compose", () => {
  it("the nav badge shows the open count and disappears when none is open", () => {
    const open = renderToStaticMarkup(<ReviewsTabLabel data={data([item(), item({ flag: "x:y" })])} />);
    expect(open).toContain('data-testid="reviews-badge"');
    expect(open).toContain(">2<");
    expect(renderToStaticMarkup(<ReviewsTabLabel data={data([item({ state: "keep" })])} />)).not.toContain("reviews-badge");
    expect(renderToStaticMarkup(<ReviewsTabLabel data={null} />)).not.toContain("reviews-badge");
  });
  it("openFlags lists the flags of open items only", () => {
    expect(openFlags(data([item(), item({ flag: "x:y", state: "reject" })]))).toEqual([FLAG]);
    expect(openFlags(null)).toEqual([]);
  });
  const part: CPart = { id: "nav", slot: "nav", group: "solo", pageLevel: false, other: [], variants: [
    { name: "faithful", kind: "faithful", isDefault: true, class: "original", why: "the site as shipped", rows: [], refusal: null },
    { name: "earn-no-transition", kind: "proposal", isDefault: false, class: "look-change", why: "a look change", rows: [], refusal: null }] };
  it("Compose marks the variant 'look change, review pending' while its item is open, and not after", () => {
    const withOpen = renderToStaticMarkup(<PartCard part={part} chosen="faithful" rows={{}} rules={{}} onPick={noop} reviewPending={[FLAG]} />);
    expect(withOpen).toContain("look change, review pending");
    const closed = renderToStaticMarkup(<PartCard part={part} chosen="faithful" rows={{}} rules={{}} onPick={noop} reviewPending={[]} />);
    expect(closed).not.toContain("look change, review pending");
    expect(closed).toContain("look-change");
  });
  it("the reviews tab can be a landing", () => {
    expect(landingOf("?tab=reviews").tab).toBe("reviews");
  });
});

describe("frame strips in the review card", () => {
  const redo = "[ci:trajectory-probe] [frames:nav:earn-no-transition]";
  const ready = { engine: "chromium", state: "ready" as const, width: 390, push: "close" as const, file: "chromium-390-close.png", run: "1", artifact: "a", expires: "2026-11-19",
    note: "Look at the dark Join waitlist pill.", diff: "about 0.4 s earlier" };
  it("a ready strip shows tag, push name, diff, note, the legend and a scroll box for the image", () => {
    const html = renderToStaticMarkup(<StripCard flag={FLAG} s={ready} />);
    for (const w of ["Chromium · Phone 390", "Button comes back", "about 0.4 s earlier", "Look at the dark Join waitlist pill.",
      "Top row original, bottom row flag; frame number and ms under each shot", 'data-testid="strip-scroll"', "overflow-x-auto", "max-w-full"]) expect(html).toContain(w);
  });
  it("an empty note reads no note yet; the desktop tag and the open push name", () => {
    const html = renderToStaticMarkup(<StripCard flag={FLAG} s={{ ...ready, engine: "webkit", width: 1280, push: "open", note: "", diff: "" }} />);
    expect(html).toContain("WebKit · Desktop 1280");
    expect(html).toContain("Button leaves");
    expect(html).toContain("no note yet");
    expect(html).not.toContain('data-testid="strip-diff"');
  });
  it("an expired strip says which dispatch re-makes it and has no image box; a missing one is one plain line", () => {
    const ex = renderToStaticMarkup(<StripCard flag={FLAG} s={{ ...ready, state: "expired", redo }} />);
    expect(ex).toContain("expired on 2026-11-19");
    expect(ex).toContain(redo);
    expect(ex).not.toContain("strip-scroll");
    const miss = renderToStaticMarkup(<StripCard flag={FLAG} s={{ engine: "webkit", state: "missing", redo }} />);
    expect(miss).toContain("WebKit strips: none made");
    expect(miss).toContain(redo);
  });
  it("the card lists its strips with the external link kept as a fallback; the image address is encoded", () => {
    const html = renderToStaticMarkup(<ReviewCard item={item({ strips: [ready, { ...ready, file: "chromium-1280-close.png", width: 1280 }], link: "https://example.test/r" })}
      confirming={null} busy={false} error={null} onAsk={noop} onConfirm={noop} onCancel={noop} />);
    expect(html).toContain('data-testid="strips"');
    expect(html.match(/data-testid="strip"/g)).toHaveLength(2);
    expect(html).toContain("Fallback:");
    expect(html).toContain('href="https://example.test/r"');
    expect(html.indexOf('data-testid="strips"')).toBeLessThan(html.indexOf(">Keep<"));
    expect(stripUrl(FLAG, "a b.png")).toBe("/api/reviews/nav%3Aearn-no-transition/strips/a%20b.png");
  });
});
