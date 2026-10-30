import { test, after } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { ClaimsServer, defaultTargets, lintNote, readArtifact } from "../src/claims-lint.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const rows = readFileSync(join(root, "packages/contracts/golden/plan/claims.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; req: object; res: unknown });
const server = new ClaimsServer(root);
after(() => server.close());

test("the golden has lint and reads rows", () => {
  assert.ok(rows.length > 20);
  assert.ok(rows.some((r) => (r.req as { op: string }).op === "claims.reads"));
});

for (const r of rows) test(`golden: ${r.name}`, async () => assert.deepEqual(await server.ask(r.req), r.res));

test("a note's key reference is read from disk and checked", async () => {
  const dir = mkdtempSync(join(tmpdir(), "claims-lint-"));
  mkdirSync(join(dir, "results/x"), { recursive: true });
  writeFileSync(join(dir, "results/x/summary.json"), JSON.stringify({ rows: [{ id: "a", ms: 12.5 }] }));
  const text = "Files: `results/x/summary.json`.\n\nMEASURED, run 123456789: `summary.json` `rows[a].ms` 12 ms.\n";
  const fs = await lintNote(server, dir, "note.md", text, new Set(["results/x/summary.json"]));
  assert.deepEqual(fs.map((f) => [f.line, f.code]), [[3, "keyMismatch"]]);
  const ok = await lintNote(server, dir, "note.md", text.replace("12 ms", "12.5 ms"), new Set());
  assert.deepEqual(ok, []);
});

test("artifact reads stay inside the repo", () => {
  assert.equal(readArtifact(root, "../outside.json"), null);
  assert.equal(readArtifact(root, "/etc/hosts"), null);
  assert.equal(readArtifact(root, "results/none/missing.json"), null);
});

test("the default targets are tracked notes and handoffs", () => {
  const t = defaultTargets(new Set(["research/notes/2026/a.md", "docs/team/handoffs/b.md", "docs/team/handoffs/x/c.md", "docs/plan/PLAN.md"]));
  assert.deepEqual(t, ["docs/team/handoffs/b.md", "research/notes/2026/a.md"]);
});
