// The align-self equivalence of the breakpoint gate, mirrored from Lean (lean/Fw/Gate/AlignEquiv.lean, statements and
// proofs there; test/align-equiv.test.mjs replays packages/contracts/golden/gate/align-equiv.jsonl):
//   two declared align-self values of a grid item are judged equal when, each read in its own arm's context, they
//   give the same used alignment under css-align-3 6.1/6.2/6.2.5 and css-grid-1 6.2 (Lean `equivSpec_sound`).
// The gate then sets the rewrite item's align-self to the original's (Lean `canonItem`); boxes are still compared
// (Lean `geometry_still_compared`). collectAlignFacts runs in the page (self-contained, no closures) and only reads.

// ---------------------------------------------------------------------------------------------------------------
// The rule (each function is the Lean definition of the same name)
// ---------------------------------------------------------------------------------------------------------------

const NUM = '-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?'; // Fw.Gate.numAt
const PX = new RegExp(`^(${NUM})px$`);
const POS = new RegExp(`^(${NUM})$`);
export const tolFill = 1 / 16;

export const near = (t, x, y) => x - y <= t && y - x <= t;
export const resolve = (s) => (s.alignSelf === 'auto' ? s.alignItems : s.alignSelf);
export const posNum = (v) => { const m = POS.exec(v); return m !== null && Number(m[1]) > 0; };

export function ratioOf(v) {
  if (v === 'auto') return false;
  const body = v.startsWith('auto ') ? v.slice(5) : v;
  const ab = body.split(' / ');
  return ab.length === 2 && posNum(ab[0]) && posNum(ab[1]) ? true : null;
}

export const replacedTags = ['img', 'video', 'audio', 'canvas', 'iframe', 'embed', 'object', 'input', 'textarea', 'select', 'button', 'meter', 'progress', 'frame'];
export const blockContainer = (s) => s.html && (s.display === 'block' || s.display === 'flow-root') && !replacedTags.includes(s.localName);

/** 'content' | 'fill' | 'other' */
export function modeOf(s) {
  const v = resolve(s);
  if (v === 'stretch') return 'fill';
  if (v === 'start' || v === 'flex-start') return 'content';
  if (v === 'normal' && blockContainer(s)) {
    const r = ratioOf(s.aspectRatio);
    return r === false ? 'fill' : 'other'; // with a ratio: Chromium stretches, WebKit does not (Lean modeOf_normal_ratio)
  }
  return 'other';
}

export const eligible = (s) =>
  (s.parentDisplay === 'grid' || s.parentDisplay === 'inline-grid') &&
  s.position !== 'absolute' && s.position !== 'fixed' &&
  s.display !== 'none' && s.display !== 'contents' &&
  s.writingMode === 'horizontal-tb' && s.parentWritingMode === 'horizontal-tb' &&
  !s.autoMargin && s.heightAuto;

export const px = (v) => { const m = PX.exec(v); return m === null ? null : Number(m[1]); };

export function stripNames(v) {
  let d = 0, out = '';
  for (const c of v) {
    if (c === '[') { out += ' '; d += 1; } else if (c === ']') { out += ' '; d = Math.max(0, d - 1); } else if (d === 0) out += c;
  }
  return out;
}

export function parseTracks(v) {
  const ws = stripNames(v).split(' ').filter((w) => w !== '');
  if (ws.length === 0) return null;
  const ts = ws.map(px);
  return ts.includes(null) ? null : ts;
}

export const gapOf = (s) => (s.rowGap === 'normal' ? 0 : px(s.rowGap));

export function borderH(s) {
  const h = px(s.height);
  if (h === null) return null;
  if (s.boxSizing === 'border-box') return h;
  const xs = [s.paddingTop, s.paddingBottom, s.borderTop, s.borderBottom].map(px);
  return xs.includes(null) ? null : h + xs[0] + xs[1] + xs[2] + xs[3];
}

export function outerOf(s) {
  const b = borderH(s), mt = px(s.marginTop), mb = px(s.marginBottom);
  return b === null || mt === null || mb === null ? null : b + mt + mb;
}

export function offsetOf(s) {
  const bt = px(s.parentBorderTop), pt = px(s.parentPaddingTop), mt = px(s.marginTop);
  return bt === null || pt === null || mt === null ? null : s.rectTop - s.parentRectTop - bt - pt - mt;
}

export function starts(ts, g) {
  const out = [];
  let acc = 0;
  for (const t of ts) { out.push(acc); acc += t + g; }
  return out;
}

export const matchesAt = (ss, x) => ss.flatMap((v, k) => (near(tolFill, v, x) ? [k] : []));
export const isIntStr = (v) => /^-?\d+$/.test(v);
export const spanOne = (s) => (s.rowEnd === 'auto' || s.rowEnd === 'span 1') && (s.rowStart === 'auto' || isIntStr(s.rowStart));

export function contentFill(s) {
  if (!['normal', 'stretch', 'start', 'flex-start'].includes(s.alignContent) || !spanOne(s)) return false;
  const ts = parseTracks(s.rows), g = gapOf(s), b = borderH(s), out = outerOf(s), off = offsetOf(s);
  if (ts === null || g === null || b === null || out === null || off === null) return false;
  if (!(b > 0) || !near(tolFill, s.rectHeight, b)) return false;
  const m = matchesAt(starts(ts, g), off);
  return m.length === 1 && near(tolFill, ts[m[0]], out);
}

export function equivSpec(o, r) {
  if (!eligible(o) || !eligible(r)) return false;
  const mo = modeOf(o), mr = modeOf(r);
  if (mo === mr) return mo !== 'other';
  if (mo === 'fill' && mr === 'content') return contentFill(r);
  if (mo === 'content' && mr === 'fill') return contentFill(o);
  return false;
}

export const alignEquiv = (o, r) => o.alignSelf === r.alignSelf || equivSpec(o, r);

// ---------------------------------------------------------------------------------------------------------------
// The gate's use (Lean canonItem): applied to the rewrite arm's parts before the verdict request
// ---------------------------------------------------------------------------------------------------------------

/** Rewrite parts with each judged-equivalent pair's align-self set to the original's (removed if the original has
 *  none). Items need `align` facts on both arms; items without them are left as they are. Nothing is mutated. */
export function canonParts(origParts, rewriteParts) {
  if (!origParts || !rewriteParts) return rewriteParts;
  const out = {};
  for (const [pid, roles] of Object.entries(rewriteParts)) {
    out[pid] = {};
    for (const [role, rr] of Object.entries(roles)) {
      const or = origParts[pid]?.[role];
      if (!or || !Array.isArray(rr.items)) { out[pid][role] = rr; continue; }
      const items = rr.items.map((ir, i) => {
        const io = or.items?.[i];
        if (!io || !io.align || !ir.align || !alignEquiv(io.align, ir.align)) return ir;
        const style = { ...ir.style };
        if (io.style?.['align-self'] === undefined) delete style['align-self'];
        else style['align-self'] = io.style['align-self'];
        return { ...ir, style };
      });
      out[pid][role] = { ...rr, items };
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Facts, collected in the page (pass to page.evaluate; self-contained)
// ---------------------------------------------------------------------------------------------------------------

/**
 * arg: { parts: { [partId]: [{ role, selector }] }, props: { [partId]: { [role]: string[] } } }
 * Returns { [partId]: { [role]: (facts | null)[] } } for the roles whose props include align-self, items in the
 * order collectInPage reports them (querySelectorAll, first 64). Declared facts read every style rule whose
 * @media / @supports holds and whose selector matches (or cannot be tested), plus the inline style.
 */
export function collectAlignFacts(arg) {
  const mm = (q) => { try { return window.matchMedia(q).matches; } catch { return true; } };
  const sup = (q) => { try { return CSS.supports(q); } catch { return true; } };
  const rules = [];
  const walk = (list) => {
    for (const r of list) {
      if (typeof CSSMediaRule !== 'undefined' && r instanceof CSSMediaRule && !mm(r.media.mediaText)) continue;
      if (typeof CSSSupportsRule !== 'undefined' && r instanceof CSSSupportsRule && !sup(r.conditionText)) continue;
      if (typeof CSSImportRule !== 'undefined' && r instanceof CSSImportRule) {
        if (mm(r.media.mediaText || 'all')) { try { walk(r.styleSheet.cssRules); } catch { /* cross-origin */ } }
        continue;
      }
      if (r.selectorText !== undefined && r.style) rules.push(r);
      if (r.cssRules) walk(r.cssRules);
    }
  };
  for (const sheet of Array.from(document.styleSheets)) {
    try { walk(sheet.cssRules); } catch { /* cross-origin sheet */ }
  }
  const matches = (el, sel) => { try { return el.matches(sel); } catch { return true; } };
  const declared = (el, names) => {
    const vals = [];
    for (const r of rules) {
      if (!matches(el, r.selectorText)) continue;
      for (const n of names) { const v = r.style.getPropertyValue(n); if (v) vals.push(v.trim()); }
    }
    for (const n of names) { const v = el.style ? el.style.getPropertyValue(n) : ''; if (v) vals.push(v.trim()); }
    return vals;
  };
  const indirect = /inherit|unset|revert|var\(|attr\(|env\(/i;
  const facts = (el) => {
    const p = el.parentElement;
    if (!p) return null;
    const cs = getComputedStyle(el), pcs = getComputedStyle(p);
    const r = el.getBoundingClientRect(), pr = p.getBoundingClientRect();
    const longMargins = declared(el, ['margin-top', 'margin-bottom', 'margin-block-start', 'margin-block-end']);
    const shortMargins = declared(el, ['margin', 'margin-block']);
    return {
      alignSelf: cs.alignSelf, alignItems: pcs.alignItems, display: cs.display, position: cs.position,
      localName: el.localName, html: el.namespaceURI === 'http://www.w3.org/1999/xhtml', aspectRatio: cs.aspectRatio,
      writingMode: cs.writingMode, parentDisplay: pcs.display, parentWritingMode: pcs.writingMode,
      autoMargin: longMargins.some((v) => /auto/i.test(v) || indirect.test(v)) || shortMargins.some((v) => indirect.test(v)),
      heightAuto: declared(el, ['height', 'block-size']).every((v) => v === 'auto' || v === 'initial' || v === 'unset'),
      alignContent: pcs.alignContent, rowStart: cs.gridRowStart, rowEnd: cs.gridRowEnd, rows: pcs.gridTemplateRows,
      rowGap: pcs.rowGap, boxSizing: cs.boxSizing, height: cs.height, paddingTop: cs.paddingTop,
      paddingBottom: cs.paddingBottom, borderTop: cs.borderTopWidth, borderBottom: cs.borderBottomWidth,
      marginTop: cs.marginTop, marginBottom: cs.marginBottom, parentBorderTop: pcs.borderTopWidth,
      parentPaddingTop: pcs.paddingTop, rectTop: r.top, rectHeight: r.height, parentRectTop: pr.top,
    };
  };
  const out = {};
  for (const [pid, roles] of Object.entries(arg.parts)) {
    for (const { role, selector } of roles) {
      const names = arg.props && arg.props[pid] && arg.props[pid][role] ? arg.props[pid][role] : [];
      if (!names.includes('align-self')) continue;
      out[pid] = out[pid] || {};
      out[pid][role] = Array.from(document.querySelectorAll(selector)).slice(0, 64).map(facts);
    }
  }
  return out;
}

/** Attach collected facts to a collectInPage record's items (item.align), in place; returns the record. */
export function attachAlignFacts(record, facts) {
  for (const [pid, roles] of Object.entries(facts ?? {})) {
    for (const [role, list] of Object.entries(roles)) {
      const items = record?.parts?.[pid]?.[role]?.items;
      if (!Array.isArray(items)) continue;
      items.forEach((it, i) => { if (list[i]) it.align = list[i]; });
    }
  }
  return record;
}
