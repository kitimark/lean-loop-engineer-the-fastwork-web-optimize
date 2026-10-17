// Regenerates packages/contracts/golden/console-apply.jsonl (one case per line) from the TS reducer table.
// fwcore `console.apply` must reproduce every `response` for its `request`.
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { goldenCases } from "../test/golden.ts";

const out = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console-apply.jsonl");
writeFileSync(out, goldenCases().map((c) => JSON.stringify(c) + "\n").join(""));
console.log(`wrote ${out}`);
