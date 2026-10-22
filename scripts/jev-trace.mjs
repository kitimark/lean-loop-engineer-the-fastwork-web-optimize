#!/usr/bin/env node
import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, linkSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { datasetsDir, logPathFor, pickedRows, redactNames } from "../apps/runner/src/oracle.ts";
import { ARM_PREAMBLE, armAnswers, jevAnswers } from "../apps/runner/src/oracle-score.ts";
import { fwcoreCall } from "../packages/gh-budget/src/index.ts";
import { childEnv, optionsOf, redactEnvelope, redactText } from "./jev-arms-clean.mjs";
import { BLOB_MAX, pairedOf } from "./jev-expand.mjs";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SELF = fileURLToPath(import.meta.url);
export const OUT = join(REPO, "results", "jev-retrieval-trace");
const ABLATION = join(REPO, "results", "jev-file-context-ablation");
const CLEAN = join(REPO, "results", "jev-arms-clean");
export const BUDGET_USD = { haiku: 0.05, sonnet: 0.6 };
export const MAX_TURNS = 10;
export const TOOLS = "Read,Grep,Glob";
export const ANSWER_TOOL = "StructuredOutput";

export const readJsonl = (f) => (existsSync(f) ? readFileSync(f, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l)) : []);
const writeJsonl = (f, rows) => writeFileSync(f, rows.map((r) => JSON.stringify(r)).join("\n") + (rows.length ? "\n" : ""));
const writeJson = (f, v) => { mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, JSON.stringify(v, null, 1) + "\n"); };

function git(args, input) {
  return execFileSync("git", ["-C", REPO, ...args], { maxBuffer: 1 << 30, input, stdio: [input ? "pipe" : "ignore", "pipe", "ignore"] });
}

export const lowerAscii = (s) => s.replace(/[A-Z]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 32));

export function hitOf(words, text) {
  const t = lowerAscii(text);
  return words.find((w) => t.includes(lowerAscii(w))) ?? null;
}

export function treeVerdict(allowed, words, path, text) {
  if (!allowed) return { verdict: "notAllowed" };
  if (text === null) return { verdict: "noText" };
  const w = hitOf(words, text);
  if (w !== null) return { verdict: "vocab", word: w };
  const p = hitOf(words, path);
  return p !== null ? { verdict: "pathVocab", word: p } : { verdict: "kept" };
}

export function textOf(buf) {
  if (buf.length > BLOB_MAX || buf.subarray(0, 8000).includes(0)) return null;
  return buf.toString("utf8");
}

function lsTree(pin) {
  const out = git(["ls-tree", "-r", "-z", "--full-tree", pin]).toString();
  return out.split("\0").filter(Boolean).flatMap((l) => {
    const [meta, path] = l.split("\t");
    const [mode, type, id] = meta.split(" ");
    return type === "blob" && mode !== "120000" ? [{ path, id }] : [];
  });
}

function catBlobs(ids) {
  const buf = git(["cat-file", "--batch"], ids.join("\n") + "\n");
  const out = new Map();
  let at = 0;
  for (const id of ids) {
    const nl = buf.indexOf(10, at);
    const [, , size] = buf.subarray(at, nl).toString().split(" ");
    const n = Number(size);
    out.set(id, buf.subarray(nl + 1, nl + 1 + n));
    at = nl + 1 + n + 1;
  }
  return out;
}

export function scopeRows(core) {
  const inputs = JSON.parse(readFileSync(join(ABLATION, "inputs.json"), "utf8"));
  const ids = new Set(core({ op: "oracle.retrieveScope", rows: inputs.rows.map((r) => ({ id: r.id, files: r.safe.files })) }).ids);
  const blockerOnly = (r) => !r.safe.files.some((f) => f.verdict === "kept" || f.verdict === "overCap");
  const rows = inputs.rows.filter((r) => ids.has(r.id)).map((r) => ({ id: r.id, label: r.label, pin: r.pin,
    named: r.safe.files.map((f) => f.path) }));
  const dropped = inputs.rows.filter((r) => ids.has(r.id) && (inputs.dropped.includes(r.id) || blockerOnly(r))).map((r) => r.id);
  return { rows, dropped, expanded: inputs.expandedIds.filter((i) => ids.has(i)) };
}

const sha = (s) => createHash("sha256").update(s).digest("hex");

function trees(f) {
  const core = fwcoreCall(REPO);
  const work = f.work;
  const { rows, dropped, expanded } = scopeRows(core);
  const byPin = new Map();
  for (const r of rows) if (!byPin.has(r.pin)) byPin.set(r.pin, lsTree(r.pin));
  const allowedOf = new Map();
  for (const [pin, files] of byPin) {
    const v = core({ op: "oracle.retrieveTree", rowId: "", blobs: Object.fromEntries(files.map((x) => [x.path, null])) }).files;
    allowedOf.set(pin, new Set(v.filter((x) => x.verdict === "noText").map((x) => x.path)));
  }
  const need = [...new Set([...byPin].flatMap(([pin, fs]) => fs.filter((x) => allowedOf.get(pin).has(x.path)).map((x) => x.id)))];
  const blobs = catBlobs(need);
  const texts = new Map(need.map((id) => [id, textOf(blobs.get(id))]));
  mkdirSync(join(work, "blobs"), { recursive: true });
  const manifest = [];
  for (const r of rows) {
    const words = core({ op: "oracle.retrieveVocab", rowId: r.id }).words;
    const files = byPin.get(r.pin);
    const allowed = allowedOf.get(r.pin);
    const verdicts = files.map((x) => ({ ...x, ...treeVerdict(allowed.has(x.path), words, x.path, allowed.has(x.path) ? texts.get(x.id) : null) }));
    const kept = verdicts.filter((x) => x.verdict === "kept");
    const root = join(work, "trees", r.id);
    rmSync(root, { recursive: true, force: true });
    for (const x of kept) {
      const blob = join(work, "blobs", x.id);
      if (!existsSync(blob)) writeFileSync(blob, blobs.get(x.id));
      mkdirSync(dirname(join(root, x.path)), { recursive: true });
      linkSync(blob, join(root, x.path));
    }
    const sample = verdicts.filter((x) => x.verdict !== "notAllowed" && (texts.get(x.id)?.length ?? 0) <= 4096)
      .filter((_, i) => i % 40 === 0).slice(0, 12);
    const lean = core({ op: "oracle.retrieveTree", rowId: r.id,
      blobs: Object.fromEntries(sample.map((x) => [x.path, texts.get(x.id)])) }).files;
    const agree = lean.every((l) => { const j = sample.find((x) => x.path === l.path); return j.verdict === l.verdict && (j.word ?? null) === (l.word ?? null); });
    if (!agree) throw new Error(`tree mirror disagrees with Lean on ${r.id}`);
    const count = (v) => verdicts.filter((x) => x.verdict === v).length;
    manifest.push({ id: r.id, label: r.label, pin: r.pin, files: files.length, allowed: allowed.size, kept: kept.length,
      vocab: count("vocab"), pathVocab: count("pathVocab"), noText: count("noText"),
      keptBytes: kept.reduce((a, x) => a + blobs.get(x.id).length, 0),
      keptSha256: sha(kept.map((x) => `${x.path} ${x.id}`).sort().join("\n")),
      named: r.named.map((p) => ({ path: p, inTree: kept.some((x) => x.path === p) })), leanChecked: sample.length });
    writeJson(join(work, "trees", `${r.id}.paths.json`), kept.map((x) => x.path).sort());
  }
  writeJson(join(OUT, "trees.json"), { pins: byPin.size, rows: manifest.length, dropped, expanded, manifest });
  console.log(`jev-trace trees: ${manifest.length} rows, ${byPin.size} pins, kept ${Math.min(...manifest.map((m) => m.kept))}-` +
    `${Math.max(...manifest.map((m) => m.kept))} files per row, ${manifest.reduce((a, m) => a + m.leanChecked, 0)} files checked by Lean`);
}

export const armName = (model, forced) => `t-${model}${forced ? "-read" : ""}`;

export function traceSystem(forced = false) {
  const how = forced
    ? "Before you answer, read at least one file with Read; an answer given before a Read is refused. Use Read, Grep and Glob"
    : "You may read them with Read, Grep and Glob";
  return ARM_PREAMBLE + " Files of the project at the incident's time are in the working directory. " + how +
    ", using paths relative to the working directory: at most 8 calls and 32 KiB of file text in " +
    "all. Your reply also has `evidence`: at most 4 items {\"path\": <file path>, \"lines\": \"<first>-<last>\"} naming " +
    "lines you read that support your choice; an empty list if none.";
}

export function answerSchema(options) {
  return { type: "object", additionalProperties: false, required: ["choice", "probabilities", "evidence"],
    properties: {
      choice: { type: "string", enum: options },
      probabilities: { type: "object", additionalProperties: false, required: options,
        properties: Object.fromEntries(options.map((o) => [o, { type: "number" }])) },
      evidence: { type: "array", maxItems: 4, items: { type: "object", additionalProperties: false, required: ["path", "lines"],
        properties: { path: { type: "string" }, lines: { type: "string", pattern: "^[0-9]+-[0-9]+$" } } } },
    } };
}

export function hookSettings(statePath, extra = {}) {
  const cmd = `${JSON.stringify(process.execPath)} ${JSON.stringify(SELF)} hook --state ${JSON.stringify(statePath)}`;
  return { ...extra, hooks: { PreToolUse: [{ matcher: "*", hooks: [{ type: "command", command: cmd, timeout: 60 }] }] } };
}

export function traceArgs(model, system, schema, settings) {
  return ["-p", "--model", model, "--tools", TOOLS, "--restricted", "--system-prompt", system, "--setting-sources", "",
    "--settings", JSON.stringify(settings), "--strict-mcp-config", "--no-session-persistence", "--permission-mode", "dontAsk",
    "--output-format", "stream-json", "--verbose", "--json-schema", JSON.stringify(schema), "--max-turns", String(MAX_TURNS),
    "--max-budget-usd", String(BUDGET_USD[model])];
}

export function readSpan(text, offset, limit) {
  const lines = text.split("\n");
  if (lines.at(-1) === "") lines.pop();
  const first = Math.max(1, Number(offset ?? 1) || 1);
  const last = Math.min(lines.length, first + Math.max(1, Number(limit ?? 2000) || 2000) - 1);
  if (first > last) return { first, last: first - 1, bytes: 0 };
  return { first, last, bytes: lines.slice(first - 1, last).reduce((a, l) => a + Buffer.byteLength(l) + 1, 0) };
}

export function callOf(root, tool, input) {
  if (tool === "Read") {
    const path = String(input.file_path ?? "");
    let span = { first: 0, last: -1, bytes: 0 };
    const abs = path.startsWith("/") ? path : join(root, path);
    try { if (abs.startsWith(root + "/")) span = readSpan(readFileSync(abs, "utf8"), input.offset, input.limit); } catch { }
    return { tool, path, glob: "", bytes: span.bytes, span };
  }
  if (tool === "Grep") return { tool, path: String(input.path ?? ""), glob: String(input.glob ?? ""), bytes: 0 };
  if (tool === "Glob") return { tool, path: String(input.path ?? ""), glob: String(input.pattern ?? ""), bytes: 0 };
  return { tool, path: "", glob: "", bytes: 0 };
}

function withLock(lock, fn) {
  const t0 = Date.now();
  for (;;) {
    try { mkdirSync(lock); break; } catch {
      if (Date.now() - t0 > 20_000) throw new Error("hook lock timeout");
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
    }
  }
  try { return fn(); } finally { rmSync(lock, { recursive: true, force: true }); }
}

const HELP = { outside: "outside: use Read, Grep or Glob on a file or directory of the working directory, with relative paths and no '..'",
  overReads: "overReads: the 8 calls are used; answer now", overBytes: "overBytes: this read passes 32 KiB; read fewer lines with offset and limit",
  readFirst: "readFirst: read at least one file of the working directory with Read before you answer" };

export const gateLog = (log) => log.map((l) => ({ tool: l.tool, decision: l.decision }));

function hook(f) {
  const input = JSON.parse(readFileSync(0, "utf8"));
  const reply = (decision, reason) => process.stdout.write(JSON.stringify({ hookSpecificOutput: {
    hookEventName: "PreToolUse", permissionDecision: decision, permissionDecisionReason: reason } }));
  const tool = String(input.tool_name ?? "");
  try {
    const out = withLock(f.state + ".lock", () => {
      const st = JSON.parse(readFileSync(f.state, "utf8"));
      const entry = { id: input.tool_use_id ?? null, tool, at: Date.now() };
      if (tool === ANSWER_TOOL) {
        const g = fwcoreCall(REPO)({ op: "oracle.retrieveAnswer", forced: st.forced === true, log: gateLog(st.log) });
        st.log.push({ ...entry, decision: g.decision === "allow" ? "answer" : "deny", why: g.why ?? null, reads: g.reads });
        writeFileSync(f.state, JSON.stringify(st));
        return g.decision === "allow" ? ["allow", "the answer"] : ["deny", HELP[g.why] ?? String(g.why)];
      }
      const paths = JSON.parse(readFileSync(st.pathsFile, "utf8"));
      const c = callOf(st.root, tool, input.tool_input ?? {});
      const r = fwcoreCall(REPO)({ op: "oracle.retrieveHook", root: st.root, paths, state: { calls: st.calls, bytes: st.bytes },
        call: { tool: c.tool, path: c.path, glob: c.glob, bytes: c.bytes } });
      st.log.push({ ...entry, input: input.tool_input ?? {}, rel: r.path ?? null, bytes: c.bytes, span: c.span ?? null,
        decision: r.decision, why: r.why ?? null });
      if (r.decision === "allow") { st.calls = r.state.calls; st.bytes = r.state.bytes; }
      writeFileSync(f.state, JSON.stringify(st));
      return r.decision === "allow" ? ["allow", "in the tree"] : ["deny", HELP[r.why] ?? String(r.why)];
    });
    reply(...out);
  } catch (e) {
    reply("deny", `hook error: ${String(e.message ?? e).slice(0, 120)}`);
  }
}

function parseLines(text) {
  return text.split("\n").filter((l) => l.trim()).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
}

export function streamOf(events) {
  const uses = [], thinking = [];
  let result = null, init = null;
  for (const e of events) {
    if (e.type === "system" && e.subtype === "init") init = { tools: e.tools ?? [], model: e.model ?? null };
    if (e.type === "assistant") for (const b of e.message?.content ?? []) {
      if (b.type === "tool_use") uses.push({ id: b.id, name: b.name, input: b.input });
      if (b.type === "thinking" || b.type === "redacted_thinking") {
        thinking.push({ type: b.type, chars: (b.thinking ?? "").length, signatureBytes: (b.signature ?? b.data ?? "").length,
          text: b.thinking ?? "" });
      }
    }
    if (e.type === "result") result = e;
  }
  return { init, uses, thinking, result, structured: result?.structured_output ?? null };
}

export function spawnClaude(args, cwd, prompt, timeoutMs = 600_000) {
  const t0 = performance.now();
  return new Promise((done) => {
    const p = spawn("claude", args, { cwd, env: childEnv(process.env), detached: true, stdio: ["pipe", "pipe", "pipe"] });
    let out = "", err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    const timer = setTimeout(() => { try { process.kill(-p.pid, "SIGTERM"); } catch { } }, timeoutMs);
    p.on("close", (code, signal) => {
      clearTimeout(timer);
      done({ exit: code ?? -1, signal, ms: Math.round(performance.now() - t0), out, stderr: err.slice(0, 400) });
    });
    p.stdin.end(prompt);
  });
}

export function traceCalls(root, uses, log) {
  const by = new Map(log.filter((l) => l.id).map((l) => [l.id, l]));
  const out = [];
  let unhooked = 0, denied = 0;
  for (const u of uses) {
    if (u.name === ANSWER_TOOL) continue;
    const h = by.get(u.id);
    if (h?.decision === "deny") { denied++; continue; }
    if (!h) unhooked++;
    const c = callOf(root, u.name, u.input ?? {});
    out.push({ tool: c.tool, path: c.path, glob: c.glob, bytes: c.bytes });
  }
  return { calls: out, unhooked, denied };
}

export function readsOf(log) {
  return log.filter((l) => l.decision === "allow" && l.tool === "Read" && l.span && l.span.last >= l.span.first)
    .map((l) => ({ path: l.rel, lines: Array.from({ length: l.span.last - l.span.first + 1 }, (_, i) => l.span.first + i) }));
}

export function evidenceOf(structured) {
  return (structured?.evidence ?? []).flatMap((e) => {
    const m = /^(\d+)-(\d+)$/.exec(String(e.lines ?? ""));
    const path = String(e.path ?? "").replace(/^\.\//, "");
    return m ? [{ path, first: Number(m[1]), last: Number(m[2]) }] : [{ path, first: 0, last: 0 }];
  });
}

const relLog = (log) => log.map((l) => ({ tool: l.tool, decision: l.decision, why: l.why ?? null, path: l.rel ?? null,
  ...(l.tool === "Grep" || l.tool === "Glob" ? { glob: l.input?.glob ?? l.input?.pattern ?? null } : {}),
  ...(l.span ? { first: l.span.first, last: l.span.last } : {}), bytes: l.bytes ?? 0 }));

async function traceRow(core, a, p, attempt) {
  const root = realpathSync(join(a.work, "trees", p.id));
  const pathsFile = join(a.work, "trees", `${p.id}.paths.json`);
  const arm = armName(a.model, a.forced);
  const stDir = join(a.work, "state", arm);
  mkdirSync(stDir, { recursive: true });
  const statePath = join(stDir, `${p.id}.${attempt}.json`);
  writeFileSync(statePath, JSON.stringify({ root, pathsFile, forced: a.forced === true, calls: 0, bytes: 0, log: [] }));
  const options = optionsOf(p.prompt);
  const settings = hookSettings(statePath, a.thinking ? { showThinkingSummaries: true } : {});
  const run = await spawnClaude(traceArgs(a.model, traceSystem(a.forced), answerSchema(options), settings), root, p.prompt);
  const rawDir = join(a.work, "raw", arm);
  mkdirSync(rawDir, { recursive: true });
  writeFileSync(join(rawDir, `${p.id}.${attempt}.jsonl`), run.out);
  const s = streamOf(parseLines(run.out));
  const log = JSON.parse(readFileSync(statePath, "utf8")).log;
  const paths = JSON.parse(readFileSync(pathsFile, "utf8"));
  const t = traceCalls(root, s.uses, log);
  const verdict = core({ op: "oracle.retrieveTrace", root, paths, calls: t.calls });
  const ranges = core({ op: "oracle.retrieveRanges", reads: readsOf(log) }).ranges;
  const ev = core({ op: "oracle.retrieveEvidence", ranges, evidence: evidenceOf(s.structured) });
  const gate = core({ op: "oracle.retrieveAnswer", forced: a.forced === true, log: gateLog(log.filter((l) => l.tool !== ANSWER_TOOL)) });
  const env = s.result ? redactEnvelope(s.result) : null;
  const red = (x) => redactText(x, { work: root, home: process.env.HOME, user: process.env.USER });
  const st = s.structured;
  const answered = st && typeof st.choice === "string";
  return { id: p.id, attempt, exit: run.exit, signal: run.signal, wallMs: run.ms, subtype: env?.subtype ?? null,
    isError: env?.isError ?? null, numTurns: env?.numTurns ?? null, costUsd: env?.costUsd ?? null, usage: env?.usage ?? null,
    models: Object.keys(env?.models ?? {}), durationApiMs: env?.durationApiMs ?? null,
    trace: { verdict: verdict.verdict, calls: verdict.calls, bytes: verdict.bytes, denied: t.denied, unhooked: t.unhooked,
      hooked: log.length, reads: gate.reads, gate: gate.decision,
      answerDenied: log.filter((l) => l.tool === ANSWER_TOOL && l.decision === "deny").length },
    log: relLog(log), ranges, evidence: { valid: ev.valid, invalid: ev.invalid },
    thinking: s.thinking.map((b) => ({ type: b.type, chars: b.chars, signatureBytes: b.signatureBytes,
      ...(a.thinking && b.chars > 0 ? { text: red(b.text) } : {}) })),
    ...(answered ? { choice: st.choice, probabilities: st.probabilities } : {}),
    ...(run.exit !== 0 && !env ? { stderr: red(run.stderr) } : {}) };
}

async function pool(items, jobs, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(jobs, items.length) }, async () => {
    while (next < items.length) { const i = next++; await fn(items[i], i); }
  }));
}

export const answerLine = (r) => (r.choice !== undefined && r.trace.verdict === "ok" && (r.trace.gate ?? "allow") === "allow"
  ? { id: r.id, choice: r.choice, probabilities: r.probabilities } : null);

async function runArm(a) {
  const core = fwcoreCall(REPO);
  const ids = new Set(scopeRows(core).rows.map((r) => r.id));
  const prompts = readJsonl(a.prompts).filter((p) => ids.has(p.id) && (!a.only || a.only.split(",").includes(p.id)));
  const arm = armName(a.model, a.forced);
  const rowsFile = join(OUT, `${arm}.rows.jsonl`);
  mkdirSync(OUT, { recursive: true });
  const have = new Set(readJsonl(rowsFile).map((r) => r.id));
  const todo = prompts.filter((p) => !have.has(p.id));
  const t0 = performance.now();
  await pool(todo, Number(a.jobs ?? 4), async (p) => {
    let r;
    for (let attempt = 1; attempt <= 2; attempt++) {
      r = await traceRow(core, a, p, attempt);
      if (r.exit === 0 || r.subtype !== null) break;
    }
    appendFileSync(rowsFile, JSON.stringify(r) + "\n");
  });
  const rows = readJsonl(rowsFile);
  writeJsonl(join(OUT, `${arm}.answers.jsonl`), rows.map(answerLine).filter((l) => l !== null));
  const cost = rows.reduce((s, r) => s + (r.costUsd ?? 0), 0);
  appendFileSync(join(OUT, "runs.jsonl"), JSON.stringify({ arm, asked: todo.length,
    wallMs: Math.round(performance.now() - t0), costUsd: cost }) + "\n");
  const by = (k) => rows.filter((r) => r.trace.verdict === k).length;
  const reads = rows.reduce((x, r) => x + (r.trace.reads ?? 0), 0);
  console.log(`jev-trace run ${arm}: ${rows.length}/${prompts.length} rows, ${rows.filter((r) => answerLine(r)).length} answered ` +
    `in trace, ${reads} reads over ${rows.filter((r) => (r.trace.reads ?? 0) > 0).length} rows, ` +
    `verdicts ok ${by("ok")} outside ${by("outside")} overReads ${by("overReads")} overBytes ${by("overBytes")}, ` +
    `cost $${cost.toFixed(3)}`);
}

async function probe(a) {
  const core = fwcoreCall(REPO);
  const id = a.row ?? scopeRows(core).rows[0].id;
  const p = readJsonl(a.prompts).find((x) => x.id === id);
  const out = {};
  for (const model of ["haiku", "sonnet"]) {
    const r = await traceRow(core, { ...a, model, thinking: true }, p, 0);
    const raw = parseLines(readFileSync(join(a.work, "raw", armName(model, false), `${id}.0.jsonl`), "utf8"));
    const s = streamOf(raw);
    out[model] = { row: id, exit: r.exit, subtype: r.subtype, numTurns: r.numTurns, costUsd: r.costUsd,
      initTools: s.init?.tools ?? null, structured: s.structured !== null, answered: r.choice !== undefined,
      hookFired: r.trace.hooked > 0, answerToolHooked: r.log.some((l) => l.decision === "answer"),
      trace: r.trace, thinkingBlocks: r.thinking.length, thinkingWithText: r.thinking.filter((b) => b.chars > 0).length,
      thinkingChars: r.thinking.reduce((x, b) => x + b.chars, 0), evidence: r.evidence, log: r.log };
  }
  const exposed = Object.values(out).some((m) => m.thinkingWithText > 0);
  writeJson(join(OUT, "probe.json"), { settings: { showThinkingSummaries: true }, maxTurns: MAX_TURNS, budgetUsd: BUDGET_USD,
    thinkingExposed: exposed, models: out });
  console.log(`jev-trace probe: thinking text exposed: ${exposed ? "yes" : "no"}; ` + Object.entries(out).map(([m, v]) =>
    `${m}: exit ${v.exit} ${v.subtype} turns ${v.numTurns} hook ${v.hookFired} structured ${v.structured} trace ${v.trace.verdict} ` +
    `thinking ${v.thinkingWithText}/${v.thinkingBlocks} $${v.costUsd}`).join("; "));
}

const texts = (work, id, ps) => Object.fromEntries(ps.flatMap((p) => {
  const f = join(work, "trees", id, p);
  return existsSync(f) ? [[p, readFileSync(f, "utf8")]] : [];
}));

const rowFields = (r) => ({ title: r.title, symptom: r.symptom, cause: r.cause });

function d1Rows(dir) { return readJsonl(join(dir, "d1.jsonl")); }

function hybrid(a) {
  const core = fwcoreCall(REPO);
  const dir = a.dir ?? datasetsDir(REPO);
  const ids = new Set(scopeRows(core).rows.map((r) => r.id));
  const t = new Map(readJsonl(join(OUT, "t-sonnet.rows.jsonl")).map((r) => [r.id, r]));
  const rec = [];
  const rows = d1Rows(dir).filter((r) => ids.has(r.id)).map((r) => {
    const tr = t.get(r.id);
    const ranges = tr && tr.trace.verdict === "ok" ? tr.ranges : [];
    const h = core({ op: "oracle.retrieveHybrid", row: rowFields(r), ranges, texts: texts(a.work, r.id, ranges.map((x) => x.path)) });
    rec.push({ id: r.id, ranges: ranges.length, kept: h.kept, cut: h.cut, esc: h.esc });
    return { ...r, ...h.row };
  });
  writeJsonl(join(dir, "d1-hybrid.jsonl"), rows);
  writeJson(join(OUT, "hybrid.json"), { rows: rec });
  console.log(`jev-trace hybrid: ${rows.length} rows, ${rec.filter((x) => x.kept.length).length} with read ranges in state`);
}

function pick1(a) {
  const core = fwcoreCall(REPO);
  const dir = a.dir ?? datasetsDir(REPO);
  const tr = JSON.parse(readFileSync(join(OUT, "trees.json"), "utf8")).manifest;
  const named = new Map(tr.map((m) => [m.id, m.named.filter((x) => x.inTree).map((x) => x.path)]));
  const rec = [];
  const rows = d1Rows(dir).filter((r) => named.has(r.id)).flatMap((r) => {
    const p = core({ op: "oracle.retrievePick1", row: rowFields(r), paths: named.get(r.id) });
    rec.push({ id: r.id, candidates: p.candidates });
    return p.candidates.length ? [{ ...r, label: "none", ...p.row }] : [];
  });
  writeJsonl(join(dir, "d1-pick1.jsonl"), rows);
  writeJson(join(OUT, "pick1.json"), { rows: rec });
  console.log(`jev-trace pick1: ${rows.length} rows with candidates of ${rec.length}`);
}

function replyAnswer(reply, question) {
  try { return JSON.parse(reply).answers?.[question] ?? null; } catch { return null; }
}

function pick2(a) {
  const core = fwcoreCall(REPO);
  const dir = a.dir ?? datasetsDir(REPO);
  const names = redactNames(REPO);
  const k = pickedRows(core, "d1k", dir);
  if (typeof k === "string") throw new Error(k);
  const step1 = new Map(jevAnswers(core, k.question, names, k.rows, logPathFor(REPO)).map((x) => [x.id, x]));
  const cands = new Map(JSON.parse(readFileSync(join(OUT, "pick1.json"), "utf8")).rows.map((r) => [r.id, r.candidates]));
  const rec = [];
  const rows = d1Rows(dir).filter((r) => cands.has(r.id)).map((r) => {
    const cs = cands.get(r.id);
    const s1 = step1.get(r.id);
    const ans = s1?.reply ? replyAnswer(s1.reply, k.question) : null;
    if (cs.length && !ans) throw new Error(`no step-1 answer for ${r.id}: send d1k first`);
    const p = core({ op: "oracle.retrievePick", candidates: cs, probabilities: ans?.probabilities ?? {}, row: rowFields(r),
      texts: texts(a.work, r.id, cs) });
    rec.push({ id: r.id, candidates: cs, step1: ans ? { choice: ans.choice, probabilities: ans.probabilities } : null,
      pick: p.pick, sends: p.sends });
    return { ...r, ...p.row };
  });
  writeJsonl(join(dir, "d1-pick.jsonl"), rows);
  writeJson(join(OUT, "pick.json"), { rows: rec });
  console.log(`jev-trace pick2: ${rec.filter((x) => x.pick).length} picks, ${rec.filter((x) => x.candidates.length && !x.pick).length} none, ` +
    `${rec.filter((x) => !x.candidates.length).length} without candidates`);
}

export const pickPosRows = (rows) => rows.map((r) => ({ candidates: r.candidates, pick: r.pick ?? null }));

function position() {
  const core = fwcoreCall(REPO);
  const rows = JSON.parse(readFileSync(join(OUT, "pick.json"), "utf8")).rows;
  const r = core({ op: "oracle.retrievePickPos", rows: pickPosRows(rows) });
  writeJson(join(OUT, "position.json"), { source: "pick.json", op: "oracle.retrievePickPos", ...r });
  const q = (x) => `${x.num}/${x.den}`;
  console.log(`jev-trace position: ${r.multi} rows with 2+ candidates of ${r.rows} (${r.single} single, ${r.empty} empty); ` +
    r.slots.map((x) => `${x.slot} ${x.count} (${q(x.share)})`).join(", ") + `, none ${r.none.count}; uniform f1 share ${q(r.uniformFirst)}`);
}

function plan(a) {
  const core = fwcoreCall(REPO);
  const day = new Date().toISOString().slice(0, 10);
  const logged = readJsonl(logPathFor(REPO)).filter((e) => e.day === day).length;
  const items = JSON.parse(a.items);
  const r = core({ op: "oracle.retrievePlan", logged, items });
  console.log(JSON.stringify({ day, logged, ...r }));
}

export function armsOf(core, dir, rowIds) {
  const names = redactNames(REPO);
  const log = logPathFor(REPO);
  const only = (l) => l.filter((x) => rowIds.has(x.id));
  const pick = (set) => { const p = pickedRows(core, set, dir); if (typeof p === "string") throw new Error(p); return p; };
  const jev = (set) => { const p = pick(set); return only(jevAnswers(core, p.question, names, p.rows.filter((r) => rowIds.has(r.id)), log)); };
  const file = (f) => (existsSync(f) ? only(armAnswers(f)) : []);
  const xOf = (m) => { const x = new Map(file(join(ABLATION, `d1x-${m}.answers.jsonl`)).map((r) => [r.id, r]));
    return file(join(CLEAN, `d1-${m}.answers.jsonl`)).map((r) => x.get(r.id) ?? r); };
  return {
    question: pick("d1").question,
    replay: pick("d1").rows.filter((r) => rowIds.has(r.id)).map((r) => ({ id: r.id, label: r.label })),
    c: { jev: jev("d1"), haiku: file(join(CLEAN, "d1-haiku.answers.jsonl")), sonnet: file(join(CLEAN, "d1-sonnet.answers.jsonl")) },
    x: { jev: jev("d1x"), haiku: xOf("haiku"), sonnet: xOf("sonnet") },
    t: { "t-haiku": file(join(OUT, "t-haiku.answers.jsonl")), "t-sonnet": file(join(OUT, "t-sonnet.answers.jsonl")),
      "t-haiku-read": file(join(OUT, "t-haiku-read.answers.jsonl")), "t-sonnet-read": file(join(OUT, "t-sonnet-read.answers.jsonl")),
      "j-hybrid": existsSync(join(dir, "d1-hybrid.jsonl")) ? jev("d1h") : [],
      "j-pick": existsSync(join(dir, "d1-pick.jsonl")) ? jev("d1p") : [] },
  };
}

export const BASE_OF = { "t-haiku": "haiku", "t-sonnet": "sonnet", "t-haiku-read": "haiku", "t-sonnet-read": "sonnet",
  "j-hybrid": "jev", "j-pick": "jev" };

export const UNFORCED_OF = { "t-haiku-read": "t-haiku", "t-sonnet-read": "t-sonnet" };

function paired(a) {
  const core = fwcoreCall(REPO);
  const dir = a.dir ?? datasetsDir(REPO);
  const sc = scopeRows(core);
  const ids = new Set(sc.rows.map((r) => r.id));
  const arms = armsOf(core, dir, ids);
  const traced = existsSync(join(OUT, "traced.json")) ? JSON.parse(readFileSync(join(OUT, "traced.json"), "utf8")).rows : [];
  const out = { question: arms.question, rows: arms.replay.length, dropped: sc.dropped, answered: {}, arms: {}, vsT: {} };
  for (const [arm, ans] of Object.entries(arms.t)) {
    if (ans.length === 0) continue;
    const b = BASE_OF[arm];
    const vsC = pairedOf(core, arms.question, arms.replay, arms.c[b], ans);
    const vsX = pairedOf(core, arms.question, arms.replay, arms.x[b], ans);
    out.answered[arm] = { arm: ans.length, c: arms.c[b].length, x: arms.x[b].length };
    out.arms[arm] = Object.fromEntries(["strict", "renorm"].map((mode) => [mode, core({ op: "oracle.retrieveAdopt",
      arm: `${arm}/${mode}`, vsC: vsC[mode].pairs, vsX: vsX[mode].pairs, dropped: sc.dropped,
      traced: traced.filter((t) => t.arm === arm).map((t) => t.id) })]));
    const u = UNFORCED_OF[arm];
    if (u && arms.t[u].length) {
      const vsT = pairedOf(core, arms.question, arms.replay, arms.t[u], ans);
      out.vsT[arm] = Object.fromEntries(["strict", "renorm"].map((mode) => {
        const { pairs, ...flips } = vsT[mode];
        return [mode, { base: u, ...flips }];
      }));
    }
  }
  writeJson(join(OUT, "paired.json"), out);
  for (const [arm, m] of Object.entries(out.arms)) for (const mode of ["strict", "renorm"]) {
    const r = m[mode];
    const f = (x) => `${x.armRight}/${x.rows} vs ${x.baseRight}, +${x.gains.length} -${x.losses.length} net ${x.net}, p ${x.p.num}/${x.p.den}`;
    console.log(`${arm} ${mode}: vs C ${f(r.vsC)}; vs X ${f(r.vsX)}; adopt ${r.adopt} (${r.reasons.map((w) => w.kind).join(",") || "-"})` +
      (out.vsT[arm] ? `; vs ${out.vsT[arm][mode].base} ${f(out.vsT[arm][mode])}` : ""));
  }
}

function flags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i += 2) o[argv[i].replace(/^--/, "")] = argv[i + 1];
  return o;
}

if (process.argv[1] && resolve(process.argv[1]) === SELF) {
  const [sub, ...rest] = process.argv.slice(2);
  const f = flags(rest);
  const need = (...ks) => ks.every((k) => f[k] !== undefined);
  if (sub === "hook" && need("state")) hook(f);
  else if (sub === "trees" && need("work")) trees(f);
  else if (sub === "probe" && need("work", "prompts")) await probe(f);
  else if (sub === "run" && need("work", "prompts", "model") && BUDGET_USD[f.model]) {
    await runArm({ ...f, thinking: f.thinking === "yes", forced: f.forced === "yes" });
  }
  else if (sub === "hybrid" && need("work")) hybrid(f);
  else if (sub === "pick1" && need("work")) pick1(f);
  else if (sub === "pick2" && need("work")) pick2(f);
  else if (sub === "plan" && need("items")) plan(f);
  else if (sub === "position") position();
  else if (sub === "paired") paired(f);
  else {
    console.error("usage: jev-trace.mjs trees --work w | probe --work w --prompts p [--row id] | run --work w --prompts p " +
      "--model haiku|sonnet [--jobs n] [--only ids] [--thinking yes] [--forced yes] | hybrid --work w | pick1 --work w | pick2 --work w | " +
      "plan --items json | position | paired | hook --state s");
    process.exitCode = 64;
  }
}
