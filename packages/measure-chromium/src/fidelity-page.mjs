export const PIN_DATE_SRC = `(() => {
  const FIXED = Date.parse('2026-10-01T00:00:00+07:00');
  const RealDate = Date;
  function FakeDate(...a) {
    if (!new.target) return new RealDate(FIXED).toString();
    return a.length === 0 ? new RealDate(FIXED) : new RealDate(...a);
  }
  FakeDate.prototype = RealDate.prototype;
  FakeDate.now = () => FIXED;
  FakeDate.parse = RealDate.parse;
  FakeDate.UTC = RealDate.UTC;
  Object.defineProperty(FakeDate, 'name', { value: 'Date' });
  window.Date = FakeDate;
  let s = 0x9e3779b9 >>> 0;
  Math.random = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();`;

/**
 * arg: { rows: [{part, sel}], readySel, capMs, settleMs, stableFor, pollMs }.
 * Returns { docH, bodyH, innerW, innerH, dpr, vvW, ready, settled, polls, parts, leaves, faces, uncovered, totalCps, marked }.
 */
export async function fidelityInPage({ rows, readySel = null, capMs = 20000, settleMs = 15000, stableFor = 6, pollMs = 250 }) {
  const sleepP = (ms) => new Promise((r) => setTimeout(r, ms));
  const frames = async (n) => { for (let i = 0; i < n; i++) await Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleepP(250)]); };
  const unq = (s) => s.trim().replace(/^["']|["']$/g, '');
  const docH = () => document.documentElement.scrollHeight;
  const faces = () => Array.from(document.fonts).map((f) => ({ family: unq(f.family), weight: f.weight, style: f.style, status: f.status, range: f.unicodeRange }));
  const visit = async (top) => { window.scrollTo({ top, behavior: 'instant' }); await frames(2); await sleepP(120); };

  let ready = readySel === null;
  const t0 = performance.now();
  while (!ready && performance.now() - t0 < capMs) {
    ready = document.querySelector(readySel) !== null;
    if (!ready) await sleepP(100);
  }
  try { await Promise.race([document.fonts.ready, sleepP(2000)]); } catch {}

  const step = Math.max(200, window.innerHeight);
  for (let y = 0, i = 0; i < 300; i++, y += step) {
    await visit(y);
    if (y + window.innerHeight >= docH()) break;
  }
  for (const { sel } of rows) {
    const el = document.querySelector(sel);
    if (!el) continue;
    el.scrollIntoView({ block: 'center', behavior: 'instant' });
    await frames(2);
    await sleepP(60);
  }
  await visit(0);
  while (performance.now() - t0 < capMs + 10000 && faces().some((f) => f.status === 'loading')) await sleepP(50);

  const skip = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE']);
  const read = () => {
    const owned = new Map();
    for (const { part, sel } of rows) for (const el of document.querySelectorAll(sel)) if (!owned.has(el)) owned.set(el, part);
    const ownerOf = (el) => { for (let e = el; e; e = e.parentElement) if (owned.has(e)) return owned.get(e); return 'page'; };
    const texts = new Map();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n && texts.size < 20000; n = walker.nextNode()) {
      const el = n.parentElement;
      if (!el || skip.has(el.tagName)) continue;
      const a = texts.get(el) ?? { text: '', nodes: [] };
      a.text += n.nodeValue;
      a.nodes.push(n);
      texts.set(el, a);
    }
    const leaves = [];
    for (const [el, { text, nodes }] of texts) {
      if (text.trim() === '') continue;
      const cs = getComputedStyle(el);
      const tops = new Set();
      let w = 0;
      for (const n of nodes) {
        const r = document.createRange();
        r.selectNodeContents(n);
        for (const q of r.getClientRects()) if (q.width > 0 && q.height > 0) { tops.add(Math.round(q.top + window.scrollY)); w = Math.max(w, q.width); }
      }
      leaves.push({ el, sec: ownerOf(el), text, family: unq(cs.fontFamily.split(',')[0] ?? ''), weight: cs.fontWeight, size: cs.fontSize, lines: tops.size, maxW: Math.round(w * 100) / 100 });
    }
    return leaves;
  };
  const sigOf = () => JSON.stringify([docH(), read().map((l) => [l.sec, l.text, l.lines]), faces().map((f) => f.status)]);
  const t1 = performance.now();
  let prev = null;
  let same = 0;
  let polls = 0;
  while (performance.now() - t1 < settleMs) {
    await sleepP(pollMs);
    polls++;
    const sig = sigOf();
    if (sig === prev) { if (++same >= stableFor) break; } else { same = 0; prev = sig; }
  }

  const round = (x) => Math.round(x * 100) / 100;
  const parts = {};
  for (const { part, sel } of rows) {
    const all = document.querySelectorAll(sel);
    const el = all[0];
    if (!el) { parts[part] = { n: 0 }; continue; }
    const r = el.getBoundingClientRect();
    parts[part] = { n: all.length, top: round(r.top + window.scrollY), height: round(r.height), left: round(r.left + window.scrollX), width: round(r.width) };
  }

  const ranges = [];
  const loadedFaces = faces().filter((f) => f.status === 'loaded');
  for (const f of loadedFaces) {
    for (const tok of (f.range || 'U+0-10FFFF').split(',')) {
      const m = /^U\+([0-9A-Fa-f?]+)(?:-([0-9A-Fa-f]+))?$/.exec(tok.trim());
      if (!m) continue;
      if (m[1].includes('?')) ranges.push([parseInt(m[1].replace(/\?/g, '0'), 16), parseInt(m[1].replace(/\?/g, 'F'), 16)]);
      else ranges.push([parseInt(m[1], 16), parseInt(m[2] ?? m[1], 16)]);
    }
  }
  const webCovered = (c) => ranges.some(([a, b]) => c >= a && c <= b);
  const ignorable = (c) => c < 0x20 || (c >= 0x7f && c < 0xa0) || c === 0xa0 || c === 0xad || (c >= 0x200b && c <= 0x200f) || c === 0x2028 || c === 0x2029 || c === 0xfeff || c === 0x20 || c === 0x3000;
  const leaves = read();
  const counts = new Map();
  const marked = [];
  let totalCps = 0;
  for (const l of leaves) {
    let hit = false;
    for (const ch of l.text) {
      const c = ch.codePointAt(0);
      if (ignorable(c)) continue;
      totalCps++;
      if (!webCovered(c)) { counts.set(c, (counts.get(c) ?? 0) + 1); hit = true; }
    }
    if (hit && marked.length < 400) { l.el.setAttribute('data-fw-fid', String(marked.length)); marked.push(marked.length); }
  }
  return {
    docH: docH(), bodyH: document.body.scrollHeight, innerW: window.innerWidth, innerH: window.innerHeight, dpr: window.devicePixelRatio,
    vvW: window.visualViewport ? round(window.visualViewport.width) : null, ready, settled: same >= stableFor, polls, parts,
    leaves: leaves.slice(0, 6000).map(({ el, text, ...rest }) => ({ ...rest, text: text.length > 80 ? `${text.slice(0, 80)}~${text.length}` : text })),
    leafCount: leaves.length, faces: faces().map(({ family, weight, style, status }) => ({ family, weight, style, status })),
    uncovered: Array.from(counts.entries()).sort((a, b) => a[0] - b[0]), totalCps, marked: marked.length,
  };
}
