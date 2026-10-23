// ghCharged: what it keeps from a GH_DEBUG=api trace, that it never calls gh when fwcore says wait or stop, and that
// it refuses `gh api` / `gh auth`.
import assert from "node:assert/strict";
import test from "node:test";
import { chmodSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { errorSummary, ghCharged, traceLines } from "../src/charged.ts";
import { tryLock } from "../src/lock.ts";
import { loadState, paths } from "../src/state.ts";
import { mkWorld } from "./util.ts";

const T0 = 1_800_000_000;

test("traceLines keeps the status line, x-ratelimit-*, retry-after and etag of responses only", () => {
  const trace = [
    "* Request at 2026-10-18 01:00:00 +0700", "> GET /repos/o/r/actions/runs HTTP/1.1", "> Authorization: token ████████",
    "< HTTP/2.0 403 Forbidden", "< Content-Type: application/json", "< X-Ratelimit-Limit: 5000", "< X-Ratelimit-Remaining: 0",
    "< Retry-After: 60", "< Etag: W/\"abc\"", "< X-Github-Request-Id: AAAA:BBBB", '{"message":"x","actor":{"login":"someone"}}', "",
  ].join("\n");
  assert.deepEqual(traceLines(trace), ["< HTTP/2.0 403 Forbidden", "< X-Ratelimit-Limit: 5000", "< X-Ratelimit-Remaining: 0", "< Retry-After: 60", '< Etag: W/"abc"']);
  assert.deepEqual(traceLines("> X-Ratelimit-Remaining: 9\nHTTP/2.0 200 OK"), []);
});

test("errorSummary carries a status and message, never a body", () => {
  assert.equal(errorSummary('{"login":"x"}\nHTTP 403: API rate limit exceeded (https://api.github.com/x)\n', 1), "HTTP 403: API rate limit exceeded");
  assert.equal(errorSummary('{"login":"x"}', 1), "gh exited with 1");
});

test("an issued call is observed, the trace is dropped, a refusal is not retried", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0, listCost: 2 });
  const r = await ghCharged(w.env, ["run", "list", "--limit", "1"], { cost: 2 });
  assert.ok(r.ran);
  assert.equal(r.status, 200);
  assert.deepEqual(r.lines.map((l) => l.split(":")[0]), ["< HTTP/2.0 200 OK", "< X-Ratelimit-Remaining", "< X-Ratelimit-Reset", "< X-Ratelimit-Resource", "< HTTP/2.0 200 OK", "< X-Ratelimit-Remaining", "< X-Ratelimit-Reset", "< X-Ratelimit-Resource"]);
  assert.ok(!JSON.stringify(r.lines).includes("someone-private"));
  assert.equal((loadState(w.stateDir) as { remaining: number }).remaining, 4998);
  assert.equal(w.calls().length, 1);
});

test("a 403 with remaining 0 is observed; the next calls wait and gh is not started", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0, overrides: [{ at: T0, lines: ["HTTP/2.0 403 Forbidden", "X-Ratelimit-Remaining: 0", `X-Ratelimit-Reset: ${T0 + 1800}`, "X-Ratelimit-Resource: core"] }] });
  const a = await ghCharged(w.env, ["run", "list"]);
  assert.ok(a.ran && a.code === 1 && a.status === 403 && a.error === "HTTP 403: API rate limit exceeded");
  w.sim.set(T0 + 10);
  for (let i = 0; i < 5; i++) {
    const b = await ghCharged(w.env, ["run", "view", "1"]);
    assert.ok(!b.ran && b.decision === "wait" && b.until >= T0 + 1800, JSON.stringify(b));
  }
  assert.equal(w.calls().length, 1, "no further gh call");
});

test("blocking waits sleep until the time fwcore named, then call once", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0, overrides: [{ at: T0, lines: ["HTTP/2.0 403 Forbidden", "Retry-After: 120"] }] });
  await ghCharged(w.env, ["run", "list"]);
  const p = ghCharged(w.env, ["run", "view", "1"], { block: true });
  let done = false;
  void p.then(() => { done = true; });
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
  assert.equal(done, false);
  assert.equal(w.calls().length, 1);
  w.sim.advance();
  const r = await p;
  assert.ok(r.ran && w.sim.t >= T0 + 120);
  assert.equal(w.calls().length, 2);
});

test("gh api and gh auth are refused before anything happens", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0 });
  await assert.rejects(ghCharged(w.env, ["api", "rate_limit"]), /not approved/);
  await assert.rejects(ghCharged(w.env, ["auth", "token"]), /never read/);
  assert.equal(w.calls().length, 0);
  assert.equal(loadState(w.stateDir), null);
});

test("fail closed: an fwcore error means no gh call", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0 });
  const env = { ...w.env, core: () => { throw new Error("fwcore missing"); } };
  await assert.rejects(ghCharged(env, ["run", "list"]), /fwcore missing/);
  assert.equal(w.calls().length, 0);
});

test("a lock held past lockWaitMs gives busy by name: no gh call, nothing booked", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0 });
  const held = tryLock(paths(w.stateDir).lock);
  assert.ok(held);
  try {
    const r = await ghCharged(w.env, ["workflow", "run", "x.yml"], { cost: 2, block: true, lockWaitMs: 150 });
    assert.ok(!r.ran && r.decision === "busy" && /held by another fw process for 0.15 s/.test(r.reason), JSON.stringify(r));
    assert.equal(w.calls().length, 0);
    assert.equal(loadState(w.stateDir), null);
  } finally { held.release(); }
  const again = await ghCharged(w.env, ["run", "list"], { cost: 2, lockWaitMs: 150 });
  assert.ok(again.ran, "free lock: the same options still call gh");
});

test("a hung gh is killed at timeoutMs and the failure is named", async () => {
  const w = mkWorld(T0);
  w.config({ start: T0 });
  const hang = join(w.root, "hang-gh.sh");
  writeFileSync(hang, "#!/bin/sh\nsleep 30\n");
  chmodSync(hang, 0o755);
  const r = await ghCharged({ ...w.env, gh: hang }, ["workflow", "run", "x.yml"], { cost: 2, timeoutMs: 300 });
  assert.ok(r.ran && r.code === null && r.error === "gh timed out after 0.3 s and was killed; the request may still have reached GitHub, check gh run list before running it again", JSON.stringify(r));
});
