#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSync } from 'vite';

const siteDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.resolve(siteDir, '../..');
const partsDir = path.join(siteDir, 'src/parts');
const appFile = path.join(siteDir, 'src/App.tsx');
const goldenPath = path.join(repo, 'packages/contracts/golden/parts/footprint.gen.json');
const leanPath = path.join(repo, 'lean/Fw/Parts/FootprintData.lean');

const SKIP = /\.(test|testutil|golden\.test)\.tsx?$|\.d\.ts$/;
const partIds = fs.readdirSync(partsDir).filter((d) => fs.statSync(path.join(partsDir, d)).isDirectory()).sort();

const DRIVERS = new Set(partIds.filter((p) => !fs.readdirSync(path.join(partsDir, p)).some((f) => f.endsWith('.tsx') && !SKIP.test(f))));
const partAt = (file) => (DRIVERS.has(folderOf(file.abs)) ? folderOf(file.abs) : cur.part);
const rel = (f) => path.relative(partsDir, f).split(path.sep).join('/');
const folderOf = (f) => (f === appFile ? 'app' : rel(f).split('/')[0]);

const files = new Map();
function lineStarts(text) {
  const s = [0];
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) s.push(i + 1);
  return s;
}
function lineOf(file, off) {
  const s = file.lines;
  let lo = 0;
  let hi = s.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (s[mid] <= off) lo = mid;
    else hi = mid - 1;
  }
  return lo + 1;
}
function loadTs(abs) {
  if (files.has(abs)) return files.get(abs);
  const text = fs.readFileSync(abs, 'utf8');
  const res = parseSync(abs, text, { lang: abs.endsWith('.tsx') ? 'tsx' : 'ts' });
  if (res.errors.length) throw new Error(`parse error in ${abs}: ${res.errors[0].message}`);
  const f = { abs, text, lines: lineStarts(text), program: res.program, kind: 'ts', imports: new Map(), top: null };
  files.set(abs, f);
  return f;
}
function resolveImport(from, spec) {
  if (!spec.startsWith('.')) return null;
  const base = path.resolve(path.dirname(from), spec);
  for (const c of [base, `${base}.ts`, `${base}.tsx`, path.join(base, 'index.tsx'), path.join(base, 'index.ts')]) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) return c;
  }
  return null;
}
const isEntry = (abs) => path.basename(abs) === 'index.tsx' || path.basename(abs) === 'index.ts';
const inParts = (abs) => abs.startsWith(partsDir + path.sep);

const SKIPKEYS = new Set(['type', 'start', 'end', 'range', 'loc', 'typeAnnotation', 'returnType', 'typeParameters', 'typeArguments', 'decorators']);
function children(node) {
  const out = [];
  for (const k of Object.keys(node)) {
    if (SKIPKEYS.has(k)) continue;
    const v = node[k];
    if (Array.isArray(v)) {
      for (const x of v) if (x && typeof x.type === 'string') out.push(x);
    } else if (v && typeof v.type === 'string') out.push(v);
  }
  return out;
}
const isFn = (n) => n && (n.type === 'ArrowFunctionExpression' || n.type === 'FunctionExpression' || n.type === 'FunctionDeclaration');
function strip(n) {
  while (n && ['TSAsExpression', 'TSNonNullExpression', 'TSSatisfiesExpression', 'TSTypeAssertion', 'ParenthesizedExpression', 'ChainExpression'].includes(n.type)) n = n.expression;
  return n;
}
const propName = (m) => (m.computed ? (m.property.type === 'Literal' ? String(m.property.value) : null) : m.property.name);
const kebab = (s) => s.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

const UNKNOWN = { k: 'unknown' };
const el = (owners, sel) => ({ k: 'el', owners: [...new Set(owners)].sort(), sel });
function union(a, b) {
  if (!a) return b;
  if (!b) return a;
  if (a.k === 'el' && b.k === 'el') return el([...a.owners, ...b.owners], a.sel ?? b.sel);
  if (a.k === 'str' && b.k === 'str') return { k: 'str', vs: [...new Set([...a.vs, ...b.vs])] };
  if (a.k === 'anim' && b.k === 'anim') return { k: 'anim', owners: [...new Set([...a.owners, ...b.owners])].sort() };
  if (CLASS_KINDS.has(a.k) || CLASS_KINDS.has(b.k)) return { k: 'calt', v: classUnion(classValue(a), classValue(b)) };
  if (a.k === 'unknown') return b;
  if (b.k === 'unknown') return a;
  return a;
}
const CLASS_KINDS = new Set(['cls', 'calt']);

const elements = [];
function jsxAttrValue(a) {
  if (!a.value) return { lit: '' };
  if (a.value.type === 'Literal') return { lit: String(a.value.value) };
  if (a.value.type === 'JSXExpressionContainer') {
    const e = strip(a.value.expression);
    if (e.type === 'Literal') return { lit: String(e.value) };
    if (e.type === 'TemplateLiteral' && e.expressions.length === 0) return { lit: e.quasis.map((q) => q.value.cooked).join('') };
    return { expr: e };
  }
  return { expr: a.value };
}
function jsxName(n) {
  if (n.type === 'JSXIdentifier') return n.name;
  if (n.type === 'JSXNamespacedName') return `${n.namespace.name}:${n.name.name}`;
  if (n.type === 'JSXMemberExpression') return `${jsxName(n.object)}.${n.property.name}`;
  return '?';
}
const propOverrides = new Map();
const nestedJsx = new Set();
function collectElements(file) {
  const owner = folderOf(file.abs);
  const visit = (n, inJsx, scope) => {
    if (isFn(n)) {
      scope = new Scope(scope, file);
      for (const p of n.params) bindPattern(scope, p, () => UNKNOWN, 'param');
    } else if (n.type === 'BlockStatement') {
      scope = new Scope(scope, file);
      hoist(n.body, scope);
    }
    if (n.type === 'JSXElement' && inJsx) nestedJsx.add(n.openingElement);
    if (n.type === 'JSXOpeningElement') {
      const tag = jsxName(n.name);
      if (tag !== 'Fragment' && tag !== 'React.Fragment') {
        const attrs = new Map();
        const classes = new Set();
        let spread = false;
        let open = false;
        for (const a of n.attributes) {
          if (a.type !== 'JSXAttribute') { spread = true; continue; }
          const name = jsxName(a.name);
          const v = jsxAttrValue(a);
          if (name === 'className') {
            if (v.lit !== undefined) literalClasses(v.lit).forEach((c) => classes.add(c));
            else {
              const ts = collectClassTokens(v.expr, classEnv(scope, staticMemberClass));
              ts.forEach((c) => c.op === 'setClass' && classes.add(c.name));
              open ||= isOpenElement(ts);
            }
          } else attrs.set(name, v.lit !== undefined ? v.lit : null);
          const target = /^[A-Z]/.test(tag) && v.lit !== undefined ? componentFolder(tag, file) : null;
          if (target) {
            const key = `${target}.${name}`;
            propOverrides.set(key, [...new Set([...(propOverrides.get(key) ?? []), v.lit])]);
          }
        }
        elements.push({ owner, file: rel(file.abs), line: lineOf(file, n.start), tag: tag === 'Box' ? 'div' : tag, attrs, classes, spread, open });
      }
    }
    const jsxNow = inJsx || n.type === 'JSXElement' || n.type === 'JSXFragment';
    for (const c of children(n)) visit(c, jsxNow, scope);
  };
  visit(file.program, false, topScope(file));
}
const runtimeKeys = new Set();
function addRuntimeElements(acc) {
  const before = runtimeKeys.size;
  for (const a of acc) {
    const k = `${a.op}|${a.name}|${a.owner}`;
    if (runtimeKeys.has(k)) continue;
    runtimeKeys.add(k);
    if (!a.owner || a.owner === '?' || a.owner === 'document' || a.owner.endsWith('^')) continue;
    if (a.op === 'setAttr') elements.push({ owner: a.owner, file: a.file, line: a.line, tag: '*', attrs: new Map([[a.name, null]]), classes: new Set(), runtime: true });
    if (a.op === 'setClass' && a.name !== '*' && a.name !== '?') elements.push({ owner: a.owner, file: a.file, line: a.line, tag: '*', attrs: new Map(), classes: new Set([a.name]), runtime: true });
  }
  return runtimeKeys.size !== before;
}

function splitTop(s, seps) {
  const out = [];
  let depth = 0;
  let q = null;
  let cur = '';
  for (const ch of s) {
    if (q) { cur += ch; if (ch === q) q = null; continue; }
    if (ch === '"' || ch === "'") { q = ch; cur += ch; continue; }
    if (ch === '(' || ch === '[') depth++;
    if (ch === ')' || ch === ']') depth--;
    if (depth === 0 && seps.includes(ch)) { out.push(cur); cur = ''; continue; }
    cur += ch;
  }
  out.push(cur);
  return out.map((x) => x.trim()).filter(Boolean);
}
function parseCompound(c) {
  const r = { tag: null, id: null, classes: [], attrs: [], universal: false };
  let i = 0;
  const ident = () => {
    const m = /^-?[_a-zA-Z0-9-]+/.exec(c.slice(i));
    i += m ? m[0].length : 0;
    return m ? m[0] : '';
  };
  if (c[0] === '*') { r.universal = true; i = 1; } else if (/[a-zA-Z]/.test(c[0] ?? '')) r.tag = ident();
  while (i < c.length) {
    const ch = c[i];
    if (ch === '#') { i++; r.id = ident(); }
    else if (ch === '.') { i++; r.classes.push(ident()); }
    else if (ch === '[') {
      const end = c.indexOf(']', i);
      const body = c.slice(i + 1, end);
      const m = /^([a-zA-Z0-9_:-]+)\s*(?:([~|^$*]?=)\s*["']?([^"'\]]*)["']?)?/.exec(body);
      r.attrs.push({ name: m[1], op: m[2] ?? null, value: m[3] ?? null });
      i = end + 1;
    } else if (ch === ':') {
      i++;
      if (c[i] === ':') i++;
      ident();
      if (c[i] === '(') {
        let d = 0;
        for (; i < c.length; i++) { if (c[i] === '(') d++; if (c[i] === ')') { d--; if (d === 0) { i++; break; } } }
      }
    } else i++;
  }
  return r;
}
const HOLE = '\u0001';
function valueMatches(pattern, v) {
  if (!pattern.includes(HOLE)) return pattern === v;
  const re = new RegExp(`^${pattern.split(HOLE).map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*')}$`);
  return re.test(v);
}
function classMatchOf(sel, e) {
  const has = (c) => e.classes.has(c) || (c.includes(HOLE) && [...e.classes].some((x) => valueMatches(c, x)));
  return classMatch(has, sel.classes, Boolean(e.open));
}
function matchElement(sel, e) {
  if (sel.tag && e.tag !== '*' && sel.tag !== e.tag) return false;
  if (sel.id && !(e.spread && !e.attrs.has('id')) && !(e.attrs.has('id') && (e.attrs.get('id') === null || valueMatches(sel.id, e.attrs.get('id'))))) return false;
  if (classMatchOf(sel, e) === 'none') return false;
  for (const a of sel.attrs) {
    if (!e.attrs.has(a.name)) { if (e.spread) continue; return false; }
    const v = e.attrs.get(a.name);
    if (a.op === '=' && v !== null && !valueMatches(a.value, v)) return false;
  }
  return true;
}
function literalMatch(sel, e) {
  if (sel.id && e.attrs.get('id') == null) return false;
  return sel.attrs.every((a) => a.op !== '=' || e.attrs.get(a.name) != null);
}
function matchOwners(compound, within) {
  const pool = within ? elements.filter((e) => within.includes(e.owner)) : elements;
  const cands = pool.filter((e) => matchElement(compound, e)).map((e) => [e.owner, classStrength(Boolean(e.spread), literalMatch(compound, e), classMatchOf(compound, e))]);
  const { owners: hit, weak } = pickOwners(cands);
  matchOwners.weak = weak;
  return hit.length || !within ? hit : matchOwners(compound, null);
}
function resolveSelector(s, site) {
  if (s.includes(HOLE)) finding(site, 'templated-selector', s);
  const owners = [];
  const alts = splitTop(s, [',']);
  const dead = [];
  for (const alt of alts) {
    const compounds = splitTop(alt.replace(/\s*([>+~])\s*/g, ' '), [' ']);
    const last = parseCompound(compounds[compounds.length - 1] ?? '');
    if (last.universal && !last.id && !last.classes.length && !last.attrs.length) {
      finding(site, 'universal-selector', alt);
      owners.push('?');
      continue;
    }
    const hit = matchOwners(last);
    if (matchOwners.weak && !alt.includes(HOLE)) finding(site, 'dynamic-match', `${alt} matches only dynamic or spread attributes of ${[...new Set(hit)].sort().join(' ')}`);
    if (hit.length === 0) dead.push(alt);
    owners.push(...hit);
  }
  if (dead.length === alts.length) finding(site, 'dead-selector', s);
  else for (const d of dead) finding(site, 'dead-alternative', `${d} in ${s}`);
  return el(owners, s);
}

const accesses = new Map();
const findings = new Map();
let cur = null;
function site(node) {
  return { part: partAt(cur.file), file: rel(cur.file.abs), line: lineOf(cur.file, node.start) };
}
function finding(s, kind, detail) {
  const d = detail.replace(/\s+/g, ' ').replaceAll(HOLE, '*');
  const key = `${s.part}\u0000${s.file}\u0000${String(s.line).padStart(5, '0')}\u0000${kind}\u0000${d}`;
  findings.set(key, { part: s.part, file: s.file, line: s.line, kind, detail: d });
}
function emit(node, op, name, owner, ctxTag) {
  const s = site(node);
  if (name.includes(HOLE)) {
    finding(s, 'templated-name', `${op} ${name}`);
    name = name.replaceAll(HOLE, '*');
  }
  if (name === '?') finding(s, 'dynamic-name', op);
  const key = `${s.part}\u0000${s.file}\u0000${String(s.line).padStart(5, '0')}\u0000${op}\u0000${name}\u0000${owner}\u0000${ctxTag}`;
  accesses.set(key, { ...s, op, name, owner, ctx: ctxTag });
}
function emitOn(node, op, name, v, ctxTag) {
  if (!v || v.k === 'unknown') {
    finding(site(node), 'unresolved-target', `${op}${name ? ` ${name}` : ''}`);
    emit(node, op, name, '?', ctxTag);
    return;
  }
  if (v.k === 'win' || v.k === 'doc') return emit(node, op, name, 'document', ctxTag);
  if (v.k === 'el') {
    if (v.owners.length === 0) emit(node, op, name, '', ctxTag);
    for (const o of v.owners) emit(node, op, name, o, ctxTag);
  }
}

export class Scope {
  constructor(parent, file) { this.parent = parent; this.file = file; this.vars = new Map(); }
  lookup(name) {
    for (let s = this; s; s = s.parent) if (s.vars.has(name)) return { scope: s, b: s.vars.get(name) };
    return null;
  }
}
function bindPattern(scope, pat, thunk, kind = 'var') {
  pat = strip(pat);
  if (!pat) return;
  if (pat.type === 'Identifier') scope.vars.set(pat.name, { thunk, kind });
  else if (pat.type === 'AssignmentPattern') bindPattern(scope, pat.left, () => union(thunk(), valueOf(pat.right, scope)), kind);
  else if (pat.type === 'ObjectPattern') {
    for (const p of pat.properties) {
      if (p.type === 'RestElement') { bindPattern(scope, p.argument, () => UNKNOWN, kind); continue; }
      const key = p.computed ? null : p.key.name ?? p.key.value;
      bindPattern(scope, p.value, () => { const o = thunk(); return o.k === 'obj' && o.props.has(key) ? o.props.get(key)() : UNKNOWN; }, kind);
    }
  } else if (pat.type === 'ArrayPattern') {
    pat.elements.forEach((p, i) => p && bindPattern(scope, p, () => { const o = thunk(); return o.k === 'state' ? (i === 0 ? { k: 'stateVal' } : UNKNOWN) : o.k === 'els' ? el(o.owners) : UNKNOWN; }, kind));
  } else if (pat.type === 'RestElement') bindPattern(scope, pat.argument, () => UNKNOWN, kind);
}
function memo(fn) {
  let done = false;
  let v;
  let busy = false;
  return () => {
    if (done) return v;
    if (busy) return UNKNOWN;
    busy = true;
    v = fn();
    busy = false;
    done = true;
    return v;
  };
}
function hoist(stmts, scope) {
  for (let st of stmts) {
    if (st.type === 'ExportNamedDeclaration' || st.type === 'ExportDefaultDeclaration') st = st.declaration ?? st;
    if (!st) continue;
    if (st.type === 'VariableDeclaration') {
      for (const d of st.declarations) {
        bindPattern(scope, d.id, memo(() => (d.init ? valueOf(d.init, scope) : UNKNOWN)), st.kind);
        if (st.kind === 'const' && d.id.type === 'Identifier' && d.init) scope.vars.get(d.id.name).init = d.init;
      }
    } else if (st.type === 'FunctionDeclaration' && st.id) {
      scope.vars.set(st.id.name, { thunk: () => ({ k: 'fn', node: st, scope }), kind: 'fn' });
    } else if (st.type === 'ImportDeclaration') {
      const target = resolveImport(scope.file.abs, st.source.value);
      for (const sp of st.specifiers) {
        const local = sp.local.name;
        if (target && target.endsWith('.css')) { scope.vars.set(local, { thunk: () => ({ k: 'cssmod', file: target }), kind: 'import', css: target }); continue; }
        if (!target || !inParts(target) && target !== appFile) {
          const src = st.source.value;
          scope.vars.set(local, { thunk: () => ({ k: 'ext', name: sp.imported?.name ?? local, src }), kind: 'import' });
          continue;
        }
        const name = sp.type === 'ImportDefaultSpecifier' ? 'default' : sp.imported?.name ?? sp.imported?.value;
        scope.vars.set(local, { thunk: () => exportOf(target, name), kind: 'import' });
      }
    }
  }
}
function topScope(f) {
  if (!f.top) {
    f.top = new Scope(null, f);
    hoist(f.program.body, f.top);
  }
  return f.top;
}
function exportOf(abs, name) {
  if (!abs.endsWith('.ts') && !abs.endsWith('.tsx')) return UNKNOWN;
  const f = loadTs(abs);
  const sc = topScope(f);
  if (name === 'default') {
    const d = f.program.body.find((s) => s.type === 'ExportDefaultDeclaration');
    return d ? (isFn(d.declaration) ? { k: 'fn', node: d.declaration, scope: sc } : valueOf(d.declaration, sc)) : UNKNOWN;
  }
  const r = sc.lookup(name);
  return r ? r.b.thunk() : UNKNOWN;
}
const ELEMENT_PROPS = new Set(['parentElement', 'parentNode', 'firstElementChild', 'lastElementChild', 'nextElementSibling', 'previousElementSibling', 'offsetParent']);
const OBSERVERS = new Set(['IntersectionObserver', 'ResizeObserver', 'MutationObserver']);
function valueOf(n, scope) {
  n = strip(n);
  if (!n) return UNKNOWN;
  switch (n.type) {
    case 'Literal':
      return typeof n.value === 'string' ? { k: 'str', vs: [n.value] } : typeof n.value === 'number' ? { k: 'num', v: n.value } : UNKNOWN;
    case 'TemplateLiteral':
      return { k: 'str', vs: [n.quasis.map((q, i) => {
        if (i === n.expressions.length) return q.value.cooked;
        const v = valueOf(n.expressions[i], scope);
        return q.value.cooked + (v.k === 'str' && v.vs.length === 1 ? v.vs[0] : v.k === 'num' ? String(v.v) : HOLE);
      }).join('')] };
    case 'Identifier': {
      if (n.name === 'window' || n.name === 'globalThis') return { k: 'win' };
      if (n.name === 'document') return { k: 'doc' };
      const r = scope.lookup(n.name);
      return r ? r.b.thunk() : UNKNOWN;
    }
    case 'ArrowFunctionExpression':
    case 'FunctionExpression':
      return { k: 'fn', node: n, scope };
    case 'ObjectExpression': {
      const props = new Map();
      for (const p of n.properties) {
        if (p.type === 'SpreadElement') {
          const o = valueOf(p.argument, scope);
          if (o.k === 'obj') for (const [k, t] of o.props) props.set(k, t);
          continue;
        }
        if (p.type !== 'Property' || p.computed) continue;
        const key = p.key.name ?? p.key.value;
        props.set(key, memo(() => valueOf(p.value, scope)));
      }
      return { k: 'obj', props };
    }
    case 'ConditionalExpression':
      return union(valueOf(n.consequent, scope), valueOf(n.alternate, scope));
    case 'LogicalExpression':
      return union(valueOf(n.left, scope), valueOf(n.right, scope));
    case 'MemberExpression': {
      const o = valueOf(n.object, scope);
      const p = propName(n);
      if (o.k === 'obj' && p === null) return [...o.props.values()].reduce((acc, t) => union(acc, t()), null) ?? UNKNOWN;
      if (o.k === 'obj') return o.props.has(p) ? o.props.get(p)() : UNKNOWN;
      if (o.k === 'ref' && p === 'current') return o.target;
      if (o.k === 'cssmod') return { k: 'cls', file: o.file, local: p };
      if (o.k === 'doc' && (p === 'documentElement' || p === 'body' || p === 'scrollingElement')) return { k: 'doc' };
      if (o.k === 'win' && p === 'document') return { k: 'doc' };
      if (o.k === 'el' && o.nested && (p === 'parentElement' || p === 'parentNode')) return el(o.owners, o.sel);
      if (o.k === 'el' && ELEMENT_PROPS.has(p)) return el(o.owners.map((x) => `${x}^`), o.sel);
      if (o.k === 'els' && n.computed) return el(o.owners, o.sel);
      if (o.k === 'el' && n.computed) return o;
      return UNKNOWN;
    }
    case 'CallExpression': {
      const c = strip(n.callee);
      if (c.type === 'Identifier' && (c.name === 'useRef' || c.name === 'createRef')) return { k: 'ref', target: refTarget(n, scope) };
      if (c.type === 'Identifier' && c.name === 'useState') return { k: 'state' };
      if (c.type === 'Identifier' && c.name === 'getClock') return { k: 'clock' };
      if (c.type === 'Identifier' && (c.name === 'matchList' || c.name === 'matchMedia')) return { k: 'mql' };
      if (c.type === 'Identifier' && c.name === 'getComputedStyle') return UNKNOWN;
      if (c.type === 'MemberExpression') {
        const m = propName(c);
        const o = valueOf(c.object, scope);
        if (m === 'matchMedia') return { k: 'mql' };
        if ((m === 'createElement' || m === 'createElementNS' || m === 'createTextNode') && o.k === 'doc') return el([folderOf(scope.file.abs)]);
        if (['querySelector', 'closest', 'getElementById', 'querySelectorAll', 'getElementsByClassName'].includes(m)) {
          const a = valueOf(n.arguments[0], scope);
          if (a.k !== 'str') return UNKNOWN;
          const sel = m === 'getElementById' ? a.vs.map((x) => `#${x}`).join(', ') : m === 'getElementsByClassName' ? a.vs.map((x) => `.${x}`).join(', ') : a.vs.join(', ');
          const within = (o.k === 'el' || o.k === 'els') && (m === 'querySelector' || m === 'querySelectorAll') && o.owners.every((x) => partIds.includes(x)) ? o.owners : null;
          const owners = splitTop(sel, [',']).flatMap((alt) => { const cs = splitTop(alt.replace(/\s*([>+~])\s*/g, ' '), [' ']); return matchOwners(parseCompound(cs[cs.length - 1]), within); });
          return m === 'querySelectorAll' || m === 'getElementsByClassName' ? { k: 'els', owners: [...new Set(owners)], sel } : el(owners, sel);
        }
        if (m === 'animate') return o.k === 'el' ? { k: 'anim', owners: o.owners } : UNKNOWN;
        if (m === 'getAnimations') return { k: 'arr', item: o.k === 'el' ? { k: 'anim', owners: o.owners } : UNKNOWN };
        if (m === 'from' && c.object.type === 'Identifier' && c.object.name === 'Array') return valueOf(n.arguments[0], scope);
        if (['filter', 'slice', 'concat'].includes(m) && (o.k === 'els')) return o;
        if (['find', 'at', 'item'].includes(m) && o.k === 'els') return el(o.owners, o.sel);
        if (['find', 'at'].includes(m) && o.k === 'arr') return o.item;
      }
      const f = valueOf(c, scope);
      if (f.k === 'fn') return returnValue(f, n.arguments, scope);
      return UNKNOWN;
    }
    case 'NewExpression': {
      const c = strip(n.callee);
      if (c.type === 'Identifier' && OBSERVERS.has(c.name)) return { k: 'observer', kind: c.name, cb: n.arguments[0] ? valueOf(n.arguments[0], scope) : null };
      return UNKNOWN;
    }
    case 'ArrayExpression': {
      let item = null;
      for (const x of n.elements) {
        if (!x) continue;
        const v = valueOf(x.type === 'SpreadElement' ? x.argument : x, scope);
        item = union(item, x.type !== 'SpreadElement' ? v : v.k === 'els' ? el(v.owners, v.sel) : v.k === 'arr' ? v.item : UNKNOWN);
      }
      if (item && item.k === 'el') return { k: 'els', owners: item.owners, sel: item.sel };
      return { k: 'arr', item: item ?? UNKNOWN };
    }
    case 'AwaitExpression':
      return valueOf(n.argument, scope);
    default:
      return UNKNOWN;
  }
}
const retDepth = { n: 0 };
function returnValue(f, args, callerScope) {
  if (retDepth.n > 6) return UNKNOWN;
  retDepth.n++;
  try {
    const sc = new Scope(f.scope, f.scope.file);
    f.node.params.forEach((p, i) => bindPattern(sc, p, memo(() => (args[i] ? valueOf(args[i], callerScope) : UNKNOWN))));
    const body = f.node.body;
    if (body.type !== 'BlockStatement') return valueOf(body, sc);
    hoist(body.body, sc);
    let v = null;
    const visit = (s) => {
      if (!s || isFn(s)) return;
      if (s.type === 'ReturnStatement' && s.argument) v = union(v, valueOf(s.argument, sc));
      for (const c of children(s)) if (!isFn(c) && c.type.endsWith('Statement') || c.type === 'SwitchCase' || c.type === 'BlockStatement') visit(c);
    };
    body.body.forEach(visit);
    return v ?? UNKNOWN;
  } finally {
    retDepth.n--;
  }
}
function refTarget(call, scope) {
  const f = scope.file;
  let name = null;
  const findDecl = (n) => {
    if (name) return;
    if (n.type === 'VariableDeclarator' && n.init && strip(n.init) === call && n.id.type === 'Identifier') name = n.id.name;
    for (const c of children(n)) findDecl(c);
  };
  findDecl(f.program);
  if (!name) return UNKNOWN;
  let owners = null;
  let nested = true;
  const visit = (n) => {
    if (n.type === 'JSXOpeningElement') {
      for (const a of n.attributes) {
        if (a.type !== 'JSXAttribute' || jsxName(a.name) !== 'ref' || !a.value || a.value.type !== 'JSXExpressionContainer') continue;
        const e = strip(a.value.expression);
        if (e.type === 'Identifier' && e.name === name) {
          const tag = jsxName(n.name);
          if (!nestedJsx.has(n) || !/^[a-z]/.test(tag)) nested = false;
          owners = [...(owners ?? []), /^[a-z]/.test(tag) || tag === 'Box' ? folderOf(f.abs) : componentFolder(tag, f) ?? folderOf(f.abs)];
        }
      }
    }
    for (const c of children(n)) visit(c);
  };
  visit(f.program);
  const assigned = (n, fnStack) => {
    if (n.type === 'AssignmentExpression' && n.left.type === 'MemberExpression' && propName(n.left) === 'current' && strip(n.left.object).type === 'Identifier' && strip(n.left.object).name === name) {
      const r = strip(n.right);
      if (!(r.type === 'Literal' && r.value === null)) {
        const o = handlerTarget(r, fnStack, f, 0);
        if (o) { owners = [...(owners ?? []), ...o]; nested = false; } else unresolvedRefs.add(`${f.abs}|${name}`);
      }
    }
    const fs2 = isFn(n) ? [...fnStack, n] : fnStack;
    for (const c of children(n)) assigned(c, fs2);
  };
  assigned(f.program, []);
  if (unresolvedRefs.has(`${f.abs}|${name}`)) return UNKNOWN;
  return owners ? { ...el(owners), nested } : UNKNOWN;
}
const unresolvedRefs = new Set();
function handlerTarget(e, fnStack, f, d) {
  e = strip(e);
  if (e.type === 'MemberExpression' && (propName(e) === 'currentTarget' || propName(e) === 'target')) return [folderOf(f.abs)];
  if (e.type !== 'Identifier' || d > 2) return null;
  for (let i = fnStack.length - 1; i >= 0; i--) {
    const fn = fnStack[i];
    const idx = fn.params.findIndex((p) => strip(p).type === 'Identifier' && strip(p).name === e.name);
    if (idx < 0) continue;
    let fname = null;
    const findName = (n, stack) => {
      if (n.type === 'VariableDeclarator' && n.init && strip(n.init) === fn && n.id.type === 'Identifier') fname = { id: n.id.name, stack };
      const st = isFn(n) ? [...stack, n] : stack;
      if (!fname) for (const c of children(n)) findName(c, st);
    };
    findName(f.program, []);
    if (!fname && fn.type === 'FunctionDeclaration' && fn.id) fname = { id: fn.id.name };
    if (!fname) return null;
    const out = [];
    let bad = false;
    const calls = (n, stack) => {
      if (n.type === 'CallExpression' && strip(n.callee).type === 'Identifier' && strip(n.callee).name === fname.id) {
        const o = n.arguments[idx] ? handlerTarget(n.arguments[idx], stack, f, d + 1) : null;
        if (o) out.push(...o); else bad = true;
      }
      const st = isFn(n) ? [...stack, n] : stack;
      for (const c of children(n)) calls(c, st);
    };
    calls(f.program, []);
    return bad || out.length === 0 ? null : out;
  }
  return null;
}
function componentFolder(tag, f) {
  const r = topScope(f).lookup(tag);
  if (!r) return null;
  for (const st of f.program.body) {
    if (st.type !== 'ImportDeclaration') continue;
    if (st.specifiers.some((sp) => sp.local.name === tag)) {
      const t = resolveImport(f.abs, st.source.value);
      return t && inParts(t) ? folderOf(t) : null;
    }
  }
  return null;
}

const done = new Set();
const pending = [];
const fallback = [];
const fnKey = (f) => `${partAt(f.scope.file)}|${f.scope.file.abs}|${f.node.start}`;
function drain() {
  for (;;) {
    while (pending.length) pending.shift()();
    const f = fallback.shift();
    if (!f) return;
    if (!analyzedFns.has(fnKey(f))) analyzeFn(f, 'callback', null, f.scope);
  }
}
let depth = 0;
const EFFECTS = new Set(['useEffect', 'useLayoutEffect', 'useInsertionEffect']);
const ARRAY_SYNC = new Set(['forEach', 'map', 'filter', 'some', 'every', 'find', 'findIndex', 'reduce', 'flatMap', 'sort']);
const RECT_PROPS = new Set(['offsetTop', 'offsetLeft', 'offsetWidth', 'offsetHeight', 'clientWidth', 'clientHeight', 'clientTop', 'clientLeft', 'scrollWidth', 'scrollHeight', 'scrollTop', 'scrollLeft']);
const STYLE_METHODS = new Set(['setProperty', 'removeProperty']);
const QUERIES = ['querySelector', 'closest', 'querySelectorAll', 'getElementById', 'getElementsByClassName'];
const ARIA = /^aria[A-Z]/;
const REFLECTED = new Map([['tabIndex', 'tabindex'], ['hidden', 'hidden'], ['inert', 'inert'], ['id', 'id'], ['title', 'title'], ['lang', 'lang'], ['dir', 'dir'], ['src', 'src']]);
const CONTENT_PROPS = new Set(['textContent', 'innerText', 'innerHTML', 'outerHTML', 'data', 'nodeValue']);
const CONTENT_CALLS = new Set(['append', 'prepend', 'after', 'before', 'remove', 'replaceWith', 'replaceChildren', 'appendChild', 'removeChild', 'insertBefore']);
const DIALOG_CALLS = new Set(['showModal', 'show', 'close']);
const ANIM_TIME = new Set(['currentTime', 'startTime', 'playbackRate']);
const ANIM_CALLS = new Set(['cancel', 'finish', 'pause', 'play', 'reverse', 'updatePlaybackRate', 'commitStyles', 'persist']);
const MODELLED = {
  call: {
    el: new Set(['addEventListener', 'removeEventListener', 'setAttribute', 'removeAttribute', 'toggleAttribute', 'getAttribute', 'hasAttribute', 'matches', 'getBoundingClientRect', 'getClientRects', 'scrollTo', 'scrollBy', 'scrollIntoView', 'animate', 'getAnimations', ...QUERIES, ...CONTENT_CALLS, ...DIALOG_CALLS]),
    els: new Set([...ARRAY_SYNC, 'filter', 'slice', 'concat', 'at', 'item', 'includes', 'indexOf']),
    anim: ANIM_CALLS,
    style: new Set([...STYLE_METHODS, 'getPropertyValue']),
    classList: new Set(['add', 'remove', 'toggle', 'replace', 'contains']),
  },
  set: { el: new Set(['className', 'scrollTop', 'scrollLeft', ...CONTENT_PROPS, ...REFLECTED.keys()]), anim: ANIM_TIME },
  get: {
    el: new Set([...RECT_PROPS, ...ELEMENT_PROPS, 'style', 'classList', 'dataset', 'open']),
    els: new Set(['length']),
    anim: new Set(),
  },
};
const elementKind = (v) => (v && (v.k === 'el' || v.k === 'els' || v.k === 'anim') ? v.k : null);
function modelled(kind, recvKind, member) {
  if (kind === 'set' && recvKind === 'el' && member && ARIA.test(member)) return true;
  if (kind === 'get' && recvKind === 'els' && member === null) return true;
  return MODELLED[kind][recvKind]?.has(member) ?? false;
}
function unmodelled(n, kind, recvKind, member) {
  finding(site(n), 'unmodelled-api', `${kind} ${recvKind}.${member ?? '[?]'}`);
}

function bindingKey(sc, f) {
  const parts = [];
  for (const p of f.node.params) parts.push(p.type);
  return parts.join(',');
}
function analyzeFn(f, ctxTag, args, callerScope, elemArg) {
  const key = `${cur.part}|${f.scope.file.abs}|${f.node.start}|${ctxTag}|${args ? args.map((a) => JSON.stringify(sig(valueOf(a, callerScope)))).join(';') : ''}|${elemArg ? JSON.stringify(sig(elemArg)) : ''}`;
  if (done.has(key) || depth > 8) return;
  done.add(key);
  analyzedFns.add(fnKey(f));
  const sc = new Scope(f.scope, f.scope.file);
  f.node.params.forEach((p, i) => {
    if (elemArg && i === 0) bindPattern(sc, p, () => elemArg);
    else if (ctxTag === 'render' && i === 0 && !args) bindPattern(sc, p, () => jsxProps(folderOf(f.scope.file.abs)), 'param');
    else bindPattern(sc, p, memo(() => (args && args[i] ? valueOf(args[i], callerScope) : UNKNOWN)), 'param');
  });
  const prevFile = cur.file;
  cur.file = f.scope.file;
  depth++;
  const body = f.node.body;
  if (body.type === 'BlockStatement') {
    hoist(body.body, sc);
    for (const st of body.body) walk(st, sc, ctxTag, f);
  } else walk(body, sc, ctxTag, f);
  depth--;
  cur.file = prevFile;
}
function jsxProps(folder) {
  const props = new Map();
  for (const [k, vs] of propOverrides) if (k.startsWith(`${folder}.`)) props.set(k.slice(folder.length + 1), () => ({ k: 'str', vs }));
  return { k: 'obj', props };
}
function sig(v) {
  if (!v) return null;
  if (v.k === 'el' || v.k === 'els') return { k: v.k, o: v.owners };
  if (v.k === 'str') return { k: 'str', v: v.vs };
  if (v.k === 'obj') return { k: 'obj', p: [...v.props.keys()] };
  return { k: v.k };
}
const analyzedFns = new Set();

function callbackTag(call, argIndex, scope) {
  const c = strip(call.callee);
  const name = c.type === 'Identifier' ? c.name : c.type === 'MemberExpression' ? propName(c) : null;
  if (call.type === 'NewExpression' && name && OBSERVERS.has(name)) return `observer:${name}`;
  if (EFFECTS.has(name)) return 'effect';
  if (name === 'addEventListener') {
    const t = valueOf(call.arguments[0], scope);
    const recv = c.type === 'MemberExpression' ? valueOf(c.object, scope) : UNKNOWN;
    const type = t.k === 'str' ? t.vs[0] : '?';
    return recv.k === 'mql' ? `listener:media-${type}` : `listener:${type}`;
  }
  if (name === 'requestAnimationFrame') return 'raf';
  if (name === 'setTimeout' || name === 'setInterval' || name === 'queueMicrotask') return 'timer';
  if (name === 'register' || name === 'registerScroll') return 'scroll';
  if (['subscribe', 'interval', 'advance', 'after', 'every'].includes(name)) return 'clock';
  if (name === 'useCallback' || name === 'useMemo') return 'callback';
  return 'callback';
}

function walk(n, scope, ctxTag, fnVal) {
  if (!n) return;
  if (isFn(n)) {
    if (n.type !== 'FunctionDeclaration') fallback.push({ node: n, scope });
    return;
  }
  switch (n.type) {
    case 'VariableDeclaration':
      for (const d of n.declarations) {
        if (d.init && isFn(strip(d.init))) { fallback.push({ node: strip(d.init), scope }); continue; }
        if (d.init) walk(d.init, scope, ctxTag, fnVal);
      }
      return;
    case 'BlockStatement': {
      const sc = new Scope(scope, scope.file);
      hoist(n.body, sc);
      for (const st of n.body) walk(st, sc, ctxTag, fnVal);
      return;
    }
    case 'ForOfStatement':
    case 'ForInStatement': {
      const sc = new Scope(scope, scope.file);
      const it = valueOf(n.right, scope);
      const decl = n.left.type === 'VariableDeclaration' ? n.left.declarations[0].id : n.left;
      bindPattern(sc, decl, () => (it.k === 'els' ? el(it.owners, it.sel) : it.k === 'arr' ? it.item : UNKNOWN));
      walk(n.right, scope, ctxTag, fnVal);
      walk(n.body, sc, ctxTag, fnVal);
      return;
    }
    case 'ReturnStatement':
      if (n.argument && isFn(strip(n.argument)) && ctxTag === 'effect') {
        analyzeLater({ node: strip(n.argument), scope }, 'cleanup', null, scope);
        return;
      }
      break;
    case 'CallExpression':
    case 'NewExpression':
      return walkCall(n, scope, ctxTag, fnVal);
    case 'AssignmentExpression':
      walkAssign(n, scope, ctxTag);
      walk(n.right, scope, ctxTag, fnVal);
      if (n.left.type === 'MemberExpression') { walk(n.left.object, scope, ctxTag, fnVal); if (n.left.computed) walk(n.left.property, scope, ctxTag, fnVal); }
      return;
    case 'MemberExpression':
      walkRead(n, scope, ctxTag);
      break;
    case 'JSXOpeningElement':
      walkJsx(n, scope, ctxTag);
      for (const a of n.attributes) {
        if (a.type === 'JSXSpreadAttribute') { walk(a.argument, scope, ctxTag, fnVal); continue; }
        if (!a.value || a.value.type !== 'JSXExpressionContainer') continue;
        const e = strip(a.value.expression);
        const an = jsxName(a.name);
        if (isFn(e)) analyzeLater({ node: e, scope }, an === 'ref' ? 'ref' : an.startsWith('on') ? `jsx:${an}` : 'callback', null, scope);
        else if (e.type === 'Identifier' && an.startsWith('on')) {
          const v = valueOf(e, scope);
          if (v.k === 'fn') analyzeLater(v, `jsx:${an}`, null, scope);
        } else walk(e, scope, ctxTag, fnVal);
      }
      return;
    case 'Property':
      if (isFn(strip(n.value))) { fallback.push({ node: strip(n.value), scope }); return; }
      break;
    case 'TSTypeAliasDeclaration':
    case 'TSInterfaceDeclaration':
    case 'ImportDeclaration':
      return;
    default:
  }
  for (const c of children(n)) walk(c, scope, ctxTag, fnVal);
}
function analyzeLater(f, tag, args, scope, elemArg) {
  pending.push(() => analyzeFn(f, tag, args, scope, elemArg));
}
export const classListOf = (method, args, scope) => classListReport(method, args.map((a) => classValue(valueOf(a, scope))));
function classValue(v) {
  if (v.k === 'cls') return v.local == null ? { modKey: rel(v.file) } : { mod: `${rel(v.file)}#${v.local}` };
  if (v.k === 'str') return { str: v.vs };
  if (v.k === 'calt') return v.v;
  return {};
}
function memberClassOf(x, scope) {
  const cv = valueOf(x, scope);
  if (cv.k !== 'cls') return null;
  return cv.local == null || (x.computed && propName(x) === null) ? { key: rel(cv.file) } : { mod: `${rel(cv.file)}#${cv.local}` };
}
function staticMemberClass(x, scope) {
  const o = strip(x.object);
  const r = o.type === 'Identifier' ? scope.lookup(o.name) : null;
  if (!r || !r.b.css) return null;
  const local = propName(x);
  return local === null ? { key: rel(r.b.css) } : { mod: `${rel(r.b.css)}#${local}` };
}
function classEnv(scope, memberClass = memberClassOf) {
  return {
    memberClass: (x) => memberClass(x, scope),
    constInit: (name) => {
      const r = scope.lookup(name);
      return r && r.b.kind === 'const' && r.b.init ? { init: r.b.init, env: classEnv(r.scope, memberClass) } : null;
    },
  };
}
function walkCall(n, scope, ctxTag, fnVal) {
  const c = strip(n.callee);
  const name = c.type === 'Identifier' ? c.name : c.type === 'MemberExpression' ? propName(c) : null;
  const recv = c.type === 'MemberExpression' ? valueOf(c.object, scope) : null;
  if (c.type === 'MemberExpression') walk(c.object, scope, ctxTag, fnVal);
  if (c.type === 'Identifier' && ['requestAnimationFrame', 'setInterval', 'setTimeout', 'after'].includes(name)) emit(n, 'clock', name, '', ctxTag);
  if (c.type === 'MemberExpression' && ['subscribe', 'interval', 'every'].includes(name) && (recv.k === 'clock' || /clock/i.test(c.object.type === 'Identifier' ? c.object.name : c.object.type === 'MemberExpression' ? propName(c.object) ?? '' : ''))) emit(n, 'clock', name, '', ctxTag);
  if (c.type === 'MemberExpression' && ['now'].includes(name) && c.object.type === 'Identifier' && ['Date', 'performance'].includes(c.object.name)) emit(n, 'clock', `${c.object.name}.now`, '', ctxTag);
  if (name === 'matchList' || name === 'matchMedia') {
    const a = valueOf(n.arguments[0], scope);
    emit(n, 'media', a.k === 'str' ? a.vs.join('|') : '?', '', ctxTag);
  }
  if (name === 'register' || name === 'registerScroll') {
    const a = valueOf(n.arguments[1], scope);
    emit(n, 'register', a.k === 'num' ? String(a.v) : '?', '', ctxTag);
  }
  if (name === 'addEventListener' && recv) {
    const t = valueOf(n.arguments[0], scope);
    const type = t.k === 'str' ? t.vs[0] : '?';
    if (recv.k === 'mql') emit(n, 'listen', `media-${type}`, '', ctxTag);
    else emitOn(n, 'listen', type, recv, ctxTag);
  }
  if (recv) {
    const sub = c.object.type === 'MemberExpression' ? propName(strip(c.object)) : null;
    const subOwner = sub === 'style' || sub === 'classList' ? valueOf(strip(c.object).object, scope) : null;
    if (sub === 'style' && STYLE_METHODS.has(name)) {
      const a = valueOf(n.arguments[0], scope);
      const props = a.k === 'str' ? a.vs : ['?'];
      for (const p of props) emitOn(n, p.startsWith('--') ? 'setVar' : 'setStyle', p, subOwner, ctxTag);
    } else if (sub === 'style' && name === 'getPropertyValue') {
      emitOn(n, 'styleRead', '', subOwner, ctxTag);
    } else if (sub === 'classList' && CLASS_LIST_METHODS.includes(name)) {
      const { writes, findings: found } = classListOf(name, n.arguments, scope);
      for (const [kind, d] of found) finding(site(n), kind, d);
      for (const [op, cn] of writes) emitOn(n, op, cn, subOwner, ctxTag);
    } else if (['setAttribute', 'removeAttribute', 'toggleAttribute'].includes(name)) {
      const a = valueOf(n.arguments[0], scope);
      for (const p of a.k === 'str' ? a.vs : ['?']) emitOn(n, 'setAttr', p, recv, ctxTag);
    } else if (['getAttribute', 'hasAttribute'].includes(name)) {
      const a = valueOf(n.arguments[0], scope);
      for (const p of a.k === 'str' ? a.vs : ['?']) emitOn(n, 'attrRead', p, recv, ctxTag);
    } else if (name === 'getBoundingClientRect' || name === 'getClientRects') {
      emitOn(n, 'rect', '', recv, ctxTag);
    } else if (['scrollTo', 'scrollBy', 'scrollIntoView'].includes(name)) {
      emitOn(n, 'scroll', name, recv, ctxTag);
    } else if (name === 'elementFromPoint' || name === 'elementsFromPoint') {
      emit(n, 'hitTest', name, '', ctxTag);
    } else if (name === 'observe' && recv.k === 'observer') {
      const target = valueOf(n.arguments[0], scope);
      if (recv.kind === 'MutationObserver') {
        const opts = valueOf(n.arguments[1], scope);
        const filt = opts.k === 'obj' && opts.props.has('attributeFilter') ? opts.props.get('attributeFilter')() : null;
        emitOn(n, 'attrRead', filt && filt.k === 'str' ? filt.vs.join('|') : '*', target, `observer:${recv.kind}`);
      } else emitOn(n, 'rect', '', target, `observer:${recv.kind}`);
    } else if (name === 'matches') {
      const a = valueOf(n.arguments[0], scope);
      emitOn(n, 'attrRead', a.k === 'str' ? `matches:${a.vs.join('|')}` : '?', recv, ctxTag);
    } else if (QUERIES.includes(name)) {
      const a = valueOf(n.arguments[0], scope);
      if (a.k !== 'str') finding(site(n), 'dynamic-selector', `${name}(${n.arguments[0] ? cur.file.text.slice(n.arguments[0].start, n.arguments[0].end) : ''})`);
      else resolveSelector(name === 'getElementById' ? a.vs.map((x) => `#${x}`).join(', ') : a.vs.join(', '), site(n));
    } else if (name === 'animate') {
      emitOn(n, 'setStyle', '?', recv, ctxTag);
    } else if (CONTENT_CALLS.has(name) && recv.k === 'el') {
      emitOn(n, 'setContent', name, recv, ctxTag);
    } else if (DIALOG_CALLS.has(name) && recv.k === 'el') {
      emitOn(n, 'setAttr', 'open', recv, ctxTag);
    } else if (ANIM_CALLS.has(name) && recv.k === 'anim') {
      emitOn(n, 'setStyle', '?', el(recv.owners), ctxTag);
    }
    const subKind = elementKind(subOwner);
    if (subKind) {
      if (!modelled('call', sub, name)) unmodelled(n, 'call', sub, name);
    } else if (elementKind(recv) && !modelled('call', recv.k, name)) unmodelled(n, 'call', recv.k, name);
  }
  if (name === 'push' && recv && recv.k === 'arr') for (const a of n.arguments) recv.item = union(recv.item.k === 'unknown' ? null : recv.item, valueOf(a, scope));
  if (c.type === 'Identifier' && name === 'getComputedStyle') emitOn(n, 'styleRead', '', valueOf(n.arguments[0], scope), ctxTag);
  const fv = valueOf(c, scope);
  n.arguments.forEach((a, i) => {
    const s = strip(a);
    const v = isFn(s) ? { k: 'fn', node: s, scope } : s.type === 'Identifier' ? valueOf(s, scope) : null;
    if (v && v.k === 'fn' && !(fv.k === 'fn')) {
      if (ARRAY_SYNC.has(name) && recv && (recv.k === 'els' || recv.k === 'arr')) {
        analyzeFn(v, ctxTag, null, scope, recv.k === 'els' ? el(recv.owners, recv.sel) : recv.item);
      } else analyzeLater(v, callbackTag(n, i, scope), null, scope);
    } else if (!isFn(s)) walk(a, scope, ctxTag, fnVal);
    else if (fv.k === 'fn') { }
  });
  if (fv.k === 'fn') {
    analyzeFn(fv, ctxTag, n.arguments, scope);
    n.arguments.forEach((a) => {
      const s = strip(a);
      if (isFn(s)) analyzeLater({ node: s, scope }, 'callback', null, scope);
    });
  }
}
function walkAssign(n, scope, ctxTag) {
  const l = strip(n.left);
  if (l.type !== 'MemberExpression') return;
  const p = propName(l);
  const o = strip(l.object);
  const sub = o.type === 'MemberExpression' ? propName(o) : null;
  if (sub === 'style') {
    emitOn(n, 'setStyle', p === 'cssText' ? 'cssText' : kebab(p ?? '?'), valueOf(o.object, scope), ctxTag);
    return;
  }
  if (sub === 'dataset') {
    emitOn(n, 'setAttr', p === null ? '?' : `data-${kebab(p)}`, valueOf(o.object, scope), ctxTag);
    return;
  }
  const t = valueOf(o, scope);
  if (p === 'className') for (const [op, name] of n.operator === '=' ? classAssign(collectClassTokens(n.right, classEnv(scope), 'text')) : [['setClass', '*']]) emitOn(n, op, name, t, ctxTag);
  else if (p === 'scrollTop' || p === 'scrollLeft') emitOn(n, 'scroll', p, t, ctxTag);
  else if (CONTENT_PROPS.has(p)) emitOn(n, 'setContent', p, t, ctxTag);
  else if (REFLECTED.has(p)) emitOn(n, 'setAttr', REFLECTED.get(p), t, ctxTag);
  else if (p && ARIA.test(p) && t.k === 'el') emitOn(n, 'setAttr', kebab(p), t, ctxTag);
  else if (ANIM_TIME.has(p) && (t.k === 'anim' || t.k === 'unknown')) emitOn(n, 'setStyle', '?', t.k === 'anim' ? el(t.owners) : t, ctxTag);
  const k = elementKind(t);
  if (k && !modelled('set', k, p)) unmodelled(n, 'set', k, p);
}
function walkRead(n, scope, ctxTag) {
  const p = propName(n);
  const o = valueOf(n.object, scope);
  const k = elementKind(o);
  if (k && !modelled('get', k, p)) unmodelled(n, 'get', k, p);
  const sub = strip(n.object).type === 'MemberExpression' ? propName(strip(n.object)) : null;
  if (sub === 'style' && elementKind(valueOf(strip(n.object).object, scope)) === 'el') emitOn(n, 'styleRead', '', valueOf(strip(n.object).object, scope), ctxTag);
  if (o.k === 'win') {
    if (p === 'innerWidth') emit(n, 'vw', p, '', ctxTag);
    else if (p === 'innerHeight') emit(n, 'vh', p, '', ctxTag);
    else if (['scrollY', 'pageYOffset', 'scrollX', 'pageXOffset'].includes(p)) emit(n, 'scrollY', p, '', ctxTag);
    else if (p === 'visualViewport') { emit(n, 'vw', p, '', ctxTag); emit(n, 'vh', p, '', ctxTag); }
  } else if (o.k === 'doc' && strip(n.object).type === 'MemberExpression') {
    if (p === 'clientWidth') emit(n, 'vw', p, '', ctxTag);
    else if (p === 'clientHeight') emit(n, 'vh', p, '', ctxTag);
    else if (p === 'scrollTop') emit(n, 'scrollY', p, '', ctxTag);
    else if (p === 'scrollHeight') emit(n, 'rect', p, 'document', ctxTag);
  } else if (o.k === 'el' && RECT_PROPS.has(p)) {
    emitOn(n, 'rect', p, o, ctxTag);
  } else if (o.k === 'el' && p === 'open') {
    emitOn(n, 'attrRead', 'open', o, ctxTag);
  } else if (strip(n.object).type === 'MemberExpression' && propName(strip(n.object)) === 'dataset') {
    emitOn(n, 'attrRead', `data-${kebab(p ?? '?')}`, valueOf(strip(n.object).object, scope), ctxTag);
  } else if (n.object.type === 'Identifier' && (n.object.name === 'innerWidth' || n.object.name === 'innerHeight')) {
  }
}
const STATEFUL = new Set(['state', 'stateVal', 'ref', 'unknown']);
function exprIsProps(e, scope) {
  let ok = true;
  const visit = (x) => {
    if (!ok || !x) return;
    if (x.type === 'Identifier') {
      const r = scope.lookup(x.name);
      if (!r) return;
      if (r.b.kind === 'param' || r.b.kind === 'import' || r.b.kind === 'fn') return;
      if (r.scope.parent === null) return;
      ok = false;
      return;
    }
    if (x.type === 'MemberExpression') { visit(x.object); if (x.computed) visit(x.property); return; }
    if (x.type === 'CallExpression') { ok = false; return; }
    for (const c of children(x)) visit(c);
  };
  visit(e);
  return ok;
}
export const LIST_HELPERS = ['clsx', 'classNames', 'classnames'];
export const JOIN_HELPERS = ['cx', 'cls'];
export const CLASS_SEPARATORS = [' ', '\t', '\n', '\f', '\r'];
const SEP = /[ \t\n\f\r]/;
const classTokensOf = (s) => s.split(SEP).filter(Boolean).map((name) => ({ op: 'setClass', name }));
const lose = (t) => ({ op: 'lost', name: t.name });
const marker = (form, toks) => [{ op: 'lost', name: form }, ...toks.map(lose)];
const modKeyToks = (m) => [{ op: 'modLost', name: `module key ${m}` }];
function classPush(w, a) {
  if (a.chars === undefined) return [...w, a];
  if (a.chars === '') return w;
  const last = w[w.length - 1];
  return last && last.chars !== undefined ? [...w.slice(0, -1), { chars: last.chars + a.chars }] : [...w, a];
}
function classWords(ps) {
  const done = [];
  let cur = [];
  for (const p of ps) {
    if (p.text === undefined) { cur = classPush(cur, p); continue; }
    const [g, ...gs] = p.text.split(SEP);
    cur = classPush(cur, { chars: g });
    for (const x of gs) { done.push(cur); cur = classPush([], { chars: x }); }
  }
  done.push(cur);
  const atomToks = (a) => (a.chars !== undefined ? [{ op: 'setClass', name: a.chars }] : a.toks);
  return done.flatMap((w) => {
    if (w.length < 2) return w.flatMap(atomToks);
    return [{ op: 'glued', name: w.map((a) => a.chars ?? '*').join('') }, ...w.flatMap(atomToks)];
  });
}
function classSepOk(args) {
  if (args.length !== 1) return false;
  const a = strip(args[0]);
  return a.type === 'Literal' && typeof a.value === 'string' && a.value.length > 0 && a.value.split(SEP).every((x) => x === '');
}
const CMP_OPS = new Set(['===', '!==', '==', '!=', '<', '<=', '>', '>=', 'in', 'instanceof']);
const NUM_UNARY = new Set(['-', '+', '~']);
const drops = (c) => c === 'list' || c === 'join';
const clsTok = (name) => ({ op: 'setClass', name });
function boolToks(c, b) {
  if (c === 'text' || c === 'elem') return [clsTok(String(b))];
  return c === 'join' && b ? [clsTok('true')] : [];
}
const testToks = (c) => [...boolToks(c, true), ...boolToks(c, false)];
const nullToks = (c, n) => (c === 'text' ? [clsTok(n)] : []);
const isTest = (x) => (x.type === 'BinaryExpression' && CMP_OPS.has(x.operator)) || (x.type === 'UnaryExpression' && x.operator === '!') || (x.type === 'Literal' && typeof x.value === 'boolean');
const isStr = (x) => x.type === 'Literal' && typeof x.value === 'string';
const calleeCtx = (n) => (LIST_HELPERS.includes(n) ? 'list' : JOIN_HELPERS.includes(n) ? 'join' : null);
function filterCtx(args) {
  const a = args.length === 1 ? strip(args[0]) : null;
  return a && a.type === 'Identifier' && a.name === 'Boolean' ? 'join' : 'elem';
}
export const NO_CLASS_ENV = { memberClass: () => null, constInit: () => null };
export function collectClassTokens(expr, env = NO_CLASS_ENV, ctx = 'attr') {
  const busy = new Set();
  const hole = (toks) => ({ toks, ps: [{ toks }] });
  const list = (xs, c, en) => xs.flatMap((x) => (x ? go(x, c, en).toks : []));
  const elems = (r) => {
    if (r.type === 'ArrayExpression') return { es: r.elements, c: 'elem' };
    const f = r.type === 'CallExpression' ? strip(r.callee) : null;
    if (f && f.type === 'MemberExpression' && !f.computed && f.property.type === 'Identifier' && f.property.name === 'filter' && strip(f.object).type === 'ArrayExpression') return { es: strip(f.object).elements, c: filterCtx(r.arguments) };
    return null;
  };
  const prop = (p, en) => {
    if (p.type !== 'Property') return marker('spread', go(p.argument, 'list', en).toks);
    if (p.computed) return go(p.key, 'text', en).toks;
    return classTokensOf(p.key.type === 'Identifier' ? p.key.name : String(p.key.value));
  };
  const other = (x, en) => hole(marker('other', list(children(x), 'attr', en)));
  const go = (x, c, en) => {
    x = strip(x);
    switch (x.type) {
      case 'Literal':
        if (typeof x.value === 'string') return { toks: classTokensOf(x.value), ps: [{ text: x.value }] };
        if (typeof x.value === 'number' || typeof x.value === 'bigint') return hole(marker('number', []));
        if (typeof x.value === 'boolean') return hole(boolToks(c, x.value));
        if (x.value === null && !x.regex) return hole(nullToks(c, 'null'));
        return other(x, en);
      case 'Identifier': {
        if (x.name === 'undefined') return hole(nullToks(c, 'undefined'));
        const k = en.constInit(x.name);
        if (!k || busy.has(k.init)) return hole(marker(`id ${x.name}`, []));
        busy.add(k.init);
        try { return go(k.init, c, k.env); } finally { busy.delete(k.init); }
      }
      case 'MemberExpression': {
        const m = en.memberClass(x);
        if (!m) return hole(marker('member', []));
        return hole(m.key !== undefined ? modKeyToks(m.key) : [{ op: 'setModuleClass', name: m.mod }]);
      }
      case 'UnaryExpression':
        if (x.operator === '!') return hole(testToks(c));
        if (NUM_UNARY.has(x.operator)) return hole(marker('number', []));
        return other(x, en);
      case 'BinaryExpression': {
        if (CMP_OPS.has(x.operator)) return hole(testToks(c));
        if (x.operator !== '+') return hole(marker('number', []));
        const ps = [...go(x.left, 'text', en).ps, ...go(x.right, 'text', en).ps];
        return { toks: classWords(ps), ps };
      }
      case 'ConditionalExpression': return hole([...go(x.consequent, c, en).toks, ...go(x.alternate, c, en).toks]);
      case 'LogicalExpression': {
        if (x.operator !== '&&') return hole([...go(x.left, c, en).toks, ...go(x.right, c, en).toks]);
        const l = strip(x.left);
        const left = drops(c) || isStr(l) ? [] : isTest(l) ? boolToks(c, false) : go(l, c, en).toks;
        return hole([...left, ...go(x.right, c, en).toks]);
      }
      case 'TemplateLiteral': {
        const ps = x.quasis.flatMap((q, i) => [{ text: q.value.cooked ?? '' }, ...(i < x.expressions.length ? go(x.expressions[i], 'text', en).ps : [])]);
        return { toks: classWords(ps), ps };
      }
      case 'ArrayExpression': return hole(c === 'list' ? list(x.elements, c, en) : marker('array', list(x.elements, 'elem', en)));
      case 'ObjectExpression': {
        const ts = x.properties.flatMap((p) => prop(p, en));
        return hole(c === 'list' ? ts : marker('object', ts));
      }
      case 'CallExpression': {
        const f = strip(x.callee);
        if (f.type === 'Identifier') {
          const k = calleeCtx(f.name);
          return hole(k ? list(x.arguments, k, en) : marker(`call ${f.name}`, list(x.arguments, 'attr', en)));
        }
        if (f.type === 'MemberExpression' && !f.computed && f.property.type === 'Identifier') {
          const es = f.property.name === 'join' ? elems(strip(f.object)) : null;
          if (es) return hole(classSepOk(x.arguments) ? list(es.es, es.c, en) : marker('join separator', list(es.es, es.c, en)));
          return hole(marker(`method ${f.property.name}`, [...go(f.object, 'attr', en).toks, ...list(x.arguments, 'attr', en)]));
        }
        return other(x, en);
      }
      case 'SpreadElement': return hole(marker('spread', go(x.argument, c, en).toks));
      default: return other(x, en);
    }
  };
  return go(expr, ctx, env).toks;
}
export const isOpenClass = (toks) => toks.some((t) => t.op === 'lost' || t.op === 'modLost' || t.op === 'glued');
export const isOpenElement = (toks) => toks.some((t) => t.op === 'lost' || t.op === 'glued');
export const literalClasses = (s) => classTokensOf(s).map((t) => t.name);
export const CLASS_LIST_METHODS = ['add', 'remove', 'toggle', 'replace', 'contains'];
const HOLE_RE = new RegExp(HOLE, 'g');
function tokenToks(w) {
  if (w.includes(HOLE)) return [{ op: 'glued', name: w.replace(HOLE_RE, '*') }];
  if (w === '' || SEP.test(w)) return marker('invalid token', [{ op: 'setClass', name: w }]);
  return [{ op: 'setClass', name: w }];
}
function valueToks(v) {
  if (v.str) return v.str.flatMap(tokenToks);
  if (v.mod !== undefined) return [{ op: 'setModuleClass', name: v.mod }];
  if (v.modKey !== undefined) return modKeyToks(v.modKey);
  if (v.alt) return v.alt.flatMap(valueToks);
  return marker('unresolved', []);
}
const valueAlts = (v) => (v.alt ? v.alt : [v]);
export const classUnion = (a, b) => ({ alt: [...valueAlts(a), ...valueAlts(b)] });
export function classListReport(method, values) {
  const args = method === 'toggle' || method === 'contains' ? values.slice(0, 1) : values;
  const { writes, findings } = classReport(args.flatMap(valueToks));
  return { writes: method === 'contains' ? writes.map(([, n]) => ['classRead', n]) : writes, findings };
}
const CLASS_FINDING = { lost: 'unmodelled-class', modLost: 'unmodelled-class', glued: 'glued-class' };
export function classReport(toks) {
  const writes = toks.filter((t) => !CLASS_FINDING[t.op]).map((t) => [t.op, t.name]);
  const findings = toks.filter((t) => CLASS_FINDING[t.op]).map((t) => [CLASS_FINDING[t.op], t.name]);
  return { writes: isOpenClass(toks) ? [...writes, ['setClass', '?']] : writes, findings };
}
export const classAssign = (toks) => (isOpenClass(toks) ? [['setClass', '*']] : classReport(toks).writes);
export function classMatch(has, sel, open) {
  if (sel.every(has)) return 'strong';
  return open ? 'weak' : 'none';
}
export function classStrength(spread, literalAttrs, m) {
  if (m === 'none') return null;
  if (spread) return 'spread';
  if (m === 'weak') return 'weak';
  return literalAttrs ? 'literal' : 'dynamic';
}
export function pickOwners(cands) {
  const lit = cands.filter(([, k]) => k === 'literal');
  const dyn = cands.filter(([, k]) => k === 'dynamic');
  const weak = cands.filter(([, k]) => k === 'weak');
  if (lit.length) return { owners: lit.map(([o]) => o), weak: false };
  if (dyn.length) return { owners: dyn.map(([o]) => o), weak: true };
  if (weak.length) return { owners: weak.map(([o]) => o), weak: true };
  return { owners: cands.map(([o]) => o), weak: cands.length > 0 };
}
function walkJsx(n, scope, ctxTag) {
  const tag = jsxName(n.name);
  if (!(/^[a-z]/.test(tag) || tag === 'Box')) return;
  const owner = el([folderOf(scope.file.abs)]);
  for (const a of n.attributes) {
    if (a.type !== 'JSXAttribute') continue;
    const an = jsxName(a.name);
    const v = jsxAttrValue(a);
    if (v.lit !== undefined || an === 'ref' || an === 'key' || an.startsWith('on') || an === 'children' || an === 'dangerouslySetInnerHTML') continue;
    const tagCtx = exprIsProps(v.expr, scope) ? 'props' : ctxTag;
    if (an === 'className') {
      const toks = collectClassTokens(v.expr, classEnv(scope));
      const { writes, findings: found } = classReport(toks);
      const dynamic = !(strip(v.expr).type === 'MemberExpression') && !(strip(v.expr).type === 'TemplateLiteral' && strip(v.expr).expressions.every((x) => strip(x).type === 'MemberExpression'));
      if (!dynamic && found.length === 0) continue;
      for (const [kind, n] of found) finding(site(a), kind, n);
      for (const [op, name] of writes) emitOn(a, op, name, owner, tagCtx);
    } else if (an === 'style') {
      const e = strip(v.expr);
      if (e.type === 'ObjectExpression') {
        for (const p of e.properties) {
          if (p.type !== 'Property') { emitOn(a, 'setStyle', '?', owner, tagCtx); continue; }
          const pv = strip(p.value);
          if (pv.type === 'Literal' || (pv.type === 'TemplateLiteral' && pv.expressions.length === 0)) continue;
          const key = p.key.type === 'Identifier' ? p.key.name : String(p.key.value);
          const pc = exprIsProps(pv, scope) ? 'props' : ctxTag;
          emitOn(a, key.startsWith('--') ? 'setVar' : 'setStyle', key.startsWith('--') ? key : kebab(key), owner, pc);
        }
      } else {
        const ov = valueOf(e, scope);
        if (ov.k !== 'obj') emitOn(a, 'setStyle', '?', owner, tagCtx);
        else for (const key of ov.props.keys()) emitOn(a, key.startsWith('--') ? 'setVar' : 'setStyle', key.startsWith('--') ? key : kebab(key), owner, tagCtx);
      }
    } else if (an.startsWith('data-') || an.startsWith('aria-') || ['hidden', 'id', 'role', 'tabIndex', 'inert', 'open'].includes(an)) {
      emitOn(a, 'setAttr', an === 'tabIndex' ? 'tabindex' : an, owner, tagCtx);
    }
  }
}

function cssReads(abs, part) {
  const text = fs.readFileSync(abs, 'utf8');
  const lines = lineStarts(text);
  const f = { abs, lines };
  const clean = text.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
  const out = [];
  const owner = folderOf(abs);
  const re = /([^{};]+)\{/g;
  let m;
  while ((m = re.exec(clean))) {
    const selText = m[1];
    const at = m.index + (m[1].length - m[1].trimStart().length);
    if (selText.trim().startsWith('@')) continue;
    for (const alt of splitTop(selText, [','])) {
      const compounds = splitTop(alt.replace(/\s*([>+~])\s*/g, ' '), [' ']);
      for (const comp of compounds) {
        const hasLocalClass = /(^|[^\w-])\.[_a-zA-Z]/.test(comp.replace(/:(global|has|not|is|where)\([^)]*\)/g, ''));
        const am = comp.match(/\[[a-zA-Z0-9_-]+/g) ?? [];
        const inFn = comp.match(/:(has|global|not|is|where)\(([^)]*)\)/g) ?? [];
        const fnAttrs = new Set(inFn.flatMap((x) => x.match(/\[[a-zA-Z0-9_-]+/g) ?? []));
        for (const a of am) {
          const name = a.slice(1);
          const scoped = hasLocalClass && !fnAttrs.has(a);
          out.push({ line: lineOf(f, at), op: 'cssAttr', name, owner: scoped ? owner : '' });
        }
        for (const g of comp.match(/:global\(([^)]*)\)/g) ?? []) {
          for (const c of g.match(/\.[_a-zA-Z][\w-]*/g) ?? []) out.push({ line: lineOf(f, at), op: 'cssClass', name: c.slice(1), owner: '' });
        }
        if (/:has\(/.test(comp)) out.push({ line: lineOf(f, at), op: 'cssHas', name: comp.replace(/\s+/g, ' '), owner: '' });
      }
    }
  }
  const vr = /var\(\s*(--[\w-]+)/g;
  while ((m = vr.exec(clean))) out.push({ line: lineOf(f, m.index), op: 'cssVar', name: m[1], owner: '' });
  const dr = /(--[\w-]+)\s*:([^;{}]*)/g;
  while ((m = dr.exec(clean))) {
    for (const d of m[2].match(/var\(\s*(--[\w-]+)/g) ?? []) out.push({ line: lineOf(f, m.index), op: 'cssAlias', name: `${m[1]}>${d.replace(/var\(\s*/, '')}`, owner: '' });
  }
  return out.map((r) => ({ part, file: rel(abs), ...r, ctx: 'style' }));
}

function partFiles(part) {
  const dir = path.join(partsDir, part);
  return fs.readdirSync(dir).filter((n) => /\.(tsx?|css)$/.test(n) && !SKIP.test(n)).sort().map((n) => path.join(dir, n));
}
function closure(part) {
  const own = partFiles(part);
  const seen = new Set(own);
  const queue = own.filter((f) => !f.endsWith('.css'));
  while (queue.length) {
    const f = queue.shift();
    const src = loadTs(f);
    for (const st of src.program.body) {
      if (st.type !== 'ImportDeclaration' && !(st.type === 'ExportNamedDeclaration' && st.source)) continue;
      const t = resolveImport(f, st.source.value);
      if (!t || !inParts(t) || seen.has(t)) continue;
      if (folderOf(t) !== part && isEntry(t)) continue;
      seen.add(t);
      if (!t.endsWith('.css')) queue.push(t);
    }
  }
  return { own, all: [...seen].sort() };
}

const importedElsewhere = new Set();
function exportedFns(src) {
  const out = new Set();
  for (const st of src.program.body) {
    if (st.type !== 'ExportNamedDeclaration' && st.type !== 'ExportDefaultDeclaration') continue;
    const d = st.declaration;
    if (!d) continue;
    if (isFn(d)) out.add(d);
    if (d.type === 'VariableDeclaration') for (const v of d.declarations) if (v.init && isFn(strip(v.init))) out.add(strip(v.init));
  }
  return out;
}
function extract() {
  for (const p of partIds) for (const f of closure(p).all) if (folderOf(f) !== p && !DRIVERS.has(folderOf(f))) importedElsewhere.add(f);
  for (const p of partIds) for (const f of partFiles(p)) if (!f.endsWith('.css')) collectElements(loadTs(f));
  collectElements(loadTs(appFile));
  for (let pass = 0; pass < 4; pass++) {
    accesses.clear();
    findings.clear();
    done.clear();
    analyzedFns.clear();
    for (const f of files.values()) f.top = null;
    extractPass();
    if (!addRuntimeElements([...accesses.values()])) return;
  }
  throw new Error('part-footprint: runtime elements did not reach a fixpoint in 4 passes');
}
function extractPass() {
  const out = [];
  for (const part of partIds) {
    const { own, all } = closure(part);
    cur = { part, file: null };
    for (const f of all) {
      if (f.endsWith('.css')) {
        for (const r of cssReads(f, DRIVERS.has(folderOf(f)) ? folderOf(f) : part)) accesses.set(`${r.part}\u0000${r.file}\u0000${String(r.line).padStart(5, '0')}\u0000${r.op}\u0000${r.name}\u0000${r.owner}\u0000${r.ctx}`, r);
        continue;
      }
      if (!own.includes(f)) continue;
      const src = loadTs(f);
      cur.file = src;
      const sc = topScope(src);
      for (let st of src.program.body) {
        const exported = st.type === 'ExportNamedDeclaration' || st.type === 'ExportDefaultDeclaration';
        const d = exported ? st.declaration : st;
        if (!d) continue;
        if (d.type === 'FunctionDeclaration' && d.id && /^[A-Z]/.test(d.id.name) && f.endsWith('.tsx')) {
          analyzeFn({ node: d, scope: sc }, 'render', null, sc);
        } else if (d.type === 'FunctionDeclaration') {
          continue;
        } else if (d.type === 'VariableDeclaration') {
          for (const v of d.declarations) {
            const init = v.init && strip(v.init);
            if (init && isFn(init) && v.id.name && /^[A-Z]/.test(v.id.name) && f.endsWith('.tsx')) analyzeFn({ node: init, scope: sc }, 'render', null, sc);
            else if (init && !isFn(init)) walk(init, sc, 'module', null);
          }
        } else if (d.type !== 'ImportDeclaration') walk(d, sc, 'module', null);
      }
      drain();
    }
    for (const f of own) {
      if (f.endsWith('.css')) continue;
      const src = loadTs(f);
      cur.file = src;
      const sc = topScope(src);
      const fns = [];
      for (const st of src.program.body) {
        const d = st.type === 'ExportNamedDeclaration' || st.type === 'ExportDefaultDeclaration' ? st.declaration : st;
        if (!d) continue;
        if (d.type === 'FunctionDeclaration') fns.push(d);
        if (d.type === 'VariableDeclaration') for (const v of d.declarations) if (v.init && isFn(strip(v.init))) fns.push(strip(v.init));
      }
      for (const fn of fns) {
        if (analyzedFns.has(fnKey({ node: fn, scope: sc }))) continue;
        if (importedElsewhere.has(src.abs) && exportedFns(src).has(fn)) continue;
        analyzeFn({ node: fn, scope: sc }, 'fn', null, sc);
        drain();
      }
    }
  }
  return out;
}

const partDefs = new Map(partIds.map((p) => {
  const f = path.join(partsDir, p, 'part.json');
  return [p, fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null];
}));
const fileClosures = new Map();
function fileClosure(abs, part) {
  const key = `${part}|${abs}`;
  if (fileClosures.has(key)) return fileClosures.get(key);
  const seen = new Set([abs]);
  const queue = abs.endsWith('.css') || !fs.existsSync(abs) ? [] : [abs];
  while (queue.length) {
    const f = queue.shift();
    for (const st of loadTs(f).program.body) {
      if (st.type !== 'ImportDeclaration' && !(st.type === 'ExportNamedDeclaration' && st.source)) continue;
      const t = resolveImport(f, st.source.value);
      if (!t || !inParts(t) || seen.has(t)) continue;
      if (folderOf(t) !== part && isEntry(t)) continue;
      seen.add(t);
      if (!t.endsWith('.css')) queue.push(t);
    }
  }
  fileClosures.set(key, seen);
  return seen;
}
function variantsOf(part, file) {
  const def = partDefs.get(part);
  if (!def) return [];
  const vs = Object.entries(def.variants);
  if (!vs.some(([, v]) => v.files)) return vs.map(([k]) => k);
  const abs = path.join(partsDir, file);
  if (folderOf(abs) === part) {
    const base = path.relative(path.join(partsDir, part), abs).split(path.sep).join('/');
    return vs.filter(([, v]) => (v.files ?? []).includes(base)).map(([k]) => k);
  }
  return vs.filter(([, v]) => (v.files ?? []).some((g) => fileClosure(path.join(partsDir, part, g), part).has(abs))).map(([k]) => k);
}
const variantRows = partIds.flatMap((p) => {
  const def = partDefs.get(p);
  return def ? Object.entries(def.variants).map(([k, v]) => ({ part: p, variant: k, files: v.files ?? [] })) : [];
});
const layerRows = partIds.flatMap((p) => (partDefs.get(p)?.layers ?? []).map((l) => ({ part: p, id: l.id, text: l.text === true })));

const AKEYS = ['part', 'file', 'line', 'op', 'name', 'owner', 'ctx', 'variants'];
const FKEYS = ['part', 'file', 'line', 'kind', 'detail'];
const json = (s) => JSON.stringify(s);
function render() {
  extract();
  const acc = [...accesses.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)).map((e) => ({ ...e[1], variants: variantsOf(e[1].part, e[1].file) }));
  const fin = [...findings.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)).map((e) => e[1]);
  const row = (o, keys) => `{${keys.map((k) => `${json(k)}:${json(o[k])}`).join(',')}}`;
  const text = `{"parts":${json(partIds)},\n"accesses":[\n${acc.map((a) => row(a, AKEYS)).join(',\n')}\n],\n"findings":[\n${fin.map((f) => row(f, FKEYS)).join(',\n')}\n]}\n`;
  const lean = renderLean(acc, fin);
  return { text, lean, acc, fin };
}
function leanStr(s) {
  return `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}
function renderLean(acc, fin) {
  const head = `-- GENERATED by node apps/site/scripts/part-footprint.mjs --write from apps/site/src/parts: do not edit by hand
import Fw.Parts.Footprint

namespace Fw.Parts.FootprintData
open Fw.Parts.Footprint

`;
  const list = (xs) => `[${xs.map(leanStr).join(', ')}]`;
  const a = acc.map((r) => `  ⟨${leanStr(r.part)}, ${leanStr(r.file)}, ${r.line}, .${r.op}, ${leanStr(r.name)}, ${leanStr(r.owner)}, ${leanStr(r.ctx)}, ${list(r.variants)}⟩`);
  const v = variantRows.map((r) => `  (${leanStr(r.part)}, ${leanStr(r.variant)}, ${list(r.files)})`);
  const l = layerRows.map((r) => `  (${leanStr(r.part)}, ${leanStr(r.id)}, ${r.text})`);
  const f = fin.map((r) => `  ⟨${leanStr(r.part)}, ${leanStr(r.file)}, ${r.line}, ${leanStr(r.kind)}, ${leanStr(r.detail)}⟩`);
  return `${head}/-- Part ids, one per folder of apps/site/src/parts, in byte order of the folder names. -/
def partIds : List String := [${partIds.map(leanStr).join(', ')}]

/-- Every extracted access, in key order: (part, file, line, op, name, owner, callback, variants). -/
def accesses : List Access := [
${a.join(',\n')}]

/-- Extractor findings (dead, dynamic, unresolved selectors and targets): (part, file, line, kind, detail). -/
def findings : List Finding := [
${f.join(',\n')}]

/-- Every variant of every part.json with its \`files\` list, in part then part.json order: (part, variant, files). -/
def variantFiles : List (String × String × List String) := [
${v.join(',\n')}]

/-- Every declared layer of every part.json, in part then part.json order: (part, layer id, holds text). -/
def layerDecls : List (String × String × Bool) := [
${l.join(',\n')}]

end Fw.Parts.FootprintData
`;
}

const mode = process.argv[2] ?? '--print';
const isMain = process.argv[1] !== undefined && fs.realpathSync(path.resolve(process.argv[1])) === fs.realpathSync(fileURLToPath(import.meta.url));
const { text, lean } = isMain ? render() : { text: '', lean: '' };
if (!isMain) {} else if (mode === '--print') process.stdout.write(text);
else if (mode === '--write') {
  fs.writeFileSync(goldenPath, text);
  fs.writeFileSync(leanPath, lean);
  process.stderr.write(`part-footprint: wrote ${path.relative(repo, goldenPath)} and ${path.relative(repo, leanPath)}\n`);
} else if (mode === '--check') {
  let ok = true;
  for (const [p, t] of [[goldenPath, text], [leanPath, lean]]) {
    const cur = fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
    if (cur !== t) { ok = false; process.stderr.write(`part-footprint: ${path.relative(repo, p)} differs from the extraction (run --write)\n`); }
  }
  process.exit(ok ? 0 : 1);
} else {
  process.stderr.write('usage: part-footprint.mjs [--print | --write | --check]\n');
  process.exit(2);
}
