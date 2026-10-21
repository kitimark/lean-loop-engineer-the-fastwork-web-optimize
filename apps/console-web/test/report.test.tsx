import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { ReportsPanel, openReports, tagWords, type ReportItem, type ReportsData } from "../src/Reports";

const EXAMPLE = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../../../results/review-reports/example.json"), "utf8"));
const item = (o: Partial<ReportItem> = {}): ReportItem => ({ id: EXAMPLE.id, step: `report-${EXAMPLE.id}`, title: EXAMPLE.title, state: "open", post: true, report: EXAMPLE, feedback: null, ...o });
const data = (items: ReportItem[]): ReportsData => ({ ok: true, open: items.filter((i) => i.state === "open").length, options: ["approve", "hold", "reject"], items, invalid: [] });
const noop = () => undefined;
const panel = (d: ReportsData, over: Partial<Parameters<typeof ReportsPanel>[0]> = {}) => renderToStaticMarkup(
  <ReportsPanel data={d} confirm={null} comments={{}} busy={false} error={null} onComment={noop} onAsk={noop} onConfirm={noop} onCancel={noop} {...over} />);

describe("Reports section", () => {
  it("shows the arms side by side with their searches and a metric table with a column per arm", () => {
    const html = panel(data([item()]));
    expect(html.match(/data-testid="report-arm"/g)).toHaveLength(2);
    expect(html).toContain("original-snapshot");
    expect(html).toContain("rewrite");
    expect(html).toContain('data-testid="report-table"');
    expect(html.match(/data-testid="report-row"/g)!.length).toBe(EXAMPLE.lanes[0].rows.length);
    expect(html).toContain("frame interval p50");
    expect(html).toContain("2491.18");
    expect(html).toContain("report, waiting for you");
    expect(html).toContain("Recommendation: adopt.");
  });
  it("every cell prints its tag: MEASURED with the run id, INFERRED with its reason", () => {
    const html = panel(data([item()]));
    expect(html).toContain("MEASURED run 39634194664");
    expect(html).toContain("INFERRED: ");
    expect(html.match(/data-testid="tag"/g)!.length).toBe(EXAMPLE.lanes[0].rows.length * 2);
    expect(tagWords({ kind: "measured", run: "7" })).toBe("MEASURED run 7");
    expect(tagWords(undefined)).toBe("no tag");
  });
  it("links the strips over https only", () => {
    expect(panel(data([item()]))).toContain('data-testid="report-strips"');
    const bad = { ...EXAMPLE, strips: "javascript:alert(1)" };
    const html = panel(data([item({ report: bad })]));
    expect(html).not.toContain('data-testid="report-strips"');
    expect(html).toContain('data-testid="report-no-strips"');
  });
  it("an open report asks first: Approve / Hold / Reject, then a confirm step with Cancel and no window.confirm", () => {
    const html = panel(data([item()]));
    for (const w of [">Approve<", ">Hold<", ">Reject<", 'data-testid="report-comment"']) expect(html).toContain(w);
    expect(html).not.toContain('data-testid="report-confirm"');
    const c = panel(data([item()]), { confirm: { id: EXAMPLE.id, word: "approve" }, comments: { [EXAMPLE.id]: "check the phone" } });
    expect(c).toContain('data-testid="report-confirm"');
    expect(c).toContain("Approve this report?");
    expect(c).toContain("Yes, approve");
    expect(c).toContain(">Cancel<");
    expect(c).toContain("check the phone");
    expect(c).not.toContain(">Hold<");
  });
  it("an answered report shows the decision and no buttons", () => {
    const html = panel(data([item({ state: "hold" })]));
    expect(html).toContain("You put this report on hold.");
    expect(html).not.toContain(">Approve<");
    expect(openReports(data([item({ state: "hold" })]))).toBe(0);
    expect(openReports(data([item()]))).toBe(1);
  });
  it("fits 390 px: min-w-0 cards, scrolling tables, 44 px buttons, wrapping text", () => {
    const html = panel(data([item()]));
    for (const c of ["min-w-0", "overflow-x-auto", "min-h-11", "break-words", "table-fixed"]) expect(html).toContain(c);
    expect(html).not.toMatch(/\bw-\[\d{3,}px\]/);
  });
  it("shows a refused report with its reason and an empty list with a plain line", () => {
    const d = { ...data([]), invalid: [{ index: 0, id: "x1", reason: "the number has no tag" }] };
    const html = panel(d);
    expect(html).toContain("Report x1 is not shown: the number has no tag");
    expect(html).toContain('data-testid="no-reports"');
  });
  it("escapes a title from the report", () => {
    const html = panel(data([item({ report: { ...EXAMPLE, title: "<script>x</script>" } })]));
    expect(html).not.toContain("<script>x");
  });
  it("keeps one comment per report: text typed for report A does not show in report B", () => {
    const b = item({ id: "other-report", step: "report-other-report" });
    const html = panel(data([item(), b]), { comments: { [EXAMPLE.id]: "only for A" } });
    expect(html.match(/only for A/g)).toHaveLength(1);
    expect(html.match(/data-testid="report-comment"/g)).toHaveLength(2);
    const both = panel(data([item(), b]), { comments: { [EXAMPLE.id]: "text A", "other-report": "text B" } });
    expect(both.match(/text A/g)).toHaveLength(1);
    expect(both.match(/text B/g)).toHaveLength(1);
  });
});
