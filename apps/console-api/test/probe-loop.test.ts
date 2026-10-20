// TEMPORARY PROBE (task drain-wake-flake round 2): repeat the whole console-api suite in child `vitest run`s (two at a time, the
// load of the land lane) until a wake test misses or LOOPS suite runs are done or the time budget is spent. Prints DWF lines.
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "vitest";

const LOOPS = Number(process.env.DWF_LOOPS ?? 30), BUDGET_MS = Number(process.env.DWF_BUDGET_MIN ?? 24) * 60_000, PAR = 2;
const child = process.env.DWF_CHILD === "1";

describe("probe: loop the suite", () => {
  it.skipIf(child)("loops the whole suite", { timeout: 40 * 60_000 }, async () => {
    const out = mkdtempSync(join(tmpdir(), "dwf-"));
    const t0 = Date.now();
    let started = 0, done = 0, stop = false;
    console.log(`DWF start node ${process.version} loops ${LOOPS} par ${PAR} cpus ${(await import("node:os")).cpus().length}`);
    const one = (k: number) => new Promise<void>((res) => {
      const log = join(out, `wake-${k}.jsonl`), rep = join(out, `rep-${k}.json`), s = Date.now();
      const p = spawn(join(process.cwd(), "node_modules/.bin/vitest"), ["run", "--reporter=json", `--outputFile=${rep}`], {
        cwd: process.cwd(), env: { ...process.env, DWF_CHILD: "1", DWF_LOG: log }, stdio: "ignore" });
      p.on("close", (rc) => {
        const rows = existsSync(log) ? readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l) as Record<string, unknown>) : [];
        let failed: string[] = [];
        try {
          const j = JSON.parse(readFileSync(rep, "utf8")) as { testResults: { assertionResults: { status: string; fullName: string }[] }[] };
          failed = j.testResults.flatMap((f) => f.assertionResults).filter((a) => a.status === "failed").map((a) => a.fullName);
        } catch { failed = ["(no report)"]; }
        done++;
        const miss = rows.some((r) => r.kind === "miss") || failed.some((n) => /wake|event path|tick rescue/.test(n));
        for (const r of rows) console.log(`DWF loop ${k} old-test ${JSON.stringify(r)}`);
        console.log(`DWF loop ${k} rc ${rc} secs ${Math.round((Date.now() - s) / 1000)} wake-miss ${miss} failed ${JSON.stringify(failed)}`);
        if (miss) stop = true;
        res();
      });
    });
    const worker = async () => {
      while (!stop && started < LOOPS && Date.now() - t0 < BUDGET_MS) { const k = ++started; await one(k); }
    };
    await Promise.all(Array.from({ length: PAR }, worker));
    console.log(`DWF end loops-done ${done} wake-miss ${stop} secs ${Math.round((Date.now() - t0) / 1000)}`);
  });
});
