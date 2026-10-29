import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export type Legs = { gh: string[]; all: string[] };
export type LandIntent = { task: string; merge: string; again: boolean; marker: string; pid: number; legs: Legs | null };
export type IntentStore = { write(i: LandIntent): () => void };

export const INTENT_DIR = "fw-land-intent";
export const intentPath = (commonDir: string, marker: string): string => join(commonDir, INTENT_DIR, `${marker}.json`);

export function fileIntents(commonDir: () => string): IntentStore {
  return {
    write(i) {
      const p = intentPath(commonDir(), i.marker);
      mkdirSync(join(p, ".."), { recursive: true });
      writeFileSync(`${p}.tmp`, JSON.stringify(i));
      renameSync(`${p}.tmp`, p);
      return () => rmSync(p, { force: true });
    },
  };
}

export function readIntent(commonDir: string, sha: string): LandIntent | null {
  if (!/^[0-9a-f]{40,64}$/.test(sha)) return null;
  try {
    const i = JSON.parse(readFileSync(intentPath(commonDir, sha), "utf8")) as LandIntent;
    const legsOk = i.legs === null || (Array.isArray(i.legs.gh) && Array.isArray(i.legs.all));
    return typeof i.task === "string" && typeof i.merge === "string" && typeof i.again === "boolean" && i.marker === sha && Number.isInteger(i.pid) && legsOk ? i : null;
  } catch { return null; }
}

export function ancestors(start: number = process.ppid, ppidOf: (pid: number) => number = psParent): number[] {
  const out: number[] = [];
  for (let p = start; p > 1 && out.length < 64 && !out.includes(p); ) {
    out.push(p);
    try { p = ppidOf(p); } catch { break; }
  }
  return out;
}

const psParent = (pid: number): number => Number(execFileSync("ps", ["-o", "ppid=", "-p", String(pid)], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim());
