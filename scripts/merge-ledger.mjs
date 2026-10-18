#!/usr/bin/env node
// git merge driver for the JSON ledgers (docs/team/tools/ledger-merge.md).
//
//   git config merge.ledger.driver "node scripts/merge-ledger.mjs %O %A %B"
//
// %O base, %A ours (the result is written here), %B theirs. The decision is Lean's Fw.Ops.LedgerMerge (merge,
// rows, pick3; checked against packages/contracts/golden/ops/ledger-merge.jsonl by
// apps/runner/test/ledger-merge.test.ts): per id, a side that left the base unchanged takes the other side's version,
// equal versions agree, both changed differently is a conflict; order is ours' ids, then theirs' ids ours lacks.
// This file is glue: it parses the three files, applies the rule to every id-keyed array (top-level array, or each
// top-level member such as .incidents/.findings/.notes/.mistakes/.classes) and to the other top-level members as whole
// values, and renders the result with the file's own indent and trailing newline.
// Exit 0: merged cleanly. Exit 1: conflicts, written as standard <<<<<<< ======= >>>>>>> blocks around each
// conflicting entry (or the whole file via `git merge-file` when a file is not a ledger we can read).
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

/** Canonical text of a version (undefined = absent). Key order counts, as it does for a line diff. */
const canon = (v) => (v === undefined ? undefined : JSON.stringify(v));

/**
 * Lean `pick3`: base b, ours o, theirs t (canonical texts, undefined = absent). Returns { v } with the merged
 * version (v undefined = deleted) or null for a conflict.
 */
export function pick3(b, o, t) {
  if (o === b) return { v: t };
  if (t === b) return { v: o };
  if (o === t) return { v: o };
  return null;
}

/**
 * The id of a ledger entry: `id`, else `candidate` (research/findings/ledger.json has no id field), else the note key
 * (entry, task) of a note row as `note:` + JSON.stringify([entry, task]) (Lean `NoteKey`, `Golden.noteKey`; the JSON
 * pair keeps the key injective whatever characters the strings hold).
 */
export function keyOf(e) {
  if (e === null || typeof e !== "object" || Array.isArray(e)) return undefined;
  if (typeof e.id === "string") return e.id;
  if (typeof e.candidate === "string") return `candidate:${e.candidate}`;
  if (typeof e.entry === "string" && typeof e.task === "string") return `note:${JSON.stringify([e.entry, e.task])}`;
  return undefined;
}

/** True iff every element has an id and the ids are distinct (Lean's nodup(κ(L)) premise). */
export function idKeyed(arr) {
  if (!Array.isArray(arr)) return false;
  const seen = new Set();
  for (const e of arr) {
    const k = keyOf(e);
    if (k === undefined || seen.has(k)) return false;
    seen.add(k);
  }
  return true;
}

/** Lean `ids`: ours' ids, then theirs' ids ours lacks, in theirs' order. */
function ids(ok, tk) {
  const inOurs = new Set(ok);
  return [...ok, ...tk.filter((i) => !inOurs.has(i))];
}

/**
 * Lean `rows` over generic keyed versions: `get(side, i)` returns the version or undefined. Rows are
 * { keep: value } | { drop: id } | { clash: id, base, ours, theirs } (null for an absent version), as in the golden.
 */
function rowsBy(order, look) {
  return order.map((i) => {
    const [b, o, t] = [look.base(i), look.ours(i), look.theirs(i)];
    const p = pick3(canon(b), canon(o), canon(t));
    if (p === null) return { clash: i, base: b ?? null, ours: o ?? null, theirs: t ?? null };
    // p.v is the canonical text of o or t; take the matching parsed version
    const v = p.v === undefined ? undefined : p.v === canon(o) ? o : t;
    return v === undefined ? { drop: i } : { keep: v };
  });
}

const indexBy = (arr) => new Map(arr.map((e) => [keyOf(e), e]));

/** Lean `rows` on three id-keyed entry arrays. */
export function rows(base, ours, theirs) {
  const [mb, mo, mt] = [indexBy(base), indexBy(ours), indexBy(theirs)];
  return rowsBy(ids([...mo.keys()], [...mt.keys()]), {
    base: (i) => mb.get(i), ours: (i) => mo.get(i), theirs: (i) => mt.get(i),
  });
}

/** Lean `merge`: the kept entries, or null on any clash. */
export function merge(base, ours, theirs) {
  const rs = rows(base, ours, theirs);
  return rs.some((r) => "clash" in r) ? null : rs.filter((r) => "keep" in r).map((r) => r.keep);
}

class Unreadable extends Error {}

const TOKEN = "@@fw-ledger-conflict-";

/**
 * Merge three parsed ledger documents. Returns { value, clashes } where value holds a placeholder string for each
 * clash (clashes[n] = { ours, theirs, member } with member the top-level key for a member-level clash).
 */
export function mergeDocs(b, o, t) {
  const clashes = [];
  const hole = (c) => { clashes.push(c); return `${TOKEN}${clashes.length - 1}@@`; };
  const mergeArr = (ba, oa, ta) =>
    rows(ba, oa, ta).flatMap((r) => ("keep" in r ? [r.keep] : "drop" in r ? [] : [hole({ ours: r.ours, theirs: r.theirs })]));
  if (Array.isArray(o) && Array.isArray(t)) {
    const ba = b === undefined ? [] : b;
    if (!idKeyed(ba) || !idKeyed(o) || !idKeyed(t)) throw new Unreadable("top-level array without distinct ids");
    return { value: mergeArr(ba, o, t), clashes };
  }
  const isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
  const bo = b === undefined ? {} : b;
  if (!isObj(bo) || !isObj(o) || !isObj(t)) throw new Unreadable("not a JSON object or array ledger");
  const has = (x, k) => Object.prototype.hasOwnProperty.call(x, k);
  const get = (x) => (k) => (has(x, k) ? x[k] : undefined);
  const out = {};
  for (const k of ids(Object.keys(o), Object.keys(t))) {
    const [bv, ov, tv] = [get(bo)(k), get(o)(k), get(t)(k)];
    if (idKeyed(ov) && idKeyed(tv) && (bv === undefined || idKeyed(bv)) && canon(ov) !== canon(tv)) {
      out[k] = mergeArr(bv ?? [], ov, tv);
      continue;
    }
    const [r] = rowsBy([k], { base: () => bv, ours: () => ov, theirs: () => tv });
    if ("keep" in r) out[k] = r.keep;
    else if ("clash" in r) out[k] = hole({ ours: r.ours, theirs: r.theirs, member: k });
  }
  return { value: out, clashes };
}

/** The indent of a JSON text: the leading whitespace of its second line (1 space when there is none). */
export function indentOf(text) {
  const m = /^[[{][ \t]*\r?\n([ \t]+)\S/.exec(text);
  return m ? m[1] : " ";
}

/** Render a value at a base indent (later lines are prefixed by it). */
const renderAt = (v, ind, base) => JSON.stringify(v, null, ind).split("\n").join(`\n${base}`);

/**
 * Merge three ledger texts (base may be "" when the file has no common ancestor). Returns { text, conflicts }.
 * Throws Unreadable if a text is not a ledger this driver can merge.
 */
export function mergeTexts(baseText, oursText, theirsText) {
  const parse = (s, what) => {
    if (s.trim() === "") return undefined;
    try { return JSON.parse(s); } catch { throw new Unreadable(`${what} is not JSON`); }
  };
  const [b, o, t] = [parse(baseText, "base"), parse(oursText, "ours"), parse(theirsText, "theirs")];
  if (o === undefined || t === undefined) throw new Unreadable("ours or theirs is empty");
  const { value, clashes } = mergeDocs(b, o, t);
  const ind = indentOf(oursText);
  const nl = oursText.endsWith("\n") ? "\n" : "";
  let text = JSON.stringify(value, null, ind);
  if (clashes.length > 0) {
    text = text.split("\n").map((line) => {
      const m = new RegExp(`^([ \\t]*)(?:("(?:[^"\\\\]|\\\\.)*"): )?"${TOKEN}(\\d+)@@"(,?)$`).exec(line);
      if (!m) return line;
      const [, lead, , n, comma] = m;
      const c = clashes[Number(n)];
      const side = (v) => (v === undefined || v === null ? []
        : [`${lead}${c.member === undefined ? "" : `${JSON.stringify(c.member)}: `}${renderAt(v, ind, lead)}${comma}`]);
      return ["<<<<<<< ours", ...side(c.ours), "=======", ...side(c.theirs), ">>>>>>> theirs"].join("\n");
    }).join("\n");
  }
  return { text: text + nl, conflicts: clashes.length };
}

/** git merge driver entry point: node merge-ledger.mjs %O %A %B */
function main(argv) {
  const [O, A, B] = argv;
  if (!O || !A || !B) {
    process.stderr.write("usage: merge-ledger.mjs <base %O> <ours %A> <theirs %B>\n");
    return 2;
  }
  try {
    const { text, conflicts } = mergeTexts(readFileSync(O, "utf8"), readFileSync(A, "utf8"), readFileSync(B, "utf8"));
    writeFileSync(A, text);
    if (conflicts > 0) process.stderr.write(`merge-ledger: ${conflicts} conflicting entr${conflicts === 1 ? "y" : "ies"} in ${A}\n`);
    return conflicts > 0 ? 1 : 0;
  } catch (e) {
    if (!(e instanceof Unreadable)) throw e;
    // not a ledger we can read: git's own line merge, conflict markers included
    process.stderr.write(`merge-ledger: ${e.message}; falling back to git merge-file\n`);
    const r = spawnSync("git", ["merge-file", "-L", "ours", "-L", "base", "-L", "theirs", A, O, B], { stdio: "inherit" });
    return r.status === 0 ? 0 : 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) process.exit(main(process.argv.slice(2)));
