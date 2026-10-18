import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import type { Plan, PlanTask } from "@fw/contracts";
import { Columns } from "../src/Plan";
import { TaskDetail, refusedText, targetText, urls, wantsDetail } from "../src/TaskDetail";

const t = (id: string): PlanTask => ({ id, title: "t", stream: "s", milestone: null, owner: "lead", deps: [], needs: [], lane: "agent", state: "running", blockers: [], agent: "a", evidence: null });

describe("task detail", () => {
  it("is offered for port- and fix- tasks only, collapsed (no fetch until opened)", () => {
    expect(wantsDetail("port-hero")).toBe(true);
    expect(wantsDetail("fix-nav")).toBe(true);
    expect(wantsDetail("lean-x")).toBe(false);
    const plan: Plan = { tasks: [t("port-a"), t("lean-b")], milestones: [], criticalPath: [], parallelSafe: [] };
    const html = renderToStaticMarkup(<Columns plan={plan} />);
    expect(html.match(/data-testid="task-detail"/g)).toHaveLength(1);
    expect(renderToStaticMarkup(<TaskDetail id="port-a" />)).not.toContain("Preview</button>");
  });
  it("a notOwner refusal tells the user how to become the owner; other reasons pass through", () => {
    expect(refusedText("notOwner")).toContain("owner link");
    expect(refusedText("tooMany")).toBe("refused: tooMany");
  });
  it("builds the three loopback URLs and the target text", () => {
    expect(urls({ rp: 47100, op: 47101 })).toEqual({ rewrite: "http://127.0.0.1:47100/", original: "http://127.0.0.1:47101/", compare: "http://127.0.0.1:47100/__fw/compare" });
    expect(targetText({ kind: "none", ref: null, sha: null })).toMatch(/no work/);
    expect(targetText({ kind: "integration", ref: "integrate-x", sha: "abc1234" })).toContain("integrate-x");
  });
});
