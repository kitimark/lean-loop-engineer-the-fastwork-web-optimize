import { appendFileSync, existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { coreCaller } from "../src/watch.ts";
import { startPush } from "../src/watch-push.ts";

const here = dirname(fileURLToPath(import.meta.url));
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const have = existsSync(bin);

// Append-to-line latency over 20 appends; set PUSH_LATENCY=1 to print p50/p95. Always asserts p95 under the 2 s deadline.
describe.skipIf(!have)("push latency", () => {
  it("20 appends, p95 under 2 s", async () => {
    const d = mkdtempSync(join(tmpdir(), "fwpushlat-"));
    const f = join(d, "events.jsonl");
    writeFileSync(f, "");
    const got: number[] = [];
    const stop = startPush(f, coreCaller([bin]), () => got.push(Date.now()));
    const lat: number[] = [];
    for (let i = 0; i < 20; i++) {
      const n = got.length, t0 = Date.now();
      appendFileSync(f, JSON.stringify({ type: "review.feedback", actor: "user", flag: "step:s", id: `fb-${i}`, text: "q" }) + "\n");
      while (got.length === n && Date.now() - t0 < 3000) await new Promise((r) => setTimeout(r, 2));
      lat.push((got[n] ?? Date.now()) - t0);
      await new Promise((r) => setTimeout(r, 150));
    }
    stop();
    rmSync(d, { recursive: true, force: true });
    const s = [...lat].sort((a, b) => a - b);
    const p50 = s[9]!, p95 = s[18]!;
    if (process.env.PUSH_LATENCY) console.log(`push latency ms p50=${p50} p95=${p95} max=${s[19]} all=${lat.join(",")}`);
    expect(p95).toBeLessThan(2000);
  }, 120000);
});
