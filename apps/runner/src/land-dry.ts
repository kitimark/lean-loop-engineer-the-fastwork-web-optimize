export type DryPhase = "reads" | "lints" | "ledger" | "local";
export type DryRes = Record<DryPhase, boolean>;
export const DRY_ORDER: DryPhase[] = ["reads", "lints", "ledger", "local"];

export const dryVerdict = (r: DryRes): DryPhase | null => DRY_ORDER.find((p) => !r[p]) ?? null;

export const DRY_WAVES: DryPhase[][] = [["reads", "lints", "local"]];

export const dryRecordLake = (r: DryRes, lakeRan: boolean): boolean => r.reads && r.lints && lakeRan;
