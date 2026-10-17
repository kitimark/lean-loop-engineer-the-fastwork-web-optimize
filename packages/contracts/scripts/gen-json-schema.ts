import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { allJsonSchemas } from "../src/schemas.ts";

const out = join(dirname(fileURLToPath(import.meta.url)), "../schema");
mkdirSync(out, { recursive: true });
for (const [name, schema] of Object.entries(allJsonSchemas())) {
  writeFileSync(join(out, `${name}.schema.json`), JSON.stringify(schema, null, 2) + "\n");
}
console.log(`wrote JSON Schemas to ${out}`);
