import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { timingsFile } from "./timing.ts";

const flagValue = (a: string[], f: string): string | undefined => { const i = a.indexOf(f); const v = i >= 0 ? a[i + 1] : undefined; return v && !v.startsWith("-") ? v : undefined; };

export function slotStep(rest: string[]): string {
  const base = slotStepBase(rest);
  const dash = rest.indexOf("--");
  return rest[0] === "run" && dash >= 0 && rest.slice(dash + 1).includes("--dry") ? `${base} dry` : base;
}

export const writesOwnSpans = (rest: string[]): boolean => rest[0] === "run";

export const SLOT_SUBS = ["run", "acquire", "renew", "release", "pass", "status", "sim", "held", "admit"] as const;

function slotStepBase(rest: string[]): string {
  const sub = rest[0];
  if (!sub || sub.startsWith("-")) return "slot";
  if (sub === "run" || sub === "acquire" || sub === "held") {
    const k = flagValue(rest.slice(0, rest.includes("--") ? rest.indexOf("--") : undefined), "--kind");
    return k ? `slot ${sub} ${k}` : `slot ${sub}`;
  }
  return `slot ${sub}`;
}

const VALUE_FLAGS = ["--filter", "-F", "-C", "--dir", "--kind"];
const FILTER_FLAGS = ["--filter", "-F"];
const LAUNCH_WORDS = ["exec", "dlx"];
const SKIP_WORDS = ["run"];
export const FW_LAUNCHER = "fw";
export const kindCap = (kind: string): number => (kind === "land" ? 8 : kind === "sim" ? 4 : 24);

const lastSeg = (t: string): string => t.split("/").at(-1) ?? t;
const okTok = (t: string): boolean => t.length > 0 && t.length <= 60 && /^[A-Za-z0-9._/-]*$/.test(t);
const tidy = (a: string): string => (a.startsWith("/") ? lastSeg(a) : a);

function scan(args: string[]): { filt: string | null; first: string | null; rest: string[] } {
  let filt: string | null = null;
  for (let i = 0; i < args.length; i++) {
    const t = args[i]!;
    const v = args[i + 1];
    if (v !== undefined && VALUE_FLAGS.includes(t)) { if (FILTER_FLAGS.includes(t)) filt ??= v; i++; continue; }
    if (t.startsWith("-") || SKIP_WORDS.includes(t)) continue;
    return { filt, first: t, rest: args.slice(i + 1) };
  }
  return { filt, first: null, rest: [] };
}

export function cmdKey(argv: string[]): string | null {
  const [h, ...args] = argv;
  if (h === undefined) return null;
  const { filt, first, rest } = scan(args);
  const head = [lastSeg(h), ...(filt === null ? [] : [lastSeg(filt)])];
  let parts: string[];
  if (first !== null && LAUNCH_WORDS.includes(first) && rest.length > 0) {
    const inner = scan(rest.slice(1));
    parts = [...head, lastSeg(rest[0]!), ...(inner.first === null ? [] : [tidy(inner.first)])];
  } else if (first === FW_LAUNCHER && rest.length > 0) {
    const sub = rest.find((a) => !a.startsWith("-"));
    parts = [...head, first, ...(sub === undefined ? [] : [tidy(sub)])];
  } else parts = [...head, ...(first === null ? [] : [tidy(first)])];
  return parts.every(okTok) ? parts.join(" ") : null;
}

export const capKey = (seen: readonly string[], cap: number, k: string | null): string | null => (k !== null && (seen.includes(k) || seen.length < cap) ? k : null);

export function runStep(kind: string, seen: readonly string[], argv: string[]): string {
  const k = capKey(seen, kindCap(kind), cmdKey(argv));
  return k === null ? `slot run ${kind}` : `slot run ${kind} ${k}`;
}

export const WAIT_TOOL = "fw wait";
export const waitStep = (kind: string): string => `slot wait ${kind}`;

const dropSuffix = (suf: string, s: string): string => (s.endsWith(suf) ? s.slice(0, s.length - suf.length) : s);

export function stepKey(kind: string, step: string): string | null {
  const pre = `slot run ${kind} `;
  if (!step.startsWith(pre)) return null;
  const k = dropSuffix(" dry", dropSuffix(" cached", step.slice(pre.length)));
  return k === "" || k === "dry" || k === "cached" ? null : k;
}

export function seenKeys(chunk: string, kind: string, into: Set<string> = new Set()): string[] {
  for (const m of chunk.matchAll(/"step":"([^"]*)"/g)) {
    const k = stepKey(kind, m[1]!);
    if (k !== null) into.add(k);
  }
  return [...into];
}

const CHUNK_BYTES = 4 << 20;

export function seenInFile(f: string, kind: string): string[] {
  const fd = openSync(f, "r");
  const seen = new Set<string>();
  try {
    const size = fstatSync(fd).size;
    let pos = 0, carry = "";
    while (pos < size) {
      const len = Math.min(CHUNK_BYTES, size - pos);
      const buf = Buffer.alloc(len);
      readSync(fd, buf, 0, len, pos);
      pos += len;
      const text = carry + buf.toString("utf8");
      const cut = text.lastIndexOf("\n");
      if (pos < size && cut >= 0) { seenKeys(text.slice(0, cut), kind, seen); carry = text.slice(cut + 1); } else { seenKeys(text, kind, seen); carry = ""; }
    }
  } finally { closeSync(fd); }
  return [...seen];
}

export function runLabel(kind: string, argv: string[], dry: boolean, cwd: string = process.cwd()): string {
  let seen: string[] = [];
  try {
    const f = timingsFile(cwd);
    if (f) seen = seenInFile(f, kind);
  } catch { }
  const s = runStep(kind, seen, argv);
  return dry ? `${s} dry` : s;
}
