// The close-start identity and the close-end gap of the nav background (task scoped-close-start-cause, round 3).
//   node src/trajectory/closegap.mjs <run id>=<raw-playwright-webkit.json of that run's trajectory-apple artifact> [...]
// For every close of every arm it takes the last sample with `is-morphing` (i) and the first sample without it (j), the gap
// g = t_j - t_i, and the red channel of `nav.background-color` at j. It prints the arms' identity (search and config hash read from
// the raw file), the table of readings and gaps, the gap distribution per arm with a seeded permutation test, the close-phase frame
// intervals, the block differences, the earn readings at j and three checks on the measured channel (Lean
// `Fw.Parts.HeroExitCloseStart`). Check 3 (`closeStartOk`) is the claim; checks 1 and 2 (`floorOk`, LAG) are superseded by it.
// TS stand-in: `redCh`, `prevBound`, `floorOk` and `closeStartOk` are checked against Lean's literals and `closeStartCases` in
// test/closegap.test.mjs, not generated.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { colourFromV1 } from './kit.mjs';

/** The tween's duration and the nav's cut (`MORPHING_CUT`, Lean `Fw.Parts.Nav.morphingCut`) in the units of the raw files. */
export const CUT = 1 / 1000;
/** Read lag in ms: the sample of the last morphing frame is read up to one 60 Hz frame after that frame (INFERRED). */
export const LAG = 17;
/** The raw files hold the morph value in units of 1e-4 (`m` of a sample). */
export const M_SCALE = 10000;
/** Check 3 tolerance in red units (Lean `closeStartOk`: a fixed constant). */
export const TOL = 0.5;

/** Lean `bgRed`: red (0 to 255) of `color-mix(in srgb, #ffffff1a, #131922)` at morph value m (premultiplied mix, then unpremultiplied). */
export const redCh = (m) => (26 * (1 - m) + 19 * m) / ((26 / 255) * (1 - m) + m);
/** Lean `bgAlpha`: alpha (0 to 1) of the same colour. */
export const alphaCh = (m) => (26 / 255) * (1 - m) + m;
/** Lean `prevBound`: the largest morph value the last morphing frame can hold when the next frame comes g ms later. */
export const prevBound = (g) => (0.1 + g / 680) ** 3;
/** Lean `floorOk cap lag reading`: no darker than the darkest start a previous frame of gap cap + lag can leave. */
export const floorOk = (cap, lag, reading) => redCh(prevBound(cap + lag)) <= reading;

/** Lean `closeStartOk reading m`: the red read at j is within `TOL` of `bgRed m`, `m` the morph value of the last sample with the class. */
export const closeStartOk = (reading, m) => Math.abs(reading - redCh(m)) <= TOL;

/** The smallest gap g (ms) whose floor is at or below the reading: g such that redCh(prevBound(g)) = reading. */
export function gapFor(reading) {
  if (reading >= redCh(prevBound(0))) return 0;
  let lo = 0, hi = 680;
  for (let k = 0; k < 60; k++) { const mid = (lo + hi) / 2; if (redCh(prevBound(mid)) <= reading) hi = mid; else lo = mid; }
  return hi;
}

const MORPHING = 2; // index of `is-morphing` among the nav's class properties (registry NAV_CLASSES)
const BG = 9; // index of `background-color` in the nav's reading
const EARN_OPACITY = 2, EARN_MAX_WIDTH = 5; // indices of `opacity` and `max-width` in the earn button's reading (registry earn props)

/** One cell per (width, arm, rep): the close's last morphing sample, the first sample without the class, the gap and the reading. */
export function closeCells(raw, run = '') {
  const cells = [];
  for (const x of raw.runs) {
    if (!x.morph) continue;
    const close = x.morph.phases.close;
    for (const rep of [...new Set(close.map((q) => q.rep))]) {
      const c = close.filter((q) => q.rep === rep);
      let i = -1;
      c.forEach((q, k) => { if (q.nodes.nav[0][MORPHING] === 'on') i = k; });
      if (i < 0 || i + 1 >= c.length) continue;
      const a = c[i], b = c[i + 1];
      cells.push({
        run, width: x.width, role: x.role, search: x.search, want: x.want, rep,
        g: b.t - a.t, sinceJ: b.since, mI: a.m, m: a.m / M_SCALE, redI: colourFromV1(a.nodes.nav[0][BG])[0] / 1000, redJ: colourFromV1(b.nodes.nav[0][BG])[0] / 1000,
        earnOpacity: b.nodes.earn[0][EARN_OPACITY][0] / 1000, earnMaxWidth: b.nodes.earn[0][EARN_MAX_WIDTH][0] / 1000,
      });
    }
  }
  return cells;
}

/** The arms' identity as the raw file reports it (identity, never run order). */
export function identity(raw) {
  const arms = [...new Set(raw.runs.map((x) => `${x.role}:${x.search === '' ? '(none)' : x.search}:${x.want ?? 'none'}`))];
  return { search: raw.search, hash: raw.hash, baseHash: raw.baseHash, reps: raw.reps, arms };
}

const quantile = (a, p) => {
  const s = [...a].sort((x, y) => x - y), k = (s.length - 1) * p, f = Math.floor(k);
  return s[f] + (s[Math.min(f + 1, s.length - 1)] - s[f]) * (k - f);
};
const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;

/** Distribution of gaps of one arm. */
export function gapStats(gs) {
  return {
    n: gs.length, mean: mean(gs), median: quantile(gs, 0.5), p90: quantile(gs, 0.9), max: Math.max(...gs),
    over150: gs.filter((g) => g > 150).length, meanLog: mean(gs.map(Math.log)),
  };
}

/** Seeded linear congruential generator (deterministic across runs). */
const lcg = (seed) => { let s = seed; return () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; }; };

/**
 * Permutation test, blocked by (run, width): the null is that every arm of a run draws its gaps from the same distribution at a width.
 * `cells` carry a `run` field. Returns P(statistic of a random arm >= the candidate's) for the mean of log g and for the mean of g.
 */
export function permutationP(cells, role = 'cand', iterations = 20000, seed = 12345) {
  const keys = [...new Set(cells.map((c) => `${c.run}/${c.width}`))].sort(); // sorted: the p does not depend on the order of the files
  const stat = (gs) => ({ meanLog: mean(gs.map(Math.log)), mean: mean(gs) });
  const obs = stat(cells.filter((c) => c.role === role).map((c) => c.g));
  const rnd = lcg(seed), ge = { meanLog: 0, mean: 0 };
  const pools = keys.map((k) => { const of = cells.filter((c) => `${c.run}/${c.width}` === k); return { all: of.map((c) => c.g), k: of.filter((c) => c.role === role).length }; });
  for (let it = 0; it < iterations; it++) {
    const pick = [];
    for (const { all, k } of pools) {
      const a = [...all];
      for (let m = 0; m < k; m++) { const j = m + Math.floor(rnd() * (a.length - m)); [a[m], a[j]] = [a[j], a[m]]; pick.push(a[m]); }
    }
    const t = stat(pick);
    for (const key of Object.keys(ge)) if (t[key] >= obs[key] - 1e-12) ge[key]++;
  }
  return { meanLog: ge.meanLog / iterations, mean: ge.mean / iterations };
}

/** Check 1, own gap: reading at j against the floor of the cell's own sample gap. A violator needs `slack` ms more than the sample gap. */
export function ownGapCheck(cells) {
  return cells.map((c) => ({ ...c, slack: gapFor(c.redJ) - c.g })).filter((c) => c.slack > 0).sort((a, b) => b.slack - a.slack);
}

/** Check 2, original's gap: the cap of a width is the largest gap of the original arm there (same run); cells below the floor of cap + LAG. */
export function capCheck(cells) {
  const cap = {};
  for (const w of new Set(cells.map((c) => c.width))) cap[w] = Math.max(...cells.filter((c) => c.width === w && c.role === 'orig').map((c) => c.g));
  const viol = cells.filter((c) => c.role !== 'orig' && !floorOk(cap[c.width], LAG, c.redJ));
  return { cap, viol };
}

/** Check 3, the close-start identity: every cell passes `closeStartOk (red at j) (m_i)`. Returns each cell with its deviation and verdict. */
export function identityCheck(cells) {
  return cells.map((c) => ({ ...c, bg: redCh(c.m), dev: Math.abs(c.redJ - redCh(c.m)), ok: closeStartOk(c.redJ, c.m) }));
}

/** Close-phase frame intervals (ms between consecutive samples of one rep) per arm role. */
export function frameIntervals(raw) {
  const out = {};
  for (const x of raw.runs) {
    if (!x.morph) continue;
    const close = x.morph.phases.close, ds = (out[x.role] ??= []);
    for (const rep of new Set(close.map((q) => q.rep))) {
      const c = close.filter((q) => q.rep === rep);
      for (let k = 1; k < c.length; k++) ds.push(c[k].t - c[k - 1].t);
    }
  }
  return out;
}

/** Per width of one run: mean of log g of the candidate minus mean of log g of the original and base arms together. */
export function blockDiffs(cells) {
  return [...new Set(cells.map((c) => c.width))].map((w) => {
    const of = cells.filter((c) => c.width === w), ml = (r) => mean(of.filter((c) => r(c.role)).map((c) => Math.log(c.g)));
    return { width: w, diff: ml((r) => r === 'cand') - ml((r) => r !== 'cand') };
  });
}

const f1 = (x) => x.toFixed(1);
const f3 = (x) => x.toFixed(3);

/** The text report of one raw file. */
export function report(raw, run = '') {
  const id = identity(raw), cells = closeCells(raw, run), out = [];
  out.push(`search ${id.search || '(default)'} hash ${id.hash} baseHash ${id.baseHash} reps ${id.reps}`, `arms: ${id.arms.join(' | ')}`, '');
  out.push('reading (red at j) and gap g (ms), reps 0..n');
  for (const w of [...new Set(cells.map((c) => c.width))]) for (const role of ['orig', 'base', 'cand']) {
    const r = cells.filter((c) => c.width === w && c.role === role).sort((a, b) => a.rep - b.rep);
    out.push(`${String(w).padEnd(5)}${role.padEnd(5)}${r.map((c) => `${f1(c.redJ)} (${c.g})`).join('  ')}`);
  }
  out.push('', 'gap per arm: n, mean, median, p90, max, count > 150, mean of log g');
  for (const role of ['orig', 'base', 'cand']) {
    const s = gapStats(cells.filter((c) => c.role === role).map((c) => c.g));
    out.push(`${role.padEnd(5)}${s.n} ${f1(s.mean)} ${f1(s.median)} ${f1(s.p90)} ${s.max} ${s.over150} ${s.meanLog.toFixed(3)}`);
  }
  const p = permutationP(cells);
  out.push(`permutation, candidate vs all arms of the run, blocked by width: p(mean log g) ${p.meanLog.toFixed(4)}, p(mean g) ${p.mean.toFixed(4)}`);
  const own = ownGapCheck(cells);
  out.push('', `check 1 (superseded by check 3), floor of the cell's own gap: ${own.length} of ${cells.length} cells below it`);
  for (const c of own) out.push(`  ${c.width} ${c.role} rep ${c.rep}: red ${f1(c.redJ)} g ${c.g} needs ${f1(c.g + c.slack)} (slack ${f1(c.slack)} ms, since ${c.sinceJ}) ${c.slack <= LAG ? 'within LAG' : 'BEYOND LAG'}`);
  const { cap, viol } = capCheck(cells);
  out.push('', `check 2 (superseded by check 3), floor of (largest original gap of the width + ${LAG}): cap ${JSON.stringify(cap)}; ${viol.length} base/cand cells below it`);
  for (const c of viol.sort((a, b) => a.width - b.width || a.role.localeCompare(b.role) || a.rep - b.rep)) out.push(`  ${c.width} ${c.role} rep ${c.rep}: red ${f1(c.redJ)} g ${c.g}`);
  const ids = identityCheck(cells), bad = ids.filter((c) => !c.ok);
  out.push('', `check 3, close-start identity closeStartOk (red at j) (m_i / ${M_SCALE}), tolerance ${TOL} red: ${ids.length - bad.length} of ${ids.length} cells pass`,
    `  max |red_j - bgRed m_i| ${f3(Math.max(...ids.map((c) => c.dev)))}, max |red_i - bgRed m_i| ${f3(Math.max(...ids.map((c) => Math.abs(c.redI - c.bg))))}, max |red_j - red_i| ${f3(Math.max(...ids.map((c) => Math.abs(c.redJ - c.redI))))}, min m_i ${Math.min(...ids.map((c) => c.mI))} (1e-4), cells red_j = red_i within 0.001 (readings are in units of 0.001): ${ids.filter((c) => Math.abs(c.redJ - c.redI) <= 0.0011).length}`,
    '  width arm  rep m_i(1e-4) g(ms)  red_j   bgRed(m_i) dev    verdict');
  for (const c of ids.sort((a, b) => a.width - b.width || ['orig', 'base', 'cand'].indexOf(a.role) - ['orig', 'base', 'cand'].indexOf(b.role) || a.rep - b.rep))
    out.push(`  ${String(c.width).padEnd(5)} ${c.role.padEnd(5)} ${c.rep}   ${String(c.mI).padEnd(11)} ${String(c.g).padEnd(7)} ${f3(c.redJ).padEnd(7)} ${f3(c.bg).padEnd(10)} ${f3(c.dev).padEnd(6)} ${c.ok ? 'ok' : 'FAIL'}`);
  out.push('', 'earn at j (first sample without is-morphing), the close@0 reading: opacity and max-width (px) with g (ms), reps 0..n',
    '  width arm   opacity (max-width px, g)');
  for (const w of [...new Set(cells.map((c) => c.width))]) for (const role of ['orig', 'base', 'cand']) {
    const r = cells.filter((c) => c.width === w && c.role === role).sort((a, b) => a.rep - b.rep);
    out.push(`  ${String(w).padEnd(5)} ${role.padEnd(5)} ${r.map((c) => `${c.earnOpacity.toFixed(3)} (${f1(c.earnMaxWidth)}, ${c.g})`).join('  ')}`);
  }
  const fi = frameIntervals(raw);
  out.push('', 'close-phase frame intervals per arm (ms): n, mean, median');
  for (const role of ['orig', 'base', 'cand']) out.push(`  ${role.padEnd(5)} ${fi[role].length} ${f1(mean(fi[role]))} ${f1(quantile(fi[role], 0.5))}`);
  out.push('', `block difference per width, candidate minus orig+base, mean of log g: ${blockDiffs(cells).map((b) => `${b.width} ${b.diff.toFixed(2)}`).join('  ')}`);
  return out.join('\n');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const groups = {};
  for (const arg of process.argv.slice(2)) {
    const [run, f] = arg.split('=');
    const raw = JSON.parse(readFileSync(f, 'utf8'));
    console.log(`== run ${run}\n${report(raw, run)}\n`);
    (groups[raw.search] ??= []).push(...closeCells(raw, run));
  }
  for (const [search, cells] of Object.entries(groups)) {
    const runs = new Set(cells.map((c) => c.run)).size, p = permutationP(cells);
    console.log(`pooled ${search}: ${runs} runs, ${cells.length / 3} cells per arm, candidate vs all arms, blocked by run and width: p(mean log g) ${p.meanLog.toFixed(4)}, p(mean g) ${p.mean.toFixed(4)}`);
  }
}
