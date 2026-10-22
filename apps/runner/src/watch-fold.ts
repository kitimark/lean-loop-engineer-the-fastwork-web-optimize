// The transcript summaries of `fw watch` as one fold over the lines of the file: state, step, finish.
// Spec and proof: lean/Fw/Obs/Fold.lean (`feed_append`, `pass_eq_full`: reading the appended lines on top of the state
// of the earlier lines equals reading the whole file; `Fw.Obs.Fold.decide`: when the saved state may be resumed).
// The step bodies below (JSON -> fields) are TS glue and are NOT checked against Lean: they are the same code that
// `summarizeTranscript` and `signalsOf` ran before, folded. Their incremental = full property is tested by split points.
// Privacy: only names, counts, ids and times are kept. Bash command text is kept only when `aux` (the in-memory
// `signalsOf` for `fw next`); the state that is written to disk never holds it.
import type { SigEnd, SigFacts, TaskNote, TranscriptInfo, TranscriptSignals } from "./watch-collect.ts";

const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

export const BG_TEXT = /(?:running in background with ID:|moved to the background \(ID:)\s*([A-Za-z0-9]+)/;
export const OUT_TEXT = /Output is being written to:\s*(\S+?\.output)\b/;
/** Every `<task-notification>` block in a text. */
export function parseNotifications(text: string): TaskNote[] {
  const out: TaskNote[] = [];
  for (const m of text.matchAll(/<task-notification>([^]*?)<\/task-notification>/g)) {
    const tag = (k: string) => new RegExp(`<${k}>([^]*?)</${k}>`).exec(m[1]!)?.[1]?.trim() ?? null;
    const id = tag("task-id");
    if (id) out.push({ id, status: tag("status") ?? "", summary: tag("summary") ?? "", outputFile: tag("output-file") });
  }
  return out;
}
/** A notification that only says the agent stopped with its own background work still running: not an end. */
export const waitingNote = (n: TaskNote) => /waiting on its own background work/.test(n.summary);
const noteEnd = (n: TaskNote, time: number): SigEnd => ({ id: n.id, time, how: n.status === "killed" ? "killed" : "notified" });
export const textOf = (c: unknown): string =>
  typeof c === "string" ? c : Array.isArray(c) ? c.map((x: any) => (typeof x === "string" ? x : typeof x?.text === "string" ? x.text : textOf(x?.content))).join("\n") : "";

/** Bump when the shape or meaning of `FoldState` changes (the code hash of the cache covers the rest). */
export const FOLD_SCHEMA = 2;

type Usage = [number, number, number, number]; // input, output, cache read, cache write
/** What `summarizeTranscript` reads: everything except the meta file, which `finishInfo` adds. */
interface SumState {
  model: string | null; firstAt: number | null; lastAt: number | null; toolUses: number; toolErrors: number;
  lastTool: string | null; lastToolAt: number | null; agentCalls: string[]; bgTasks: string[];
  usage: Map<string, Usage>; n: number; ctx: number | null; endedTurn: boolean; structDone: boolean;
  open: Map<string, { tool: string; at: number; msg: string }>; newest: string | null; anon: number;
}
/** What `signalsOf` reads. `commands` and `outputs` are only filled when `aux`. */
interface SigState {
  launched: { id: string; time: number }[]; ends: SigEnd[]; bounds: { time: number; start: boolean }[]; handbacks: number[];
  commands: Map<string, string>; outputs: Map<string, string>; uses: Map<string, { name: string; command: string | null }>;
  open: Map<string, string>; newest: string | null; lastAt: number | null;
  launchedIds: Set<string>; endedIds: Set<string>; // rebuilt from `launched` and `ends` on load
}
export interface FoldState { aux: boolean; sum: SumState; sig: SigState }

export function initFold(aux = false): FoldState {
  return {
    aux,
    sum: { model: null, firstAt: null, lastAt: null, toolUses: 0, toolErrors: 0, lastTool: null, lastToolAt: null, agentCalls: [], bgTasks: [],
      usage: new Map(), n: 0, ctx: null, endedTurn: false, structDone: false, open: new Map(), newest: null, anon: 0 },
    sig: { launched: [], ends: [], bounds: [], handbacks: [], commands: new Map(), outputs: new Map(), uses: new Map(), open: new Map(), newest: null,
      lastAt: null, launchedIds: new Set(), endedIds: new Set() },
  };
}

function newestMessage<V>(open: Map<string, V>, msg: string, of: (v: V) => string): void {
  for (const [id, v] of open) if (of(v) !== msg) open.delete(id);
}

/** One non-empty line. A line that is not JSON changes nothing. */
export function stepLine(st: FoldState, line: string): void {
  let o: any;
  try { o = JSON.parse(line); } catch { return; }
  if (o === null) return; // `null.timestamp` threw in the unfolded loops (the file then counted as unreadable)
  const msg = o.type === "assistant" && o.message ? str(o.message.id) ?? `#anon${st.sum.anon++}` : null;
  stepSum(st.sum, o, msg);
  stepSig(st, o, msg);
}

function stepSum(s: SumState, o: any, msg: string | null): void {
  const at = typeof o.timestamp === "string" ? Date.parse(o.timestamp) : NaN;
  if (Number.isFinite(at)) { s.firstAt ??= at; s.lastAt = Math.max(s.lastAt ?? 0, at); }
  const m = o.message;
  const bg = str(o.toolUseResult?.backgroundTaskId);
  if (bg) s.bgTasks.push(bg);
  if (o.type === "assistant" && m) {
    if (typeof m.model === "string" && m.model !== "<synthetic>") s.model = m.model;
    if (m.usage && typeof m.usage === "object") {
      const u = m.usage as Record<string, unknown>;
      s.usage.set(typeof m.id === "string" ? m.id : `#${s.n++}`, [num(u.input_tokens), num(u.output_tokens), num(u.cache_read_input_tokens), num(u.cache_creation_input_tokens)]); // streamed copies share the id
      s.ctx = num(u.input_tokens) + num(u.cache_read_input_tokens) + num(u.cache_creation_input_tokens);
    }
  }
  if ((o.type === "assistant" || o.type === "user") && Array.isArray(m?.content)) {
    let hasUse = false;
    if (msg !== null) { s.newest = msg; newestMessage(s.open, msg, (v) => v.msg); }
    for (const c of m.content) {
      if (c?.type === "tool_use" && typeof c.id === "string") {
        hasUse = true; s.toolUses++;
        const tool = String(c.name ?? "?"), t = Number.isFinite(at) ? at : 0;
        s.open.set(c.id, { tool, at: t, msg: s.newest ?? "" });
        if (s.lastToolAt === null || t >= s.lastToolAt) { s.lastTool = tool; s.lastToolAt = t; }
        if (o.type === "assistant" && (tool === "Agent" || tool === "Task")) s.agentCalls.push(c.id); // a child's meta.toolUseId
      }
      else if (c?.type === "tool_result" && typeof c.tool_use_id === "string") {
        const tool = s.open.get(c.tool_use_id)?.tool;
        if (tool === "StructuredOutput") s.structDone = true;
        // a workflow agent's Bash result names its background id only in the text
        const tb = !bg && tool === "Bash" ? BG_TEXT.exec(textOf(c.content))?.[1] : undefined;
        if (tb && !s.bgTasks.includes(tb)) s.bgTasks.push(tb);
        s.open.delete(c.tool_use_id); if (c.is_error === true) s.toolErrors++;
      }
    }
    s.endedTurn = o.type === "assistant" && !hasUse && m.content.some((c: any) => c?.type === "text");
  }
}

function stepSig(st: FoldState, o: any, msg: string | null): void {
  const s = st.sig;
  const t0 = typeof o.timestamp === "string" ? Date.parse(o.timestamp) : NaN;
  if (!Number.isFinite(t0)) return;
  const at = Math.floor(t0);
  const launch = (id: string, time: number, command: string | null) => {
    if (s.launchedIds.has(id)) return;
    s.launchedIds.add(id); s.launched.push({ id, time });
    if (command && st.aux) s.commands.set(id, command);
  };
  const end = (n: TaskNote) => { if (!waitingNote(n) && !s.endedIds.has(n.id)) { s.endedIds.add(n.id); s.ends.push(noteEnd(n, at)); } };
  if (s.lastAt === null) s.bounds.push({ time: at, start: true });
  s.lastAt = Math.max(s.lastAt ?? 0, at);
  const m = o.message;
  if (o.type === "user" && o.origin && typeof o.origin === "object") s.bounds.push({ time: at, start: true });
  if (o.type === "assistant" && m?.stop_reason === "end_turn") s.bounds.push({ time: at, start: false });
  if (o.type === "attachment" && o.attachment?.type === "queued_command") {
    for (const n of parseNotifications(textOf(o.attachment.prompt))) {
      if (n.outputFile && st.aux) s.outputs.set(n.id, n.outputFile);
      end(n);
    }
  }
  if ((o.type === "assistant" || o.type === "user") && Array.isArray(m?.content)) {
    if (msg !== null) { s.newest = msg; newestMessage(s.open, msg, (v) => v); }
    for (const c of m.content) {
      if (c?.type === "tool_use" && typeof c.id === "string") {
        s.uses.set(c.id, { name: String(c.name ?? ""), command: st.aux && typeof c.input?.command === "string" ? c.input.command : null });
        s.open.set(c.id, s.newest ?? "");
      } else if (c?.type === "tool_result" && typeof c.tool_use_id === "string") {
        s.open.delete(c.tool_use_id);
        const u = s.uses.get(c.tool_use_id);
        const txt = textOf(c.content);
        const bg = str(o.toolUseResult?.backgroundTaskId) ?? (u?.name === "Bash" ? BG_TEXT.exec(txt)?.[1] ?? null : null);
        if (bg) {
          launch(bg, at, u?.command ?? null);
          const f = OUT_TEXT.exec(txt)?.[1];
          if (f && st.aux) s.outputs.set(bg, f);
        }
        const child = o.toolUseResult?.status === "async_launched" ? str(o.toolUseResult?.agentId) : null;
        if (child) launch(child, at, null);
        if (o.toolEndsTurn === true) {
          s.bounds.push({ time: at, start: false });
          if (u && /(?:SubagentHandback|StructuredOutput)$/.test(u.name) && o.toolUseResult?.success !== false) s.handbacks.push(at);
        }
      }
    }
  } else if (o.type === "user" && typeof m?.content === "string" && o.origin?.kind === "task-notification") {
    for (const n of parseNotifications(m.content)) end(n);
  }
}

/** Fold the lines of a text (any chunk of whole lines; the empty line is skipped). */
export function foldText(st: FoldState, text: string): FoldState {
  for (const line of text.split("\n")) if (line) stepLine(st, line);
  return st;
}

/** `summarizeTranscript`'s result from a state and the meta file. Does not change `st`. `metaAt`: the mtime of the meta
 *  file. A `meta.finished` is stale (ignored) on a resumed agent: when a tool call is still open or the transcript has
 *  records more than 1 s after the meta was written. */
export function finishInfo(st: FoldState, meta: Record<string, unknown> | null, metaAt: number | null = null): TranscriptInfo {
  const s = st.sum;
  const info: TranscriptInfo = {
    name: str(meta?.name), task: str(meta?.description), type: str(meta?.agentType), model: s.model,
    teammate: (str(meta?.taskKind) ?? "").includes("teammate"), workflowPhase: meta?.workflowPhase != null,
    toolUseId: str(meta?.toolUseId), agentCalls: s.agentCalls.slice(), bgTasks: s.bgTasks.slice(),
    finished: meta?.finished === true, endedTurn: false, toolUses: s.toolUses, toolErrors: s.toolErrors,
    firstAt: s.firstAt, lastAt: s.lastAt, lastTool: s.lastTool, lastToolAt: s.lastToolAt, ctxTokens: s.ctx,
    tokens: { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 }, inflight: null,
  };
  for (const u of s.usage.values()) { info.tokens.in += u[0]; info.tokens.out += u[1]; info.tokens.cacheRead += u[2]; info.tokens.cacheWrite += u[3]; }
  info.endedTurn = (s.endedTurn || s.structDone) && s.open.size === 0;
  if (info.finished && (s.open.size > 0 || (metaAt !== null && info.lastAt !== null && info.lastAt > metaAt + 1000))) info.finished = false;
  let last: { tool: string; at: number } | null = null;
  for (const v of s.open.values()) if (!last || v.at >= last.at) last = v;
  if (last) info.inflight = { tool: last.tool, verb: null, since: last.at };
  return info;
}

/** `signalsOf`'s result from a state. Does not change `st`. */
export function finishSignals(agent: string, st: FoldState): TranscriptSignals {
  const s = st.sig;
  const facts: SigFacts = {
    agent, launched: s.launched.map((x) => ({ ...x })), ends: s.ends.map((x) => ({ ...x })), bounds: s.bounds.map((x) => ({ ...x })),
    handbacks: s.handbacks.slice(), notices: [], procs: [], metaFinished: [],
  };
  return { facts, commands: new Map(s.commands), outputs: new Map(s.outputs), openCall: s.open.size > 0, lastAt: s.lastAt };
}

// ---- the saved form (JSON): `aux` is never saved, so command text never reaches the disk ----
type Json = unknown;
export function saveFold(st: FoldState): Json {
  const s = st.sum, g = st.sig;
  return {
    sum: { ...s, usage: [...s.usage], open: [...s.open] },
    sig: { launched: g.launched, ends: g.ends, bounds: g.bounds, handbacks: g.handbacks, uses: [...g.uses].map(([k, v]) => [k, v.name]), open: [...g.open], newest: g.newest, lastAt: g.lastAt },
  };
}
/** The state saved by `saveFold`, or null when the shape does not fit (the caller then reads the whole file). */
export function loadFold(j: any): FoldState | null {
  try {
    const st = initFold(false);
    const s = j.sum, g = j.sig;
    Object.assign(st.sum, s, { usage: new Map(s.usage), open: new Map(s.open) });
    st.sig.launched = g.launched; st.sig.ends = g.ends; st.sig.bounds = g.bounds; st.sig.handbacks = g.handbacks;
    st.sig.uses = new Map((g.uses as [string, string][]).map(([k, name]) => [k, { name, command: null }]));
    st.sig.open = new Map(g.open); st.sig.newest = g.newest ?? null; st.sig.lastAt = g.lastAt;
    st.sig.launchedIds = new Set(st.sig.launched.map((x) => x.id)); st.sig.endedIds = new Set(st.sig.ends.map((x) => x.id));
    if (typeof st.sum.toolUses !== "number" || !Array.isArray(st.sig.launched) || !Array.isArray(st.sig.ends) || !Array.isArray(st.sum.agentCalls)) return null;
    return st;
  } catch { return null; }
}
