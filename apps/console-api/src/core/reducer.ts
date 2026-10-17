// replaced by fwcore console.apply  (Lean: research/kickoff/10-automation-and-proof/lean-scratch/02-events/ConsoleV2.lean)
// Pure TS stand-in with the SAME JSON contract: apply(state, event) -> { state, outcome }.
// Deviation from the Lean sketch (to be ported to Lean): steps have kinds + start/done, runs exist.
import type { ApplyResponse, Card, Actor, ReducerEvent, State, Step } from "@fw/contracts";
import { emptyState } from "@fw/contracts";

type Ev = ReducerEvent;
type Type = Ev["type"];

/** who may cause what (Lean: `may`). Anything absent is refused. */
export const MAY: Record<Type, readonly Actor[]> = {
  "card.open": ["owner", "lead", "user"],
  "card.approve": ["lead", "user"],
  "card.build": ["git"],
  "card.screen": ["script"],
  "card.review": ["reviewer"],
  "card.swipe": ["script"],
  "card.land_request": ["lead", "user"],
  "card.landed": ["git"],
  "step.post": ["script", "owner", "lead", "user"],
  "step.start": ["user"],
  "step.answer": ["user"],
  "step.done": ["user", "owner", "script"],
  "step.cancel": ["script", "user", "lead"],
  "run.start": ["script", "owner", "lead"],
  "run.finish": ["script"],
};

export const may = (a: Actor, t: Type): boolean => MAY[t].includes(a);

export const ready = (c: Card): boolean =>
  c.approved && c.head !== null && c.screenAt === c.head && c.reviewAt === c.head &&
  (!c.needsDevice || c.deviceAt === c.head);

const touch = (t: number, c: Card): Card => ({ ...c, lastAt: Math.max(c.lastAt, t) });

/** Refusal reason for a card event, or null (Lean: `cardStep` unchanged => refused). */
function cardRefusal(c: Card, e: Ev): string | null {
  switch (e.type) {
    case "card.approve":
      if (c.landed) return "card already landed";
      return c.approved ? "already approved" : null;
    case "card.build":
      return c.landed ? "card already landed" : null;
    case "card.screen":
      if (c.landed) return "card already landed";
      if (c.head !== e.sha) return "stale sha: not the head commit";
      return e.pass ? null : "failed screen does not advance the card";
    case "card.review":
      if (c.landed) return "card already landed";
      if (c.head !== e.sha) return "stale sha: not the head commit";
      if (e.signedBy === c.owner || c.builders.includes(e.signedBy)) return "reviewer owns or built this card";
      return e.accept ? null : "rejected review does not advance the card";
    case "card.swipe":
      if (c.landed) return "card already landed";
      if (c.head !== e.sha) return "stale sha: not the head commit";
      return e.better ? null : "not better: device evidence not recorded";
    case "card.land_request":
      if (c.landed) return "card already landed";
      if (c.head !== e.sha) return "stale sha: not the head commit";
      return ready(c) ? null : "card is not land-ready";
    case "card.landed":
      return c.landed ? "card already landed" : null;
    default:
      return null;
  }
}

function cardStep(t: number, e: Ev, c: Card): Card {
  switch (e.type) {
    case "card.approve": return touch(t, { ...c, approved: true });
    case "card.build":
      return touch(t, { ...c, head: e.sha, builders: [e.agent, ...c.builders], screenAt: null,
        reviewAt: null, reviewedBy: null, deviceAt: null, landReq: null });
    case "card.screen": return touch(t, { ...c, screenAt: e.sha });
    case "card.review": return touch(t, { ...c, reviewAt: e.sha, reviewedBy: e.signedBy });
    case "card.swipe": return touch(t, { ...c, deviceAt: e.sha });
    case "card.land_request": return touch(t, { ...c, landReq: e.sha });
    case "card.landed": return touch(t, { ...c, landed: true, violation: !(c.landReq === e.sha && ready(c)) });
    default: return c;
  }
}

const isOpen = (s: Step) => s.status === "waiting" || s.status === "started";

/** Returns a refusal reason or null when the event is acceptable on `s` (Lean: `check`). */
export function check(s: State, e: Ev): string | null {
  if (!may(e.actor, e.type)) return `actor ${e.actor} may not cause ${e.type}`;
  switch (e.type) {
    case "card.open":
      return s.cards.some((c) => c.id === e.card) ? "card exists" : null;
    case "step.post": {
      if (s.steps.some((x) => x.id === e.step)) return "step exists";
      if (e.card !== null && !s.cards.some((c) => c.id === e.card)) return "no such card";
      if (e.kind === "choice" && (!e.options || e.options.length < 2)) return "choice step needs at least 2 options";
      return null;
    }
    case "step.start": case "step.answer": case "step.done": case "step.cancel": {
      const st = s.steps.find((x) => x.id === e.step);
      if (!st) return "no such step";
      if (e.type === "step.start") return st.status === "waiting" ? null : `step is ${st.status}, not waiting`;
      if (e.type === "step.cancel") return isOpen(st) ? null : `step already ${st.status}`;
      if (e.type === "step.done")
        return st.status === "started" ? null : `step is ${st.status}, only a started step can be done`;
      // answer
      if (!isOpen(st)) return `step already ${st.status}`;
      if (st.kind === "action") return "an action step is finished with step.done, not an answer";
      if (st.kind === "yes_no" && e.answer !== "yes" && e.answer !== "no") return "answer must be yes or no";
      if (st.kind === "choice" && !st.options?.includes(e.answer)) return "answer is not one of the options";
      return null;
    }
    case "run.start": {
      if (!s.cards.some((c) => c.id === e.card)) return "no such card";
      return s.runs.some((r) => r.id === e.run) ? "run exists" : null;
    }
    case "run.finish": {
      const r = s.runs.find((x) => x.id === e.run);
      if (!r) return "no such run";
      return r.status === "running" ? null : "run already finished";
    }
    default: {
      const c = s.cards.find((x) => x.id === e.card);
      if (!c) return "no such card";
      return cardRefusal(c, e);
    }
  }
}

function accept(s: State, e: Ev): State {
  const t = e.ts;
  const mapCard = (id: string, f: (c: Card) => Card) =>
    ({ ...s, cards: s.cards.map((c) => (c.id === id ? f(c) : c)) });
  const mapStep = (id: string, f: (x: Step) => Step) =>
    ({ ...s, steps: s.steps.map((x) => (x.id === id ? { ...f(x), lastAt: Math.max(x.lastAt, t) } : x)) });
  switch (e.type) {
    case "card.open":
      return { ...s, cards: [...s.cards, { id: e.card, owner: e.owner, needsDevice: e.needsDevice,
        approved: false, head: null, builders: [], screenAt: null, reviewAt: null, reviewedBy: null,
        deviceAt: null, landReq: null, landed: false, violation: false, lastAt: t }] };
    case "step.post":
      return { ...s, steps: [...s.steps, { id: e.step, card: e.card, title: e.title, kind: e.kind,
        options: e.options, status: "waiting", answer: null, postedAt: t, lastAt: t }] };
    case "step.start": return mapStep(e.step, (x) => ({ ...x, status: "started" }));
    case "step.answer": return mapStep(e.step, (x) => ({ ...x, status: "answered", answer: e.answer }));
    case "step.done": return mapStep(e.step, (x) => ({ ...x, status: "done" }));
    case "step.cancel": return mapStep(e.step, (x) => ({ ...x, status: "cancelled" }));
    case "run.start":
      return { ...mapCard(e.card, (c) => touch(t, c)),
        runs: [...s.runs, { id: e.run, card: e.card, kind: e.kind, status: "running", startedAt: t }] };
    case "run.finish": {
      const r = s.runs.find((x) => x.id === e.run)!;
      return { ...mapCard(r.card, (c) => touch(t, c)),
        runs: s.runs.map((x) => (x.id === e.run ? { ...x, status: e.ok ? "passed" : "failed" } : x)) };
    }
    default:
      return mapCard(e.card, (c) => cardStep(t, e, c));
  }
}

/** The reducer. Seen key: no-op duplicate. Refused: state untouched (key NOT marked seen, so a
 *  fact that arrived early can be re-sent). Accepted: apply and remember the key. */
export function apply(s: State, e: Ev): ApplyResponse {
  if (s.seen.includes(e.key)) return { state: s, outcome: { accepted: true, duplicate: true } };
  const why = check(s, e);
  if (why !== null) return { state: s, outcome: { accepted: false, reason: why } };
  return { state: { ...accept(s, e), seen: [e.key, ...s.seen] }, outcome: { accepted: true, duplicate: false } };
}

export const project = (log: readonly Ev[]): State =>
  log.reduce((s, e) => apply(s, e).state, emptyState());
