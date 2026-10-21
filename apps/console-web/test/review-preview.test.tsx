import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { ReviewCard, type ReviewItem } from "../src/Reviews";
import { armHref, openAndRecord, PreviewStatus, type PreviewState } from "../src/ReviewPreview";

const FLAG = "nav:earn-no-transition";
const none: PreviewState = { open: true, desktop: false, phone: false, missing: ["desktop", "phone"],
  asks: ["Not yet previewed on the phone: open the console at its LAN address on the phone and press Preview there."] };
const item = (o: Partial<ReviewItem> = {}): ReviewItem => ({
  flag: FLAG, step: `review-${FLAG}`, state: "open", date: "2026-10-21", words: "accepted, pending user visual review", audience: "user",
  changed: null, material: null, link: null, preview: none, ...o,
});
const noop = () => undefined;
const card = (i: ReviewItem) => renderToStaticMarkup(<ReviewCard item={i} confirming={null} busy={false} error={null} onAsk={noop} onConfirm={noop} onCancel={noop} />);

describe("Preview on a look-change review card", () => {
  it("an open review has the three Preview buttons next to Keep and Reject, and they are not disabled", () => {
    const html = card(item());
    for (const w of ["Preview: Flag", "Preview: Faithful", "Preview: Compare", ">Keep<", ">Reject<", 'data-testid="review-preview"']) expect(html).toContain(w);
    expect(html).not.toContain('disabled=""');
  });
  it("the device line says yes or no per device and asks for the missing one; nothing missing, no ask", () => {
    const html = card(item());
    expect(html).toContain("Previewed on: desktop no, phone no");
    expect(html).toContain("open the console at its LAN address on the phone");
    const done = renderToStaticMarkup(<PreviewStatus p={{ open: true, desktop: true, phone: true, missing: [], asks: [] }} />);
    expect(done).toContain("Previewed on: desktop yes, phone yes");
    expect(done).not.toContain('data-testid="preview-ask"');
    expect(renderToStaticMarkup(<PreviewStatus p={{ ...none, desktop: true, missing: ["phone"] }} />)).toContain("desktop yes, phone no");
  });
  it("a decided review and a card without preview data have no Preview section", () => {
    expect(card(item({ state: "keep" }))).not.toContain('data-testid="review-preview"');
    expect(card(item({ preview: null }))).not.toContain('data-testid="review-preview"');
    expect(card(item({ preview: { ...none, open: false } }))).not.toContain('data-testid="review-preview"');
  });
  it("the link is built from the page's own host (the phone over the LAN), not a fixed host", () => {
    expect(armHref(8788, `/preview/open-main-abc/r/?fw=${FLAG}`, { protocol: "http:", hostname: "fw-phone.test" })).toBe(`http://fw-phone.test:8788/preview/open-main-abc/r/?fw=${FLAG}`);
    expect(armHref(8788, "/preview/x/compare", { protocol: "http:", hostname: "localhost" })).toBe("http://localhost:8788/preview/x/compare");
    expect(armHref(null, "/preview/x/r/", { protocol: "http:", hostname: "localhost" })).toBe("/preview/x/r/");
  });

  it("a blocked pop-up records nothing at open; an opened window records once", async () => {
    let n = 0;
    const record = async () => { n++; };
    expect(await openAndRecord(null, "http://h/x", record)).toBe(false);
    expect(n).toBe(0);
    const w = { location: { href: "" } };
    expect(await openAndRecord(w, "http://h/x", record)).toBe(true);
    expect(w.location.href).toBe("http://h/x");
    expect(n).toBe(1);
  });
});
