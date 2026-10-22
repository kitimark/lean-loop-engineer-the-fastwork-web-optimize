import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { fwcoreBin, fwcoreCall } from "../packages/gh-budget/src/core.ts";
import { answerLine, answerSchema, callOf, evidenceOf, hitOf, hookSettings, lowerAscii, readSpan, readsOf, streamOf,
  traceArgs, traceCalls, treeVerdict } from "./jev-trace.mjs";

const golden = readFileSync(new URL("../packages/contracts/golden/oracle/retrieve.jsonl", import.meta.url), "utf8")
  .split("\n").filter(Boolean).map((l) => JSON.parse(l));
const one = (name) => golden.find((c) => c.name.startsWith(name));

let core = null;
try { core = existsSync(fwcoreBin(process.cwd())) ? fwcoreCall(process.cwd()) : null; } catch { core = null; }
const needCore = { skip: core ? false : "fwcore not built" };

for (const c of golden) {
  test(`golden: ${c.name}`, needCore, () => {
    const { op, ...req } = c.request;
    assert.deepEqual(core({ op, ...req }), c.response);
  });
}

test("the golden covers every op of the module", () => {
  assert.deepEqual([...new Set(golden.map((c) => c.request.op))].sort(), ["oracle.retrieveAdopt", "oracle.retrieveEvidence",
    "oracle.retrieveHook", "oracle.retrieveHybrid", "oracle.retrievePick", "oracle.retrievePick1", "oracle.retrievePlan",
    "oracle.retrieveRanges", "oracle.retrieveScope", "oracle.retrieveTrace", "oracle.retrieveTree", "oracle.retrieveVocab"]);
});

test("the JS tree mirror gives Lean's verdicts on the golden tree case", () => {
  const words = one("vocab:").response.words;
  const c = one("tree:");
  for (const f of c.response.files) {
    const text = c.request.blobs[f.path];
    const allowed = f.verdict !== "notAllowed";
    assert.deepEqual(treeVerdict(allowed, words, f.path, text), f.word ? { verdict: f.verdict, word: f.word } : { verdict: f.verdict });
  }
});

test("lower case is ASCII only, as Lean's Char.toLower", () => {
  assert.equal(lowerAscii("AbÄÖ-Z"), "abÄÖ-z");
  assert.equal(hitOf(["c-quota", "inc-a"], "see C-QUOTA"), "c-quota");
  assert.equal(hitOf(["c-quota"], "Ä"), null);
});

test("readSpan: offset, limit, the end of the file, bytes with the newline", () => {
  const t = "a\nbb\nccc\n";
  assert.deepEqual(readSpan(t), { first: 1, last: 3, bytes: 9 });
  assert.deepEqual(readSpan(t, 2, 1), { first: 2, last: 2, bytes: 3 });
  assert.deepEqual(readSpan(t, 3, 50), { first: 3, last: 3, bytes: 4 });
  assert.deepEqual(readSpan(t, 9), { first: 9, last: 8, bytes: 0 });
});

test("callOf maps each tool input to a call", () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "jt-")));
  try {
    writeFileSync(join(root, "a.ts"), "x\ny\n");
    assert.deepEqual(callOf(root, "Read", { file_path: join(root, "a.ts"), offset: 2 }),
      { tool: "Read", path: join(root, "a.ts"), glob: "", bytes: 2, span: { first: 2, last: 2, bytes: 2 } });
    assert.deepEqual(callOf(root, "Read", { file_path: "/etc/hosts" }).bytes, 0);
    assert.deepEqual(callOf(root, "Grep", { pattern: "x", path: "apps", glob: "*.ts" }), { tool: "Grep", path: "apps", glob: "*.ts", bytes: 0 });
    assert.deepEqual(callOf(root, "Glob", { pattern: "**/*.ts" }), { tool: "Glob", path: "", glob: "**/*.ts", bytes: 0 });
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("traceCalls drops the answer and denied uses and keeps unhooked uses raw", () => {
  const uses = [{ id: "1", name: "Read", input: { file_path: "/t/a.ts" } }, { id: "2", name: "Read", input: { file_path: "/x" } },
    { id: "3", name: "Glob", input: { pattern: "**" } }, { id: "4", name: "StructuredOutput", input: {} }];
  const log = [{ id: "1", decision: "allow" }, { id: "2", decision: "deny" }, { id: "4", decision: "answer" }];
  const t = traceCalls("/t", uses, log);
  assert.equal(t.denied, 1);
  assert.equal(t.unhooked, 1);
  assert.deepEqual(t.calls.map((c) => [c.tool, c.path]), [["Read", "/t/a.ts"], ["Glob", ""]]);
});

test("evidence items parse; a bad line range becomes line 0, which Lean refuses", () => {
  assert.deepEqual(evidenceOf({ evidence: [{ path: "./a.ts", lines: "3-9" }, { path: "b", lines: "x" }] }),
    [{ path: "a.ts", first: 3, last: 9 }, { path: "b", first: 0, last: 0 }]);
  assert.deepEqual(evidenceOf(null), []);
});

test("readsOf keeps the allowed reads with lines", () => {
  const log = [{ tool: "Read", decision: "allow", rel: "a", span: { first: 2, last: 4 } },
    { tool: "Read", decision: "deny", rel: "b", span: { first: 1, last: 1 } }, { tool: "Grep", decision: "allow", rel: "" }];
  assert.deepEqual(readsOf(log), [{ path: "a", lines: [2, 3, 4] }]);
});

test("streamOf reads tool uses, thinking shape and the structured answer", () => {
  const s = streamOf([{ type: "system", subtype: "init", tools: ["Read"] },
    { type: "assistant", message: { content: [{ type: "thinking", thinking: "", signature: "abcd" }, { type: "tool_use", id: "u", name: "Read", input: {} }] } },
    { type: "result", structured_output: { choice: "none" } }]);
  assert.deepEqual(s.uses, [{ id: "u", name: "Read", input: {} }]);
  assert.deepEqual(s.thinking.map((b) => [b.chars, b.signatureBytes]), [[0, 4]]);
  assert.deepEqual(s.structured, { choice: "none" });
});

test("an answer counts only with an ok trace", () => {
  assert.equal(answerLine({ id: "a", choice: "x", probabilities: {}, trace: { verdict: "overReads" } }), null);
  assert.deepEqual(answerLine({ id: "a", choice: "x", probabilities: { x: 1 }, trace: { verdict: "ok" } }),
    { id: "a", choice: "x", probabilities: { x: 1 } });
});

test("the claude arguments: three read tools, restricted, the hook, the schema, the caps", () => {
  const a = traceArgs("haiku", "s", answerSchema(["a", "none"]), hookSettings("/w/st.json"));
  const at = (k) => a[a.indexOf(k) + 1];
  assert.equal(at("--tools"), "Read,Grep,Glob");
  assert.ok(a.includes("--restricted"));
  assert.equal(at("--setting-sources"), "");
  assert.equal(at("--max-turns"), "10");
  assert.equal(at("--max-budget-usd"), "0.05");
  assert.equal(at("--permission-mode"), "dontAsk");
  assert.match(JSON.parse(at("--settings")).hooks.PreToolUse[0].hooks[0].command, /jev-trace\.mjs" hook --state "\/w\/st\.json"$/);
  assert.equal(JSON.parse(at("--json-schema")).properties.evidence.maxItems, 4);
});

test("the hook allows a read in the tree, denies one outside, and counts", needCore, () => {
  const work = realpathSync(mkdtempSync(join(tmpdir(), "jt-")));
  try {
    const root = join(work, "tree");
    mkdirSync(join(root, "apps"), { recursive: true });
    writeFileSync(join(root, "apps", "a.ts"), "one\ntwo\n");
    writeFileSync(join(work, "paths.json"), JSON.stringify(["apps/a.ts"]));
    const st = join(work, "st.json");
    writeFileSync(st, JSON.stringify({ root, pathsFile: join(work, "paths.json"), calls: 0, bytes: 0, log: [] }));
    const run = (tool_name, tool_input, id) => JSON.parse(spawnSync(process.execPath,
      [fileURLToPath(new URL("./jev-trace.mjs", import.meta.url)), "hook", "--state", st],
      { input: JSON.stringify({ tool_name, tool_input, tool_use_id: id }) }).stdout.toString()).hookSpecificOutput;
    assert.equal(run("Read", { file_path: join(root, "apps", "a.ts") }, "1").permissionDecision, "allow");
    assert.equal(run("Read", { file_path: "/etc/hosts" }, "2").permissionDecision, "deny");
    assert.equal(run("StructuredOutput", {}, "3").permissionDecision, "allow");
    const s = JSON.parse(readFileSync(st, "utf8"));
    assert.deepEqual([s.calls, s.bytes, s.log.map((l) => l.decision)], [1, 8, ["allow", "deny", "answer"]]);
  } finally { rmSync(work, { recursive: true, force: true }); }
});
