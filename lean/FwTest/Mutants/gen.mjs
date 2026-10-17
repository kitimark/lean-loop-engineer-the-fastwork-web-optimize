// gen.mjs: mechanical mutant generator for Lean sources (task m0-mutants, PLAN §10.2 M0 / V-r).
// Glue only: it rewrites text; the verdict (killed / survived) comes from `lake build` and `lake test`.
//
//   node gen.mjs list [--skip d,d] [--str-cap N] <file.lean>...
//                                              one TSV line per mutant: file id op def line from to
//   node gen.mjs apply <file.lean> <id> <out>  write the mutated file to <out>
//   node gen.mjs shard <i> <n> <in.tsv         the lines of shard i of n (FNV-1a of "file<TAB>id", mod n)
//   node gen.mjs regions <file.lean>           JSON: [{kind,name,start,end}] line ranges (1-based, inclusive)
//   node gen.mjs classify <log> <leanDir> <file>  verdict<TAB>detail of a failed build log (see mutants.sh)
//
// Mutant id: `<decl>#<k>:<op>:<repl>`, e.g. `samples#3:str:""`: decl = the enclosing def/abbrev/instance name
// (`_` if anonymous; `name@n` if the file has several with that name), k = the 1-based ordinal of the mutation
// site among the sites of the same op in that declaration, repl = the replacement (see mutantId). No line numbers,
// so an edit elsewhere in the file keeps the ids (and equivalent.tsv) valid. Tests: node --test gen.test.mjs.
//
// Mutants are only placed inside the bodies of `def`/`abbrev`/`instance` commands (after the first `:=` or the
// first match arm), never in comments, docstrings, string escapes, theorems, `#guard`s or signatures.
// Operators: rel (< <= > >= swapped with their strict/non-strict twin), eq (== !=), eqp (` = ` to ≠), bool (&& ||),
// prop (∧ ∨), opt (isSome/isNone), not (drop `!`),
// tf (true/false), ite (negate an `if` condition = swap its branches), num (n+1, n-1), arith (+ -), minmax,
// anyall, filter (drop a `.filter p`), list (head?/getLast?, take/drop, drop `.reverse`), str (empty a literal).
import { readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** Code mask: 1 for code chars, 0 for comments; 2 for string-literal contents (incl. quotes). */
function mask(src) {
  const m = new Uint8Array(src.length).fill(1);
  let i = 0, depth = 0;
  while (i < src.length) {
    if (depth > 0) {
      if (src.startsWith('/-', i)) { depth++; m[i] = m[i + 1] = 0; i += 2; continue; }
      if (src.startsWith('-/', i)) { depth--; m[i] = m[i + 1] = 0; i += 2; continue; }
      m[i++] = 0; continue;
    }
    if (src.startsWith('/-', i)) { depth = 1; m[i] = m[i + 1] = 0; i += 2; continue; }
    if (src.startsWith('--', i)) { while (i < src.length && src[i] !== '\n') m[i++] = 0; continue; }
    if (src[i] === '"') {
      m[i++] = 2;
      while (i < src.length && src[i] !== '"') { if (src[i] === '\\') m[i++] = 2; m[i++] = 2; }
      m[i++] = 2; continue;
    }
    if (src[i] === "'" && /[^\\]'/.test(src.slice(i + 1, i + 3)) && !/[A-Za-z0-9_]/.test(src[i - 1] ?? '')) {
      m[i] = m[i + 1] = m[i + 2] = 2; i += 3; continue; // char literal 'x'
    }
    i++;
  }
  return m;
}

const DEF_RE = /^(@\[[^\]]*\]\s*)?((private|protected|partial|noncomputable|unsafe)\s+)*(def|abbrev|instance)\b\s*([^\s:({\[]*)/;
const CMD_RE = /^(@\[[^\]]*\]\s*)?((private|protected|partial|noncomputable|unsafe)\s+)*(theorem|lemma|example|def|abbrev|instance|structure|inductive|class)\b\s*([^\s:({\[]*)/;

/** Top-level command regions by line (a region ends where the next column-0 code line starts, `|` arms excepted). */
export function regions(src) {
  const m = mask(src);
  const lines = src.split('\n');
  const starts = []; let off = 0;
  for (const l of lines) { starts.push(off); off += l.length + 1; }
  const out = []; let cur = null;
  for (let k = 0; k < lines.length; k++) {
    const l = lines[k];
    const top = l.length > 0 && !/^\s/.test(l) && m[starts[k]] !== 0 && !l.startsWith('|');
    const comment = l.length > 0 && m[starts[k]] === 0; // docstring / comment line at column 0
    if (top || (comment && !/^\s/.test(l))) {
      if (cur) { cur.end = k; out.push(cur); cur = null; }
      if (top) {
        const c = CMD_RE.exec(l);
        cur = { kind: c ? c[4] : (l.startsWith('#') ? l.split(/\s/)[0] : 'other'), name: c ? c[5] : '', start: k + 1, end: lines.length };
      }
    }
  }
  if (cur) out.push(cur);
  // trim trailing blank lines
  for (const r of out) while (r.end > r.start && lines[r.end - 1].trim() === '') r.end--;
  return out;
}

const isId = (ch) => ch !== undefined && /[A-Za-z0-9_'.!?₀-₉α-ωΑ-Ω]/u.test(ch);

/** Matching close for a balanced group starting at `i` (src[i] in `([{`), on code chars only. */
function closeOf(src, m, i) {
  const pairs = { '(': ')', '[': ']', '{': '}' };
  const stack = [pairs[src[i]]];
  for (let j = i + 1; j < src.length; j++) {
    if (m[j] !== 1) continue;
    const ch = src[j];
    if (pairs[ch]) stack.push(pairs[ch]);
    else if (ch === stack[stack.length - 1]) { stack.pop(); if (!stack.length) return j; }
  }
  return -1;
}

/** End (exclusive) of one application argument starting at `i`: a balanced group or an identifier. */
function argEnd(src, m, i) {
  if ('([{'.includes(src[i])) { const j = closeOf(src, m, i); return j < 0 ? -1 : j + 1; }
  let j = i; while (j < src.length && isId(src[j])) j++;
  return j > i ? j : -1;
}

/** All mutants of one file: {start,end,to,op} edits on code chars inside def bodies. */
export function mutants(src) {
  const m = mask(src);
  const lines = src.split('\n');
  const starts = []; let off = 0;
  for (const l of lines) { starts.push(off); off += l.length + 1; }
  const res = [];
  // declaration label: the name (`_` for an anonymous instance), plus `@n` (n-th of them, 1-based) when the same
  // label names several def/abbrev/instance commands of the file (same short name in two namespaces)
  const decls = regions(src).filter((r) => ['def', 'abbrev', 'instance'].includes(r.kind));
  const uses = {}, seen = {};
  for (const r of decls) uses[r.name || '_'] = (uses[r.name || '_'] ?? 0) + 1;
  for (const r of decls) {
    const nm = r.name || '_';
    seen[nm] = (seen[nm] ?? 0) + 1;
    const label = uses[nm] > 1 ? `${nm}@${seen[nm]}` : nm;
    const a = starts[r.start - 1], z = r.end < lines.length ? starts[r.end] - 1 : src.length;
    // body start: first `:=` in code, or the first line starting with an arm `|`
    let b = -1;
    for (let j = a; j < z - 1; j++) if (m[j] === 1 && src[j] === ':' && src[j + 1] === '=') { b = j + 2; break; }
    for (let k = r.start; k < r.end; k++) if (/^\s*\|/.test(lines[k]) && m[starts[k]] !== 0) { const p = starts[k]; if (b < 0 || p < b) b = p; break; }
    if (b < 0) continue;
    // a `deriving` / `where` structure-instance tail stays in; `termination_by`/`decreasing_by` proofs are cut off
    let e = z;
    for (let k = r.start; k < r.end; k++) if (/^\s*(termination_by|decreasing_by)\b/.test(lines[k])) { e = Math.min(e, starts[k]); break; }
    const add = (s, t, to, op) => res.push({ start: s, end: t, to, op, def: r.name, label });
    const code = (s, t) => { for (let j = s; j < t; j++) if (m[j] !== 1) return false; return true; };
    for (let j = b; j < e; j++) {
      if (m[j] === 2 && src[j] === '"' && (j === 0 || m[j - 1] !== 2)) { // string literal start
        let k = j + 1; while (k < e && !(src[k] === '"' && m[k] === 2 && (k + 1 >= src.length || m[k + 1] !== 2))) k++;
        // literal is src[j..k]
        if (k > j + 1 && !src.slice(j, k + 1).includes('{')) add(j, k + 1, '""', 'str');
        j = k; continue;
      }
      if (m[j] !== 1) continue;
      const sp = (s, t) => src[s - 1] === ' ' && src[t] === ' ';
      const tok = (w) => src.startsWith(w, j) && code(j, j + w.length) && !isId(src[j - 1]) && !isId(src[j + w.length]);
      // relational operators, space-delimited only (keeps <|>, |>, ->, => etc. out)
      for (const [f, t] of [['<', '≤'], ['≤', '<'], ['<=', '<'], ['>', '≥'], ['≥', '>'], ['>=', '>']])
        if (src.startsWith(f, j) && sp(j, j + f.length)) add(j, j + f.length, t, 'rel');
      for (const [f, t] of [['==', '!='], ['!=', '=='], ['&&', '||'], ['||', '&&'], ['≠', '=']])
        if (src.startsWith(f, j) && sp(j, j + f.length)) add(j, j + f.length, t, f === '==' || f === '!=' || f === '≠' ? 'eq' : 'bool');
      // propositional `=` (in `if`/`decide` conditions) and the connectives ∧ ∨ (ops added in round 2)
      if (src[j] === '=' && sp(j, j + 1)) add(j, j + 1, '≠', 'eqp');
      for (const [f, t] of [['∧', '∨'], ['∨', '∧']]) if (src[j] === f && sp(j, j + 1)) add(j, j + 1, t, 'prop');
      if ((src[j] === '+' || src[j] === '-') && sp(j, j + 1)) add(j, j + 1, src[j] === '+' ? '-' : '+', 'arith');
      // logical negation `!x` / `!(..)` (not `!=`)
      if (src[j] === '!' && src[j + 1] !== '=' && (src[j - 1] === ' ' || src[j - 1] === '(') && (isId(src[j + 1]) || src[j + 1] === '(')) add(j, j + 1, '', 'not');
      if (tok('true')) add(j, j + 4, 'false', 'tf');
      if (tok('false')) add(j, j + 5, 'true', 'tf');
      if (tok('max')) add(j, j + 3, 'min', 'minmax');
      if (tok('min')) add(j, j + 3, 'max', 'minmax');
      // numerals (not part of identifiers / decimals)
      if (/[0-9]/.test(src[j]) && !isId(src[j - 1]) && src[j - 1] !== '.') {
        let k = j; while (/[0-9]/.test(src[k])) k++;
        if (!isId(src[k]) && src[k] !== '.') {
          const n = BigInt(src.slice(j, k));
          add(j, k, String(n + 1n), 'num');
          if (n > 0n) add(j, k, String(n - 1n), 'num');
        }
        j = k - 1; continue;
      }
      // `if c then` → `if ¬(c) then` (same as swapping the branches); dependent `if h : c` skipped
      if (tok('if') && src[j + 2] === ' ') {
        let k = j + 3, depth = 0, ok = false;
        for (; k < e; k++) {
          if (m[k] !== 1) continue;
          if ('([{'.includes(src[k])) depth++;
          else if (')]}'.includes(src[k])) depth--;
          else if (depth === 0 && src.startsWith('then', k) && !isId(src[k - 1]) && !isId(src[k + 4])) { ok = true; break; }
        }
        const cond = src.slice(j + 3, k).trimEnd();
        if (ok && !/^[A-Za-z_][A-Za-z0-9_']*\s*:[^=]/.test(cond) && !cond.includes('let ')) add(j + 3, j + 3 + cond.length, `¬(${cond})`, 'ite');
      }
      if (src[j] === '.' && isId(src[j - 1]) || src[j] === '.' && src[j - 1] === ')') {
        const rest = src.slice(j + 1, j + 12);
        const w = /^[A-Za-z?]+/.exec(rest)?.[0] ?? '';
        const swap = { any: 'all', all: 'any', 'head?': 'getLast?', 'getLast?': 'head?', take: 'drop', drop: 'take', isSome: 'isNone', isNone: 'isSome' };
        const kind = { any: 'anyall', all: 'anyall', isSome: 'opt', isNone: 'opt' };
        if (Object.hasOwn(swap, w) && !isId(src[j + 1 + w.length])) add(j + 1, j + 1 + w.length, swap[w], kind[w] ?? 'list');
        if (w === 'reverse' && !isId(src[j + 8])) add(j, j + 8, '', 'list');
        if (w === 'filter' && src[j + 7] === ' ') {
          const t = argEnd(src, m, j + 8);
          if (t > 0) add(j, t, '', 'filter');
        }
      }
      if (tok('List.filter') && src[j + 11] === ' ') { // `List.filter p xs` → `xs`
        const t = argEnd(src, m, j + 12);
        if (t > 0) add(j, t + (src[t] === ' ' ? 1 : 0), '', 'filter');
      }
    }
  }
  const lineOf = (p) => { let lo = 0, hi = starts.length - 1; while (lo < hi) { const md = (lo + hi + 1) >> 1; if (starts[md] <= p) lo = md; else hi = md - 1; } return lo; };
  // id = <label>#<k>:<op>:<repl>, k = rank (1-based) of this mutant's start offset among the distinct start offsets
  // of the same op in the same declaration. Edits outside the declaration leave it unchanged (no line numbers).
  const sites = {};
  for (const x of res) (sites[`${x.label}\t${x.op}`] ??= new Set()).add(x.start);
  const rank = {};
  for (const [k, s] of Object.entries(sites)) rank[k] = new Map([...s].sort((p, q) => p - q).map((p, i) => [p, i + 1]));
  const out = res.map((x) => {
    const ln = lineOf(x.start);
    return { ...x, line: ln + 1, col: x.start - starts[ln] + 1, from: src.slice(x.start, x.end), id: mutantId(x.label, rank[`${x.label}\t${x.op}`].get(x.start), x.op, x.to) };
  });
  // Unique by construction: (label, op, k) fixes the start offset, and the only op with two mutants at one start is
  // num (n+1 vs n-1), whose replacements are rendered in full. Checked anyway, since apply picks by id.
  const ids = new Set();
  for (const x of out) {
    if (ids.has(x.id)) throw new Error(`gen: duplicate mutant id ${x.id} (line ${x.line})`);
    ids.add(x.id);
  }
  return out;
}

/** The id text: `<label>#<k>:<op>:<repl>`; repl is `drop` for an empty replacement, `x` for one longer than 12
 * characters or holding a tab/newline (num replacements always in full, so n+1 and n-1 stay apart). */
export function mutantId(label, k, op, to) {
  const repl = to === '' ? 'drop' : op === 'num' || ([...to].length <= 12 && !/[\t\n]/.test(to)) ? to : 'x';
  return `${label}#${k}:${op}:${repl}`;
}

/** Kind and name of the top-level command that holds line `ln` of `src`. */
function where(src, ln) {
  return regions(src).find((x) => x.start <= ln && ln <= x.end) ?? { kind: 'other', name: '' };
}

const PROOF = new Set(['theorem', 'lemma', 'example']);
const esc = (s) => s.replace(/\\/g, '\\\\').replace(/\t/g, '\\t').replace(/\n/g, '\\n');

/** 32-bit FNV-1a of the UTF-8 bytes of `s` (the shard key hash). */
export const fnv = (s) => { let h = 0x811c9dc5; for (const b of Buffer.from(s, 'utf8')) h = Math.imul(h ^ b, 0x01000193) >>> 0; return h; };

// CLI only when run as a script (the tests import this module)
const main = process.argv[1] !== undefined && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
const [cmd, ...args] = main ? process.argv.slice(2) : ['--imported'];
if (cmd === '--imported') {
  // imported as a module: nothing to run
} else if (cmd === 'list') {
  // list [--skip def,def] <file>...  → TSV: file id op def line from to
  // --str-cap N: at most N `str` mutants per def, evenly spread over its literals (first and last included)
  let skip = new Set(), cap = Infinity;
  for (;;) {
    if (args[0] === '--skip') { skip = new Set(args[1].split(',')); args.splice(0, 2); }
    else if (args[0] === '--str-cap') { cap = +args[1]; args.splice(0, 2); }
    else break;
  }
  const cut = (s) => esc(s.length > 60 ? s.slice(0, 57) + '...' : s);
  for (const f of args) {
    const ms = mutants(readFileSync(f, 'utf8')).filter((x) => !skip.has(x.def));
    const strs = {};
    for (const x of ms) if (x.op === 'str') (strs[x.def] ??= []).push(x);
    const keep = new Set();
    for (const xs of Object.values(strs)) {
      const n = xs.length, k = Math.min(cap, n);
      for (let i = 0; i < k; i++) keep.add(xs[k === 1 ? 0 : Math.round((i * (n - 1)) / (k - 1))]);
    }
    for (const x of ms) if (x.op !== 'str' || keep.has(x)) console.log([f, x.id, x.op, x.def, x.line, cut(x.from), cut(x.to)].join('\t'));
  }
} else if (cmd === 'classify') {
  // classify <lake.log> <leanDir> <mutatedFile>  → "<verdict>\t<detail>"
  // killed:proof / killed:guard: an error inside a theorem / #guard (any module);
  // killed:build: an error in a def of another module; stillborn: errors only in defs of the mutated module.
  const [log, dir, mf] = args;
  const errs = [];
  for (const l of readFileSync(log, 'utf8').split('\n')) {
    const e = /^error: (?:\.\/)*([^:\s]+\.lean):(\d+):(\d+): ?(.*)$/.exec(l);
    if (e) errs.push({ file: e[1], line: +e[2], msg: e[4] });
  }
  if (!errs.length) { console.log('error\tno located error in the log'); process.exit(0); }
  const srcs = {};
  const ws = errs.map((e) => [e, where(srcs[e.file] ??= readFileSync(`${dir}/${e.file}`, 'utf8'), e.line)]);
  const tag = (e, w) => esc(`${e.file}:${e.line} ${w.kind} ${w.name} | ${e.msg.slice(0, 80)}`);
  const hit = ws.find(([, w]) => PROOF.has(w.kind)) ?? ws.find(([, w]) => w.kind.startsWith('#'));
  const other = ws.find(([e]) => e.file !== mf);
  if (hit) console.log(`${PROOF.has(hit[1].kind) ? 'killed:proof' : 'killed:guard'}\t${tag(...hit)}`);
  else if (other) console.log(`killed:build\t${tag(...other)}`);
  else console.log(`stillborn\t${tag(...ws[0])}`);
} else if (cmd === 'apply') {
  const [f, id, out] = args;
  const src = readFileSync(f, 'utf8');
  const x = mutants(src).find((y) => y.id === id);
  if (!x) { console.error(`gen: no mutant ${id} in ${f}`); process.exit(2); }
  writeFileSync(out, src.slice(0, x.start) + x.to + src.slice(x.end));
} else if (cmd === 'shard') {
  // shard <i> <n>: the TSV lines of stdin (file id ...) whose 32-bit FNV-1a hash of "file<TAB>id" (UTF-8) is i mod n.
  // Depends on the mutant id alone, so a mutant lands in the same shard whatever else is in the list.
  const [i, n] = args.map(Number);
  if (!(Number.isInteger(i) && Number.isInteger(n) && n >= 1 && i >= 0 && i < n)) {
    console.error('gen: shard <i> <n> needs integers 0 <= i < n'); process.exit(2);
  }
  const out = [];
  for (const l of readFileSync(0, 'utf8').split('\n')) {
    if (l === '') continue;
    const [f, id] = l.split('\t');
    if (fnv(`${f}\t${id}`) % n === i) out.push(l);
  }
  if (out.length) console.log(out.join('\n'));
} else if (cmd === 'regions') {
  console.log(JSON.stringify(regions(readFileSync(args[0], 'utf8'))));
} else {
  console.error('usage: gen.mjs list [--skip defs] <file>... | apply <file> <id> <out> | shard <i> <n> | regions <file> | classify <log> <dir> <file>');
  process.exit(2);
}
