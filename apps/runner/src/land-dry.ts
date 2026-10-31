// TS stand-in, checked against the Lean golden packages/contracts/golden/ops/land-dry.jsonl (Fw.Ops.LandDry:
// par_eq_seq, seqRan_sub_parRan, waves_cover, waves_single). Marked for Lean replacement by a fwcore op.
export type DryPhase = "reads" | "lints" | "ledger" | "local";
export type DryRes = Record<DryPhase, boolean>;
export const DRY_ORDER: DryPhase[] = ["reads", "lints", "ledger", "local"];

/** The refusal the dry land names: the first failing phase in DRY_ORDER, or null when all pass. */
export const dryVerdict = (r: DryRes): DryPhase | null => DRY_ORDER.find((p) => !r[p]) ?? null;

/** The waves of checks: one wave starts together. Builds queue in the machine-wide Lake slot; a test that needs fwcore waits for the build step (checkDeps). */
export const DRY_WAVES: DryPhase[][] = [["reads", "lints", "local"]];

/** The lake pass record is written only when reads and lints passed and the lake lint ran. */
export const dryRecordLake = (r: DryRes, lakeRan: boolean): boolean => r.reads && r.lints && lakeRan;
