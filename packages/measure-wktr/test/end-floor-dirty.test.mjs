import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ARMS_D, CARRIER_SHARE, DOCUMENT_SHARE, FLOOR_BAND, FLUSH_KEYS, HIDE_KEYS, MIN_FRAMES, SKIP_FRAMES, animOf, armSets, bareN, decideDirtyJob, dName, flushOverall, flushVerdict, hideOverall, hideVerdict, hitN,
  jobLinesD, overall, overallLinesD, rate, repSets, rowLineD, rowsByKey, top, countName, verdict,
} from '../src/end-floor-dirty.mjs';
import { probeSource } from '../src/mid-page.mjs';
import { decideDirsD } from '../src/end-floor-dirty-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/end-floor-dirty.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const expand = (gs) => gs.flatMap(([n, r, s]) => Array.from({ length: n }, () => [r, s]));
const frames = (fs) => fs.map(([r, h, e]) => ({ r, h, e }));

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.equal(FLOOR_BAND, k.floorBand);
  assert.equal(CARRIER_SHARE, k.carrierShare);
  assert.equal(DOCUMENT_SHARE, k.documentShare);
  assert.equal(SKIP_FRAMES, k.skipFrames);
  assert.equal(MIN_FRAMES, k.minFrames);
});

test('verdict lines: rate, counts, top name and verdict', () => {
  assert.ok(of('verdict').length >= 15);
  for (const l of of('verdict')) {
    const xs = expand(l.groups);
    assert.equal(rate(xs), l.rate, l.name);
    assert.equal(hitN(xs), l.hit, l.name);
    assert.equal(bareN(xs), l.bare, l.name);
    assert.equal(top(xs), l.top, l.name);
    assert.deepEqual(verdict(xs), l.verdict, l.name);
    assert.equal(dName(verdict(xs)), l.name2, l.name);
  }
});

test('rep lines: a frame is explained by the previous frame and its own start', () => {
  assert.ok(of('rep').length >= 3);
  for (const l of of('rep')) assert.deepEqual(repSets(frames(l.frames)), l.sets, l.name);
});

test('arm lines: reps are cut on their own', () => {
  assert.ok(of('arm').length >= 1);
  for (const l of of('arm')) assert.deepEqual(armSets(l.reps.map(frames)), l.sets, l.name);
});

test('hide lines', () => {
  assert.ok(of('hide').length >= 9);
  for (const l of of('hide')) assert.equal(hideVerdict(l.carrier, l.hidden, l.ref, l.hide), l.verdict, l.name);
});

test('flush lines', () => {
  assert.ok(of('flush').length >= 9);
  for (const l of of('flush')) assert.equal(flushVerdict({ frames: l.frames, auto: l.auto, flush: l.flush }), l.verdict, l.name);
});

test('flush overall lines', () => {
  assert.ok(of('flushOverall').length >= 4);
  for (const l of of('flushOverall')) assert.equal(flushOverall(l.verdicts), l.overall, l.name);
});

test('hide overall lines', () => {
  assert.ok(of('hideOverall').length >= 5);
  for (const l of of('hideOverall')) assert.equal(hideOverall(l.verdicts), l.overall, l.name);
});

test('overall lines', () => {
  assert.ok(of('overall').length >= 6);
  for (const l of of('overall')) assert.equal(overall(l.verdicts), l.overall, l.name);
});

const kt = ['e:a|div[0]', 'p:a', 'e:b|svg[0]'];
const fr = (r, h, e) => [r, 0, h, e, 2, 3, 4];
const pb = (n, r) => ({ n, r, u: n, ms: n * 16, src: 'raf', w: n });
const row = (arm, reps, perFrame, extra = {}) => ({
  arm,
  rs: { kt, reps, hid: null, pb: Array.from({ length: reps }, () => pb(48, perFrame)), dn: Array.from({ length: reps }, () => ({ f: Array.from({ length: 48 }, () => fr(1, [], [0, 1])), nodes: 900, caps: 0, ag: { h: 96, e: 96, hEl: 48, eEl: 48, cyc: 96, maxH: 2, maxE: 2, fl: 0 }, mu: [['attributes:style e:a|div[0]', 48]] })), ...extra },
});

test('rowsByKey tells a repeated arm apart by occurrence', () => {
  const m = rowsByKey({ rows: [row('rs-flip-pbpd', 1, 1), row('rs-flip-pbpoff', 1, 0), row('rs-flip-pbpd', 1, 1), row('rs-idle-pbpd', 1, 1), { arm: 'rs-flip-pbon', rs: {} }] });
  assert.deepEqual([...m.keys()], ['flip-pbpd', 'flip-pbpoff', 'flip-pbpd#2', 'idle-pbpd']);
});

test('a job report: a carrier, its hide confirmed, a hide of another element unmatched', () => {
  const rep = { rows: [
    row('rs-flip-pbpd', 12, 48),
    row('rs-flip-pbphide', 12, 0, { hid: 'e:a|div[0]' }),
    { ...row('rs-flip-pbphidep', 12, 48), rs: { ...row('rs-flip-pbphidep', 12, 48).rs, hid: 'p:z' } },
  ] };
  rep.rows[1].rs.dn = rep.rows[1].rs.dn.map((w) => ({ ...w, f: w.f.map(() => fr(0, [], [])) }));
  const d = decideDirtyJob(rep);
  assert.deepEqual(d.ref.v, { kind: 'carrier', name: 'e:a|div[0]' });
  assert.equal(d.hides.find((h) => h.key === 'flip-pbphide').v, 'confirmed');
  assert.equal(d.hides.find((h) => h.key === 'flip-pbphidep').v, 'unmatched');
  const { lines: ls } = jobLinesD('j1', rep);
  assert.match(ls[0], /^end-floor-dirty j1 flip-pbpd: frames 576 recalcs 576 rate 100 per 100 rAF callbacks, read frames 480 rate 100, recalc frames 480 of which no dirty name 0, top e:a\|div\[0\] in 480 recalc frames, verdict carrier e:a\|div\[0\]$/);
  assert.match(ls[1], /^end-floor-dirty-dirt j1 flip-pbpd: dirty nodes per sample at rAF start 2 \(elements 1, max 2\), after the update 2 \(elements 1, max 2\), cycling names per frame 2, mutations attributes:style e:a\|div\[0\] x\d+$/);
  assert.match(ls[2], /^end-floor-dirty-facts j1 flip-pbpd: timeline invalidations per 100 frames 200, style invalidation traversals per 100 frames 300, largest last style update 4, nodes walked 900, capped windows 0,/);
  assert.ok(ls.some((l) => /^end-floor-dirty-hide j1 flip-pbphide: hid e:a\|div\[0\] \(elements hidden 1\), .*verdict confirmed$/.test(l)));
  const o = overallLinesD([d, d, d]);
  assert.match(o[0], /^end-floor-dirty overall flip-pbpd: carrier e:a\|div\[0\] \(jobs carrier e:a\|div\[0\] \| carrier e:a\|div\[0\] \| carrier e:a\|div\[0\]\)$/);
  assert.ok(o.some((l) => /^end-floor-dirty-hide overall flip-pbphide: confirmed/.test(l)));
});

test('a document-level floor and a floor-free reference', () => {
  const bare = row('rs-flip-pbpd', 12, 48);
  bare.rs.dn = bare.rs.dn.map((w) => ({ ...w, f: w.f.map(() => fr(1, [], [])) }));
  assert.equal(decideDirtyJob({ rows: [bare] }).ref.v.kind, 'documentLevel');
  const none = row('rs-flip-pbpd', 12, 0);
  none.rs.dn = none.rs.dn.map((w) => ({ ...w, f: w.f.map(() => fr(0, [], [])) }));
  assert.equal(decideDirtyJob({ rows: [none] }).ref.v.kind, 'noFloor');
});

test('a typed arm tallies the change types of the dirty names', () => {
  const r = row('rs-flip-pbpdt', 12, 48);
  r.rs.dn = r.rs.dn.map((w) => ({ ...w, f: w.f.map(() => [...fr(1, [0, 1], [0, 1]), [3, 3], [4, 4]]) }));
  const ls = jobLinesD('j', { rows: [r] }).lines[2];
  assert.match(ls, /change types e:a\|div\[0\] 3 x\d+; e:a\|div\[0\] 4 x\d+; p:a 3 x\d+; p:a 4 x\d+$/);
});

test('a flush arm reports where the dirt sits and a pair of jobs agree', () => {
  const t = row('rs-flip-pbpft', 12, 0);
  t.rs.dn = t.rs.dn.map((w) => ({ ...w, f: w.f.map(() => [...fr(0, [], []), 1]) }));
  const d = decideDirtyJob({ rows: [t] });
  assert.equal(d.arms[0].flush, 'held');
  const ls = jobLinesD('j', { rows: [t] }).lines;
  assert.ok(ls.some((l) => /^end-floor-dirty-flush j flip-pbpft: frames 480 update recalcs 0 flush recalcs 480, verdict held$/.test(l)));
  assert.ok(overallLinesD([d, d, d]).some((l) => /^end-floor-dirty-flush overall flip-pbpft: held \(jobs held held held\)$/.test(l)));
  assert.deepEqual(FLUSH_KEYS, ['flip-pbpft', 'flip-pbpfh']);
});

test('rowLineD and a missing result file', () => {
  assert.match(rowLineD('wktr-j1', 'f.json', 2, row('rs-flip-pbpd', 12, 48), 2), /rs-flip-pbpd#2: frames 576 recalcs 576 rate 100 per 100 rAF callbacks, reps 12, dirty windows 12, hid -$/);
  assert.match(decideDirsD(['/nonexistent-dir']).lines[0], /result file missing/);
});

test('count by name ignores frames without a recalc', () => {
  assert.equal(countName('x', [[0, ['x']], [1, ['x']], [1, []]]), 1);
});

test('the page source reads the dirty set without styleChangeType before the pure pass, and the arms are wired', () => {
  const src = probeSource({ mode: 'timed', rsWin: 48, tk: true });
  assert.match(src, /dirtWindow/);
  assert.match(src, /nodeNeedsStyleRecalc/);
  assert.ok(src.indexOf('nodeNeedsStyleRecalc(n)') < src.indexOf('I.styleChangeType(n)'));
  for (const a of ['pbdn', 'pbpd', 'pbpdt', 'pbphide', 'pbphidep', 'pbphides', 'pbpan', 'pbpft', 'pbpfh', 'MutationObserver', 'getComputedStyle']) assert.match(src, new RegExp(a));
  assert.equal(ARMS_D.filter((a) => a === 'rs-flip-pbpd').length, 2);
  assert.ok(ARMS_D.includes('rs-idle-pbpd'));
  assert.deepEqual(HIDE_KEYS, ['flip-pbphide', 'flip-pbphidep', 'flip-pbphides']);
  const cli = readFileSync(join(here, '../src/accel-cli.mjs'), 'utf8');
  assert.match(cli, /jobLinesD/);
});

test('the animation line ties the steady dirty elements to the targets of non-document timelines', () => {
  const an = { total: 3, kinds: { ViewTimeline: 2, DocumentTimeline: 1 }, els: [['e:a|div[0]', 'ViewTimeline', 'paused', 'x', 'e:s|div[1]'], ['e:q|div[3]', 'ViewTimeline', 'paused', 'y', 'e:a|div[0]'], ['e:z|div[2]', 'DocumentTimeline', 'running', 'z', '-']] };
  const r = row('rs-flip-pbpan', 12, 48);
  r.rs.an = an;
  const { lines } = jobLinesD('j1', { rows: [r] });
  const l = lines.find((x) => x.startsWith('end-floor-dirty-anim'));
  assert.equal(l, 'end-floor-dirty-anim j1 flip-pbpan: animations 3 (ViewTimeline 2, DocumentTimeline 1), targets 3, targets on a non-document timeline 2, steady dirty elements 1 of which targets 1 and timeline subjects 0');
  assert.equal(animOf(null, []), null);
  assert.ok(ARMS_D.includes('rs-flip-pbpan'));
});

test('the set hide arm counts the elements it hid and confirms the top name', () => {
  const rep = { rows: [row('rs-flip-pbpd', 12, 48), row('rs-flip-pbphides', 12, 0, { hid: 'e:a|div[0]', hidSet: 7 })] };
  rep.rows[1].rs.dn = rep.rows[1].rs.dn.map((w) => ({ ...w, f: w.f.map(() => fr(0, [], [])) }));
  const { lines } = jobLinesD('j1', rep);
  assert.ok(lines.some((l) => /^end-floor-dirty-hide j1 flip-pbphides: hid e:a\|div\[0\] \(elements hidden 7\), .*verdict confirmed$/.test(l)));
});
