// Code that runs inside the page. Every exported function is self-contained (no closure over module scope): the engines
// serialise it with toString(). Nothing here decides; it reports computed values and where each one is declared.

/**
 * Properties that inherit by default in CSS (restated by value; the list is ours). A computed value of one of these that
 * no rule sets on the element itself comes from the nearest ancestor that sets it: that ancestor is the "declared source".
 */
export const INHERITED = [
  'azimuth', 'border-collapse', 'border-spacing', 'caption-side', 'color', 'color-scheme', 'cursor', 'direction',
  'empty-cells', 'font', 'font-family', 'font-feature-settings', 'font-kerning', 'font-optical-sizing',
  'font-size', 'font-size-adjust', 'font-stretch', 'font-style', 'font-synthesis', 'font-variant',
  'font-variant-caps', 'font-variant-east-asian', 'font-variant-ligatures', 'font-variant-numeric',
  'font-variation-settings', 'font-weight', 'hyphens', 'image-rendering', 'letter-spacing', 'line-break',
  'line-height', 'list-style-image', 'list-style-position', 'list-style-type', 'orphans', 'overflow-wrap',
  'pointer-events', 'quotes', 'tab-size', 'text-align', 'text-align-last', 'text-indent', 'text-justify',
  'text-rendering', 'text-shadow', 'text-size-adjust', 'text-transform', 'text-wrap', 'text-wrap-mode',
  'visibility', 'white-space', 'widows', 'word-break', 'word-spacing', 'word-wrap', 'writing-mode',
  '-webkit-font-smoothing', '-webkit-text-fill-color', '-webkit-text-stroke-color', '-webkit-text-stroke-width',
  '-webkit-tap-highlight-color',
];

/** Properties read on every element, declared or not, because the port's gaps show up there first. */
export const BASE = [
  'background-color', 'color', 'display', 'font-family', 'font-size', 'font-style', 'font-weight', 'letter-spacing',
  'line-height', 'opacity', 'text-align', 'text-transform', 'visibility',
];

/**
 * One load, one set of roles.
 * arg: { roles: [{ part, role, selector }], props: null | { 'part/role': string[] }, inherited: string[], base: string[], withSelector: boolean }
 * With props == null the property list of a role is `base` plus every longhand declared by any rule that matches the
 * element (any media condition), minus custom properties; otherwise exactly the listed names.
 * Result: [{ part, role, count, cells: { prop: { v: string, s: { k, ... } } } }] for the first element of each role
 * (count 0 and no cells when the role matches nothing).
 */
export function collectReference(arg) {
  const mm = (q) => { try { return window.matchMedia(q).matches; } catch { return false; } };
  const base = (u) => { try { const p = new URL(u, location.href).pathname; return p.slice(p.lastIndexOf('/') + 1) || p; } catch { return String(u); } };

  // 1. every style rule, in document order, with whether its enclosing @media / @supports conditions hold now
  const flat = [];
  let order = 0;
  const walk = (list, sheetName, active, inMedia) => {
    for (const r of Array.from(list)) {
      if (r.selectorText !== undefined) {
        flat.push({ r, sheet: sheetName, order: order++, active, inMedia, names: null });
      } else if (r.styleSheet && r.media !== undefined) {
        try { walk(r.styleSheet.cssRules, sheetName, active && mm(r.media.mediaText || 'all'), true); } catch { /* unreadable */ }
      } else if (r.cssRules) {
        const nm = r.constructor && r.constructor.name;
        if (nm === 'CSSKeyframesRule' || nm === 'CSSFontFaceRule') continue;
        let a = active;
        let m = inMedia;
        if (r.media !== undefined) { a = a && mm(r.media.mediaText || 'all'); m = true; }
        else if (nm === 'CSSSupportsRule') { try { a = a && CSS.supports(r.conditionText); } catch { a = false; } }
        walk(r.cssRules, sheetName, a, m);
      }
    }
  };
  Array.from(document.styleSheets).forEach((sheet, i) => {
    if (sheet.disabled) return;
    let rules;
    try { rules = sheet.cssRules; } catch { return; }
    const name = sheet.href ? base(sheet.href) : `style-${i}`;
    walk(rules, name, !sheet.media || !sheet.media.mediaText || mm(sheet.media.mediaText), false);
  });
  const namesOf = (f) => {
    if (!f.names) { f.names = new Set(); for (let i = 0; i < f.r.style.length; i++) f.names.add(f.r.style[i]); }
    return f.names;
  };

  // 2. selector matching and an approximate specificity (ids, classes/attributes/pseudo-classes, types); layers are ignored
  const splitTop = (sel) => {
    const out = [];
    let depth = 0, q = '', cur = '';
    for (const ch of sel) {
      if (q) { cur += ch; if (ch === q) q = ''; continue; }
      if (ch === '"' || ch === "'") { q = ch; cur += ch; continue; }
      if (ch === '(' || ch === '[') depth++;
      if (ch === ')' || ch === ']') depth--;
      if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
      cur += ch;
    }
    if (cur.trim()) out.push(cur.trim());
    return out;
  };
  const specOf = (sel) => {
    let s = sel.replace(/"[^"]*"|'[^']*'/g, '""');
    let a = 0, b = 0, c = 0;
    // functional pseudo-classes: :where() counts 0; :is/:not/:has count their most specific argument
    for (;;) {
      const m = /:(where|is|not|has|matches|-webkit-any)\(/.exec(s);
      if (!m) break;
      let i = m.index + m[0].length, depth = 1;
      while (i < s.length && depth > 0) { if (s[i] === '(') depth++; else if (s[i] === ')') depth--; i++; }
      const inner = s.slice(m.index + m[0].length, i - 1);
      if (m[1] !== 'where') {
        let best = [0, 0, 0];
        for (const part of splitTop(inner)) {
          const p = specOf(part);
          if (p[0] > best[0] || (p[0] === best[0] && (p[1] > best[1] || (p[1] === best[1] && p[2] > best[2])))) best = p;
        }
        a += best[0]; b += best[1]; c += best[2];
      }
      s = s.slice(0, m.index) + s.slice(i);
    }
    s = s.replace(/\[[^\]]*\]/g, () => { b++; return ''; });
    s = s.replace(/::[\w-]+(\([^)]*\))?/g, () => { c++; return ''; });
    s = s.replace(/:[\w-]+(\([^)]*\))?/g, () => { b++; return ''; });
    s = s.replace(/#[\w-]+/g, () => { a++; return ''; });
    s = s.replace(/\.[\w-]+/g, () => { b++; return ''; });
    s = s.replace(/(^|[\s>+~])([a-zA-Z][\w-]*)/g, () => { c++; return ''; });
    return [a, b, c];
  };
  const matchCache = new Map();
  /** rules that match el (any media), with the specificity of the most specific matching selector of each */
  const matching = (el) => {
    if (matchCache.has(el)) return matchCache.get(el);
    const out = [];
    for (const f of flat) {
      let ok = false;
      try { ok = el.matches(f.r.selectorText); } catch { ok = false; }
      if (!ok) continue;
      let best = null;
      for (const part of splitTop(f.r.selectorText)) {
        let hit = false;
        try { hit = el.matches(part); } catch { hit = false; }
        if (!hit) continue;
        const p = specOf(part);
        if (!best || p[0] > best[0] || (p[0] === best[0] && (p[1] > best[1] || (p[1] === best[1] && p[2] > best[2])))) best = p;
      }
      out.push({ f, spec: best || [0, 0, 0] });
    }
    matchCache.set(el, out);
    return out;
  };
  const cmp = (x, y) => {
    for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return x[i] - y[i];
    return 0;
  };
  /** the declaration that wins the cascade for `name` on el, or null */
  const winner = (el, name) => {
    let best = null, bestKey = null;
    for (const m of matching(el)) {
      if (!m.f.active || !namesOf(m.f).has(name)) continue;
      const imp = m.f.r.style.getPropertyPriority(name) === 'important' ? 1 : 0;
      const key = [imp, 0, m.spec[0], m.spec[1], m.spec[2], m.f.order];
      if (!bestKey || cmp(key, bestKey) > 0) { best = m; bestKey = key; }
    }
    const inline = el.style && el.style.getPropertyValue(name) !== '' ? { inline: true, imp: el.style.getPropertyPriority(name) === 'important' } : null;
    if (inline && (!best || !bestKey[0] || inline.imp)) return { inline: true };
    return best ? { m: best } : null;
  };
  const sourceOf = (el, name) => {
    const w = winner(el, name);
    if (w && w.inline) return { k: 'inline' };
    if (w) {
      const s = { k: 'rule', sheet: w.m.f.sheet, ord: w.m.f.order };
      if (w.m.f.inMedia) s.media = true;
      if (w.m.f.r.style.getPropertyPriority(name) === 'important') s.imp = true;
      if (arg.withSelector) s.sel = w.m.f.r.selectorText;
      return s;
    }
    if (arg.inherited.includes(name)) {
      let up = 0;
      for (let a = el.parentElement; a; a = a.parentElement) {
        up++;
        if (winner(a, name)) return { k: 'inherited', from: a.tagName.toLowerCase(), up };
      }
    }
    return { k: 'initial' };
  };

  // 3. animated properties (a running animation changes the computed value from frame to frame; its value is not data)
  const animatedProps = (el) => {
    const set = new Set();
    let anims = [];
    try { anims = el.getAnimations(); } catch { anims = []; }
    for (const a of anims) {
      if (a.playState !== 'running') continue;
      let kfs = [];
      try { kfs = a.effect.getKeyframes(); } catch { kfs = []; }
      for (const kf of kfs) {
        for (const key of Object.keys(kf)) {
          if (['offset', 'easing', 'composite', 'computedOffset'].includes(key)) continue;
          set.add(key === 'cssFloat' ? 'float' : key.replace(/[A-Z]/g, (ch) => '-' + ch.toLowerCase()));
        }
      }
    }
    return set;
  };

  const out = [];
  for (const { part, role, selector } of arg.roles) {
    let els = [];
    try { els = Array.from(document.querySelectorAll(selector)); } catch { els = []; }
    if (els.length === 0) { out.push({ part, role, count: 0, cells: {} }); continue; }
    const el = els[0];
    const cs = getComputedStyle(el);
    let names;
    if (arg.props) names = arg.props[`${part}/${role}`] || [];
    else {
      const set = new Set(arg.base);
      for (const m of matching(el)) for (const n of namesOf(m.f)) if (!n.startsWith('--')) set.add(n);
      names = Array.from(set).sort();
    }
    const animated = animatedProps(el);
    const cells = {};
    for (const n of names) {
      const animates = animated.has(n) || (n === 'transform' && animated.has('translate')) || (n === 'translate' && animated.has('transform'));
      cells[n] = { v: animates ? '@animated' : cs.getPropertyValue(n), s: sourceOf(el, n) };
    }
    out.push({ part, role, count: els.length, cells });
  }
  return out;
}

/**
 * Fonts of one loaded page: the computed font-family of every element with its own text, the FontFace objects the page
 * holds (family, weight, style, load status), and the @font-face rules (family, weight, style, source file paths).
 * Reports; decides nothing.
 */
export async function collectFonts() {
  try { await document.fonts.ready; } catch { /* no font API */ }
  const unq = (s) => String(s).trim().replace(/^["']|["']$/g, '');
  const used = new Map();
  const all = document.body ? document.body.querySelectorAll('*') : [];
  for (const el of all) {
    let has = false;
    for (const n of el.childNodes) if (n.nodeType === 3 && n.nodeValue.trim() !== '') { has = true; break; }
    if (!has) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none') continue;
    const key = cs.fontFamily;
    const e = used.get(key) || { family: key, elements: 0, weights: new Set(), styles: new Set() };
    e.elements++; e.weights.add(cs.fontWeight); e.styles.add(cs.fontStyle);
    used.set(key, e);
  }
  const faces = [];
  try { document.fonts.forEach((f) => faces.push({ family: unq(f.family), weight: f.weight, style: f.style, status: f.status })); } catch { /* none */ }
  const rules = [];
  const walk = (list, href) => {
    for (const r of Array.from(list)) {
      const nm = r.constructor && r.constructor.name;
      if (nm === 'CSSFontFaceRule') {
        const src = r.style.getPropertyValue('src') || '';
        const urls = [];
        for (const m of src.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*))\s*\)/g)) {
          const u = m[1] ?? m[2] ?? m[3];
          if (u.startsWith('data:')) { urls.push('data:'); continue; }
          try { urls.push(new URL(u, href || location.href).pathname); } catch { urls.push(u); }
        }
        rules.push({ family: unq(r.style.getPropertyValue('font-family')), weight: r.style.getPropertyValue('font-weight'), style: r.style.getPropertyValue('font-style'), urls });
      } else if (r.styleSheet) { try { walk(r.styleSheet.cssRules, r.styleSheet.href); } catch { /* unreadable */ } }
      else if (r.cssRules) walk(r.cssRules, href);
    }
  };
  for (const sheet of Array.from(document.styleSheets)) { try { walk(sheet.cssRules, sheet.href); } catch { /* unreadable */ } }
  return {
    used: Array.from(used.values()).map((e) => ({ family: e.family, elements: e.elements, weights: Array.from(e.weights).sort(), styles: Array.from(e.styles).sort() }))
      .sort((a, b) => (a.family < b.family ? -1 : a.family > b.family ? 1 : 0)),
    faces: faces.sort((a, b) => JSON.stringify(a) < JSON.stringify(b) ? -1 : 1),
    rules,
  };
}
