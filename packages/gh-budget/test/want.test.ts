// Which run does a wait mean? The TS twin (src/want.ts) equals Lean Fw.Ci.Dispatch.select on every `select` line of the golden, and
// `fw ci wait --branch --workflow` uses it: a push and a dispatch of one commit are never swapped.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { parseWait } from "../src/cli.ts";
import { hintOf, relevant, waitFor } from "../src/wait.ts";
import { DISPATCH_WORKFLOWS, dispatchOnly, select, titleFor, titleOf, type WRun, type Want } from "../src/want.ts";
import { drive, mkWorld, repoRoot } from "./util.ts";

const all = readFileSync(join(repoRoot, "packages", "contracts", "golden", "ci", "dispatch.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const lines = all.filter((l) => l.kind === "select");

test("the workflows that carry a nonce equal Lean dispatchWorkflows, and the hint equals Lean dispatchOnly on every golden line", () => {
  assert.deepEqual([...DISPATCH_WORKFLOWS], all.find((l) => l.kind === "workflows").list);
  const hints = all.filter((l) => l.kind === "hint");
  assert.ok(hints.length >= 6 && hints.some((h) => h.hint) && hints.some((h) => !h.hint));
  for (const h of hints) assert.equal(dispatchOnly(h.want as Want, h.rows as WRun[]), h.hint, h.name);
});

test("the golden has select cases of both wants", () => {
  assert.ok(lines.length >= 12);
  for (const k of ["push", "dispatch"]) assert.ok(lines.some((l) => l.want.kind === k), k);
});

test("select equals Lean on every golden line", () => {
  for (const l of lines) assert.deepEqual(select(l.want as Want, l.rows as WRun[]), l.ids, l.name);
});

const T0 = 1_800_000_000;
const SHA = "abcdef1234567890abcdef1234567890abcdef12";
const row = (databaseId: number, event: string, displayTitle: string, createdAt = T0) => ({ databaseId, createdAt, completeAt: createdAt + 50, conclusion: "success", workflowName: "trajectory-probe", headBranch: "ci/x", headSha: SHA, event, displayTitle });

test("a dispatch newer than the push does not replace the push run, and the nonce picks its own dispatch", async () => {
  const runs = [row(10, "push", "ci: m"), row(11, "workflow_dispatch", titleOf("aaaa1111"), T0 + 5), row(12, "workflow_dispatch", titleOf("bbbb2222"), T0 + 6)];
  for (const [want, id] of [[{ kind: "push", sha: SHA }, 10], [{ kind: "dispatch", workflow: "trajectory-probe", nonce: "aaaa1111" }, 11], [{ kind: "dispatch", workflow: "trajectory-probe", nonce: "bbbb2222" }, 12]] as [Want, number][]) {
    const w = mkWorld(T0 + 100, { fastGh: true });
    w.config({ start: T0 + 100, listCost: 2, runs });
    const [res] = await drive(w.sim, [waitFor(w.env, { kind: "branch", branch: "ci/x", workflow: "trajectory-probe", sha: SHA, since: T0 - 1, want }, { timeoutS: 3600 })]);
    assert.deepEqual(res, { code: 0, lines: [`run ${id} trajectory-probe success -> pass`] });
  }
});

test("relevant: without a want the newest run is kept (legacy); with one only the wanted runs", () => {
  const r = (databaseId: number, event: string, displayTitle: string) => ({ status: "completed", conclusion: "success", databaseId, headBranch: "ci/x", workflowName: "w", headSha: SHA, createdAt: new Date(T0 * 1000).toISOString(), event, displayTitle });
  const rows = [r(5, "push", "a"), r(6, "workflow_dispatch", titleOf("aaaa1111"))];
  const t = { kind: "branch" as const, branch: "ci/x", workflow: "w", sha: SHA, since: T0 };
  assert.deepEqual(relevant(rows, t).map((x) => x.databaseId), [6]);
  assert.deepEqual(relevant(rows, { ...t, want: { kind: "push", sha: SHA } }).map((x) => x.databaseId), [5]);
  assert.deepEqual(relevant(rows, { ...t, want: { kind: "dispatch", workflow: "trajectory-probe", nonce: "aaaa1111" } }).map((x) => x.databaseId), [6]);
  assert.deepEqual(relevant([{ ...rows[0]!, event: undefined }], { ...t, want: { kind: "push", sha: SHA } }), []);
});

test("parseWait: --workflow means the push of --sha; --nonce the dispatch; --nonce alone or a bad nonce is refused", () => {
  const base = ["--branch", "ci/x", "--sha", SHA, "--since", "100"];
  const t = (a: string[]) => parseWait([...base, ...a], repoRoot).target;
  assert.deepEqual((t(["--workflow", "w"]) as { want: Want }).want, { kind: "push", sha: SHA });
  assert.deepEqual((t(["--workflow", "trajectory-probe", "--nonce", "abc12345"]) as { want: Want }).want, { kind: "dispatch", workflow: "trajectory-probe", nonce: "abc12345" });
  assert.deepEqual((t(["--workflow", "breakpoint-gate", "--nonce", "abc12345"]) as { want: Want }).want, { kind: "dispatch", workflow: "breakpoint-gate", nonce: "abc12345" });
  assert.throws(() => t(["--nonce", "abc12345"]), /needs --workflow/);
  assert.throws(() => t(["--workflow", "trajectory-probe", "--nonce", "ABC"]), /8 to 32/);
  // no run-name of the workflow carries a nonce: the wait could never match, so it is refused
  assert.throws(() => t(["--workflow", "w", "--nonce", "abc12345"]), /no run-name of workflow w carries a nonce/);
  assert.throws(() => t(["--workflow", "land", "--nonce", "abc12345"]), /no run-name/);
});

test("relevant: a nonce dispatch on another head sha, created before the commit, is found (Lean dispatch_any_sha)", () => {
  const OTHER = "1234567abcdef1234567abcdef1234567abcdef1";
  const r = { status: "completed", conclusion: "success", databaseId: 7, headBranch: "ci/x", workflowName: "breakpoint-gate", headSha: OTHER, createdAt: new Date((T0 - 5000) * 1000).toISOString(), event: "workflow_dispatch", displayTitle: titleFor("breakpoint-gate", "aaaa1111") };
  const t = { kind: "branch" as const, branch: "ci/x", workflow: "breakpoint-gate", sha: SHA, since: T0 };
  assert.deepEqual(relevant([r], { ...t, want: { kind: "dispatch", workflow: "breakpoint-gate", nonce: "aaaa1111" } }).map((x) => x.databaseId), [7]);
  assert.deepEqual(relevant([r], { ...t, want: { kind: "dispatch", workflow: "breakpoint-gate", nonce: "bbbb2222" } }), []);
  assert.deepEqual(relevant([{ ...r, event: "push" }], { ...t, want: { kind: "dispatch", workflow: "breakpoint-gate", nonce: "aaaa1111" } }), []);
});

test("hintOf: only dispatch runs of the commit under a push wait say so; a push run or a dispatch wait stay silent", () => {
  const r = (databaseId: number, event: string) => ({ status: "completed", conclusion: "success", databaseId, headBranch: "ci/x", workflowName: "trajectory-probe", headSha: SHA, createdAt: new Date(T0 * 1000).toISOString(), event, displayTitle: "t" });
  const t = { kind: "branch" as const, branch: "ci/x", workflow: "trajectory-probe", sha: SHA, since: T0, want: { kind: "push" as const, sha: SHA } };
  const st = (rows: ReturnType<typeof r>[]) => ({ rows }) as never;
  assert.match(hintOf(st([r(1, "workflow_dispatch")]), t) ?? "", /only workflow_dispatch runs of abcdef1.*--nonce/);
  assert.equal(hintOf(st([r(1, "workflow_dispatch"), r(2, "push")]), t), null);
  assert.equal(hintOf(st([]), t), null);
  assert.equal(hintOf(st([r(1, "workflow_dispatch")]), { ...t, want: { kind: "dispatch", workflow: "trajectory-probe", nonce: "abc12345" } }), null);
});
