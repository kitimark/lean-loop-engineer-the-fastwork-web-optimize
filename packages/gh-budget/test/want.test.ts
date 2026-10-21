// Which run does a wait mean? The TS twin (src/want.ts) equals Lean Fw.Ci.Dispatch.select on every `select` line of the golden, and
// `fw ci wait --branch --workflow` uses it: a push and a dispatch of one commit are never swapped.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { parseWait } from "../src/cli.ts";
import { relevant, waitFor } from "../src/wait.ts";
import { select, titleOf, type WRun, type Want } from "../src/want.ts";
import { drive, mkWorld, repoRoot } from "./util.ts";

const lines = readFileSync(join(repoRoot, "packages", "contracts", "golden", "ci", "dispatch.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((l) => l.kind === "select");

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
  for (const [want, id] of [[{ kind: "push", sha: SHA }, 10], [{ kind: "dispatch", nonce: "aaaa1111" }, 11], [{ kind: "dispatch", nonce: "bbbb2222" }, 12]] as [Want, number][]) {
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
  assert.deepEqual(relevant(rows, { ...t, want: { kind: "dispatch", nonce: "aaaa1111" } }).map((x) => x.databaseId), [6]);
  assert.deepEqual(relevant([{ ...rows[0]!, event: undefined }], { ...t, want: { kind: "push", sha: SHA } }), []);
});

test("parseWait: --workflow means the push of --sha; --nonce the dispatch; --nonce alone or a bad nonce is refused", () => {
  const base = ["--branch", "ci/x", "--sha", SHA, "--since", "100"];
  const t = (a: string[]) => parseWait([...base, ...a], repoRoot).target;
  assert.deepEqual((t(["--workflow", "w"]) as { want: Want }).want, { kind: "push", sha: SHA });
  assert.deepEqual((t(["--workflow", "w", "--nonce", "abc12345"]) as { want: Want }).want, { kind: "dispatch", nonce: "abc12345" });
  assert.throws(() => t(["--nonce", "abc12345"]), /needs --workflow/);
  assert.throws(() => t(["--workflow", "w", "--nonce", "ABC"]), /8 to 32/);
});
