#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.floor((s.length - 1) / 2)] : 0; };
const sum = (xs) => xs.reduce((a, b) => a + b, 0);
const bytes = (s) => Buffer.byteLength(s ?? "");

export function normPath(p, { home, cwd }) {
  const i = p.indexOf("/scratchpad/");
  if (i >= 0) return "<scratchpad>/" + p.slice(i + "/scratchpad/".length);
  if (cwd && p.startsWith(cwd + "/")) return "<repo>/" + p.slice(cwd.length + 1);
  if (home && p.startsWith(home)) return "<home>";
  return "<other>";
}

export function pathClass(n) {
  return n.startsWith("<scratchpad>/") ? "scratchpad" : n.startsWith("<repo>/") ? "repo" : n === "<home>" ? "home" : "other";
}

export function resultText(block) {
  return typeof block.content === "string" ? block.content
    : Array.isArray(block.content) ? block.content.map((x) => x.text ?? "").join("") : "";
}

export function linesSeen(text) {
  return text.split("\n").map((s) => (s.match(/^\s*(\d+)[\t→]/) ?? [])[1]).filter(Boolean).map(Number);
}

export function agentTrace(events, { home, description }) {
  const cwd = events.find((e) => typeof e.cwd === "string")?.cwd;
  const t0 = Date.parse(events.find((e) => e.timestamp)?.timestamp ?? 0);
  const calls = [];
  const byId = new Map();
  const requests = new Map();
  const models = new Set(); const effort = new Set(); const display = new Set();
  const thinking = { blocks: 0, withText: 0, textChars: 0, signatureBytes: 0 };
  let visible = 0; let answer = null; let notices = 0; let totalLines = null; const attachments = {};
  for (const e of events) {
    if (e.type === "attachment" && e.attachment?.type) attachments[e.attachment.type] = (attachments[e.attachment.type] ?? 0) + 1;
    if (e.type === "attachment" && e.attachment?.type === "read_truncation_notice") {
      notices++;
      const m = String(e.attachment.banner ?? "").match(/of (\d+) total/);
      if (m) totalLines = Number(m[1]);
    }
    if (e.type === "assistant") {
      const m = e.message ?? {};
      if (m.model) models.add(m.model);
      if (e.effort) effort.add(e.effort);
      if (e.thinkingDisplay) display.add(e.thinkingDisplay);
      if (e.requestId && m.usage) requests.set(e.requestId, m.usage);
      for (const b of m.content ?? []) {
        if (b.type === "thinking" || b.type === "redacted_thinking") {
          thinking.blocks++;
          const t = b.thinking ?? "";
          if (t.length > 0) thinking.withText++;
          thinking.textChars += t.length;
          thinking.signatureBytes += bytes(b.signature ?? b.data ?? "");
          visible += bytes(t);
        }
        if (b.type === "text") visible += bytes(b.text);
        if (b.type !== "tool_use") continue;
        visible += bytes(JSON.stringify(b.input ?? {}));
        const c = { seq: calls.length + 1, tool: b.name, ms: Date.parse(e.timestamp) - t0 };
        if (b.name === "StructuredOutput") {
          const a = Array.isArray(b.input?.answers) ? b.input.answers : [];
          c.rows = a.length;
          c.keys = [...new Set(a.flatMap((x) => Object.keys(x ?? {})))].sort();
          answer ??= c.seq;
        }
        const p = b.input?.file_path ?? b.input?.path;
        if (typeof p === "string") { c.path = normPath(p, { home, cwd }); c.class = pathClass(c.path); }
        if (b.input?.offset !== undefined) c.offset = b.input.offset;
        if (b.input?.limit !== undefined) c.limit = b.input.limit;
        if (b.name === "Bash") { c.program = String(b.input?.command ?? "").trim().split(/\s+/)[0]; c.commandBytes = bytes(b.input?.command); }
        calls.push(c); byId.set(b.id, c);
      }
    }
    if (e.type === "user" && Array.isArray(e.message?.content)) {
      for (const b of e.message.content) {
        if (b.type !== "tool_result" || !byId.has(b.tool_use_id)) continue;
        const c = byId.get(b.tool_use_id); const t = resultText(b);
        c.resultBytes = bytes(t);
        if (c.tool === "Read") c.lines = linesSeen(t);
        if (b.is_error) c.error = true;
      }
    }
  }
  for (const c of calls) c.beforeAnswer = answer === null || c.seq < answer;
  const usage = [...requests.values()];
  const seen = new Set(calls.flatMap((c) => c.lines ?? []));
  const [arm, rest] = String(description ?? "").split(":");
  const m = String(rest ?? "").match(/^(d\d)-chunk-(\d+)$/);
  return {
    arm, set: m?.[1] ?? null, chunk: m ? Number(m[2]) : null, models: [...models], effort: [...effort], thinkingDisplay: [...display],
    requests: requests.size,
    usage: { input: sum(usage.map((u) => u.input_tokens ?? 0)), cacheRead: sum(usage.map((u) => u.cache_read_input_tokens ?? 0)),
      cacheCreation: sum(usage.map((u) => u.cache_creation_input_tokens ?? 0)), output: sum(usage.map((u) => u.output_tokens ?? 0)) },
    visibleOutputBytes: visible, thinking, truncationNotices: notices, fileLines: totalLines, attachments,
    linesCovered: seen.size, answerSeq: answer, answerMs: answer ? calls[answer - 1].ms : null,
    calls: calls.map(({ lines, ...c }) => ({ ...c, ...(lines ? { lineRange: lines.length ? [Math.min(...lines), Math.max(...lines)] : null } : {}) })),
  };
}

export function armTable(agents) {
  const groups = new Map();
  for (const a of agents) { const k = `${a.arm} ${a.set}`; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(a); }
  return [...groups.entries()].sort().map(([k, as]) => {
    const calls = as.flatMap((a) => a.calls);
    const reads = calls.filter((c) => c.tool === "Read");
    const cls = (x) => reads.filter((c) => c.class === x).length;
    const answers = calls.filter((c) => c.tool === "StructuredOutput");
    return {
      arm: k.split(" ")[0], set: k.split(" ")[1], agents: as.length, rows: sum(answers.map((c) => c.rows ?? 0)),
      reads: reads.length, readsPerAgent: [Math.min(...as.map((a) => a.calls.filter((c) => c.tool === "Read").length)), Math.max(...as.map((a) => a.calls.filter((c) => c.tool === "Read").length))],
      distinctFiles: new Set(reads.map((c) => c.path)).size, scratchpad: cls("scratchpad"), repo: cls("repo"), home: cls("home"), other: cls("other"),
      readBytes: sum(reads.map((c) => c.resultBytes ?? 0)), truncationNotices: sum(as.map((a) => a.truncationNotices)),
      fullCoverage: as.filter((a) => a.fileLines !== null ? a.linesCovered >= a.fileLines - 1 : true).length,
      bash: calls.filter((c) => c.tool === "Bash").length, other_tools: calls.filter((c) => !["Read", "Bash", "StructuredOutput"].includes(c.tool)).length,
      callsAfterAnswer: calls.filter((c) => !c.beforeAnswer && c.tool !== "StructuredOutput").length,
      answerKeys: [...new Set(answers.flatMap((c) => c.keys ?? []))].sort(),
      thinkingBlocks: sum(as.map((a) => a.thinking.blocks)), thinkingWithText: sum(as.map((a) => a.thinking.withText)),
      attachmentTypes: [...new Set(as.flatMap((a) => Object.keys(a.attachments)))].sort(),
      thinkingTextChars: sum(as.map((a) => a.thinking.textChars)), signatureBytes: sum(as.map((a) => a.thinking.signatureBytes)),
      outputTokens: sum(as.map((a) => a.usage.output)), visibleOutputBytes: sum(as.map((a) => a.visibleOutputBytes)),
      medianAnswerMs: median(as.map((a) => a.answerMs ?? 0)),
      models: [...new Set(as.flatMap((a) => a.models))], effort: [...new Set(as.flatMap((a) => a.effort))], thinkingDisplay: [...new Set(as.flatMap((a) => a.thinkingDisplay))],
    };
  });
}

export const FILE_RE = /(?:^|[^A-Za-z0-9_./-])((?:[A-Za-z0-9_.@-]+\/)+[A-Za-z0-9_.@-]+\.[A-Za-z0-9]{1,6})(?![A-Za-z0-9])/g;

export function proseBytes(text) {
  const t = String(text ?? "").trim();
  const fenced = t.match(/^```[a-z]*\n([\s\S]*?)\n```$/);
  const body = fenced ? fenced[1] : t;
  const i = body.indexOf("{"); const j = body.lastIndexOf("}");
  if (i < 0 || j < i) return bytes(body);
  return bytes(body.slice(0, i).trim()) + bytes(body.slice(j + 1).trim());
}

export function cleanTable(dir) {
  const out = [];
  for (const f of fs.readdirSync(dir).filter((x) => /^d\d-(haiku|sonnet)\.rows\.jsonl$/.test(x)).sort()) {
    const [set, arm] = f.split(".")[0].split("-");
    const rows = fs.readFileSync(path.join(dir, f), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
    const callLines = fs.readFileSync(path.join(dir, `${set}-${arm}.calls.jsonl`), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
    const call = new Map(); for (const c of callLines) if (c.exit === 0) call.set(c.id, c);
    const answered = rows.filter((r) => typeof r.text === "string");
    const outTok = answered.map((r) => call.get(r.id)?.usage?.output ?? 0);
    const textB = answered.map((r) => bytes(r.text));
    out.push({
      arm, set, rows: rows.length, replies: answered.length,
      parse: Object.fromEntries([...new Set(answered.map((r) => r.parse ?? "none"))].map((k) => [k, answered.filter((r) => (r.parse ?? "none") === k).length])),
      withProse: answered.filter((r) => proseBytes(r.text) > 0).length,
      namingFile: answered.filter((r) => [...r.text.matchAll(FILE_RE)].length > 0).length,
      numTurns: [...new Set(answered.map((r) => call.get(r.id)?.numTurns ?? null))],
      medianReplyBytes: median(textB), medianOutputTokens: median(outTok),
      replyBytes: sum(textB), outputTokens: sum(outTok),
    });
  }
  return out;
}

function md(first, clean) {
  const L = [];
  L.push("# What the Claude arms read and recorded (generated by scripts/jev-trace-forensics.mjs)", "");
  L.push("## First run: workflow agents with tools (one agent per arm, set and chunk)", "");
  L.push("| arm | set | agents | rows answered | Read calls | per agent | distinct files | scratchpad / repo / home / other | bytes read | truncation notices | agents seeing every line | Bash | other tools | calls after answer | answer keys |");
  L.push("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
  for (const r of first) L.push(`| ${r.arm} | ${r.set} | ${r.agents} | ${r.rows} | ${r.reads} | ${r.readsPerAgent.join("-")} | ${r.distinctFiles} | ${r.scratchpad} / ${r.repo} / ${r.home} / ${r.other} | ${r.readBytes} | ${r.truncationNotices} | ${r.fullCoverage} | ${r.bash} | ${r.other_tools} | ${r.callsAfterAnswer} | ${r.answerKeys.join(", ")} |`);
  L.push("", "| arm | set | model | effort | thinking display | thinking blocks | blocks with text | thinking chars | signature bytes | output tokens | visible output bytes | median ms to answer |");
  L.push("|---|---|---|---|---|---|---|---|---|---|---|---|");
  for (const r of first) L.push(`| ${r.arm} | ${r.set} | ${r.models.join(", ")} | ${r.effort.join(", ")} | ${r.thinkingDisplay.join(", ") || "-"} | ${r.thinkingBlocks} | ${r.thinkingWithText} | ${r.thinkingTextChars} | ${r.signatureBytes} | ${r.outputTokens} | ${r.visibleOutputBytes} | ${r.medianAnswerMs} |`);
  L.push("", "Context injected without a tool call (attachment types seen across the 42 logs): "
    + [...new Set(first.flatMap((r) => r.attachmentTypes))].sort().join(", ") + ".");
  L.push("", "## Clean run: one `claude -p` call per row, no tools (results/jev-arms-clean)", "");
  L.push("| arm | set | rows | replies | parse kinds | replies with prose outside the JSON | replies naming a file | turns per call | median reply bytes | median output tokens | reply bytes | output tokens |");
  L.push("|---|---|---|---|---|---|---|---|---|---|---|---|");
  for (const r of clean) L.push(`| ${r.arm} | ${r.set} | ${r.rows} | ${r.replies} | ${Object.entries(r.parse).map(([k, v]) => `${k} ${v}`).join(", ")} | ${r.withProse} | ${r.namingFile} | ${r.numTurns.join(", ")} | ${r.medianReplyBytes} | ${r.medianOutputTokens} | ${r.replyBytes} | ${r.outputTokens} |`);
  return L.join("\n") + "\n";
}

function main(argv) {
  const args = Object.fromEntries(argv.reduce((acc, a, i, xs) => a.startsWith("--") ? [...acc, [a.slice(2), xs[i + 1]]] : acc, []));
  if (!args.dir || !args.out) { console.error("usage: jev-trace-forensics.mjs --dir <workflow dir> [--clean <dir>] --out <dir>"); process.exit(2); }
  const home = process.env.HOME ?? "";
  const files = fs.readdirSync(args.dir).filter((f) => /^agent-.*\.jsonl$/.test(f)).sort();
  const agents = [];
  for (const f of files) {
    const meta = JSON.parse(fs.readFileSync(path.join(args.dir, f.replace(/\.jsonl$/, ".meta.json")), "utf8"));
    const events = fs.readFileSync(path.join(args.dir, f), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
    agents.push(agentTrace(events, { home, description: meta.description }));
  }
  agents.sort((a, b) => `${a.arm}${a.set}${String(a.chunk).padStart(3, "0")}`.localeCompare(`${b.arm}${b.set}${String(b.chunk).padStart(3, "0")}`));
  const first = armTable(agents);
  const clean = args.clean ? cleanTable(args.clean) : [];
  const outs = {
    "first-run-agents.json": JSON.stringify(agents, null, 1) + "\n",
    "summary.json": JSON.stringify({ agentLogs: files.length, firstRun: first, clean }, null, 1) + "\n",
    "tables.md": md(first, clean),
  };
  const sid = path.basename(path.dirname(path.dirname(path.dirname(args.dir))));
  for (const [name, text] of Object.entries(outs)) {
    if ((home && text.includes(home)) || (sid.length > 30 && text.includes(sid)) || /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}/.test(text.replace(/claude-[a-z]+-\d-\d/g, ""))) {
      console.error(`refusing to write ${name}: it holds a home path, the session id or an email`); process.exit(1);
    }
  }
  fs.mkdirSync(args.out, { recursive: true });
  for (const [name, text] of Object.entries(outs)) fs.writeFileSync(path.join(args.out, name), text);
  console.log(`${files.length} agent logs; wrote ${Object.keys(outs).join(", ")}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main(process.argv.slice(2));
