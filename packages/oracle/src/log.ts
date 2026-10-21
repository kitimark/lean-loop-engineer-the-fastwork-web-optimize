// The append-only answer log (`.fw-console/oracle.jsonl` of the main checkout, gitignored). One line per call that
// went out. The key is the sha256 of the exact request body (question, redacted state, pinned model), so a logged
// reply replays exactly and costs nothing. The key itself and the request body are never written here.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname } from "node:path";

export type LogEntry = {
  /** sha256 hex of the request body text. */
  key: string;
  question: string;
  model: string;
  /** UTC day of the call, YYYY-MM-DD (the daily cap counts these). */
  day: string;
  at: string;
  ms: number;
  /** The response body text (status 200), or the failure as `oracle.decide` reads it. */
  reply?: string;
  failure?: Record<string, unknown>;
};

/** sha256 hex of a text. */
export function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

/** Every entry of the log (unreadable lines are skipped; a missing file is empty). */
export function readLog(path: string): LogEntry[] {
  if (!existsSync(path)) return [];
  const out: LogEntry[] = [];
  for (const line of readFileSync(path, "utf8").split("\n")) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line) as LogEntry); } catch { /* a torn line is skipped */ }
  }
  return out;
}

/** The logged reply for a key (the latest), if any. Failures are not replayed: a later call may succeed. */
export function loggedReply(entries: LogEntry[], key: string): string | undefined {
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i]!;
    if (e.key === key && typeof e.reply === "string") return e.reply;
  }
  return undefined;
}

/** Append one entry. */
export function appendLog(path: string, e: LogEntry): void {
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(path, JSON.stringify(e) + "\n");
}
