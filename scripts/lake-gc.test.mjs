// node --test scripts/lake-gc.test.mjs (tasks lean-bin-slim, lake-gc-refs): the golden of ops.lakeGc replayed through
// the built fwcore, and `fw lake-gc` on a scratch cache with given checkouts and processes, listing and deleting.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, linkSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
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

/** The gatherer of `lakeGcCli` with real file facts and the given checkouts and processes; the outputs map is `outs`. */
const fakeGather = (checkouts, procs, outs = []) => (_top, root) => ({ files: gatherFacts(root), checkouts, procs, outputs: () => outs });

function scratch(body) {
  const base = mkdtempSync(join(tmpdir(), "lakegc"));
  const root = join(base, "artifacts");
  mkdirSync(root);
  try {
    for (const n of ["old.o", "linked.olean", "young.c", "named.ilean"]) writeFileSync(join(root, n), n);
    const old = Date.now() / 1000 - 3 * 3600;
    utimesSync(join(root, "old.o"), old, old);
    utimesSync(join(root, "linked.olean"), old, old);
    linkSync(join(root, "linked.olean"), join(base, "checkout.olean"));
    symlinkSync(join(root, "old.o"), join(root, "sym"));
    body(root);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
}

const has = (root, names) => names.every((n) => readdirSync(root).includes(n));

test("scratch cache, no writer: unreferenced unlinked files are listed by identity, nothing is deleted", { skip: !existsSync(bin) && "fwcore not built" }, () => scratch((root) => {
  const facts = Object.fromEntries(gatherFacts(root).map((f) => [f.name, f]));
  assert.equal(facts["linked.olean"].links, 2);
  assert.equal(facts.sym.file, false);
  const gather = fakeGather([{ path: "/w", refs: ["named.ilean"] }], []);
  const out = [];
  assert.equal(lakeGcCli(["--list", "--root", root], top, coreCall(bin), (s) => out.push(s), gather), 0);
  assert.deepEqual(out.sort(), [join(root, "old.o"), join(root, "young.c")]);
  assert.ok(has(root, ["old.o", "linked.olean", "young.c", "named.ilean", "sym"]));
  const sum = [];
  lakeGcCli(["--root", root], top, coreCall(bin), (s) => sum.push(s), gather);
  assert.match(sum.join("\n"), /basis: +identity/);
  assert.match(sum.join("\n"), /listed: 2 files/);
  assert.match(sum.join("\n"), /fw lake-gc --delete/);
}));

test("scratch cache, live writer: entries it may have touched are kept; no process table falls back to the age floor", { skip: !existsSync(bin) && "fwcore not built" }, () => scratch((root) => {
  const now = Math.floor(Date.now() / 1000);
  const build = (start) => ({ pid: 7, start, exe: "/x/lake", args: "lake build", cwd: "/w" });
  const touched = [];
  lakeGcCli(["--list", "--root", root], top, coreCall(bin), (s) => touched.push(s), fakeGather([], [build(now - 60)], []));
  assert.deepEqual(touched, []);
  const later = [];
  lakeGcCli(["--list", "--root", root], top, coreCall(bin), (s) => later.push(s), fakeGather([], [build(now + 3600)], ["young.c"]));
  assert.deepEqual(later.sort(), [join(root, "named.ilean"), join(root, "old.o")]);
  const age = [];
  lakeGcCli(["--list", "--root", root], top, coreCall(bin), (s) => age.push(s), fakeGather([], null));
  assert.deepEqual(age, [join(root, "old.o")]);
}));

test("--delete removes exactly the listed files", { skip: !existsSync(bin) && "fwcore not built" }, () => scratch((root) => {
  const out = [];
  const rc = lakeGcCli(["--delete", "--root", root], top, coreCall(bin), (s) => out.push(s), fakeGather([{ path: "/w", refs: ["named"] }], []));
  assert.equal(rc, 0);
  assert.match(out[0], /deleted 2 files/);
  assert.ok(!existsSync(join(root, "old.o")) && !existsSync(join(root, "young.c")));
  assert.ok(has(root, ["linked.olean", "named.ilean", "sym"]));
}));
