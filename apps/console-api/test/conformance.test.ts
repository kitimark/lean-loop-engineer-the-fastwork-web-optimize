// Runs the language-neutral golden cases against fwcore (Lean only; the TS stand-in is gone).
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";

const file = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console-apply.jsonl");
const cases = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const core = selectCore();
afterAll(() => core.close());

describe("console.apply golden conformance (fwcore)", () => {
  for (const c of cases) {
    it(c.name, async () => {
      expect(JSON.parse(JSON.stringify(await core.apply(c.request.state, c.request.event)))).toEqual(c.response);
    });
  }
});
