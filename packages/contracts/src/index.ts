// @fw/contracts: zod is the source of truth for every console JSON shape (PLAN §5.2).
// Lean's `fwcore console.apply` must accept/emit exactly these shapes (golden fixtures in ../fixtures).
import { z } from "zod";

export const Actor = z.enum(["user", "lead", "owner", "reviewer", "script", "git", "hook"]);
export type Actor = z.infer<typeof Actor>;

const Id = z.string().min(1).max(120);
const Sha = z.string().min(1).max(64);
const Text = z.string().min(1).max(200);

export const StepKind = z.enum(["action", "yes_no", "choice", "text"]);
export type StepKind = z.infer<typeof StepKind>;

export const RunKind = z.enum(["screen", "gate", "run", "device"]);
export type RunKind = z.infer<typeof RunKind>;

// ---- typed commands: the ONLY input of agents and of the user ---------------------------
// A command is a request. console-api stamps `seq` and `ts` and the reducer may refuse it.
// Free text exists only in `title` / `answer` / `note` and is never read by a decision.
const cmd = <T extends string, S extends z.ZodRawShape>(type: T, shape: S) =>
  z.object({ type: z.literal(type), key: Id, actor: Actor, ...shape });

export const Command = z.discriminatedUnion("type", [
  cmd("card.open", { card: Id, owner: Id, needsDevice: z.boolean() }),
  cmd("card.approve", { card: Id }),
  cmd("card.build", { card: Id, sha: Sha, agent: Id }),
  cmd("card.screen", { card: Id, sha: Sha, pass: z.boolean() }),
  cmd("card.review", { card: Id, sha: Sha, signedBy: Id, accept: z.boolean() }),
  cmd("card.swipe", { card: Id, sha: Sha, better: z.boolean() }),
  cmd("card.land_request", { card: Id, sha: Sha }),
  cmd("card.landed", { card: Id, sha: Sha }),
  cmd("step.post", {
    step: Id,
    card: Id.nullable(),
    title: Text,
    kind: StepKind,
    options: z.array(Text).max(12).nullable(),
  }),
  cmd("step.start", { step: Id }),
  cmd("step.answer", { step: Id, answer: Text }),
  cmd("step.done", { step: Id }),
  cmd("step.cancel", { step: Id }),
  cmd("run.start", { run: Id, card: Id, kind: RunKind }),
  cmd("run.finish", { run: Id, ok: z.boolean() }),
  // work graph (lean/Fw/Plan): the plan is events too. Upsert by task id; the reducer refuses cycles and unknown deps.
  cmd("task.define", {
    task: Id, title: Text, stream: Id, milestone: Id.nullable(), deps: z.array(Id).max(32), owner: Id,
    writes: z.array(Text).max(32), devices: z.array(Id).max(8),
    /** what the task needs besides an agent; "device" = the measurement iPhone and the user at it. Missing = [] */
    needs: z.array(Id).max(8).optional(),
    evidence: Sha.nullable(),
    /** the task was cut from the plan (Lean `Fw.Plan` state `cut`: never ready, not counted). Missing = false */
    cut: z.boolean().optional(),
    /** LEGACY (claim-order-lean): the live agent names console-api once added on receipt. New writers omit it; an
     *  agent is bound by agent.spawn / agent.stop (Lean `Fw.Plan.agentOf`). Still decoded so old logs replay to the
     *  same board. Missing = [] */
    live: z.array(Id).max(64).optional(),
  }),
  cmd("task.drop", { task: Id }),
  cmd("task.claim", { task: Id, agent: Id }),
  cmd("task.done", { task: Id, evidence: Sha }),
  cmd("milestone.define", { milestone: Id, title: Text }),
  // agent life (Lean `Fw.Plan`): an agent of this name started / stopped. The board derives the binding from the set
  // of these facts (an agent named like a task works on it), so their order relative to task.define never matters.
  cmd("agent.spawn", { agent: Id }),
  cmd("agent.stop", { agent: Id }),
]);
export type Command = z.infer<typeof Command>;
export type CommandType = Command["type"];

/** An event is a command that console-api stamped. One JSON object per line of events.jsonl.
 *  `fwcore console.apply` takes exactly this shape (without `seq`, which the reducer ignores). */
export const StampedFields = { seq: z.number().int().nonnegative(), ts: z.number().int().nonnegative() };
export const Event = z.intersection(Command, z.object(StampedFields));
export type Event = z.infer<typeof Event>;
/** What the reducer sees: a command plus the stamp time. */
export const ReducerEvent = z.intersection(Command, z.object({ ts: StampedFields.ts }));
export type ReducerEvent = z.infer<typeof ReducerEvent>;

// ---- reducer state (the JSON contract of `console.apply`) ------------------------------
export const Card = z.object({
  id: Id,
  owner: Id,
  needsDevice: z.boolean(),
  approved: z.boolean(),
  head: Sha.nullable(),
  builders: z.array(Id),
  screenAt: Sha.nullable(),
  reviewAt: Sha.nullable(),
  reviewedBy: Id.nullable(),
  deviceAt: Sha.nullable(),
  landReq: Sha.nullable(),
  landed: z.boolean(),
  violation: z.boolean(),
  lastAt: z.number().int().nonnegative(),
});
export type Card = z.infer<typeof Card>;

export const StepStatus = z.enum(["waiting", "started", "answered", "done", "cancelled"]);
export type StepStatus = z.infer<typeof StepStatus>;

export const Step = z.object({
  id: Id,
  card: Id.nullable(),
  title: Text,
  kind: StepKind,
  options: z.array(Text).nullable(),
  status: StepStatus,
  answer: Text.nullable(),
  postedAt: z.number().int().nonnegative(),
  lastAt: z.number().int().nonnegative(),
});
export type Step = z.infer<typeof Step>;

export const Run = z.object({
  id: Id,
  card: Id,
  kind: RunKind,
  status: z.enum(["running", "passed", "failed"]),
  startedAt: z.number().int().nonnegative(),
});
export type Run = z.infer<typeof Run>;

export const State = z.object({
  seen: z.array(Id),
  cards: z.array(Card),
  steps: z.array(Step),
  runs: z.array(Run),
});
export type State = z.infer<typeof State>;

export const Outcome = z.discriminatedUnion("accepted", [
  z.object({ accepted: z.literal(true), duplicate: z.boolean() }),
  z.object({ accepted: z.literal(false), reason: z.string() }),
]);
export type Outcome = z.infer<typeof Outcome>;

/** `fwcore console.apply` request/response. */
export const ApplyRequest = z.object({ state: State, event: ReducerEvent });
export const ApplyResponse = z.object({ state: State, outcome: Outcome });
export type ApplyResponse = z.infer<typeof ApplyResponse>;

// ---- board: a projection, every field derived from events -------------------------------
export const Stage = z.enum(["question", "build", "screen", "review", "device", "land_ready", "land"]);
export type Stage = z.infer<typeof Stage>;

export const NeedsYou = z.object({
  step: Id,
  title: Text,
  /** exact action the user must take now, e.g. "Press Start" */
  action: z.string(),
});
export type NeedsYou = z.infer<typeof NeedsYou>;

export const BoardCard = z.object({
  id: Id,
  owner: Id,
  stage: Stage,
  /** who must act next and what typed command they send */
  next: z.object({ who: z.string(), command: z.string() }),
  lastAt: z.number().int().nonnegative(),
  needsYou: NeedsYou.nullable(),
  runningRuns: z.number().int().nonnegative(),
  head: Sha.nullable(),
  landed: z.boolean(),
  violation: z.boolean(),
  stale: z.boolean(),
});
export type BoardCard = z.infer<typeof BoardCard>;

// ---- board.plan: derived by fwcore (Fw.Plan), never stored as status ---------------------
/** "cut": the task was cut from the plan (never ready, off the critical path, not in milestone totals) */
export const TaskState = z.enum(["done", "cut", "running", "ready", "blocked"]);
export type TaskState = z.infer<typeof TaskState>;
export const TaskLane = z.enum(["agent", "device"]);
export type TaskLane = z.infer<typeof TaskLane>;

export const PlanTask = z.object({
  id: Id,
  title: z.string(),
  stream: z.string(),
  milestone: Id.nullable(),
  owner: z.string(),
  deps: z.array(Id),
  /** what the task needs besides an agent ("device" = the measurement iPhone and the user at it) */
  needs: z.array(Id),
  /** derived by fwcore (Fw.Plan.lane): "device" iff "device" is in needs */
  lane: TaskLane,
  state: TaskState,
  /** undone deps */
  blockers: z.array(Id),
  agent: Id.nullable(),
  evidence: z.string().nullable(),
});
export type PlanTask = z.infer<typeof PlanTask>;

export const PlanMilestone = z.object({
  id: Id, title: z.string(), done: z.number().int().nonnegative(), total: z.number().int().nonnegative(),
});
export type PlanMilestone = z.infer<typeof PlanMilestone>;

export const Plan = z.object({
  tasks: z.array(PlanTask),
  milestones: z.array(PlanMilestone),
  /** longest chain of undone tasks, unit weights */
  criticalPath: z.array(Id),
  /** agent-lane ready tasks grouped so that no two in a group conflict (writes overlap or shared device);
   *  device-lane ready tasks are not grouped (find them by lane + state in tasks) */
  parallelSafe: z.array(z.array(Id)),
});
export type Plan = z.infer<typeof Plan>;
export const emptyPlan = (): Plan => ({ tasks: [], milestones: [], criticalPath: [], parallelSafe: [] });

export const Board = z.object({
  seq: z.number().int().nonnegative(),
  /** server clock when the board was computed; clients derive ages from it */
  now: z.number().int().nonnegative(),
  cards: z.array(BoardCard),
  steps: z.array(Step),
  needsYou: z.array(NeedsYou),
});
export type Board = z.infer<typeof Board>;
/** The stateful `console.query` board: the stateless `console.board` (golden-only) has no `plan`. */
export const LiveBoard = Board.extend({ plan: Plan });
export type LiveBoard = z.infer<typeof LiveBoard>;

/** HTTP reply of POST /api/commands */
export const CommandReply = z.discriminatedUnion("ok", [
  z.object({ ok: z.literal(true), seq: z.number().int().nullable(), duplicate: z.boolean() }),
  z.object({ ok: z.literal(false), reason: z.string() }),
]);
export type CommandReply = z.infer<typeof CommandReply>;

export const emptyState = (): State => ({ seen: [], cards: [], steps: [], runs: [] });

export const jsonSchemas = {
  Command,
  Event,
  State,
  ApplyRequest,
  ApplyResponse,
  Board,
  LiveBoard,
  CommandReply,
} as const;
export * from "./obs.ts";
export * from "./artifacts.ts";
export * from "./plan-sync.ts";
