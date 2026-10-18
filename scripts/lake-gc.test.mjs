// node --test scripts/lake-gc.test.mjs (task lean-bin-slim): the golden of ops.lakeGc replayed through the built
// fwcore, and the fact gatherer on a scratch cache (hard link, symlink, young file), which must list and never delete.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gatherFacts, lakeGcCli } from "../apps/runner/src/lake-gc.ts";
import { coreCall, top } from "./lake-gc.mjs";

const bin = process.env.FW_CORE_BIN ?? join(top, "lean/.lake/build/bin/fwcore");
const golden = readFileSync(join(top, "packages/contracts/golden/ops/lakegc.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

test("every golden line: fwcore answers the recorded response", { skip: !existsSync(bin) && "fwcore not built" }, () => {
  const input = golden.map((g, i) => JSON.stringify({ ...g.request, id: i })).join("\n") + "\n";
  const r = spawnSync(bin, [], { input, encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  const replies = r.stdout.trim().split("\n").map((l) => JSON.parse(l));
  assert.equal(replies.length, golden.length);
  golden.forEach((g, i) => {
    const { id, ...rest } = replies[i];
    assert.equal(id, i);
    assert.deepEqual(rest, g.response, g.name);
  });
});

test("scratch cache: only the old unlinked regular file is listed, nothing is deleted", { skip: !existsSync(bin) && "fwcore not built" }, () => {
  const base = mkdtempSync(join(tmpdir(), "lakegc"));
  const root = join(base, "artifacts");
  mkdirSync(root);
  try {
    const old = Date.now() / 1000 - 3 * 3600;
    for (const n of ["old.o", "linked.olean", "young.c"]) writeFileSync(join(root, n), n);
    utimesSync(join(root, "old.o"), old, old);
    utimesSync(join(root, "linked.olean"), old, old);
    linkSync(join(root, "linked.olean"), join(base, "checkout.olean"));
    symlinkSync(join(root, "old.o"), join(root, "sym"));
    const facts = Object.fromEntries(gatherFacts(root).map((f) => [f.name, f]));
    assert.equal(facts["linked.olean"].links, 2);
    assert.equal(facts.sym.file, false);
    const out = [];
    const rc = lakeGcCli(["--list", "--root", root], top, coreCall(bin), (s) => out.push(s));
    assert.equal(rc, 0);
    assert.deepEqual(out, [join(root, "old.o")]);
    for (const n of ["old.o", "linked.olean", "young.c", "sym"]) assert.ok(existsSync(join(root, n)), `${n} kept`);
    const sum = [];
    lakeGcCli(["--root", root], top, coreCall(bin), (s) => sum.push(s));
    assert.match(sum.join("\n"), /listed: 1 files/);
    assert.match(sum.join("\n"), /xargs rm -f --/);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});
