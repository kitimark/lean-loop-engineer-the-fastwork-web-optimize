import { readFileSync } from "node:fs";

export const WORKFLOW_LINT_ID = "workflow-lint";
export const WORKFLOW_LINT_READS = [".github/workflows/*.yml", ".github/workflows/*.yaml", "scripts/check-workflows.sh", "apps/runner/src/land-checks-workflow.ts"];
export const WORKFLOW_LINT_ARGV = ["sh", "scripts/check-workflows.sh", "apps/runner/src/land-checks-workflow.ts"];

export type Finding = { kind: string; file: string; message: string; line?: number };
export type WorkflowVerdict = "pass" | "warn" | "fail" | "refused";

export const ERROR_KINDS = ["syntax-check", "expression"];
export const ACCEPTED: [string, string][] = [[".github/workflows/webkit-sim.yml", "string should not be empty"]];
export const EXIT: Record<WorkflowVerdict, number> = { pass: 0, warn: 0, fail: 1, refused: 3 };

const isAccepted = (f: Finding) => ACCEPTED.some(([file, msg]) => f.file === file && f.message === msg);
export const shown = (fs: Finding[]): Finding[] => fs.filter((f) => !isAccepted(f));

export function workflowVerdict(installed: boolean, fs: Finding[]): WorkflowVerdict {
  if (!installed) return "refused";
  const s = shown(fs);
  if (s.some((f) => ERROR_KINDS.includes(f.kind))) return "fail";
  return s.length === 0 ? "pass" : "warn";
}

export function parseFindings(raw: string): Finding[] {
  const j = JSON.parse(raw.trim() || "null") as { kind: string; filepath: string; line?: number; message: string }[] | null;
  if (j !== null && !Array.isArray(j)) throw new Error("actionlint output is not a list");
  return (j ?? []).map((e) => ({ kind: e.kind, file: e.filepath, message: e.message, line: e.line }));
}

export function report(fs: Finding[]): { verdict: WorkflowVerdict; lines: string[] } {
  const verdict = workflowVerdict(true, fs);
  const lines = shown(fs).map((f) => `${ERROR_KINDS.includes(f.kind) ? "error" : "warning"} [${f.kind}] ${f.file}${f.line ? `:${f.line}` : ""}: ${f.message}`);
  lines.push(`workflow-lint: ${verdict}`);
  return { verdict, lines };
}

if (import.meta.main) {
  let fs: Finding[];
  try { fs = parseFindings(readFileSync(0, "utf8")); } catch (e) {
    console.log(`REFUSED workflow-lint: actionlint output unreadable (${(e as Error).message})`);
    process.exit(EXIT.refused);
  }
  const r = report(fs);
  console.log(r.lines.join("\n"));
  process.exit(EXIT[r.verdict]);
}
