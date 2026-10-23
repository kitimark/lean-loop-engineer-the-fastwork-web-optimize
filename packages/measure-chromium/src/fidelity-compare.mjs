import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fontDist, fontPick, notdefCount } from './profile.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const DIR = args.dir;
if (!DIR) { console.error('usage: fidelity-compare.mjs --dir=<dir> [--ref=webkit-mac] [--pick-views=m430,d1280] [--phone-doc=N] [--out=<dir>]'); process.exit(2); }
const REF = args.ref ?? 'webkit-mac';
const PICK_VIEWS = (args['pick-views'] ?? 'm430,d1280').split(',');
const OUT = args.out ?? DIR;

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const files = walk(DIR).filter((p) => /fidelity-[^/]*\.json$/.test(p));
const runs = files.map((p) => ({ file: p, ...JSON.parse(readFileSync(p, 'utf8')) })).filter((j) => j.schema === 'fw.font-fidelity/1');
const ref = runs.find((r) => r.variant === REF);
if (!ref) { console.error(`no reference file for ${REF} under ${DIR}`); process.exit(1); }
const sims = runs.filter((r) => r.variant.startsWith('sim'));
const cand = runs.filter((r) => r.set);
const names = [...new Set(cand.map((r) => r.set.name))];
const first = (n) => cand.filter((r) => r.set.name === n).sort((a, b) => a.file.localeCompare(b.file));

const rnd = (x) => Math.round(x);
const partPairs = (refV, gotV) => Object.keys(refV.parts).filter((k) => refV.parts[k].n > 0 && gotV.parts?.[k]?.n > 0).map((k) => [rnd(refV.parts[k].height), rnd(gotV.parts[k].height)]);
const partDiffs = (refV, gotV) => Object.keys(refV.parts).filter((k) => refV.parts[k].n > 0 && gotV.parts?.[k]?.n > 0)
  .map((k) => ({ part: k, ref: refV.parts[k].height, got: gotV.parts[k].height, d: Math.round((gotV.parts[k].height - refV.parts[k].height) * 100) / 100 })).filter((x) => Math.abs(x.d) >= 1).sort((a, b) => Math.abs(b.d) - Math.abs(a.d));
const usable = (v) => v && !v.crash && !v.error && typeof v.docH === 'number';
const leafKey = (l) => `${l.sec}\u0000${l.text}`;
function leafDiff(refV, gotV) {
  const seen = new Map();
  const g = new Map();
  for (const l of gotV.leaves) { const k = leafKey(l); const n = seen.get(k) ?? 0; seen.set(k, n + 1); g.set(`${k}\u0000${n}`, l); }
  const used = new Map();
  let same = 0, differ = 0, missing = 0;
  const rows = [];
  for (const l of refV.leaves) {
    const k = leafKey(l); const n = used.get(k) ?? 0; used.set(k, n + 1);
    const o = g.get(`${k}\u0000${n}`);
    if (!o) { missing++; continue; }
    if (o.lines === l.lines) same++; else { differ++; rows.push({ sec: l.sec, text: l.text.slice(0, 40), ref: l.lines, got: o.lines, family: l.family, gotFamily: o.family }); }
  }
  return { same, differ, missing, rows };
}

const score = (r, idx) => {
  let dist = 0, notdef = 0, ok = true;
  for (const id of PICK_VIEWS) {
    const rv = ref.views[id], gv = r.views[id];
    if (!usable(rv) || !usable(gv)) { ok = false; continue; }
    dist += fontDist(rnd(rv.docH), rnd(gv.docH), partPairs(rv, gv));
    notdef += notdefCount(new Set(gv.systemCovered ?? []), gv.uncovered ?? []);
  }
  return ok ? { name: r.set.name, idx, dist, notdef, pkgs: r.set.pkgs.length } : null;
};

const out = [];
const p = (s = '') => out.push(s);
const viewIds = [...new Set([...Object.keys(ref.views)])];
p(`## Font fidelity: ${names.length} candidate sets against ${REF} (${ref.browser}, ${ref.platform})`);
p();
p('### Document height (scrollHeight, CSS px) per view');
p();
p(`| engine / set | ${viewIds.map((v) => `${v} (${ref.views[v].width}x${ref.views[v].height})`).join(' | ')} |`);
p(`|---|${viewIds.map(() => '---').join('|')}|`);
p(`| **${REF}** (reference) | ${viewIds.map((v) => (usable(ref.views[v]) ? ref.views[v].docH : 'n/a')).join(' | ')} |`);
for (const s of sims) {
  const sv = s.views.sim;
  const note = usable(sv) ? ` (inner ${sv.innerW}x${sv.innerH} dpr ${sv.dpr})` : '';
  p(`| ${s.variant} (${s.browser}) | ${viewIds.map((v) => (usable(sv) && sv.innerW === ref.views[v].width && sv.innerH === ref.views[v].height && ref.views[v].mobile ? `${sv.docH}${note}` : 'n/a')).join(' | ')} |`);
}
if (args['phone-doc']) p(`| phone (iPhone 15 Pro Max Safari, results/phone/2026-10-17-s1) | n/a | ${args['phone-doc']} | n/a |`);
const scores = [];
const excluded = [];
names.forEach((n, i) => {
  const rs = first(n);
  const cells = viewIds.map((v) => {
    const vs = rs.map((r) => r.views[v]);
    if (vs.some((x) => !usable(x))) return vs.map((x) => (x?.crash ? 'CRASH' : x?.error ? 'error' : 'n/a')).join('/');
    const docs = vs.map((x) => x.docH);
    return docs.every((d) => d === docs[0]) ? `${docs[0]}` : `${docs.join(' / ')} (reps differ)`;
  });
  p(`| ${n} | ${cells.join(' | ')} |`);
  const sc = score(rs[0], i);
  if (sc) scores.push(sc); else excluded.push(n);
});
p();
p('### Distance to the reference (Lean fontDist: document-height gap + sum of part-height gaps, CSS px, rounded), .notdef occurrences, line-count mismatches');
p();
p(`| set | packages | ${viewIds.map((v) => `${v} dist | ${v} notdef | ${v} leaves (same/differ/missing)`).join(' | ')} |`);
p(`|---|---|${viewIds.map(() => '---|---|---').join('|')}|`);
for (const n of names) {
  const r = first(n)[0];
  const cells = viewIds.map((v) => {
    const rv = ref.views[v], gv = r.views[v];
    if (!usable(rv) || !usable(gv)) return 'n/a | n/a | n/a';
    const d = fontDist(rnd(rv.docH), rnd(gv.docH), partPairs(rv, gv));
    const nd = notdefCount(new Set(gv.systemCovered ?? []), gv.uncovered ?? []);
    const l = leafDiff(rv, gv);
    return `${d} | ${nd} | ${l.same}/${l.differ}/${l.missing}`;
  });
  p(`| ${n} | ${r.set.pkgs.join('+') || '-'} | ${cells.join(' | ')} |`);
}
p();
p('### Pick (Lean fontPick over the sets that did not crash in the pick views)');
p();
p(`Pick views: ${PICK_VIEWS.join(', ')}. Excluded (crash, error or missing view): ${excluded.join(', ') || 'none'}.`);
p();
p('| set | idx | dist | notdef | packages |');
p('|---|---|---|---|---|');
for (const s of scores) p(`| ${s.name} | ${s.idx} | ${s.dist} | ${s.notdef} | ${s.pkgs} |`);
const pick = fontPick(scores);
p();
p(`**Pick: ${pick ? pick.name : 'none'}**`);
p();
for (const n of names.slice(0, 99)) {
  const r = first(n)[0];
  for (const v of viewIds) {
    const rv = ref.views[v], gv = r.views[v];
    if (!usable(rv) || !usable(gv)) continue;
    const pd = partDiffs(rv, gv).slice(0, 6);
    const ld = leafDiff(rv, gv).rows.slice(0, 5);
    if (pd.length === 0 && ld.length === 0) continue;
    p(`#### ${n} at ${v}`);
    if (pd.length) p(`Largest part-height gaps (got - ${REF}): ${pd.map((x) => `${x.part} ${x.d > 0 ? '+' : ''}${x.d} (${x.ref} -> ${x.got})`).join('; ')}`);
    if (ld.length) p(`First leaves with another line count: ${ld.map((x) => `${x.sec}: "${x.text}" ${x.ref} -> ${x.got} lines (${x.family})`).join('; ')}`);
    p();
  }
}
p('### Platform fonts that drew the text no web face covers (Chromium, CDP CSS.getPlatformFontsForNode; glyph counts)');
p();
for (const n of names) {
  const r = first(n)[0];
  for (const v of viewIds) {
    const gv = r.views[v];
    if (!usable(gv)) continue;
    const pf = (gv.platformFonts ?? []).filter((x) => x.kind === 'system').slice(0, 5);
    p(`- ${n} at ${v}: ${pf.length ? pf.map((x) => `${x.family} ${x.glyphs}`).join(', ') : 'none'}; code points without a web face: ${(gv.uncovered ?? []).length} (${(gv.uncovered ?? []).reduce((a, [, k]) => a + k, 0)} occurrences of ${gv.totalCps})`);
  }
}
p();
p('### Determinism (repeat runs of one variant in the same job)');
p();
for (const n of names) {
  const rs = first(n);
  if (rs.length < 2) continue;
  const same = viewIds.every((v) => rs.every((r) => JSON.stringify(r.views[v]?.parts) === JSON.stringify(rs[0].views[v]?.parts) && r.views[v]?.docH === rs[0].views[v]?.docH));
  p(`- ${n}: ${rs.length} runs, document height and all part boxes ${same ? 'identical' : 'DIFFER'}`);
}
const text = out.join('\n') + '\n';
writeFileSync(join(OUT, 'fidelity-summary.md'), text);
writeFileSync(join(OUT, 'fidelity-choice.json'), `${JSON.stringify({ ref: REF, pickViews: PICK_VIEWS, scores, excluded, pick: pick?.name ?? null }, null, 1)}\n`);
console.log(text);
