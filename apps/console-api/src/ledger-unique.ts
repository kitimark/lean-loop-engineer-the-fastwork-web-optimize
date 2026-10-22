import { readFileSync } from "node:fs";

// TS stand-in for Lean Fw.Console.LedgerUnique (`bad`, `ok`), checked against its golden
// packages/contracts/golden/console/ledger-unique.jsonl in test/ledger-unique.test.ts. Marked for Lean replacement
// once fwcore exposes the decision.
/** First `n` that must be unique; older sub-findings share their parent's `n` (Lean `floor`). */
export const LEDGER_UNIQUE_FLOOR = 26;

/** The `n` values from the floor on that occur more than once, each once, in first-seen order. */
export function badNs(ns: readonly number[]): number[] {
  const seen = new Set<number>();
  const out: number[] = [];
  for (const n of ns) {
    if (seen.has(n)) continue;
    seen.add(n);
    if (n >= LEDGER_UNIQUE_FLOOR && ns.filter((m) => m === n).length > 1) out.push(n);
  }
  return out;
}

/** The `n` of the candidate rows (id and candidate text) of a findings ledger, in file order. */
export function candidateNs(ledger: { findings: { id?: unknown; candidate?: unknown; n: number }[] }): number[] {
  return ledger.findings.filter((f) => typeof f.id === "string" && typeof f.candidate === "string").map((f) => f.n);
}

/** Read a findings ledger file and return its refused numbers. */
export function badNsOfFile(path: string): number[] {
  return badNs(candidateNs(JSON.parse(readFileSync(path, "utf8"))));
}
