import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { NOTE_RE } from "./claims-lint.ts";

export const CLAIMS_CLI = "packages/plan-lint/src/cli.ts";
export const CLAIMS_TIMEOUT_MS = 5 * 60_000;

export function landLint(dir: string, changed: string[], timeoutMs = CLAIMS_TIMEOUT_MS): Promise<string[]> {
  const files = changed.filter((p) => NOTE_RE.test(p) && existsSync(join(dir, p))).sort();
  if (!files.length) return Promise.resolve(["claims lint: no changed note or handoff"]);
  return new Promise((done) => {
    execFile(process.execPath, [CLAIMS_CLI, ...files], { cwd: dir, timeout: timeoutMs, maxBuffer: 1 << 26 }, (e, stdout, stderr) => {
      const out = String(stdout).split("\n").filter(Boolean);
      if (!e) return done(out);
      const why = e.killed ? `timed out after ${timeoutMs} ms` : `exit ${e.code}`;
      done([...out, `claims lint: not run (${why}): ${String(stderr).trim().split("\n").at(-1) ?? ""}`]);
    });
  });
}
