// latex-strip.mjs: removes LaTeX math from the doc comments (`/-- -/`, `/-! -/`) of Lean files.
//   node scripts/latex-strip.mjs <file.lean>...          rewrite each file in place
//   node scripts/latex-strip.mjs --check <file.lean>...  exit 1 when a file still holds `$$`
// In a doc comment, a `$$...$$` block goes; an inline `$...$` becomes a code span when it is one name, number or
// string, and goes otherwise. Code spans and fences keep their `$`. Leftovers are tidied (a dangling `i.e.` or `:`, a
// blank-line run, a space before punctuation), and a doc comment with no prose left is deleted. Code, strings, chars
// and plain comments are copied unchanged. A second run changes nothing.
import { readFileSync, writeFileSync } from 'node:fs';

const isIdent = (c) => c !== undefined && /[\p{L}\p{N}_'!?.₀-ₜ]/u.test(c);

// Splits Lean source into parts { kind: 'code' | 'doc', text }. A doc part is a whole `/--...-/` or `/-!...-/`.
export function split(src) {
  const parts = [];
  let code = '';
  let i = 0;
  const n = src.length;
  const flush = () => { if (code) parts.push({ kind: 'code', text: code }); code = ''; };
  // end index (exclusive) of the block comment opening at `at` (nested `/-` `-/`)
  const blockEnd = (at) => {
    let depth = 0;
    let j = at;
    while (j < n) {
      if (src.startsWith('/-', j)) { depth++; j += 2; continue; }
      if (src.startsWith('-/', j)) { depth--; j += 2; if (depth === 0) return j; continue; }
      j++;
    }
    return n;
  };
  // end index (exclusive) of the string opening with `"` at `at`; `interp` handles `{...}` of s!/m!/f! strings
  const stringEnd = (at, interp) => {
    let j = at + 1;
    while (j < n) {
      const c = src[j];
      if (c === '\\') { j += 2; continue; }
      if (c === '"') return j + 1;
      if (interp && c === '{') { j = codeEnd(j + 1, '}'); continue; }
      j++;
    }
    return n;
  };
  // end index of a code run inside an interpolation, up to and including the matching `close`
  const codeEnd = (at, close) => {
    let j = at;
    let depth = 0;
    while (j < n) {
      const c = src[j];
      if (c === '{') depth++;
      else if (c === close) { if (depth === 0) return j + 1; depth--; }
      else if (c === '"') { j = stringEnd(j, src[j - 1] === '!'); continue; }
      else if (src.startsWith('--', j)) { const e = src.indexOf('\n', j); j = e < 0 ? n : e; continue; }
      else if (src.startsWith('/-', j)) { j = blockEnd(j); continue; }
      j++;
    }
    return n;
  };
  while (i < n) {
    const c = src[i];
    if (src.startsWith('--', i)) {
      const e = src.indexOf('\n', i);
      const end = e < 0 ? n : e;
      code += src.slice(i, end); i = end; continue;
    }
    if (src.startsWith('/-', i)) {
      const end = blockEnd(i);
      const doc = (src[i + 2] === '-' || src[i + 2] === '!') && !src.startsWith('/--/', i);
      if (doc) { flush(); parts.push({ kind: 'doc', text: src.slice(i, end) }); } else code += src.slice(i, end);
      i = end; continue;
    }
    if (c === 'r' && !isIdent(src[i - 1]) && /^r#*"/.test(src.slice(i, i + 40))) {
      const hashes = /^r(#*)"/.exec(src.slice(i, i + 40))[1];
      const close = '"' + hashes;
      const e = src.indexOf(close, i + 2 + hashes.length);
      const end = e < 0 ? n : e + close.length;
      code += src.slice(i, end); i = end; continue;
    }
    if (c === '"') {
      const end = stringEnd(i, src[i - 1] === '!');
      code += src.slice(i, end); i = end; continue;
    }
    if (c === "'" && !isIdent(src[i - 1])) {
      const m = /^'(\\(?:u\{[0-9a-fA-F]+\}|x[0-9a-fA-F]{2}|.)|[^\\'\n])'/u.exec(src.slice(i, i + 16));
      if (m) { code += m[0]; i += m[0].length; continue; }
    }
    if (c === '«') {
      const e = src.indexOf('»', i);
      const end = e < 0 ? n : e + 1;
      code += src.slice(i, end); i = end; continue;
    }
    code += c; i++;
  }
  flush();
  return parts;
}

const symbols = {
  le: '≤', leq: '≤', ge: '≥', geq: '≥', ne: '≠', neq: '≠', lt: '<', gt: '>', in: '∈', notin: '∉', ni: '∋',
  subseteq: '⊆', subset: '⊂', supseteq: '⊇', supset: '⊃', cap: '∩', cup: '∪', setminus: '∖', emptyset: '∅',
  varnothing: '∅', land: '∧', wedge: '∧', lor: '∨', vee: '∨', neg: '¬', lnot: '¬', to: '→', rightarrow: '→',
  Rightarrow: '⇒', implies: '⇒', leftarrow: '←', Leftarrow: '⇐', gets: '←', mapsto: '↦', iff: '⇔',
  Leftrightarrow: '⇔', leftrightarrow: '↔', forall: '∀', exists: '∃', cdot: '·', times: '×', circ: '∘', pm: '±',
  approx: '≈', equiv: '≡', sim: '∼', infty: '∞', bot: '⊥', top: '⊤', uparrow: '↑', downarrow: '↓', mid: '|',
  vert: '|', lvert: '|', rvert: '|', Vert: '‖', langle: '⟨', rangle: '⟩', lfloor: '⌊', rfloor: '⌋', lceil: '⌈',
  rceil: '⌉', ldots: '...', cdots: '...', dots: '...', colon: ':', bmod: 'mod', mod: 'mod', max: 'max', min: 'min',
  log: 'log', sup: 'sup', inf: 'inf', lim: 'lim', star: '⋆', prime: "'", ell: 'ℓ', partial: '∂', oplus: '⊕',
  alpha: 'α', beta: 'β', gamma: 'γ', delta: 'δ', epsilon: 'ε', varepsilon: 'ε', zeta: 'ζ', eta: 'η', theta: 'θ',
  iota: 'ι', kappa: 'κ', lambda: 'λ', mu: 'μ', nu: 'ν', xi: 'ξ', pi: 'π', rho: 'ρ', sigma: 'σ', tau: 'τ', phi: 'φ',
  varphi: 'φ', chi: 'χ', psi: 'ψ', omega: 'ω', Gamma: 'Γ', Delta: 'Δ', Theta: 'Θ', Lambda: 'Λ', Xi: 'Ξ', Pi: 'Π',
  Sigma: 'Σ', Phi: 'Φ', Psi: 'Ψ', Omega: 'Ω', quad: ' ', qquad: ' ', left: '', right: '', big: '', Big: '',
  bigl: '', bigr: '', displaystyle: '', preceq: '≼', prec: '≺', succeq: '≽', succ: '≻', sqsubseteq: '⊑',
  sqsubset: '⊏', ominus: '⊖', bigoplus: '⨁', mp: '∓', sum: 'Σ', prod: 'Π', vartheta: 'ϑ', mathbin: '', pmod: 'mod',
};
const blackboard = { N: 'ℕ', Z: 'ℤ', Q: 'ℚ', R: 'ℝ', B: '𝔹' };
const wrappers = 'mathit|mathrm|texttt|operatorname|text|textsf|mathsf|mathtt|mathbf|textit|textrm|textbf|mathcal|mathbin|mathrel|mathop|mbox|boldsymbol|emph';

// Inline math as plain text for a code span (Unicode symbols, no LaTeX), or null when it uses a construct with no
// one-line plain form (fractions, sums, environments, accents).
export function plainInline(tex) {
  let t = tex.replace(/\\([{}])/g, (m, b) => (b === '{' ? '\u0002' : '\u0003'));
  t = t.replace(/\\mathbb(?:\{([NZQRB])\}|\s+([NZQRB])(?![A-Za-z]))/g, (m, a, b) => blackboard[a ?? b]).replace(/\\dot-/g, '∸');
  const sym = (x) => x.replace(/\\([A-Za-z]+)/g, (m, c) => (c in symbols ? (/^[a-z]{2,}$/.test(symbols[c]) ? ` ${symbols[c]} ` : symbols[c]) : m));
  t = sym(t);
  const wrap = new RegExp(`\\\\(?:${wrappers})\\s*\\{([^{}]*)\\}`, 'g');
  for (let k = 0; k < 8 && wrap.test(t); k++) t = t.replace(wrap, '$1');
  const arg = (x) => { const y = x.replace(/^\{|\}$/g, '').trim(); return /^[\p{L}\p{N}.]+$/u.test(y) ? y : `(${y})`; };
  const two = '\\s*(\\{[^{}]*\\}|[\\p{L}\\p{N}])\\s*(\\{[^{}]*\\}|[\\p{L}\\p{N}])';
  t = t.replace(new RegExp(`\\\\[dt]?frac${two}`, 'gu'), (m, a, b) => `${arg(a)}/${arg(b)}`);
  t = t.replace(new RegExp(`\\\\binom${two}`, 'gu'), (m, a, b) => `choose(${arg(a).replace(/^\((.*)\)$/, '$1')}, ${arg(b).replace(/^\((.*)\)$/, '$1')})`);
  t = t.replace(/\\sqrt\s*(\{[^{}]*\}|\w)/g, (m, a) => `√${arg(a)}`);
  t = t.replace(/\\([_#%&])/g, '$1').replace(/\\!/g, '').replace(/\\[,;: ]|~/g, ' ');
  t = sym(t);
  if (t.includes('\\')) return null;
  t = t.replace(/([_^])\{([^{}]*)\}/g, (m, op, x) => (/^[\p{L}\p{N}']+$/u.test(x.trim()) ? op + x.trim() : `${op}(${x.trim()})`));
  if (/[{}]/.test(t.replace(/\{([^{}]*)\}/g, '$1'))) return null;
  t = t.replace(/\{([^{}]*)\}/g, '$1').replace(/\u0002/g, '{').replace(/\u0003/g, '}');
  t = t.replace(/\s+/g, ' ').replace(/\( /g, '(').replace(/ \)/g, ')').replace(/ ([_^])/g, '$1')
    .replace(/\b(max|min|log|sup|inf|lim) \(/g, '$1(').replace(/\[ \]/g, '[]').trim();
  if (t === '' || /[`$]/.test(t)) return null;
  return t;
}

const leadIn = /(?:,?[ \t]*\b(?:i\.e\.|e\.g\.|that is|namely)[ \t]*[,:]?|[ \t]*:)$/i;
const continuation = /^(?:where|with|so that|so|that is|that|for|in|and|i\.e\.|which|hence|thus) /;

// The end of the sentence that starts at `i`: after its period, or at a blank line; math and code spans are skipped.
function clauseEnd(body, i) {
  let j = i;
  while (j < body.length) {
    const c = body[j];
    if (c === '\\') { j += 2; continue; }
    if (c === '`' || c === '$') {
      const run = new RegExp(`^\\${c}+`).exec(body.slice(j))[0];
      const e = body.indexOf(run, j + run.length);
      j = e < 0 ? body.length : e + run.length; continue;
    }
    if (c === '.' && (j + 1 === body.length || /\s/.test(body[j + 1]))) return j + 1;
    if (c === '\n' && /^\n[ \t]*\n/.test(body.slice(j))) return j;
    j++;
  }
  return j;
}

// `out` without trailing blanks and without a lead-in (`i.e.`, `:`) that introduced removed math. With `stop`, a
// sentence whose lead-in went gets a period.
function dropLeadIn(out, stop) {
  const bare = out.replace(/[ \t]+$/, '');
  const m = leadIn.exec(bare);
  if (!m) return stop ? endSentence(bare) : bare;
  const kept = bare.slice(0, m.index).replace(/[ \t]+$/, '');
  return stop && /[\p{L}\p{N})`'"]$/u.test(kept) ? kept + '.' : kept;
}

// A paragraph that ran into removed block math ends at its last full sentence, else gets a period.
function endSentence(text) {
  if (!/[\p{L}\p{N},;]$/u.test(text)) return text;
  const para = text.lastIndexOf('\n\n') + 1;
  const cut = Math.max(text.lastIndexOf('. '), text.lastIndexOf('.\n'), text.lastIndexOf('; '), text.lastIndexOf(';\n'));
  if (cut >= para && cut > 0) return text.slice(0, cut) + '.';
  return text.replace(/[,;]$/, '') + '.';
}

// The doc body with its math removed; the text around each removal is tidied, nothing else changes.
function stripMath(body) {
  let out = '';
  let i = 0;
  const n = body.length;
  while (i < n) {
    const c = body[i];
    if (c === '\\' && body[i + 1] === '$') { out += '\\$'; i += 2; continue; }
    if (c === '`') {
      const run = /^`+/.exec(body.slice(i))[0];
      const e = body.indexOf(run, i + run.length);
      const end = e < 0 ? i + run.length : e + run.length;
      out += body.slice(i, end); i = end; continue;
    }
    if (body.startsWith('$$', i)) {
      const e = body.indexOf('$$', i + 2);
      if (e < 0) { out += body.slice(i); i = n; continue; }
      i = e + 2;
      const outNl = (/\s*$/.exec(out)[0].match(/\n/g) || []).length;
      out = dropLeadIn(out.replace(/\s+$/, ''), true);
      let ws = /^\s*/.exec(body.slice(i))[0];
      i += ws.length;
      const atStart = out === '' || /[.!?]$/.test(out) || outNl > 0 || ws.includes('\n');
      while (atStart && continuation.test(body.slice(i, i + 16))) {
        const end = clauseEnd(body, i);
        if (!/(^|[^\\])\$/.test(body.slice(i, end).replace(/`+[^`]*`+/g, ''))) break;
        const more = /^\s*/.exec(body.slice(end))[0];
        if (more.includes('\n')) ws += more;
        i = end + more.length;
      }
      const nl = Math.min(2, Math.max(outNl, (ws.match(/\n/g) || []).length));
      const indent = ws.includes('\n') ? ws.slice(ws.lastIndexOf('\n') + 1) : '';
      if (i < n) out += nl ? '\n'.repeat(nl) + indent : (out && !/^[.,;:)]/.test(body[i]) ? ' ' : '');
      if (atStart && body.startsWith('where ', i)) { out += 'Here '; i += 'where '.length; continue; }
      if (atStart && /[a-z]/.test(body[i] ?? '') && !/^[a-z][\w.]*\(/.test(body.slice(i))) {
        out += body[i].toUpperCase(); i++;
      }
      continue;
    }
    if (c === '$') {
      const m = /^((?:[^$\\\n]|\\.|\n(?![ \t]*\n))+?)\$/.exec(body.slice(i + 1));
      if (!m) { out += c; i++; continue; }
      i += m[0].length + 1;
      const plain = plainInline(m[1]);
      if (plain !== null) { out += '`' + plain + '`'; continue; }
      out = dropLeadIn(out, false);
      i += /^[ \t]*/.exec(body.slice(i))[0].length;
      if (out.endsWith('(') && body[i] === ')') { out = out.slice(0, -1).replace(/[ \t]+$/, ''); i++; }
      const next = body[i] ?? '';
      if (out && !/\s$/.test(out) && next && !/[\s.,;:)!?]/.test(next)) out += ' ';
      continue;
    }
    out += c; i++;
  }
  return out;
}

// The doc comment without its math; '' when no prose is left.
export function stripDoc(doc) {
  const open = doc.slice(0, 3);
  const body = doc.slice(3, -2);
  if (!body.includes('$')) return doc;
  const stripped = stripMath(body);
  if (stripped === body) return doc;
  const t = stripped.replace(/^\s+/, '').replace(/\s+$/, '');
  if (!/[\p{L}\p{N}]/u.test(t)) return '';
  if (/^(?:formally|in symbols|explicitly|concretely|precisely|that is|i\.e\.)[.:,]?$/i.test(t)) return '';
  const leadWs = /^\s*/.exec(body)[0];
  const lead = leadWs.includes('\n') ? '\n' + leadWs.slice(leadWs.lastIndexOf('\n') + 1) : ' ';
  const tailIndent = /\n([ \t]*)$/.exec(body);
  const multi = t.includes('\n') || lead !== ' ';
  const tail = multi && tailIndent ? '\n' + tailIndent[1] : ' ';
  return open + lead + t + tail + '-/';
}

// The Lean source with every doc comment stripped; a deleted doc comment takes its own line with it.
export function strip(src) {
  const parts = split(src);
  let out = '';
  let eatLine = false;
  for (const p of parts) {
    if (p.kind === 'code') {
      let text = p.text;
      if (eatLine) {
        const m = /^[ \t]*\n/.exec(text);
        if (m && eatLine === 'line') text = text.slice(m[0].length);
        else text = text.replace(/^[ \t]+/, '');
        eatLine = false;
      }
      out += text; continue;
    }
    const s = stripDoc(p.text);
    if (s !== '') { out += s; continue; }
    const lineStart = out.lastIndexOf('\n') + 1;
    if (/^[ \t]*$/.test(out.slice(lineStart))) { out = out.slice(0, lineStart); eatLine = 'line'; } else eatLine = 'space';
  }
  return out;
}

// The number of `$$` inside the doc comments of a Lean source (a `$$` in code, such as a shell pid in a string, is no math).
export const docDollarBlocks = (src) =>
  split(src).filter((p) => p.kind === 'doc').reduce((k, p) => k + (p.text.match(/\$\$/g) || []).length, 0);

function main(argv) {
  const check = argv[0] === '--check';
  const files = check ? argv.slice(1) : argv;
  let bad = 0;
  for (const f of files) {
    const src = readFileSync(f, 'utf8');
    if (check) {
      const k = docDollarBlocks(src);
      if (k > 0) { console.log(`latex-strip: ${f}: ${k} $$ left in doc comments`); bad++; }
      continue;
    }
    if (/^-- GENERATED/.test(src)) { console.log(`latex-strip: ${f}: generated, skipped`); continue; }
    const out = strip(src);
    if (out !== src) writeFileSync(f, out);
  }
  if (check && bad > 0) { console.log(`latex-strip: ${bad} file(s) still hold $$`); return 1; }
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main(process.argv.slice(2)));
