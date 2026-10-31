// TS stand-in, checked against the Lean golden packages/contracts/golden/ops/land-dry.jsonl (Fw.Ops.LandDry:
// par_eq_seq, seqRan_sub_parRan, waves_cover, waves_single); the order inside the wave is Fw.Ops.LandDry.deps (land-dry-deps.jsonl, checkDeps in land.ts). Marked for Lean replacement by a fwcore op.
export type DryPhase = "reads" | "lints" | "ledger" | "local";
export type DryRes = Record<DryPhase, boolean>;
export const DRY_ORDER: DryPhase[] = ["reads", "lints", "ledger", "local"];

/** The refusal the dry land names: the first failing phase in DRY_ORDER, or null when all pass. */
export const dryVerdict = (r: DryRes): DryPhase | null => DRY_ORDER.find((p) => !r[p]) ?? null;

/** The waves of checks: one wave starts together. Which check waits for which is checkDeps (Fw.Ops.LandDry.deps): the fwcore build waits for the lake lint, and a fwcore user waits for both. */
export const DRY_WAVES: DryPhase[][] = [["reads", "lints", "local"]];

/** The lake pass record is written only when reads and lints passed and the lake lint ran. */
export const dryRecordLake = (r: DryRes, lakeRan: boolean): boolean => r.reads && r.lints && lakeRan;
