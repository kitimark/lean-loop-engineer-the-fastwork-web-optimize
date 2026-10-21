import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname } from "node:path";

export type LogEntry = {
  key: string;
  question: string;
  model: string;
  day: string;
  at: string;
  ms: number;
  reply?: string;
  failure?: Record<string, unknown>;
};

export function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

export function readLog(path: string): LogEntry[] {
  if (!existsSync(path)) return [];
  const out: LogEntry[] = [];
  for (const line of readFileSync(path, "utf8").split("\n")) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line) as LogEntry); } catch {}
  }
  return out;
}

export function loggedReply(entries: LogEntry[], key: string): string | undefined {
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i]!;
    if (e.key === key && typeof e.reply === "string") return e.reply;
  }
  return undefined;
}

export function appendLog(path: string, e: LogEntry): void {
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(path, JSON.stringify(e) + "\n");
}
