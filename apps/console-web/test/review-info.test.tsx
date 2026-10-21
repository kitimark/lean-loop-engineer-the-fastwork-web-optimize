import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { ReviewInfo, mathHtml, statusText, type Excerpt, type Gain, type InfoData } from "../src/ReviewInfo";

const FLAG = "nav:earn-no-transition";

const gain = (o: Partial<Gain> = {}): Gain => ({
  metric: "earn max-width", engine: "model (both engines)", push: "open", viewport: "1440 and 390 (same)", before: [43, 43], after: [3, 3], noise: 0,
  unit: "frames of 91 with a style change", status: { kind: "modelled", theorem: "Fw.Parts.NavEarnOpt.work_le", golden: "golden/parts/nav-earn.jsonl" },
  shown: { kind: "gain", n: 40, text: "40 fewer" }, ...o,
});
const small = (gains: Gain[], excerpts: Excerpt[] = []): InfoData => ({
  ok: true, flag: FLAG, summary: "Open push: 40 fewer frames.", gains, excerpts, mechanism: ["Each frame --morph changes."],
  sources: [{ claim: "WebKit restarts a transition", status: "CONFIRMED", cite: "Styleable.cpp:743-756" }],
  formulas: [{ id: "worklE", tex: "\\mathrm{work}_{a}(n)\\le\\mathrm{work}_{f}(n)", says: "At most the faithful work.", decl: "work_le", file: "Fw/Parts/NavEarnOpt.lean", line: 230, kind: "theorem" }],
});
const html = (d: InfoData | null) => renderToStaticMarkup(<ReviewInfo flag={FLAG} data={d} />);

describe("ReviewInfo", () => {
  it("shows the three sections and the summary line", () => {
    const h = html(small([gain()]));
    for (const w of ["What you get if you keep it", "What changed in the code", "Why it is less work, and the math", "Open push: 40 fewer frames."]) expect(h).toContain(w);
  });
  it("every row prints its status; a gain inside the noise says so; UNKNOWN says why", () => {
    const h = html(small([
      gain(),
      gain({ engine: "chromium", status: { kind: "measured", runs: ["39463486725"], aa: ["39464294630"] }, before: [12, 12], after: [11, 12], noise: 2, shown: { kind: "inNoise", text: "not shown (inside A/A noise)" } }),
      gain({ engine: "webkit", before: null, after: null, status: { kind: "unknown", why: "too few frames" }, shown: { kind: "unknown", text: "unknown" } }),
    ]));
    expect(h.match(/data-testid="gain-row"/g)).toHaveLength(3);
    expect(h).toContain("MODELLED (Lean Fw.Parts.NavEarnOpt.work_le");
    expect(h).toContain("MEASURED (CI runs 39463486725; A/A runs 39464294630)");
    expect(h).toContain("UNKNOWN: too few frames");
    expect(h).toContain("not shown (inside A/A noise)");
    expect(h).toContain(">40 fewer<");
  });
  it("an overlap row prints that no difference is shown", () => {
    const h = html(small([gain({ engine: "chromium", status: { kind: "measured", runs: ["1"], aa: ["2"] }, before: [38, 40], after: [40, 41], noise: 4, shown: { kind: "overlap", text: "no difference shown (ranges overlap)" } })]));
    expect(h).toContain("no difference shown (ranges overlap)");
  });
  it("a code excerpt prints file:line and numbered lines; a moved anchor prints why it is not shown", () => {
    const h = html(small([gain()], [
      { id: "css-flag", side: "flag", file: "a/nav.css", first: 201, last: 203, anchor: "transition: none", note: "Flag only.", ok: true, lines: [{ n: 201, text: ".x {" }, { n: 202, text: "  transition: none;" }] },
      { id: "js", side: "flag", file: "a/logic.ts", first: 92, last: 95, anchor: "zz", note: "n", ok: false, reason: "the anchor is no longer there" },
    ]));
    expect(h).toContain("a/nav.css:201-203");
    expect(h).toContain(" 202    transition: none;");
    expect(h).toContain("Not shown: the anchor is no longer there");
  });
  it("a formula is KaTeX markup next to its Lean name and file:line", () => {
    const h = html(small([gain()]));
    expect(h).toContain('class="katex');
    expect(h).toContain("work_le");
    expect(h).toContain("Fw/Parts/NavEarnOpt.lean:230");
  });
  it("loading and refusal states", () => {
    expect(html(null)).toContain("review-info-loading");
    expect(html({ ok: false, reason: "no information table is written" })).toContain("No information is written");
  });
  it("statusText names the run ids", () => {
    expect(statusText({ kind: "measured", runs: ["1", "2"], aa: ["3"] })).toBe("MEASURED (CI runs 1, 2; A/A runs 3)");
  });
});

// The fixture is the Lean reply (console-api test review-info checks that it equals `console.reviewInfo`).
describe("ReviewInfo with the Lean reply", () => {
  const reply = JSON.parse(readFileSync(join(import.meta.dirname, "fixtures/review-info.earn.json"), "utf8"));
  const withLines = (): InfoData => ({
    ...reply,
    excerpts: reply.excerpts.map((e: any) => ({ ...e, ok: true, lines: [{ n: e.first, text: e.anchor }] })),
  });
  it("renders all 20 gain rows and every formula with KaTeX (throwOnError)", () => {
    const d = withLines();
    const h = html(d);
    expect(h.match(/data-testid="gain-row"/g)).toHaveLength(20);
    for (const f of reply.formulas) {
      expect(() => mathHtml(f.tex), f.id).not.toThrow();
      expect(h).toContain(`data-testid="formula-${f.id}"`);
      expect(h).toContain(`${f.file}:${f.line}`);
    }
    expect(reply.formulas.map((f: any) => f.decl)).toEqual(expect.arrayContaining(["visSame_settled", "work_le", "settled3_same", "shown_settled"]));
  });
  it("no row shows a number without a status, and WebKit rows are UNKNOWN", () => {
    const h = html(withLines());
    const rows = h.split('data-testid="gain-row"').slice(1);
    expect(rows).toHaveLength(20);
    for (const r of rows) expect(/MEASURED|MODELLED|UNKNOWN/.test(r)).toBe(true);
    const wk = rows.filter((r) => r.includes(">webkit<"));
    expect(wk).toHaveLength(2);
    expect(wk.every((r) => r.includes("UNKNOWN"))).toBe(true);
  });
});
