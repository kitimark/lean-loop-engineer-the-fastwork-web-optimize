export const TABLE = new Map([
  ['padding-inline', ['padding-inline-start', 'padding-inline-end']],
  ['padding-block', ['padding-block-start', 'padding-block-end']],
  ['margin-inline', ['margin-inline-start', 'margin-inline-end']],
  ['margin-block', ['margin-block-start', 'margin-block-end']],
  ['inset-inline', ['inset-inline-start', 'inset-inline-end']],
  ['inset-block', ['inset-block-start', 'inset-block-end']],
  ['padding', ['padding-top', 'padding-right', 'padding-bottom', 'padding-left']],
  ['margin', ['margin-top', 'margin-right', 'margin-bottom', 'margin-left']],
  ['inset', ['top', 'right', 'bottom', 'left']],
]);

const KEYS = [['props', 'transition-property'], ['durs', 'transition-duration'], ['timings', 'transition-timing-function'],
  ['delays', 'transition-delay'], ['behaviors', 'transition-behavior']];

const expand = (p) => TABLE.get(p) ?? [p];

export function normalize(t) {
  const filled = t.durs.length > 0 && t.timings.length > 0 && t.delays.length > 0 && t.behaviors.length > 0;
  if (!(t.props.some((p) => TABLE.has(p)) && filled)) return t;
  const out = { props: [], durs: [], timings: [], delays: [], behaviors: [] };
  t.props.forEach((p, i) => {
    for (const l of expand(p)) {
      out.props.push(l);
      for (const k of ['durs', 'timings', 'delays', 'behaviors']) out[k].push(t[k][i % t[k].length]);
    }
  });
  return out;
}

export function splitList(s) {
  const out = []; let depth = 0, cur = '';
  for (const c of s) {
    if (c === '(') depth++; else if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur.trim()); cur = ''; } else cur += c;
  }
  if (cur.trim() !== '' || out.length) out.push(cur.trim());
  return out;
}

export const joinList = (l) => l.join(', ');

export function normalizeStyle(style) {
  if (!style || KEYS.some(([, k]) => typeof style[k] !== 'string')) return style;
  const t = Object.fromEntries(KEYS.map(([f, k]) => [f, splitList(style[k])]));
  const n = normalize(t);
  if (n === t) return style;
  const out = { ...style };
  for (const [f, k] of KEYS) out[k] = joinList(n[f]);
  return out;
}

export function normalizeParts(parts) {
  if (!parts) return parts;
  const out = {};
  for (const [pid, roles] of Object.entries(parts)) {
    out[pid] = {};
    for (const [role, r] of Object.entries(roles)) {
      out[pid][role] = Array.isArray(r.items) ? { ...r, items: r.items.map((it) => (it.style ? { ...it, style: normalizeStyle(it.style) } : it)) } : r;
    }
  }
  return out;
}
