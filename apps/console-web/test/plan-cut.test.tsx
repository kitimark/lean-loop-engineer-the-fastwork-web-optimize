import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import type { Plan, PlanTask } from "@fw/contracts";
import { Columns, layout } from "../src/Plan";

const t = (id: string, state: PlanTask["state"], o: Partial<PlanTask> = {}): PlanTask => ({
  id, title: `title ${id}`, stream: "s", milestone: null, owner: "lead", deps: [], needs: [], lane: "agent", state, blockers: [],
  agent: null, evidence: null, ...o,
});

describe("cut tasks (fwcore state cut)", () => {
  const plan: Plan = {
    tasks: [t("a", "ready"), t("d", "done", { evidence: "abc1234" }), t("x", "cut", { milestone: "MX" })],
    milestones: [], criticalPath: ["a"], parallelSafe: [["a"]],
  };
  const html = renderToStaticMarkup(<Columns plan={plan} />);
  it("are listed greyed under Done, after the done tasks, and counted apart", () => {
    expect(html).toContain("Done (1)");
    expect(html).toContain("Cut from the plan (1)");
    expect(html.indexOf("abc1234".slice(0, 7))).toBeLessThan(html.indexOf("Cut from the plan"));
    expect(html).toMatch(/class="[^"]*opacity-50[^"]*"[^>]*data-state="cut"/);
    expect(html.match(/opacity-50/g)).toHaveLength(1);
  });
  it("are left out of the DAG layout", () => {
    expect(layout(plan.tasks).nodes.map((n) => n.id)).toEqual(["a"]);
  });
});
