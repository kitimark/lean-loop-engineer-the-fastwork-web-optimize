// The artifact store and `fw run` contracts (PLAN 10.1). Shapes only: every rule (what is valid, which jobs, which
// verdict) is Lean's (`lean/Fw/Store`, ops `store.*`). Golden vectors: ../golden/store/*.jsonl, generated from Lean;
// apps/runner/test/run-golden.test.ts parses every request and response with these schemas.
import { z } from "zod";

export const StoreEngine = z.enum(["chromium", "webkit"]);
export type StoreEngine = z.infer<typeof StoreEngine>;
/** The page a run measures: the original site (snapshot) or the rewrite (apps/site); Lean `Fw.Store.Target`. */
export const StoreTarget = z.enum(["original", "rewrite"]);
export type StoreTarget = z.infer<typeof StoreTarget>;

/** sha256 as 64 lowercase hex digits. */
export const Digest = z.string().regex(/^[0-9a-f]{64}$/);
/** A git commit id as 40 lowercase hex digits. */
export const GitSha = z.string().regex(/^[0-9a-f]{40}$/);
/** A container image digest or a CI runner label. */
export const ImageRef = z.string().regex(/^(sha256:[0-9a-f]{64}|runner:[a-z0-9][a-z0-9._-]{0,63})$/);
/** `part:variant`, both ids. */
export const FlagStr = z.string();

const Pair = z.tuple([z.string(), z.string()]);

// ---- manifest: what one run measured and where its bytes are --------------------------------------------------
export const ManifestEntry = z.object({
  name: z.string().min(1), // relative path inside the run, never leaving it (Lean `safeName`)
  digest: Digest,
  bytes: z.number().int().nonnegative(),
});
export type ManifestEntry = z.infer<typeof ManifestEntry>;

export const RunManifest = z.object({
  engine: StoreEngine,
  target: StoreTarget, // part of the run key (key version 2)
  preset: z.string(), // the original target takes only `original` and no flags
  fw: z.array(FlagStr), // strictly increasing by part
  profile: z.string(),
  gitSha: GitSha,
  image: ImageRef,
  runs: z.number().int().positive(),
  runId: z.string().regex(/^[0-9]+$/),
  entries: z.array(ManifestEntry),
});
export type RunManifest = z.infer<typeof RunManifest>;

// ---- store.plan --------------------------------------------------------------------------------------------------
export const PlanRequest = z.object({
  op: z.literal("store.plan"),
  target: z.string(), // `original` or `rewrite` (anything else is a problem); no default
  preset: z.string().optional(),
  fw: z.array(FlagStr).optional(),
  engines: z.array(z.string()),
  profile: z.string().optional(),
  runs: z.number().int().optional(),
  sha: z.string(),
  images: z.record(z.string(), z.string()).optional(),
  digests: z.record(z.string(), z.string()).optional(),
  present: z.array(z.string()).optional(),
});
export type PlanRequest = z.infer<typeof PlanRequest>;

export const PlanJob = z.object({
  engine: StoreEngine,
  workflow: z.string(),
  inputs: z.record(z.string(), z.string()), // `gh workflow run -f name=value`
  key: z.array(Pair), // the pairs whose canonical JSON is hashed to the run key
  image: z.string(),
  blocked: z.string().nullable(), // the input the workflow lacks; null = can run
  digest: z.string().optional(),
  cache: z.enum(["hit", "miss", "unknown"]).optional(),
  manifest: z.string().optional(),
});
export type PlanJob = z.infer<typeof PlanJob>;

export const PlanReply = z.object({
  problems: z.array(z.string()),
  fw: z.array(FlagStr),
  jobs: z.array(PlanJob),
});
export type PlanReply = z.infer<typeof PlanReply>;

// ---- store.gate (breakpoint-gate.yml dispatch) ------------------------------------------------------------------------
export const GateRequest = z.object({
  op: z.literal("store.gate"),
  engines: z.string().optional(), // both (default), chromium or playwright-webkit
  preset: z.string().optional(), // empty = none; exclusive with fw
  fw: z.array(FlagStr).optional(),
});
export type GateRequest = z.infer<typeof GateRequest>;

export const GateReply = z.object({
  problems: z.array(z.string()),
  fw: z.array(FlagStr),
  job: z.object({
    workflow: z.string(),
    inputs: z.record(z.string(), z.string()), // `gh workflow run -f name=value`
    blocked: z.string().nullable(),
  }).nullable(), // null when there are problems
});
export type GateReply = z.infer<typeof GateReply>;

// ---- store.trajectory (trajectory-probe.yml dispatch) -----------------------------------------------------------------
export const TrajectoryRequest = z.object({
  op: z.literal("store.trajectory"),
  engines: z.string().optional(),
  preset: z.string().optional(),
  fw: z.array(FlagStr).optional(),
  widths: z.string().optional(), // comma list of 390, 640, 641, 1280; empty = all four
});
export type TrajectoryRequest = z.infer<typeof TrajectoryRequest>;
export const TrajectoryReply = GateReply;

// ---- store.manifest / store.objectPath -----------------------------------------------------------------------------
export const ManifestRequest = z.object({ op: z.literal("store.manifest"), manifest: z.unknown() });
export const ManifestReply = z.object({
  valid: z.boolean(),
  problems: z.array(z.string()),
  key: z.array(Pair).optional(),
  paths: z.array(z.string()).optional(),
});
export type ManifestReply = z.infer<typeof ManifestReply>;

export const ObjectPathRequest = z.object({ op: z.literal("store.objectPath"), digest: z.string() });
export const ObjectPathReply = z.object({ path: z.string() });

// ---- store.reduce --------------------------------------------------------------------------------------------------
const Run = z.union([z.array(z.object({ counts: z.record(z.string(), z.number().int()) }).passthrough()), z.object({ frames: z.array(z.unknown()) }).passthrough()]);
export const ReduceArm = z.object({ engine: z.string(), base: z.array(Run), var: z.array(Run) });
export const ReduceRequest = z.object({
  op: z.literal("store.reduce"),
  kMax: z.number().int(),
  tMax: z.number().int(),
  pxRel: z.object({ num: z.number().int(), den: z.number().int() }).optional(),
  arms: z.array(ReduceArm),
});
export type ReduceRequest = z.infer<typeof ReduceRequest>;

export const ReduceClass = z.discriminatedUnion("class", [
  z.object({ class: z.literal("deterministic") }),
  z.object({ class: z.literal("stable"), k: z.number().int(), t: z.number().int() }),
  z.object({ class: z.literal("quarantined") }),
]);
export const ReduceReply = z.object({
  noMoreWork: z.boolean(),
  arms: z.array(z.object({
    engine: z.string(),
    noMoreWork: z.boolean(),
    failing: z.array(z.string()),
    types: z.array(z.object({ type: z.string(), class: ReduceClass, ok: z.boolean() })),
  })),
});
export type ReduceReply = z.infer<typeof ReduceReply>;

/** Every `store.*` reply is either its reply shape or `{error}`. */
export const StoreError = z.object({ error: z.string() });
