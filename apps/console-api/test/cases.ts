import type { ReducerEvent } from "@fw/contracts";

let n = 0;
type Body = Record<string, unknown> & { type: ReducerEvent["type"]; actor: ReducerEvent["actor"] };
/** build an event with a fresh key and increasing ts */
export const ev = (b: Body, key?: string): ReducerEvent =>
  ({ key: key ?? `k${++n}`, ts: 1000 + n, ...b }) as ReducerEvent;

const open = () => ev({ type: "card.open", actor: "owner", card: "A", owner: "o", needsDevice: false });
const approve = () => ev({ type: "card.approve", actor: "lead", card: "A" });
const build = (sha = "s1") => ev({ type: "card.build", actor: "git", card: "A", sha, agent: "b" });
const screen = (sha = "s1") => ev({ type: "card.screen", actor: "script", card: "A", sha, pass: true });
const review = (signedBy = "r", sha = "s1") =>
  ev({ type: "card.review", actor: "reviewer", card: "A", sha, signedBy, accept: true });
const post = (kind = "action", extra: Record<string, unknown> = {}) =>
  ev({ type: "step.post", actor: "script", step: "S", card: "A", title: "t", kind, options: null, ...extra });

export const base = () => [open(), approve(), build()];
export const ready = () => [...base(), screen(), review()];

export type Case = { name: string; setup: ReducerEvent[]; event: ReducerEvent; reason: string | null };

/** reason null = accepted; otherwise the exact refusal reason. */
export const cases = (): Case[] => (n = 0, [
  { name: "open a card", setup: [], event: open(), reason: null },
  { name: "open twice", setup: [open()], event: ev({ type: "card.open", actor: "lead", card: "A", owner: "o", needsDevice: false }), reason: "card exists" },
  { name: "agent cannot approve (owner)", setup: [open()], event: ev({ type: "card.approve", actor: "owner", card: "A" }), reason: "actor owner may not cause card.approve" },
  { name: "approve unknown card", setup: [], event: approve(), reason: "no such card" },
  { name: "approve", setup: [open()], event: approve(), reason: null },
  { name: "approve twice", setup: [open(), approve()], event: ev({ type: "card.approve", actor: "user", card: "A" }), reason: "already approved" },
  { name: "build is a git fact only", setup: base().slice(0, 2), event: ev({ type: "card.build", actor: "owner", card: "A", sha: "s1", agent: "b" }), reason: "actor owner may not cause card.build" },
  { name: "screen stale sha", setup: base(), event: screen("old"), reason: "stale sha: not the head commit" },
  { name: "screen before any build", setup: [open(), approve()], event: screen(), reason: "stale sha: not the head commit" },
  { name: "screen ok", setup: base(), event: screen(), reason: null },
  { name: "failed screen is refused", setup: base(), event: ev({ type: "card.screen", actor: "script", card: "A", sha: "s1", pass: false }), reason: "failed screen does not advance the card" },
  { name: "owner cannot review own card", setup: [...base(), screen()], event: review("o"), reason: "reviewer owns or built this card" },
  { name: "builder cannot review", setup: [...base(), screen()], event: review("b"), reason: "reviewer owns or built this card" },
  { name: "independent review", setup: [...base(), screen()], event: review("r"), reason: null },
  { name: "land request needs ready", setup: base(), event: ev({ type: "card.land_request", actor: "lead", card: "A", sha: "s1" }), reason: "card is not land-ready" },
  { name: "land request ready", setup: ready(), event: ev({ type: "card.land_request", actor: "lead", card: "A", sha: "s1" }), reason: null },
  { name: "device card needs swipe", setup: [ev({ type: "card.open", actor: "owner", card: "A", owner: "o", needsDevice: true }), approve(), build(), screen(), review()], event: ev({ type: "card.land_request", actor: "lead", card: "A", sha: "s1" }), reason: "card is not land-ready" },
  { name: "landed fact without request is accepted", setup: base(), event: ev({ type: "card.landed", actor: "git", card: "A", sha: "s1" }), reason: null },
  { name: "events on a landed card are refused", setup: [...base(), ev({ type: "card.landed", actor: "git", card: "A", sha: "s1" })], event: build("s2"), reason: "card already landed" },
  { name: "post a step", setup: [open()], event: post(), reason: null },
  { name: "post step on unknown card", setup: [], event: post(), reason: "no such card" },
  { name: "choice needs options", setup: [open()], event: post("choice", { options: ["A"] }), reason: "choice step needs at least 2 options" },
  { name: "post step twice", setup: [open(), post()], event: post(), reason: "step exists" },
  { name: "reviewer cannot post steps", setup: [open()], event: post("action", { actor: "reviewer" }), reason: "actor reviewer may not cause step.post" },
  { name: "agent cannot start a step", setup: [open(), post()], event: ev({ type: "step.start", actor: "script", step: "S" }), reason: "actor script may not cause step.start" },
  { name: "user starts a step", setup: [open(), post()], event: ev({ type: "step.start", actor: "user", step: "S" }), reason: null },
  { name: "start twice", setup: [open(), post(), ev({ type: "step.start", actor: "user", step: "S" })], event: ev({ type: "step.start", actor: "user", step: "S" }), reason: "step is started, not waiting" },
  { name: "done needs started", setup: [open(), post()], event: ev({ type: "step.done", actor: "user", step: "S" }), reason: "step is waiting, only a started step can be done" },
  { name: "done after start", setup: [open(), post(), ev({ type: "step.start", actor: "user", step: "S" })], event: ev({ type: "step.done", actor: "user", step: "S" }), reason: null },
  { name: "agent cannot answer", setup: [open(), post("yes_no")], event: ev({ type: "step.answer", actor: "lead", step: "S", answer: "yes" }), reason: "actor lead may not cause step.answer" },
  { name: "answer yes", setup: [open(), post("yes_no")], event: ev({ type: "step.answer", actor: "user", step: "S", answer: "yes" }), reason: null },
  { name: "answer must be yes/no", setup: [open(), post("yes_no")], event: ev({ type: "step.answer", actor: "user", step: "S", answer: "maybe" }), reason: "answer must be yes or no" },
  { name: "answer must be an option", setup: [open(), post("choice", { options: ["A", "B"] })], event: ev({ type: "step.answer", actor: "user", step: "S", answer: "C" }), reason: "answer is not one of the options" },
  { name: "action step is not answered", setup: [open(), post()], event: ev({ type: "step.answer", actor: "user", step: "S", answer: "ok" }), reason: "an action step is finished with step.done, not an answer" },
  { name: "answer a closed step", setup: [open(), post("text"), ev({ type: "step.answer", actor: "user", step: "S", answer: "x" })], event: ev({ type: "step.answer", actor: "user", step: "S", answer: "y" }), reason: "step already answered" },
  { name: "answer unknown step", setup: [], event: ev({ type: "step.answer", actor: "user", step: "S", answer: "y" }), reason: "no such step" },
  { name: "cancel an open step", setup: [open(), post()], event: ev({ type: "step.cancel", actor: "script", step: "S" }), reason: null },
  { name: "start a run", setup: [open()], event: ev({ type: "run.start", actor: "script", run: "R", card: "A", kind: "screen" }), reason: null },
  { name: "run on unknown card", setup: [], event: ev({ type: "run.start", actor: "script", run: "R", card: "A", kind: "screen" }), reason: "no such card" },
  { name: "finish a run", setup: [open(), ev({ type: "run.start", actor: "script", run: "R", card: "A", kind: "gate" })], event: ev({ type: "run.finish", actor: "script", run: "R", ok: true }), reason: null },
  { name: "finish unknown run", setup: [open()], event: ev({ type: "run.finish", actor: "script", run: "R", ok: true }), reason: "no such run" },
]);
