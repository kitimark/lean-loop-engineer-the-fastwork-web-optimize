import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import type { Plan, PlanTask } from "@fw/contracts";
import { Columns, quietLabel } from "../src/Plan";

const t = (id: string, state: PlanTask["state"], o: Partial<PlanTask> = {}): PlanTask => ({
  id, title: `title ${id}`, stream: "s", milestone: null, owner: "lead", deps: [], needs: [], lane: "agent", state, blockers: [],
  agent: null, evidence: null, ...o,
});

describe("quiet tasks (fwcore state quiet, task-state-truth round 5)", () => {
  const now = 10_000_000;
  const plan: Plan = {
    tasks: [t("r", "running", { agent: "r" }), t("q", "quiet", { since: now - 125 * 60_000 - 1 })],
    milestones: [], criticalPath: [], parallelSafe: [],
  };
  const html = renderToStaticMarkup(<Columns plan={plan} now={now} />);
  it("are listed under Running, apart from the running ones, with the age of their last sighting", () => {
    expect(html).toContain("Running (1)");
    expect(html).toContain("Quiet: not seen lately, not ended (1)");
    expect(html).toContain("quiet: last seen 125 min ago");
    expect(html.indexOf("agent r")).toBeLessThan(html.indexOf("Quiet:"));
  });
  it("label: whole minutes floored, never negative, and no time when never seen", () => {
    expect(quietLabel(t("q", "quiet", { since: now - 59_999 }), now)).toBe("quiet: last seen 0 min ago");
    expect(quietLabel(t("q", "quiet", { since: now + 5 }), now)).toBe("quiet: last seen 0 min ago");
    expect(quietLabel(t("q", "quiet", { since: null }), now)).toBe("quiet: not seen");
  });
});
