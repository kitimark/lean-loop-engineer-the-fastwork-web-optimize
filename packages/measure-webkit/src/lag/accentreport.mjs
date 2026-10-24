import { PERIODS, KINDS, BUSY_MIN, MIN_FAITHFUL, cell, busyFrozen, pooled, perFrameMilli, median2, zoneVerdict, sharePct } from './swap.mjs';
import { countOf, bgOfCapture, jobKey, jobBase, median } from './swapreport.mjs';

export const ARMS = Object.freeze(['faithful', 'nolayout', 'full']);
export const STATES = Object.freeze(['faithful', 'nolayout', 'full', 'faithful-frozen']);
export const FLAG_OF = Object.freeze({ faithful: 'default', nolayout: 'hero.accent:draw-nolayout', full: 'hero.accent:draw-nolayout-full', 'faithful-frozen': 'default, draw freeze' });

export const recordsOf = (docs) => docs.flatMap((d) => d.passes.map((p) => p.cost?.accent).filter(Boolean));

const capsOf = (state) => (state === 'faithful' ? ['faithful-a', 'faithful-b'] : [`${state}-a`]);

export function samples(recs, names, ty, phase, k) {
  const out = [];
  let dropped = 0;
  for (const rec of recs) {
    for (const name of names) {
      const cap = rec.captures[name];
      const n = countOf(cap, k, `${phase}:${k}`, ty);
      if (n === undefined) continue;
      if (n === null) { dropped++; continue; }
      out.push([n, phase === 'swap' ? bgOfCapture(cap, k) : 'unknown', jobKey(rec, name.endsWith('-b') ? 'b' : 'a')]);
    }
  }
  return { vals: out.map((s) => s[0]), bgs: out.map((s) => s[1]), keys: out.map((s) => s[2]), dropped };
}

const windowsOf = (phase) => Array.from({ length: phase === 'swap' ? PERIODS : PERIODS - 1 }, (_, k) => k);
const med = (xs) => (xs.length ? median(xs) : null);

export function armWindows(recs, arm) {
  const out = [];
  for (const phase of ['swap', 'rest']) {
    for (const k of windowsOf(phase)) {
      for (const ty of KINDS) {
        const a1 = samples(recs, ['faithful-a'], ty, phase, k), a2 = samples(recs, ['faithful-b'], ty, phase, k), c = samples(recs, [`${arm}-a`], ty, phase, k);
        const dropped = a1.dropped + a2.dropped + c.dropped;
        out.push({ phase: `${phase}:${k}`, kind: ty, faithfulA: a1.vals, faithfulB: a2.vals, arm: c.vals, dropped, cell: cell(a1.vals, a2.vals, c.vals, dropped) });
      }
    }
  }
  return out;
}

export function frozenWindows(recs) {
  const out = [];
  for (const phase of ['swap', 'rest']) {
    for (const k of windowsOf(phase)) {
      for (const ty of KINDS) {
        const free = samples(recs, ['faithful-a', 'faithful-b'], ty, phase, k), frozen = samples(recs, ['faithful-frozen-a'], ty, phase, k);
        const busy = phase === 'swap' ? free.vals.filter((_, i) => free.bgs[i] === 'busy') : free.vals;
        out.push({ phase: `${phase}:${k}`, kind: ty, basis: phase === 'swap' ? 'busy' : 'all', unfrozen: busy, unfrozenAll: free.vals, frozen: frozen.vals, cell: busyFrozen(busy, frozen.vals) });
      }
    }
  }
  return out;
}

export function pooledOf(recs, state) {
  const res = {};
  for (const phase of ['rest', 'swap']) {
    const rows = [];
    let captures = 0;
    for (const rec of recs) {
      for (const name of capsOf(state)) {
        const cap = rec.captures[name];
        const ns = windowsOf(phase).map((k) => countOf(cap, k, `${phase}:${k}`, 'Layout')).filter((n) => typeof n === 'number');
        if (ns.length) { captures++; rows.push(...ns); }
      }
    }
    res[phase] = pooled(rows, captures);
  }
  return res;
}

const zoneGroups = [['aligned', (z) => z.align && z.drew], ['natural', (z) => !z.align]];

const spread = (xs) => ({ n: xs.length, median: med(xs), min: xs.length ? Math.min(...xs) : null, max: xs.length ? Math.max(...xs) : null });

export function zonesOfState(recs, state) {
  return recs.flatMap((r) => ['a', 'b'].map((s) => r.zones[`${state}-${s}`]).filter(Boolean));
}

export function zoneStats(recs) {
  const out = {};
  for (const state of STATES) {
    const zs = zonesOfState(recs, state);
    out[state] = {};
    for (const [name, f] of [['all', () => true], ...zoneGroups]) {
      const g = zs.filter(f);
      const frames = g.reduce((a, z) => a + z.frames, 0);
      const sum = (key) => g.reduce((a, z) => a + z[key], 0);
      const draws = g.filter((z) => z.draws);
      out[state][name] = {
        captures: g.length, frames, layout: spread(g.map((z) => z.layout)), paint: spread(g.map((z) => z.paint)),
        layoutPerFrameMilli: perFrameMilli(sum('layout'), frames), paintPerFrameMilli: perFrameMilli(sum('paint'), frames),
        layoutSamples: g.map((z) => z.layout), paintSamples: g.map((z) => z.paint),
        drawStarts: draws.length ? { captures: draws.length, animations: draws.reduce((a, z) => a + z.draws.animations, 0), transitions: draws.reduce((a, z) => a + z.draws.transitions, 0) } : null,
      };
    }
  }
  return out;
}

const PAIRS = [['faithful', 'nolayout'], ['faithful', 'full'], ['nolayout', 'full'], ['faithful', 'faithful-frozen']];

export function zoneVerdicts(stats) {
  const out = [];
  for (const [name] of [['all'], ...zoneGroups]) {
    for (const [from, to] of PAIRS) {
      for (const [kind, key] of [['Layout', 'layoutSamples'], ['Paint', 'paintSamples']]) {
        const x = stats[from][name][key], y = stats[to][name][key];
        const m = (s) => median2(s.map(Number));
        out.push({ group: name, from, to, kind, fromN: x.length, toN: y.length, verdict: zoneVerdict(x, y), share: x.length && y.length ? sharePct(m(x), m(y)) : null });
      }
    }
  }
  return out;
}

const tally = (cells) => ['win', 'loss', 'unresolved'].map((w) => cells.filter((x) => x.cell.startsWith(w)).length);

export function accentAnalysis(docs) {
  const recs = recordsOf(docs);
  const stats = zoneStats(recs);
  const jobs = [...new Set(recs.map(jobBase))].sort();
  return {
    schema: 'fw.webkit.lag.accent.report/1', records: recs.length, jobs,
    units: recs.map((r) => ({ job: jobKey(r, 'lane'), ran: Object.keys(r.captures).length + Object.keys(r.zones).length, failed: r.failed, skipped: r.skipped })),
    pooled: Object.fromEntries(STATES.map((s) => [s, pooledOf(recs, s)])),
    windows: { nolayout: armWindows(recs, 'nolayout'), full: armWindows(recs, 'full') },
    frozen: frozenWindows(recs),
    zone: { stats, verdicts: zoneVerdicts(stats) },
    tally: Object.fromEntries(['nolayout', 'full'].map((a) => [a, Object.fromEntries(['swap', 'rest'].map((ph) => [ph, Object.fromEntries(KINDS.map((ty) => [ty, tally(armWindows(recs, a).filter((x) => x.phase.startsWith(ph) && x.kind === ty))]))]))])),
  };
}

const range = (xs) => (xs.length === 0 ? '-' : `${Math.min(...xs)}${Math.min(...xs) === Math.max(...xs) ? '' : `-${Math.max(...xs)}`} (n=${xs.length})`);
const num = (v) => (v === null || v === undefined ? '-' : String(v));
const tenths = (t) => `${Math.floor(t / 10)}.${t % 10}`;
const milli = (m) => (m === null ? '-' : `${Math.floor(m / 1000)}.${String(m % 1000).padStart(3, '0')}`);

export function accentMd(an, sources) {
  const L = [`Sources: ${sources.join('; ')}`, '', `Jobs counted (${an.jobs.length}): ${an.jobs.join(', ')}. Records: ${an.records}. Arms: faithful = the page without a flag; nolayout = ${FLAG_OF.nolayout}; full = ${FLAG_OF.full}; faithful-frozen = the default page with the draw-only freeze (path animations and the drawingIn width transition off, idle boil running).`, ''];
  L.push('### Units per job', '', '| job | captures run | failed | skipped |', '|---|---|---|---|');
  for (const u of an.units) L.push(`| ${u.job} | ${u.ran} | ${u.failed.length ? u.failed.join('; ') : '-'} | ${u.skipped.length ? u.skipped.join(', ') : '-'} |`);
  L.push('', `### Pooled Layout rows (windows with at least ${BUSY_MIN} rows are busy; rows per capture and median over the pooled windows)`, '',
    '| state | window kind | captures | windows | busy windows | Layout rows per capture | median |', '|---|---|---|---|---|---|---|');
  for (const s of STATES) for (const ph of ['rest', 'swap']) {
    const p = an.pooled[s][ph];
    L.push(`| ${s} | ${ph} | ${p.captures} | ${p.windows} | ${p.busyWindows} of ${p.windows} | ${tenths(p.tenthsPerCapture)} | ${p.median2 / 2} |`);
  }
  for (const arm of ['nolayout', 'full']) {
    L.push('', `### ${arm} against faithful, window by window (Lean cell: needs at least ${MIN_FAITHFUL} samples in each faithful slot)`, '');
    for (const ph of ['swap', 'rest']) {
      L.push(`Tally of ${ph} windows (win / loss / unresolved of ${ph === 'swap' ? PERIODS : PERIODS - 1} per kind): ${KINDS.map((ty) => `${ty} ${an.tally[arm][ph][ty].join('/')}`).join(', ')}`, '');
    }
    for (const ty of ['Layout', 'Paint']) {
      L.push(`${ty}:`, '', `| window | faithful a | faithful b (A/A floor) | ${arm} | dropped | verdict |`, '|---|---|---|---|---|---|');
      for (const x of an.windows[arm].filter((y) => y.kind === ty)) L.push(`| ${x.phase} | ${range(x.faithfulA)} | ${range(x.faithfulB)} | ${range(x.arm)} | ${x.dropped} | ${x.cell} |`);
      L.push('');
    }
  }
  L.push('### Faithful, draw-only freeze: unfrozen busy samples against frozen samples, window by window (Lean busyFrozen; a rest window uses all unfrozen samples)', '');
  for (const ty of ['Layout', 'Paint']) {
    L.push(`${ty}:`, '', '| window | basis | unfrozen | frozen | cell |', '|---|---|---|---|---|');
    for (const x of an.frozen.filter((y) => y.kind === ty)) L.push(`| ${x.phase} | ${x.basis} | ${range(x.unfrozen)} | ${range(x.frozen)} | ${x.cell} |`);
    L.push('');
  }
  L.push('### hero.exit zone (scroll-A): rows per capture and per scroll frame', '',
    'aligned = the scroll starts inside a draw; natural = the scroll starts wherever the page is. Per frame = Lean perFrameMilli (rows over frames, thousandths, rounded half up).', '',
    '| state | group | captures | frames | Layout median (min..max) | Layout per frame | Paint median (min..max) | Paint per frame | draw starts (animations / transitions) |', '|---|---|---|---|---|---|---|---|---|');
  for (const s of STATES) for (const g of ['all', 'aligned', 'natural']) {
    const x = an.zone.stats[s][g], r = (q) => `${num(q.median)} (${num(q.min)}..${num(q.max)})`;
    L.push(`| ${s} | ${g} | ${x.captures} | ${x.frames} | ${r(x.layout)} | ${milli(x.layoutPerFrameMilli)} | ${r(x.paint)} | ${milli(x.paintPerFrameMilli)} | ${x.drawStarts ? `${x.drawStarts.animations} / ${x.drawStarts.transitions} (${x.drawStarts.captures} captures)` : 'not probed'} |`);
  }
  L.push('', 'Verdict = Lean zoneVerdict of the first state against the second (lower = the second is lower, ranges separated). Share = whole percent of the first median that the second removed.', '',
    '| group | from | to | kind | n | verdict | share |', '|---|---|---|---|---|---|---|');
  for (const v of an.zone.verdicts) L.push(`| ${v.group} | ${v.from} | ${v.to} | ${v.kind} | ${v.fromN}+${v.toN} | ${v.verdict} | ${v.share === null ? '-' : `${v.share}%`} |`);
  return L.join('\n');
}
