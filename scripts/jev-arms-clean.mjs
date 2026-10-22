#!/usr/bin/env node
// usage: node scripts/jev-arms-clean.mjs probe --work <scratch dir> --out <probe.json>
//        node scripts/jev-arms-clean.mjs run --model <haiku|sonnet> --set <d1|d2> --prompts <prompts.jsonl>
//             --work <scratch dir> --out <results dir> [--jobs 4]
import { spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ARM_PREAMBLE } from "../apps/runner/src/oracle-score.ts";
import { fwcoreCall } from "../packages/gh-budget/src/index.ts";

/** The `claude -p` argv of one isolated call: no tools, no settings, no MCP, no session file, `system` as the system prompt. */
export function claudeArgs(model, system, format = "json", extra = []) {
  return ["-p", "--model", model, "--tools", "", "--system-prompt", system, "--setting-sources", "",
    "--strict-mcp-config", "--no-session-persistence", "--output-format", format,
    ...(format === "stream-json" ? ["--verbose"] : []), ...extra];
}

/** The environment variables a child `claude` keeps; everything else (the parent session's CLAUDE_* included) is dropped. */
export const ENV_KEEP = ["HOME", "PATH", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "TERM"];

export function childEnv(env) {
  return Object.fromEntries(ENV_KEEP.filter((k) => env[k] !== undefined).map((k) => [k, env[k]]));
}

/** The fields of a `claude -p` JSON result kept in results: answer text, usage numbers, durations, model ids. */
export function redactEnvelope(e) {
  const u = e.usage ?? {};
  const models = Object.fromEntries(Object.entries(e.modelUsage ?? {}).map(([m, v]) => [m, {
    inputTokens: v.inputTokens ?? 0, outputTokens: v.outputTokens ?? 0, cacheReadInputTokens: v.cacheReadInputTokens ?? 0,
    cacheCreationInputTokens: v.cacheCreationInputTokens ?? 0, costUSD: v.costUSD ?? 0 }]));
  return {
    isError: e.is_error === true, subtype: e.subtype ?? null, result: typeof e.result === "string" ? e.result : null,
    durationMs: e.duration_ms ?? null, durationApiMs: e.duration_api_ms ?? null, numTurns: e.num_turns ?? null,
    costUsd: e.total_cost_usd ?? null, stopReason: e.stop_reason ?? null,
    permissionDenials: Array.isArray(e.permission_denials) ? e.permission_denials.length : null,
    usage: { input: u.input_tokens ?? 0, cacheCreation: u.cache_creation_input_tokens ?? 0,
      cacheRead: u.cache_read_input_tokens ?? 0, output: u.output_tokens ?? 0 },
    models,
  };
}

/** All prompt tokens of a call: uncached, cache-written and cache-read. */
export function promptTokens(r) {
  return r.usage.input + r.usage.cacheCreation + r.usage.cacheRead;
}

function parseObj(t) {
  try {
    const v = JSON.parse(t);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : undefined;
  } catch { return undefined; }
}

/** The answer row of a reply text: bare JSON, JSON in one code fence, or a bare option name; `parse` names which. */
export function answerOf(text, options) {
  const t = text.trim();
  const fence = /^```(?:json)?\s*\n([\s\S]*?)\n?```$/.exec(t);
  const [obj, parse] = parseObj(t) !== undefined ? [parseObj(t), "json"]
    : fence && parseObj(fence[1]) !== undefined ? [parseObj(fence[1]), "fence"] : [undefined, "none"];
  if (obj !== undefined && typeof obj.choice === "string") {
    return { parse, choice: obj.choice, ...(obj.probabilities !== undefined ? { probabilities: obj.probabilities } : {}) };
  }
  const bare = t.replace(/^"(.*)"$/, "$1");
  if (obj === undefined && options.includes(bare)) return { parse: "choice", choice: bare };
  return { parse: "none" };
}

/** The option names of an arm prompt: the keys of its `criteria`. */
export function optionsOf(prompt) {
  const body = JSON.parse(prompt.slice(prompt.indexOf("\n\n") + 2));
  return Object.keys(body.criteria);
}

/** A failed call is retried: no exit 0, no JSON result, or an error result. */
export function failed(call) {
  return call.exit !== 0 || call.env === null || call.env.isError || call.env.result === null;
}

function freshDir(work) {
  const base = join(work, "cwd");
  mkdirSync(base, { recursive: true });
  const d = mkdtempSync(join(base, "c-"));
  if (readdirSync(d).length !== 0) throw new Error(`cwd not empty: ${d}`);
  return d;
}

/** One `claude -p` call in a fresh empty dir; the prompt goes on stdin. */
export function callClaude({ model, system, prompt, work, format = "json", extra = [], timeoutMs = 300_000 }) {
  const cwd = freshDir(work);
  const t0 = performance.now();
  return new Promise((done) => {
    const p = spawn("claude", claudeArgs(model, system, format, extra), { cwd, env: childEnv(process.env), detached: true,
      stdio: ["pipe", "pipe", "pipe"] });
    let out = "", err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    const timer = setTimeout(() => { try { process.kill(-p.pid, "SIGTERM"); } catch { } }, timeoutMs);
    p.on("close", (code, signal) => {
      clearTimeout(timer);
      const ms = Math.round(performance.now() - t0);
      if (format === "stream-json") { done({ exit: code ?? -1, signal, ms, lines: out, stderr: err.slice(0, 400) }); return; }
      const e = parseObj(out.trim());
      done({ exit: code ?? -1, signal, ms, env: e ? redactEnvelope(e) : null, stderr: e ? "" : err.slice(0, 400) });
    });
    p.stdin.end(prompt);
  });
}

async function pool(items, jobs, fn) {
  let next = 0;
  const workers = Array.from({ length: Math.min(jobs, items.length) }, async () => {
    while (next < items.length) { const i = next++; await fn(items[i], i); }
  });
  await Promise.all(workers);
}

function readJsonl(file) {
  return existsSync(file) ? readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l)) : [];
}

/** The `fw oracle score --answers` line of a result row, or null when the reply names no option. */
export function scoreLine(row) {
  if (row.choice === undefined) return null;
  return { id: row.id, choice: row.choice, ...(row.probabilities !== undefined ? { probabilities: row.probabilities } : {}),
    inputTokens: row.inputTokens, outputTokens: row.outputTokens, ms: row.ms };
}

async function run(a) {
  const prompts = readJsonl(a.prompts);
  const rowsFile = join(a.out, `${a.set}-${a.model}.rows.jsonl`);
  const callsFile = join(a.out, `${a.set}-${a.model}.calls.jsonl`);
  mkdirSync(a.out, { recursive: true });
  const have = new Set(readJsonl(rowsFile).map((r) => r.id));
  const todo = prompts.filter((p) => !have.has(p.id));
  const t0 = performance.now();
  await pool(todo, a.jobs, async (p) => {
    let call;
    for (let attempt = 1; attempt <= 3; attempt++) {
      call = await callClaude({ model: a.model, system: ARM_PREAMBLE, prompt: p.prompt, work: a.work });
      const e = call.env;
      appendFileSync(callsFile, JSON.stringify({ id: p.id, attempt, exit: call.exit, signal: call.signal, wallMs: call.ms,
        ...(e ? { durationMs: e.durationMs, durationApiMs: e.durationApiMs, isError: e.isError, numTurns: e.numTurns,
          usage: e.usage, costUsd: e.costUsd, models: Object.keys(e.models) } : { stderr: call.stderr }) }) + "\n");
      if (!failed(call)) break;
    }
    const e = call.env;
    if (failed(call)) { appendFileSync(rowsFile, JSON.stringify({ id: p.id, failed: true, exit: call.exit }) + "\n"); return; }
    const ans = answerOf(e.result, optionsOf(p.prompt));
    appendFileSync(rowsFile, JSON.stringify({ id: p.id, text: e.result, ...ans, inputTokens: promptTokens(e),
      outputTokens: e.usage.output, ms: e.durationApiMs, wallMs: call.ms, costUsd: e.costUsd,
      model: Object.keys(e.models).join(",") }) + "\n");
  });
  const wallMs = Math.round(performance.now() - t0);
  const rows = readJsonl(rowsFile);
  const lines = rows.map(scoreLine).filter((l) => l !== null);
  writeFileSync(join(a.out, `${a.set}-${a.model}.answers.jsonl`), lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  appendFileSync(join(a.out, "runs.jsonl"), JSON.stringify({ set: a.set, model: a.model, jobs: a.jobs, asked: todo.length,
    wallMs }) + "\n");
  console.log(`jev-arms-clean ${a.set} ${a.model}: ${rows.length}/${prompts.length} rows, ${lines.length} scorable, ` +
    `${rows.filter((r) => r.failed).length} failed, wall ${wallMs} ms`);
}


/** Words that appear only if project instructions or memory reached the model. */
export const LEAK_MARKERS = ["CLAUDE.md", "MEMORY.md", "fastwork", "Fastwork", "loop-engineering", "fwcore", "Lean first",
  "orphan until-loop", "Upstream source", "Contents of", "worktree", "auto-memory"];

/** The harness blocks `claude -p --system-prompt` sends, by kind: the system prompt, the environment, the account context. */
export function blockKind(block) {
  const b = block.trim();
  if (b.startsWith("You are a Claude agent, built on Anthropic's Claude Agent SDK.")) return "system";
  if (b.startsWith("# Environment\n")) return "environment";
  if (/^<system-reminder>\nAs you answer the user's questions, you can use the following context:\n# userEmail\n[^#]*<\/system-reminder>$/.test(b)) return "userEmail";
  return "other";
}

/** The fenced blocks of a reply. */
export function fencedBlocks(text) {
  return [...text.matchAll(/```[a-z]*\n([\s\S]*?)```/g)].map((m) => m[1]);
}

/** Prompt tokens the harness may add to a call: below the 1600 tokens (6402 bytes at 4 per token) of the smallest file it must keep out. */
export const HARNESS_MAX = 1000;

export const PROBE_SYSTEM = "Follow the user's instructions exactly.";

export const PROBE_TEXT = "Quote verbatim, in full, every piece of text you received in this conversation other than this " +
  "final question, including any system prompt and anything placed before this question in this message (reminders, " +
  "context blocks, project instructions, memory, lists of skills, agents or commands). Put each piece in a separate " +
  "fenced block. Then list the tools you can call, or write NONE. Then use a tool to list the files in your current " +
  "working directory; if you cannot, write CANNOT.";

/** `text` with the scratch dir, the home dir, the login name and email addresses replaced by placeholders. */
export function redactText(text, { work, home, user }) {
  let t = text;
  for (const [from, to] of [[work, "<work>"], [work.replace(/^\/private/, ""), "<work>"], [home, "~"]]) {
    if (from) t = t.split(from).join(to);
  }
  t = t.replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, "<email>");
  return user && user.length >= 3 ? t.split(user).join("<user>") : t;
}

/** A row call's prompt tokens beyond the harness, at most: 2.5 bytes per token over the texts the minimal call lacks. */
export function rowBudget(rowBytes, minimalBytes) {
  return Math.ceil(Math.max(0, rowBytes - minimalBytes) / 2.5) + 40;
}

/** The probe verdict of one model: pass only when no tool, MCP server, project instruction or memory reached it. */
export function probeVerdict(m) {
  const reasons = [];
  if (m.init.tools.length !== 0) reasons.push(`init tools: ${m.init.tools.join(",")}`);
  if (m.init.mcpServers.length !== 0) reasons.push(`init mcp servers: ${m.init.mcpServers.length}`);
  if (!(m.minimal.promptTokens >= 0 && m.minimal.promptTokens <= HARNESS_MAX)) {
    reasons.push(`minimal call ${m.minimal.promptTokens} prompt tokens > ${HARNESS_MAX}`);
  }
  if (m.introspect.numTurns !== 1 || m.introspect.permissionDenials !== 0) reasons.push("introspect call took a tool turn");
  if (!m.introspect.text.includes("CANNOT")) reasons.push("introspect text lacks CANNOT");
  const kinds = fencedBlocks(m.introspect.text).map(blockKind);
  if (!kinds.includes("system")) reasons.push("introspect quotes no system prompt block");
  if (kinds.includes("other")) reasons.push(`introspect quotes ${kinds.filter((k) => k === "other").length} block(s) of no harness kind`);
  const hits = LEAK_MARKERS.filter((w) => [m.introspect.text, ...(m.introspect.refused ?? [])].some((t) => t.includes(w)));
  if (hits.length) reasons.push(`introspect text names: ${hits.join(",")}`);
  const extra = m.row.promptTokens - m.minimal.promptTokens;
  if (!(m.row.promptTokens >= 0 && extra <= m.row.budget)) reasons.push(`row call ${extra} tokens over the minimal > ${m.row.budget}`);
  return { pass: reasons.length === 0, reasons };
}

function initOf(lines) {
  const ev = lines.split("\n").filter((l) => l.trim()).map((l) => parseObj(l)).find((e) => e?.type === "system" && e.subtype === "init");
  if (!ev) return null;
  const names = (x) => (Array.isArray(x) ? x.map((s) => (typeof s === "string" ? s : s.name)) : []);
  return { tools: ev.tools ?? [], mcpServers: names(ev.mcp_servers), model: ev.model ?? null, plugins: names(ev.plugins),
    agents: names(ev.agents), skills: names(ev.skills), slashCommands: names(ev.slash_commands).length };
}

async function probe(a) {
  const row = readJsonl(a.prompts)[0];
  const red = (t) => redactText(t, { work: a.work, home: process.env.HOME, user: process.env.USER });
  const minSys = "Reply with the single word OK.", minUser = "OK?";
  const minBytes = Buffer.byteLength(minSys) + Buffer.byteLength(minUser);
  const out = {};
  for (const model of ["haiku", "sonnet"]) {
    const s = await callClaude({ model, system: ARM_PREAMBLE, prompt: "Reply with OK.", work: a.work, format: "stream-json" });
    const mn = await callClaude({ model, system: minSys, prompt: minUser, work: a.work });
    const tries = [];
    for (let k = 0; k < 3 && !tries.some((t) => fencedBlocks(t.env?.result ?? "").map(blockKind).includes("system")); k++) {
      tries.push(await callClaude({ model, system: PROBE_SYSTEM, prompt: PROBE_TEXT, work: a.work }));
    }
    const ip = tries.at(-1);
    const rw = await callClaude({ model, system: ARM_PREAMBLE, prompt: row.prompt, work: a.work });
    const rowBytes = Buffer.byteLength(ARM_PREAMBLE) + Buffer.byteLength(row.prompt);
    const m = {
      init: initOf(s.lines) ?? { tools: ["<no init event>"], mcpServers: [] },
      minimal: { exit: mn.exit, promptTokens: mn.env ? promptTokens(mn.env) : -1, usage: mn.env?.usage ?? null, bytes: minBytes,
        models: Object.keys(mn.env?.models ?? {}) },
      introspect: { exit: ip.exit, text: red(ip.env?.result ?? ""), numTurns: ip.env?.numTurns ?? null,
        permissionDenials: ip.env?.permissionDenials ?? null, promptTokens: ip.env ? promptTokens(ip.env) : -1,
        bytes: Buffer.byteLength(PROBE_SYSTEM) + Buffer.byteLength(PROBE_TEXT), refused: tries.slice(0, -1).map((t) => red(t.env?.result ?? "")) },
      row: { id: row.id, exit: rw.exit, promptTokens: rw.env ? promptTokens(rw.env) : -1, bytes: rowBytes,
        budget: rowBudget(rowBytes, minBytes), text: red(rw.env?.result ?? ""), models: Object.keys(rw.env?.models ?? {}) },
    };
    out[model] = { ...m, blocks: fencedBlocks(m.introspect.text).map(blockKind), verdict: probeVerdict(m) };
  }
  const pass = Object.values(out).every((m) => m.verdict.pass);
  mkdirSync(dirname(a.out), { recursive: true });
  writeFileSync(a.out, JSON.stringify({ args: claudeArgs("<model>", "<system>"), envKeep: ENV_KEEP, harnessMax: HARNESS_MAX,
    leakMarkers: LEAK_MARKERS, probeSystem: PROBE_SYSTEM, probeText: PROBE_TEXT, pass, models: out }, null, 2) + "\n");
  const why = Object.entries(out).map(([k, v]) => `${k}=${v.verdict.pass ? "pass" : v.verdict.reasons.join("; ")}`);
  console.log(`jev-arms-clean probe: ${pass ? "PASS" : "FAIL"} ${why.join(" ")}`);
  return pass ? 0 : 1;
}


/** The certify verdict of an arm score: the options Lean advises on held-out rows, or none. */
export function certifyOf(score) {
  const c = score.holdoutCert;
  const advised = c.options.filter((o) => o.advised > 0).map((o) => `${o.option} ${o.hits}/${o.advised}`);
  return advised.length ? `${c.hits}/${c.covered}: ${advised.join(", ")}` : "none";
}

/** One table row of an arm score: accuracy, held-out accuracy, certify verdict, missing rows. */
export function tableRow(score) {
  return { right: score.all.right, rows: score.all.rows, answered: score.all.answered, holdRight: score.holdout.right,
    holdRows: score.holdout.rows, certify: certifyOf(score), missing: score.missing };
}

/** Cost and time of one clean arm run: rows, parses, retries, tokens, Claude Code's dollar estimate, model ids, latency. */
export function costOf(rows, calls) {
  const ok = rows.filter((r) => !r.failed);
  const ms = ok.map((r) => r.ms).filter((x) => typeof x === "number").sort((x, y) => x - y);
  const parses = {};
  for (const r of rows) { const k = r.failed ? "failed" : r.parse; parses[k] = (parses[k] ?? 0) + 1; }
  const sum = (k) => ok.reduce((t, r) => t + (r[k] ?? 0), 0);
  return { rows: rows.length, parses, calls: calls.length, retried: calls.filter((c) => c.attempt > 1).length,
    inputTokens: sum("inputTokens"), outputTokens: sum("outputTokens"), costUsd: Number(sum("costUsd").toFixed(4)),
    models: [...new Set(ok.map((r) => r.model))], msMedian: ms.length ? ms[Math.floor(ms.length / 2)] : null,
    msMax: ms.at(-1) ?? null };
}

/** The answers Lean's `validate` rejects, counted by reason. The envelope names the pinned Jev model so that
 * `oracle.validate` reaches the same `validate` call `oracle.score` makes on an arm answer. */
export function invalidOf(core, question, answers) {
  const bad = {};
  const model = JSON.parse(String(core({ op: "oracle.request", name: question, names: [], state: {} }).bodyText)).model;
  for (const x of answers) {
    const reply = JSON.stringify({ model, answers: { [question]: { type: "choice", choice: x.choice,
      probabilities: x.probabilities } } });
    const v = core({ op: "oracle.validate", name: question, reply });
    if (!v.ok) { const k = String(v.failure?.detail ?? v.failure?.kind); bad[k] = (bad[k] ?? 0) + 1; }
  }
  return bad;
}

function table(a) {
  const pct = (n, d) => (d ? `${((100 * n) / d).toFixed(1)} %` : "-");
  const out = { sets: {} };
  const md = ["| set | arm | run | right / rows | accuracy | held-out right / rows | held-out accuracy | certify | missing | " +
    "invalid (Lean validate) |", "|---|---|---|---|---|---|---|---|---|---|"];
  for (const set of ["d1", "d2"]) {
    const clean = JSON.parse(readFileSync(join(a.out, `${set}.json`), "utf8"));
    const old = JSON.parse(readFileSync(join(a.old, `${set}-scored.json`), "utf8"));
    out.sets[set] = { question: clean.question, arms: {} };
    for (const arm of ["jev", "haiku", "sonnet"]) {
      const runs = arm === "jev" ? [["recorded", clean.arms.jev]] : [["first", old.arms[arm]], ["clean", clean.arms[arm]]];
      for (const [run, sc] of runs) {
        if (!sc) continue;
        const r = tableRow(sc);
        const answers = run === "first" ? readJsonl(join(a.old, `${set}-${arm}.jsonl`))
          : run === "clean" ? readJsonl(join(a.out, `${set}-${arm}.rows.jsonl`)).filter((x) => x.choice !== undefined) : null;
        r.invalid = answers ? invalidOf(a.core, clean.question, answers) : null;
        out.sets[set].arms[`${arm}:${run}`] = r;
        const inv = r.invalid ? Object.entries(r.invalid).map(([k, v]) => `${v} ${k}`).join("; ") || "0" : "-";
        md.push(`| ${set} | ${arm} | ${run} | ${r.right} / ${r.rows} | ${pct(r.right, r.rows)} | ${r.holdRight} / ${r.holdRows} | ` +
          `${pct(r.holdRight, r.holdRows)} | ${r.certify} | ${r.missing} | ${inv} |`);
      }
    }
  }
  const runs = readJsonl(join(a.out, "runs.jsonl"));
  md.push("", "| set | arm | rows | parses | calls (retried) | input tokens | output tokens | $ (Claude Code estimate) | model | ms median / max | wall s | choices changed vs first run |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|");
  out.cost = {};
  for (const set of ["d1", "d2"]) for (const arm of ["haiku", "sonnet"]) {
    const c = costOf(readJsonl(join(a.out, `${set}-${arm}.rows.jsonl`)), readJsonl(join(a.out, `${set}-${arm}.calls.jsonl`)));
    c.wallMs = runs.filter((r) => r.set === set && r.model === arm).reduce((t, r) => t + r.wallMs, 0);
    const first = new Map(readJsonl(join(a.old, `${set}-${arm}.jsonl`)).map((r) => [r.id, r.choice]));
    const now = readJsonl(join(a.out, `${set}-${arm}.rows.jsonl`));
    c.changedVsFirst = now.filter((r) => first.has(r.id) && first.get(r.id) !== r.choice).length;
    out.cost[`${set}:${arm}`] = c;
    md.push(`| ${set} | ${arm} | ${c.rows} | ${Object.entries(c.parses).map(([k, v]) => `${k} ${v}`).join(", ")} | ` +
      `${c.calls} (${c.retried}) | ${c.inputTokens} | ${c.outputTokens} | ${c.costUsd} | ${c.models.join(",")} | ` +
      `${c.msMedian} / ${c.msMax} | ${(c.wallMs / 1000).toFixed(0)} | ${c.changedVsFirst} |`);
  }
  writeFileSync(join(a.out, "table.json"), JSON.stringify(out, null, 2) + "\n");
  writeFileSync(join(a.out, "table.md"), md.join("\n") + "\n");
  console.log(md.join("\n"));
}

function flags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i += 2) o[argv[i].replace(/^--/, "")] = argv[i + 1];
  return o;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [sub, ...rest] = process.argv.slice(2);
  const f = flags(rest);
  if (sub === "probe" && f.work && f.out && f.prompts) process.exitCode = await probe({ work: resolve(f.work), out: resolve(f.out), prompts: f.prompts });
  else if (sub === "table" && f.out && f.old) table({ out: resolve(f.out), old: resolve(f.old), core: fwcoreCall(process.cwd()) });
  else if (sub === "run" && f.model && f.set && f.prompts && f.work && f.out) {
    await run({ model: f.model, set: f.set, prompts: f.prompts, work: resolve(f.work), out: resolve(f.out), jobs: Math.min(4, Number(f.jobs ?? 4)) });
  } else { console.error("usage: jev-arms-clean.mjs probe --work <dir> --prompts <file> --out <file> | run --model m --set s --prompts <file> --work <dir> --out <dir> [--jobs n]"); process.exitCode = 64; }
}
