import { readFileSync } from "node:fs";

export const LEDGER_UNIQUE_FLOOR = 26;

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

export function candidateNs(ledger: { findings: { id?: unknown; candidate?: unknown; n: number }[] }): number[] {
  return ledger.findings.filter((f) => typeof f.id === "string" && typeof f.candidate === "string").map((f) => f.n);
}

export function badNsOfFile(path: string): number[] {
  return badNs(candidateNs(JSON.parse(readFileSync(path, "utf8"))));
}
