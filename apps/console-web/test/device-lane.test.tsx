import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import type { Plan, PlanTask } from "@fw/contracts";
import { DeviceLane } from "../src/Plan";

const t = (id: string, state: PlanTask["state"], o: Partial<PlanTask> = {}): PlanTask => ({
  id, title: `title ${id}`, stream: "s", milestone: null, owner: "lead", deps: [], state, blockers: [], agent: null, evidence: null, ...o,
});
const plan = (tasks: PlanTask[]): Plan => ({ tasks, milestones: [], criticalPath: [], parallelSafe: [] });

describe("DeviceLane", () => {
  const html = renderToStaticMarkup(<DeviceLane plan={plan([
    t("phone-done", "done", { needs: ["device"], lane: "device" }),
    t("phone-blocked", "blocked", { needs: ["device"], lane: "device", blockers: ["build-x"] }),
    t("phone-ready", "ready", { needs: ["device"], lane: "device" }),
    t("agent-task", "ready", { lane: "agent" }),
  ])} />);
  it("lists ready first, then blocked with its blockers, then done collapsed; no agent task", () => {
    expect(html.indexOf("phone-ready")).toBeLessThan(html.indexOf("phone-blocked"));
    expect(html.indexOf("phone-blocked")).toBeLessThan(html.indexOf("phone-done"));
    expect(html).toContain("Ready: bring the phone (1)");
    expect(html).toContain("waits on build-x");
    expect(html).toContain("<details>");
    expect(html).not.toContain("agent-task");
    expect(html.match(/data-testid="device-badge"/g)).toHaveLength(3);
  });
  it("renders nothing when the API has no lane", () => {
    expect(renderToStaticMarkup(<DeviceLane plan={plan([t("a", "ready")])} />)).toBe("");
  });
});
