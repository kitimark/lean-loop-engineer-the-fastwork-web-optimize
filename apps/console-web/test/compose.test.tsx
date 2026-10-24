import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { ComposePanel, ComposeView, Explain, PartCard, byRegion, type CData, type CRow } from "../src/Compose";
import { landingOf } from "../src/App";
import { COPY_FAILED, answersNow, copyKnown, newestWins, openSearch, pickQuery } from "../src/composeOpen";

const row = (o: Partial<CRow> = {}): CRow => ({
  index: 0, candidate: "morph.tween `waapi`", status: "refuted", chromium: "10 ms slower", webkit: "same", visual: "identical", mechanism: "one WAAPI animation",
  leanFor: ["the frames match"], leanAgainst: ["the count rose"], lesson: "a register costs more", next: "", evidence: "", runs: ["24123456789"], notes: [], ...o,
});
const data = (o: Partial<CData> = {}): CData => ({
  regions: ["hero", "morph"],
  parts: [
    { id: "hero.countdown", slot: "hero", group: "solo", pageLevel: false, other: [], variants: [
      { name: "faithful", kind: "faithful", isDefault: true, class: "original", why: "the site as shipped", rows: [], refusal: null },
      { name: "strip", kind: "optimized", isDefault: false, class: "measured", why: "measured, not in v2-proved", rows: [1], refusal: null }] },
    { id: "morph.tween", slot: "morph", group: "g2", pageLevel: true, other: [], variants: [
      { name: "faithful", kind: "faithful", isDefault: true, class: "original", why: "the site as shipped", rows: [], refusal: null },
      { name: "waapi", kind: "optimized", isDefault: false, class: "refuted", why: "refuted", rows: [0], refusal: "refuted by finding morph.tween `waapi`" }] }],
  presets: [{ name: "original", picks: [], ok: true, link: "", reasons: [], notes: [] }, { name: "v2-proved", picks: [], ok: true, link: "", reasons: [], notes: [] },
    { name: "bad", picks: [{ part: "morph.tween", variant: "waapi" }], ok: false, link: null, reasons: ["refuted"], notes: [] }],
  rules: { original: "the site as shipped", measured: "measured, not proved", refuted: "refuted: it made things worse" },
  rows: { "0": row(), "1": row({ index: 1, candidate: "hero.countdown `strip`", status: "measured", runs: [] }) },
  decision: { ok: true, link: "", reasons: [], notes: [] }, canPreview: true, previewPort: 4001, ...o,
});
const panel = (d: CData, over: Record<string, unknown> = {}) => renderToStaticMarkup(
  <ComposePanel d={d} picks={{}} setPicks={() => undefined} busy={false} msg={null} reasons={[]} opened={null} copied={false} onOpen={() => undefined} {...over} />);

describe("Compose page render", () => {
  it("one card per part, grouped by region in page order, each variant with a class badge and a why-line", () => {
    const html = panel(data());
    expect(html.indexOf('data-testid="region-hero"')).toBeLessThan(html.indexOf('data-testid="region-morph"'));
    expect(html).toContain('data-testid="part-hero.countdown"');
    expect(html).toContain('data-testid="part-morph.tween"');
    for (const w of ["original", "measured", "refuted", "the site as shipped", "refuted by finding morph.tween"]) expect(html).toContain(w);
    expect(byRegion(data().parts).map((g) => [g.region, g.parts.length])).toEqual([["hero", 1], ["morph", 1]]);
  });
  it("a GPU variant shows the GPU pill and its mechanism as text; a non-GPU one does not", () => {
    const d = data();
    d.parts[0]!.variants[1] = { ...d.parts[0]!.variants[1]!, gpu: "one strip per digit: 80 composited layers become 8", gpuEngines: "WebKit only" };
    const gpu = renderToStaticMarkup(<PartCard part={d.parts[0]!} chosen="strip" rows={d.rows} rules={d.rules} onPick={() => undefined} />);
    expect(gpu.match(/data-testid="gpu-pill"/g)?.length).toBe(1);
    expect(gpu).toContain(">GPU<");
    expect(gpu).toContain("GPU (WebKit only): one strip per digit: 80 composited layers become 8");
    const plain = renderToStaticMarkup(<PartCard part={data().parts[1]!} chosen="waapi" rows={d.rows} rules={d.rules} onPick={() => undefined} />);
    expect(plain).not.toContain("gpu-pill");
    expect(plain).not.toContain("GPU");
  });
  it("presets are one-click starts: default, v2-proved; a refused preset is disabled with its reason", () => {
    const html = panel(data());
    expect(html).toContain("Default (faithful)");
    expect(html).toContain(">v2-proved<");
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*title="refuted"[^>]*>bad</);
  });
  it("a ledger-proved variant has its own badge and why-line", () => {
    const d = data({ rules: { "ledger-proved": "proved in the ledger, not yet admitted to v2-proved by the gate" } });
    d.parts[0]!.variants[1] = { ...d.parts[0]!.variants[1]!, class: "ledger-proved" };
    const card = renderToStaticMarkup(<PartCard part={d.parts[0]!} chosen="strip" rows={d.rows} rules={d.rules} onPick={() => undefined} />);
    expect(card).toContain("ledger-proved");
    expect(card).toContain("proved in the ledger, not yet admitted to v2-proved by the gate");
  });
  it("shows the generated search and the Open, Open compare and Copy link actions", () => {
    const html = panel(data({ decision: { ok: true, link: "?fw=hero.countdown:strip", reasons: [], notes: ["a note"] } }));
    expect(html).toContain("?fw=hero.countdown:strip");
    for (const w of [">Open<", "Open compare", "Copy link", "a note"]) expect(html).toContain(w);
    expect(html).not.toMatch(/<button[^>]*disabled=""[^>]*>Open</);
  });
  it("a refused combination shows its reasons and cannot be opened", () => {
    const html = panel(data({ decision: { ok: false, link: null, reasons: ["morph.tween:waapi is refuted"], notes: [] } }));
    expect(html).toContain("(refused)");
    expect(html).toContain("morph.tween:waapi is refuted");
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Open</);
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Copy link</);
  });
  it("without an owner token the actions are disabled and the page says why", () => {
    const html = panel(data({ canPreview: false }));
    expect(html).toContain("Sign in as owner");
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Open</);
  });
  it("the explanation carries the ledger's fields and the runs it cites", () => {
    const html = renderToStaticMarkup(<Explain row={row()} />);
    for (const w of ["Mechanism", "Visual", "Chromium", "WebKit", "Lean, for", "Lean, against", "Lesson", "the frames match", "the count rose", "24123456789"]) expect(html).toContain(w);
    const card = renderToStaticMarkup(<PartCard part={data().parts[1]!} chosen="waapi" rows={data().rows} rules={data().rules} onPick={() => undefined} />);
    expect(card).toContain("Show the explanation");
    expect(card).toContain("refuted: it made things worse");
  });
  it("fits a 390 px phone: no fixed wide input, wrapping text, a stacked variant row, a wrapping nav", () => {
    const html = panel(data());
    expect(html).not.toMatch(/min-w-\[\d+rem\]/);
    expect(html).toContain("break-all");
    expect(html).toContain("flex-col");
    expect(html).toContain("sm:grid-cols-2");
    expect(html).toContain("min-w-0");
  });
  it("the tab is reachable by a landing link, and the view starts empty until the server answers", () => {
    expect(landingOf("?tab=compose")).toEqual({ tab: "compose", note: null });
    expect(landingOf("?tab=builds").tab).toBe("builds");
    expect(renderToStaticMarkup(<ComposeView />)).toContain("Loading parts");
  });
});

describe("a decision that answers an older pick", () => {
  const live = data({ decision: { ok: true, link: "?fw=hero.countdown:strip", reasons: [], notes: ["a note"] } });
  it("while stale: Open, Open compare and Copy link are disabled, the page says updating and shows no old link, reasons or notes", () => {
    const html = panel(live, { stale: true, opened: "http://h/preview/p1" });
    expect(html).toContain("updating…");
    expect(html).not.toContain("?fw=hero.countdown:strip");
    expect(html).not.toContain("a note");
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Open</);
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Open compare</);
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>Copy link</);
  });
  it("when the decision is current the Open actions are enabled", () => {
    const html = panel(live, { stale: false });
    expect(html).not.toContain("updating…");
    expect(html).not.toMatch(/<button[^>]*disabled=""[^>]*>Open</);
    expect(html).not.toMatch(/<button[^>]*disabled=""[^>]*>Open compare</);
  });
  it("a reply answers the picks only when it was fetched for the current query", () => {
    expect(answersNow("?pick=a:b", "?pick=a:b")).toBe(true);
    expect(answersNow("", "?pick=a:b")).toBe(false);
    expect(answersNow(null, "")).toBe(false);
  });
  it("the newest request wins: a late reply of an older one is dropped", () => {
    const g = newestWins();
    const first = g.next(), second = g.next();
    expect(g.isLatest(first)).toBe(false);
    expect(g.isLatest(second)).toBe(true);
  });
});

describe("Copy link", () => {
  it("is disabled until a link is opened, and then copies that link", () => {
    expect(panel(data(), { opened: null })).toMatch(/<button[^>]*disabled=""[^>]*>Copy link</);
    expect(panel(data(), { opened: "http://h/preview/p1" })).not.toMatch(/<button[^>]*disabled=""[^>]*>Copy link</);
  });
  it("copies the known link at once, and says how to get it when the copy fails", async () => {
    const seen: string[] = [];
    const ok = await copyKnown("http://h/p", (t) => { seen.push(t); return Promise.resolve(true); });
    expect(ok).toEqual({ copied: true, message: null });
    expect(seen).toEqual(["http://h/p"]);
    expect(await copyKnown("http://h/p", () => Promise.resolve(false))).toEqual({ copied: false, message: "Copy failed: long-press the link below" });
  });
  it("shows the failure message and the link as selectable text", () => {
    const html = panel(data(), { opened: "http://h/preview/p1", copyMsg: COPY_FAILED });
    expect(html).toContain("Copy failed: long-press the link below");
    expect(html).toContain('class="select-all underline"');
    expect(html.indexOf("Copy failed")).toBeLessThan(html.indexOf("http://h/preview/p1</a>"));
  });
  it("hides a copy failure message when there is no current opened link", () => {
    expect(panel(data(), { opened: null, copyMsg: COPY_FAILED })).not.toContain("Copy failed");
  });
});

describe("pickQuery", () => {
  it("is empty for no picks, sorted, and keeps part:variant readable", () => {
    expect(pickQuery({})).toBe("");
    expect(pickQuery({ "pain.notes": "visible", "hero.countdown": "strip" })).toBe("?pick=hero.countdown:strip,pain.notes:visible");
  });
});

describe("openSearch: the composed search goes through the Builds open path", () => {
  const res = (j: unknown) => Promise.resolve({ json: () => Promise.resolve(j) } as Response);
  it("posts the canonical search with the arm, waits for a building preview, then returns the preview url and path", async () => {
    const calls: { url: string; body?: unknown }[] = [];
    let serving = false;
    const f = (url: string, init?: RequestInit) => {
      calls.push({ url, body: init?.body ? JSON.parse(String(init.body)) : undefined });
      if (url === "/api/previews") { serving = true; return res({ previews: [{ id: "p1", phase: "serving" }], failed: [] }); }
      return serving ? res({ ok: true, state: "open", preview: "p1", path: "/preview/p1/compare?fw=a:b", url: "http://192.0.2.1:4001/preview/p1/compare?fw=a:b", canonical: "?fw=a:b" })
        : res({ ok: true, state: "pending", preview: "p1" });
    };
    const opened: string[] = [];
    const r = await openSearch("?fw=a:b", "compare", { fetch: f, sleep: () => Promise.resolve(), previewBase: "http://h:4001", refused: String, onOpen: (h) => opened.push(h) });
    expect(r).toEqual({ ok: true, url: "http://192.0.2.1:4001/preview/p1/compare?fw=a:b", path: "/preview/p1/compare?fw=a:b", canonical: "?fw=a:b" });
    expect(opened).toEqual(["http://h:4001/preview/p1/compare?fw=a:b"]);
    expect(calls[0]).toEqual({ url: "/api/builds/open", body: { search: "?fw=a:b", arm: "compare" } });
    expect(calls.map((c) => c.url)).toEqual(["/api/builds/open", "/api/previews", "/api/builds/open"]);
  });
  it("a refused search opens nothing and returns the reasons; a failed build returns its error", async () => {
    const refused = await openSearch("?fw=x:y", "r", { fetch: () => res({ ok: false, reason: "search refused", reasons: ["unknown part"] }), previewBase: "", refused: String });
    expect(refused).toMatchObject({ ok: false, reasons: ["unknown part"] });
    const notOwner = await openSearch("", "r", { fetch: () => res({ ok: false, reason: "notOwner" }), previewBase: "", refused: (x) => `refused: ${x}` });
    expect(notOwner).toMatchObject({ ok: false, message: "refused: notOwner" });
    const f = (url: string) => (url === "/api/previews" ? res({ previews: [], failed: [{ id: "p2", error: "pnpm failed" }] }) : res({ ok: true, state: "pending", preview: "p2" }));
    expect(await openSearch("", "r", { fetch: f, sleep: () => Promise.resolve(), previewBase: "", refused: String })).toMatchObject({ ok: false, message: "The build failed: pnpm failed" });
  });
});
