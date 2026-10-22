import assert from "node:assert/strict";
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { fwcoreBin, fwcoreCall } from "../packages/gh-budget/src/core.ts";
import { answerOf, blockKind, certifyOf, childEnv, claudeArgs, costOf, EPS_BEGIN, EPS_END, epsBlock, epsInvalid, failed,
  fencedBlocks, optionsOf, probeVerdict, redactEnvelope, redactText, scoreLine, table } from "./jev-arms-clean.mjs";

test("claudeArgs isolates the call: no tools, no setting sources, strict MCP, no session file, JSON out", () => {
  const a = claudeArgs("haiku", "SYS");
  assert.deepEqual(a.slice(0, 3), ["-p", "--model", "haiku"]);
  assert.equal(a[a.indexOf("--tools") + 1], "");
  assert.equal(a[a.indexOf("--setting-sources") + 1], "");
  assert.equal(a[a.indexOf("--system-prompt") + 1], "SYS");
  for (const f of ["--strict-mcp-config", "--no-session-persistence"]) assert.ok(a.includes(f));
  assert.equal(a[a.indexOf("--output-format") + 1], "json");
});

test("childEnv keeps only allowlisted keys", () => {
  const e = childEnv({ HOME: "/h", PATH: "/b", CLAUDECODE: "1", CLAUDE_CODE_SESSION_ID: "s", AI_AGENT: "x" });
  assert.deepEqual(e, { HOME: "/h", PATH: "/b" });
});

test("redactEnvelope drops session id, cwd and uuid", () => {
  const r = redactEnvelope({ type: "result", session_id: "abc", uuid: "u", is_error: false, result: "x", duration_ms: 5,
    usage: { input_tokens: 2, cache_creation_input_tokens: 600, cache_read_input_tokens: 0, output_tokens: 9 },
    modelUsage: { "claude-haiku-5-5": { inputTokens: 2, outputTokens: 9 } } });
  const s = JSON.stringify(r);
  assert.ok(!s.includes("abc") && !s.includes("\"u\""));
  assert.deepEqual(Object.keys(r.models), ["claude-haiku-5-5"]);
  assert.equal(r.usage.cacheCreation, 600);
});

test("answerOf reads bare JSON, one fence, or a bare option name; else none", () => {
  const opts = ["a", "b"];
  assert.deepEqual(answerOf('{"choice":"a","probabilities":{"a":0.9,"b":0.1}}', opts),
    { parse: "json", choice: "a", probabilities: { a: 0.9, b: 0.1 } });
  assert.equal(answerOf('```json\n{"choice":"b","probabilities":{"a":0,"b":1}}\n```', opts).parse, "fence");
  assert.deepEqual(answerOf("b", opts), { parse: "choice", choice: "b" });
  assert.deepEqual(answerOf("I think b", opts), { parse: "none" });
  assert.deepEqual(answerOf('{"answer":"a"}', opts), { parse: "none" });
});

test("optionsOf reads the criteria keys after the preamble", () => {
  assert.deepEqual(optionsOf('PRE\n\n{"question":"q","criteria":{"x":"..","y":".."},"state":{}}'), ["x", "y"]);
});

test("failed: nonzero exit, no envelope or error result", () => {
  const ok = { exit: 0, env: { isError: false, result: "x" } };
  assert.equal(failed(ok), false);
  assert.equal(failed({ ...ok, exit: 1 }), true);
  assert.equal(failed({ exit: 0, env: null }), true);
  assert.equal(failed({ exit: 0, env: { isError: true, result: "x" } }), true);
});

test("scoreLine leaves out rows without a choice", () => {
  assert.equal(scoreLine({ id: "r", parse: "none" }), null);
  assert.deepEqual(scoreLine({ id: "r", choice: "a", inputTokens: 1, outputTokens: 2, ms: 3, text: "t" }),
    { id: "r", choice: "a", inputTokens: 1, outputTokens: 2, ms: 3 });
});

test("redactText hides the scratch dir, home, login and emails", () => {
  const home = "/h/alice", mail = ["alice", "x.com"].join("@");
  const t = redactText(`cwd /private/tmp/w/cwd/c-1 /tmp/w/x ${home}/a ${mail} alice`, { work: "/private/tmp/w", home, user: "alice" });
  assert.equal(t, "cwd <work>/cwd/c-1 <work>/x ~/a <email> <user>");
});

test("blockKind knows the three harness blocks and nothing else", () => {
  assert.equal(blockKind("You are a Claude agent, built on Anthropic's Claude Agent SDK.Follow."), "system");
  assert.equal(blockKind("# Environment\nx"), "environment");
  assert.equal(blockKind("<system-reminder>\nAs you answer the user's questions, you can use the following context:\n# userEmail\nThe user's email address is <email>.\n</system-reminder>"), "userEmail");
  assert.equal(blockKind("<system-reminder>\nAs you answer the user's questions, you can use the following context:\n# userEmail\nx\n# claudeMd\ny\n</system-reminder>"), "other");
  assert.equal(blockKind("Contents of CLAUDE.md"), "other");
  assert.deepEqual(fencedBlocks("a\n```\nX\n```\n```json\nY\n```"), ["X\n", "Y\n"]);
});

const passing = {
  init: { tools: [], mcpServers: [] },
  minimal: { promptTokens: 628 },
  introspect: { numTurns: 1, permissionDenials: 0, refused: [],
    text: "```\nYou are a Claude agent, built on Anthropic's Claude Agent SDK.X\n```\nNONE\nCANNOT" },
  row: { promptTokens: 1898, budget: 1563 },
};

test("probeVerdict passes the clean case and fails each leak on its own", () => {
  assert.deepEqual(probeVerdict(passing), { pass: true, reasons: [] });
  const fails = [
    { ...passing, init: { tools: ["Read"], mcpServers: [] } },
    { ...passing, init: { tools: [], mcpServers: ["x"] } },
    { ...passing, minimal: { promptTokens: 2300 } },
    { ...passing, introspect: { ...passing.introspect, numTurns: 2 } },
    { ...passing, introspect: { ...passing.introspect, text: passing.introspect.text.replace("CANNOT", "done") } },
    { ...passing, introspect: { ...passing.introspect, text: passing.introspect.text + "\n```\nContents of CLAUDE.md\n```" } },
    { ...passing, introspect: { ...passing.introspect, text: "NONE CANNOT" } },
    { ...passing, introspect: { ...passing.introspect, refused: ["orphan until-loop"] } },
    { ...passing, row: { promptTokens: 4000, budget: 1563 } },
  ];
  for (const f of fails) assert.equal(probeVerdict(f).pass, false, JSON.stringify(f).slice(0, 120));
});

test("certifyOf names advised options or none; costOf sums ok rows and counts retries", () => {
  const sc = (advised) => ({ holdoutCert: { covered: advised, hits: advised, options: [{ option: "a", advised, hits: advised }] } });
  assert.equal(certifyOf(sc(0)), "none");
  assert.equal(certifyOf(sc(3)), "3/3: a 3/3");
  const c = costOf([{ id: "1", parse: "json", inputTokens: 10, outputTokens: 2, ms: 5, costUsd: 0.5, model: "m" },
    { id: "2", parse: "none", inputTokens: 20, outputTokens: 4, ms: 9, costUsd: 0.25, model: "m" }, { id: "3", failed: true }],
  [{ attempt: 1 }, { attempt: 1 }, { attempt: 1 }, { attempt: 2 }]);
  assert.deepEqual(c, { rows: 3, parses: { json: 1, none: 1, failed: 1 }, calls: 4, retried: 1, inputTokens: 30,
    outputTokens: 6, costUsd: 0.75, models: ["m"], msMedian: 9, msMax: 9 });
});

const epsRun = (o) => ({ rows: 116, answers: 116, right: { old: 69, new: 69 }, valid: { old: 101, new: 114 },
  validRight: { old: 57, new: 68 }, certify: { old: "none", new: "none" },
  invalid: { old: { "sum eps": 15 }, new: { "sum rounding": 2 } }, ...o });

test("epsBlock writes one row per re-validated run between the markers, with both rules", () => {
  const md = epsBlock({ "d1:haiku:first": epsRun(), "d2:jev:recorded": epsRun({ rows: 83, answers: 83,
    right: { old: 39, new: 40 }, valid: { old: 83, new: 83 }, validRight: { old: 40, new: 40 } }) });
  assert.equal(md[0], EPS_BEGIN);
  assert.equal(md.at(-1), EPS_END);
  assert.deepEqual(md.slice(5, 7), ["| d1 | haiku | first | 116 | 101 | 114 | 57 | 68 | 69 / 116 | none | none |",
    "| d2 | jev | recorded | 83 | 83 | 83 | 40 | 40 | 39 → 40 / 83 | none | none |"]);
});

test("epsInvalid keeps the old-rule counts only while fwcore still gives the file's sumOk counts", () => {
  const eps = { runs: { "d1:haiku:first": epsRun({ invalid: { old: { a: 1, b: 2 }, new: { a: 1, c: 3 } } }) } };
  assert.deepEqual(epsInvalid("d1:haiku:first", { c: 3, a: 1 }, eps), { a: 1, b: 2 });
  assert.throws(() => epsInvalid("d1:haiku:first", { a: 1, c: 4 }, eps), /stale/);
  assert.throws(() => epsInvalid("d1:haiku:first", { a: 1 }, eps), /stale/);
  assert.throws(() => epsInvalid("d1:sonnet:first", { a: 1, c: 3 }, eps), /no row/);
});

let core = null;
try { core = existsSync(fwcoreBin(process.cwd())) ? fwcoreCall(process.cwd()) : null; } catch { core = null; }

test("table regenerates the committed table.md and table.json, the oracle-eps block included",
  { skip: core ? false : "fwcore not built" }, () => {
    const committed = fileURLToPath(new URL("../results/jev-arms-clean", import.meta.url));
    const eps = JSON.parse(readFileSync(new URL("../results/jev/eps-rescore.json", import.meta.url), "utf8"));
    const out = mkdtempSync(join(tmpdir(), "jev-arms-table-"));
    try {
      cpSync(committed, out, { recursive: true });
      table({ out, old: join(out, "first-run"), core, eps, quiet: true });
      for (const f of ["table.md", "table.json"]) {
        assert.equal(readFileSync(join(out, f), "utf8"), readFileSync(join(committed, f), "utf8"), f);
      }
    } finally { rmSync(out, { recursive: true, force: true }); }
  });
