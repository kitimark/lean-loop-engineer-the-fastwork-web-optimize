// The scorer of the offline replay (task jev-replay): `fw oracle score` and `fw oracle arm-input`.
//
// `score` joins the rows Lean picks for a set (`oracle.replay`) with one arm's answers and asks `oracle.score` for
// the numbers; it writes them under the arm's name into `results/jev/<set>.json`, keeping the other arms. The Jev
// arm's answers are read from the answer log: per row, the logged entry of the exact request body Lean builds for
// it (sha256 of `bodyText`). Another arm's answers come from a JSONL file of {id, choice, probabilities?,
// inputTokens?, outputTokens?, ms?}.
//
// `arm-input` writes the prompt of every picked row for another arm: the same instructions, criteria and redacted
// state as the Jev body, and the answer format.
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { readLog, sha256, type FwCall, type Json, type LogEntry } from "@fw/oracle";
import type { Picked } from "./oracle.ts";

/** The arms `oracle.score` prices. */
export const ARMS = ["jev", "haiku", "sonnet"] as const;

/** The logged entry of request body `body`: the latest with a reply, else the latest failure. */
function entryFor(entries: LogEntry[], body: string): LogEntry | undefined {
  const key = sha256(body);
  const mine = entries.filter((e) => e.key === key);
  return mine.findLast((e) => e.reply !== undefined) ?? mine.at(-1);
}

/** The request body Lean builds for a picked row. */
export function bodyOf(core: FwCall, question: string, names: string[], row: Picked): string {
  return String(core({ op: "oracle.request", name: question, names, state: row.state }).bodyText);
}

/** The Jev arm's answers to the picked rows, read from the answer log; rows never asked are left out. */
export function jevAnswers(core: FwCall, question: string, names: string[], rows: Picked[], logPath: string): Json[] {
  const entries = readLog(logPath);
  return rows.flatMap((row) => {
    const e = entryFor(entries, bodyOf(core, question, names, row));
    if (e === undefined) return [];
    return [e.reply !== undefined ? { id: row.id, reply: e.reply, ms: e.ms } : { id: row.id, failure: e.failure ?? {}, ms: e.ms }];
  });
}

/** Another arm's answers: one JSON object per line. */
export function armAnswers(file: string): Json[] {
  return readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as Json);
}

/** The score of one arm (`oracle.score`) on the picked rows. */
export function scoreArm(core: FwCall, question: string, arm: string, rows: Picked[], answers: Json[]): Json {
  return core({ op: "oracle.score", name: question, arm, replay: rows.map((r) => ({ id: r.id, label: r.label })), answers });
}

/** Write `score` as arm `arm` of the results file `out`, keeping its other arms; `head` replaces the set's header. */
export function writeResult(out: string, head: Json, arm: string, score: Json): void {
  const prev = existsSync(out) ? (JSON.parse(readFileSync(out, "utf8")) as { arms?: Record<string, Json> }) : {};
  const arms = { ...(prev.arms ?? {}), [arm]: score };
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, JSON.stringify({ ...head, arms }, null, 2) + "\n");
}

/** The fixed text before each row of another arm's prompt. */
export const ARM_PREAMBLE =
  "You answer one classification question about the state below. The question, its options with their criteria, " +
  "and the state are given as JSON. Reply with one JSON object and nothing else: " +
  '{"choice": "<one option name>", "probabilities": {"<option name>": <number>, ...}}, with a probability for ' +
  "every option, summing to 1, and the choice the option with the highest probability.";

/** The prompt of a picked row for another arm: the preamble, then the question and state of the Jev body. */
export function armPrompt(body: string): string {
  const b = JSON.parse(body) as { questions: Record<string, Json>; state: Json };
  const [name, q] = Object.entries(b.questions)[0]!;
  return `${ARM_PREAMBLE}\n\n${JSON.stringify({ question: name, ...q, state: b.state }, null, 2)}`;
}
