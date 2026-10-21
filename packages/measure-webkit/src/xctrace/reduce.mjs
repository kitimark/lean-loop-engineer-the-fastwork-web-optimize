// xctrace-ci-probe: the reducer. Pure functions from `xctrace export` XML plus the sweep windows to per-zone counts.
//   toc.xml     <run number="1"><info><summary><start-date>..</start-date>: the wall-clock start of the recording
//   <schema>.xml  <node><schema/><row>..</row>..</node>: one element per column value; a repeated value is <tag ref="n"/> of an
//               earlier <tag id="n">. The time columns hold nanoseconds since the start of the recording.
// A sweep window [t0, t1] (epoch ms, the page's clock) maps to trace time (t - startDate) * 1e6 ns. The error of that map is the
// resolution of start-date plus the clock offset between the page and the recorder (same host, so the offset is 0 by construction);
// the note says what the resolution was. A row belongs to a zone when its start time lies inside one of the zone's windows.

/** Entities xctrace writes. */
const ENT = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" };
const unent = (s) => s.replace(/&(amp|lt|gt|quot|apos);/g, (m) => ENT[m]);

/** A tolerant XML reader: [{tag, attrs, text, children}] as a tree; the root is the first element. */
export function parseXml(xml) {
  const root = { tag: '#root', attrs: {}, text: '', children: [] };
  const stack = [root];
  const re = /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>|([^<]+)/g;
  let m;
  while ((m = re.exec(xml))) {
    if (m[5] !== undefined) { stack.at(-1).text += unent(m[5]); continue; }
    if (m[2] === undefined) continue;
    if (m[1]) { if (stack.length > 1) stack.pop(); continue; }
    const attrs = {};
    for (const a of m[3].matchAll(/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) attrs[a[1]] = unent(a[2] ?? a[3]);
    const node = { tag: m[2], attrs, text: '', children: [] };
    stack.at(-1).children.push(node);
    if (!m[4]) stack.push(node);
  }
  return root.children[0] ?? null;
}

const walk = (n, f) => { f(n); for (const c of n.children) walk(c, f); };

/** The wall-clock start of run 1 in epoch ms, or null. */
export function tocStartMs(toc) {
  const m = /<start-date>([^<]+)<\/start-date>/.exec(toc);
  if (!m) return null;
  const t = Date.parse(m[1].trim());
  return Number.isFinite(t) ? t : null;
}

const TIME_TAGS = new Set(['start-time', 'start', 'time', 'event-time', 'timestamp', 'begin-time']);
const DUR_TAGS = new Set(['duration']);

/** Resolve `ref` attributes against the `id` elements of the whole table; returns a function that gives the resolved node. */
function resolver(tree) {
  const byId = new Map();
  walk(tree, (n) => { if (n.attrs.id !== undefined) byId.set(n.attrs.id, n); });
  return (n) => (n.attrs.ref !== undefined ? byId.get(n.attrs.ref) ?? n : n);
}

/** Rows of one exported table: [{t (ns or null), dur (ns or null), cols: {tag: text}}]. */
export function rowsOf(xml) {
  const tree = parseXml(xml);
  if (!tree) return [];
  const res = resolver(tree);
  const rows = [];
  walk(tree, (n) => {
    if (n.tag !== 'row') return;
    const cols = {};
    let t = null, dur = null;
    for (const c of n.children) {
      const r = res(c);
      const text = (r.text || r.attrs.fmt || '').trim();
      if (!(c.tag in cols)) cols[c.tag] = text;
      if (t === null && TIME_TAGS.has(c.tag) && /^-?\d+$/.test(r.text.trim())) t = Number(r.text.trim());
      if (dur === null && DUR_TAGS.has(c.tag) && /^-?\d+$/.test(r.text.trim())) dur = Number(r.text.trim());
    }
    rows.push({ t, dur, cols });
  });
  return rows;
}

/** Windows of a zone in trace ns: [[a, b]] from the epoch-ms windows of the sweeps. */
export function traceWindows(windows, startMs, zone) {
  return windows.filter((w) => w.zone === zone).map((w) => [(w.t0 - startMs) * 1e6, (w.t1 - startMs) * 1e6]);
}

/** Per-zone counts of rows: a row counts for a zone when its time lies in one of the zone's windows (inclusive). Durations are summed in ms. */
export function zoneCounts(rows, windows, startMs, zones = ['A', 'B']) {
  const out = { rowsTotal: rows.length, timed: rows.filter((r) => r.t !== null).length };
  for (const z of zones) {
    const ws = traceWindows(windows, startMs, z);
    const inZ = rows.filter((r) => r.t !== null && ws.some(([a, b]) => r.t >= a && r.t <= b));
    out[z] = { rows: inZ.length, durMs: Math.round(inZ.reduce((s, r) => s + (r.dur ?? 0), 0) / 1e3) / 1e3 };
  }
  return out;
}

/** Lines of the recorder's own output that name a problem. */
export const issuesOf = (text) => String(text || '').split('\n').map((l) => l.trim()).filter((l) => /\[(Error|Warning)\]|failed|not supported|cannot|denied|permission/i.test(l));

/** Reduce one recorded pass: `rec` is <arm>-p<n>.json, `read(file)` returns a file's text or null. */
export function reducePass(rec, read, maxBytes = 300e6) {
  const dir = `${rec.arm}-p${rec.pass}`;
  const toc = read(`${dir}/toc.xml`);
  const startMs = toc ? tocStartMs(toc) : null;
  const res = {
    arm: rec.arm, pass: rec.pass, started: !!rec.started, sudo: !!rec.sudo, exit: rec.stopped?.code ?? null, issues: issuesOf(rec.xctraceOutput),
    sweeps: rec.windows ? rec.windows.length : 0, startDate: startMs, tables: {},
  };
  for (const t of rec.tables ?? []) {
    if (!t.bytes) { res.tables[t.schema] = { rowsTotal: 0, empty: true }; continue; }
    if (t.bytes > maxBytes) { res.tables[t.schema] = { skipped: `${t.bytes} bytes` }; continue; }
    const xml = read(`${dir}/${t.file}`);
    if (xml === null) continue;
    const rows = rowsOf(xml);
    res.tables[t.schema] = rec.windows && startMs !== null ? zoneCounts(rows, rec.windows, startMs) : { rowsTotal: rows.length, noWindows: true };
  }
  return res;
}

/** Reduce every <arm>-p<n>.json under `dir`. `io` = {readFileSync, readdirSync, existsSync, join} (so tests pass a fake). */
export function reduceDir(dir, io) {
  const read = (f) => { const p = io.join(dir, f); return io.existsSync(p) ? io.readFileSync(p, 'utf8') : null; };
  const recs = io.readdirSync(dir).filter((f) => /^[\w-]+-p\d+\.json$/.test(f)).sort().map((f) => JSON.parse(read(f)));
  return { schema: 'fw.xctrace.counts/1', passes: recs.map((r) => reducePass(r, read)) };
}
