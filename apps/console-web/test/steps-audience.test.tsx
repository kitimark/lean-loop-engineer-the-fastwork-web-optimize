import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import type { Board, Step } from "@fw/contracts";
import { Steps } from "../src/App";

const step = (id: string, o: Partial<Step> = {}): Step => ({
  id, card: null, title: `title ${id}`, kind: "action", options: null, status: "waiting", postedAt: 0, answer: null,
  audience: "user", body: "", ...o,
} as Step);
const board = (steps: Step[]): Board => ({ steps, cards: [], seq: 1, now: 1000 } as unknown as Board);
const html = (steps: Step[]) => renderToStaticMarkup(<Steps board={board(steps)} act={async () => {}} now={1000} />);

describe("Steps (task alert-steps-plain)", () => {
  const out = html([
    step("alert-a1-1", { title: "A helper needs your permission", body: "What happened: The helper asked.\nImpact: Nothing is lost.\nAction (you): Answer.\nDetails: agent x" }),
    step("alert-spool-9", { audience: "lead", title: "The log reader rejected some lines", body: "What happened: bad lines" }),
    step("alert-spool-5", { audience: "lead", status: "done", title: "Old", answer: "resolved automatically at 2026-10-20T12:40:00Z: ok" }),
  ]);
  it("counts and lists only the owner's steps under Your steps", () => {
    expect(out).toContain("Your steps (1)");
    expect(out.indexOf("A helper needs your permission")).toBeLessThan(out.indexOf('data-testid="lead-work"'));
  });
  it("puts the lead's steps apart, with no buttons", () => {
    const lead = out.slice(out.indexOf('data-testid="lead-work"'), out.indexOf("</details>"));
    expect(lead).toContain("The log reader rejected some lines");
    expect(lead).not.toContain("<button");
  });
  it("renders the plain body line by line and the auto-close note", () => {
    expect(out).toContain("<b>What happened:</b> The helper asked.");
    expect(out).toContain("<b>Impact:</b> Nothing is lost.");
    expect(out).toContain("resolved automatically at 2026-10-20T12:40:00Z: ok");
  });
  it("says nothing needs you when only lead steps are open", () => {
    expect(html([step("alert-spool-1", { audience: "lead" })])).toContain("Nothing needs you.");
  });
});

describe("review steps (task user-review-queue)", () => {
  for (const [name, o] of [["waiting", {}], ["started", { status: "started" }], ["a choice", { kind: "choice", options: ["keep", "reject"] }],
    ["a started choice", { kind: "choice", status: "started", options: ["keep", "reject"] }]] as const) {
    it(`${name}: no Start, Done or answer button, a link to Your reviews`, () => {
      const out = html([step("review-nav:earn-no-transition", { kind: "choice", options: ["keep", "reject"], ...o })]);
      for (const b of [">Start<", ">Done<", ">keep<", ">reject<"]) expect(out).not.toContain(b);
      expect(out).toContain('href="?tab=reviews"');
      expect(out).toContain("title review-nav:earn-no-transition");
    });
  }
  it("a re-posted review step (#1) is the same; another step still has its buttons", () => {
    expect(html([step("review-nav:e#1", { kind: "choice", options: ["keep", "reject"] })])).not.toContain(">keep<");
    expect(html([step("alert-x-1", { kind: "choice", options: ["a", "b"] })])).toContain(">a<");
  });
});
