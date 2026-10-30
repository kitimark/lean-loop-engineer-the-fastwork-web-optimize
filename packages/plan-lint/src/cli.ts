import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defaultTargets, lintPaths, trackedFiles } from "./claims-lint.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const tracked = trackedFiles(root);
const args = process.argv.slice(2);
const paths = args.length ? args : defaultTargets(tracked);
const results = await lintPaths(root, paths, tracked);
const byCode = new Map<string, number>();
for (const r of results) for (const f of r.findings) {
  console.log(`WARN ${r.path}:${f.line} ${f.code} ${f.detail}`);
  byCode.set(f.code, (byCode.get(f.code) ?? 0) + 1);
}
const total = [...byCode.values()].reduce((a, b) => a + b, 0);
const codes = [...byCode].sort(([a], [b]) => a.localeCompare(b)).map(([c, n]) => `${c} ${n}`).join(", ");
console.log(`claims lint: ${total} warnings in ${results.filter((r) => r.findings.length).length} of ${results.length} files${codes ? ` (${codes})` : ""}`);
