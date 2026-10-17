// Projection: State -> Board. Every field is derived; nothing here is stored or settable.
// replaced by fwcore (stage/stale are Lean definitions in ConsoleV2.lean)
import type { Board, BoardCard, Card, NeedsYou, Stage, State, Step } from "@fw/contracts";

export const STALE_MS = 30 * 60 * 1000;

export function stage(c: Card): Stage {
  if (c.landed) return "land";
  if (!c.approved) return "question";
  if (c.head === null) return "build";
  if (c.screenAt !== c.head) return "screen";
  if (c.reviewAt !== c.head) return "review";
  if (c.needsDevice && c.deviceAt !== c.head) return "device";
  return "land_ready";
}

export function next(c: Card, st: Stage): { who: string; command: string } {
  switch (st) {
    case "question": return { who: "lead or user", command: "card.approve" };
    case "build": return { who: `owner ${c.owner}`, command: "commit (git fact card.build)" };
    case "screen": return { who: "script", command: "card.screen" };
    case "review": return { who: "reviewer (not the owner or a builder)", command: "card.review" };
    case "device": return { who: "script (device swipe)", command: "card.swipe" };
    case "land_ready":
      return c.landReq === c.head
        ? { who: "git", command: "card.landed (fact)" }
        : { who: "lead or user", command: "card.land_request" };
    case "land": return { who: "nobody", command: "done" };
  }
}

/** The exact action the user must take on an open step. */
export function stepAction(s: Step): string {
  if (s.status === "waiting" && s.kind === "action") return "Press Start";
  if (s.status === "started" && s.kind === "action") return "Do it, then press Done";
  if (s.kind === "yes_no") return "Answer yes or no";
  if (s.kind === "choice") return `Choose one: ${(s.options ?? []).join(" | ")}`;
  if (s.kind === "text") return "Type an answer";
  return "Press Done";
}

const open = (s: Step) => s.status === "waiting" || s.status === "started";
const needs = (s: Step): NeedsYou => ({ step: s.id, title: s.title, action: stepAction(s) });

export function board(state: State, now: number, seq: number): Board {
  const openSteps = state.steps.filter(open);
  const cards: BoardCard[] = state.cards.map((c) => {
    const st = stage(c);
    const mine = openSteps.find((s) => s.card === c.id) ?? null;
    const running = state.runs.filter((r) => r.card === c.id && r.status === "running").length;
    return {
      id: c.id, owner: c.owner, stage: st, next: next(c, st), lastAt: c.lastAt,
      needsYou: mine ? needs(mine) : null, runningRuns: running, head: c.head,
      landed: c.landed, violation: c.violation,
      stale: !c.landed && running === 0 && !mine && now - c.lastAt >= STALE_MS,
    };
  });
  return { seq, now, cards, steps: state.steps, needsYou: openSteps.map(needs) };
}
