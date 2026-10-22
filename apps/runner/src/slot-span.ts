import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { timingsFile } from "./timing.ts";

const flagValue = (a: string[], f: string): string | undefined => { const i = a.indexOf(f); const v = i >= 0 ? a[i + 1] : undefined; return v && !v.startsWith("-") ? v : undefined; };

export function slotStep(rest: string[]): string {
  const base = slotStepBase(rest);
  const dash = rest.indexOf("--");
  return rest[0] === "run" && dash >= 0 && rest.slice(dash + 1).includes("--dry") ? `${base} dry` : base;
}

export const writesOwnSpans = (rest: string[]): boolean => rest[0] === "run";

export const SLOT_SUBS = ["run", "acquire", "renew", "release", "status", "sim", "held", "admit"] as const;

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
export const KEY_CAP = 24;

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
  } else parts = [...head, ...(first === null ? [] : [tidy(first)])];
  return parts.every(okTok) ? parts.join(" ") : null;
}

export const capKey = (seen: readonly string[], cap: number, k: string | null): string | null => (k !== null && (seen.includes(k) || seen.length < cap) ? k : null);

export function runStep(kind: string, seen: readonly string[], argv: string[]): string {
  const k = capKey(seen, KEY_CAP, cmdKey(argv));
  return k === null ? `slot run ${kind}` : `slot run ${kind} ${k}`;
}

export const waitStep = (kind: string): string => `slot wait ${kind}`;

export function seenKeys(chunk: string, kind: string): string[] {
  const pre = `slot run ${kind} `;
  const out = new Set<string>();
  for (const m of chunk.matchAll(/"step":"([^"]*)"/g)) {
    const s = m[1]!;
    if (!s.startsWith(pre)) continue;
    const k = s.slice(pre.length).replace(/ (dry|cached)$/, "");
    if (k !== "" && k !== "dry" && k !== "cached") out.add(k);
  }
  return [...out];
}

const TAIL_BYTES = 2 << 20;

export function runLabel(kind: string, argv: string[], dry: boolean, cwd: string = process.cwd()): string {
  let chunk = "";
  try {
    const f = timingsFile(cwd);
    if (f) {
      const fd = openSync(f, "r");
      try {
        const size = fstatSync(fd).size;
        const len = Math.min(size, TAIL_BYTES);
        const buf = Buffer.alloc(len);
        readSync(fd, buf, 0, len, size - len);
        chunk = buf.toString("utf8");
      } finally { closeSync(fd); }
    }
  } catch { }
  const s = runStep(kind, seenKeys(chunk, kind), argv);
  return dry ? `${s} dry` : s;
}
