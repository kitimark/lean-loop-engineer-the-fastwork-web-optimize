// Glue of the mac-safari-measure lane (local exception (c)): the arm list, the sampler reading, the quiet wait around each window
// and the per-cell summary. Every decision is Lean's (Fw.Sup.Measure, through safari-local-reduce.mjs, golden-checked): this file
// reads the machine, calls the decisions and writes down what they said. It never reports a pass the quiet rule refused.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dedupArms } from './device-session.mjs';
import { resolveFlags } from './device-arms.mjs';
import { orderFor } from '../../gate-breakpoints/src/smooth/schedule.mjs';
import { judge, quiet, whys, availMB, stat, outcome, pct, Q } from './safari-local-reduce.mjs';

const exec = promisify(execFile);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The rewrite arms of the lane: the default and the three single-flag arms (the user's list). `orig` is the original snapshot. */
export const ARM_SEARCH = Object.freeze({ base: '', hx: '?fw=hero.exit:threaded', mp: '?fw=morph.panel:const-bounds', pf: '?fw=platform:fade-threaded' });
export const ARM_LABEL = Object.freeze({ orig: 'original snapshot', base: 'rewrite default', hx: 'hero.exit:threaded', mp: 'morph.panel:const-bounds', pf: 'platform:fade-threaded' });
export const WINDOWS = Object.freeze(['hero', 'end']);
/** The Timeline zone each window is read in. */
export const ZONE_OF = Object.freeze({ hero: 'hero', end: 'finish' });

/** Arms after Lean's `dedupArms` over the resolved flags (an arm loading the same page as an earlier one is dropped, and named). */
export function localArms(siteDir, root) {
  const xs = Object.entries(ARM_SEARCH).map(([id, s]) => [id, resolveFlags(s, root)]);
  const keep = dedupArms(xs);
  const arms = [{ id: 'orig', site: 'orig', tree: { dir: null }, search: '' }, ...keep.map((id) => ({ id, site: 'rewrite', tree: { dir: siteDir, search: ARM_SEARCH[id] }, search: ARM_SEARCH[id] }))];
  return { arms, dropped: xs.filter(([id]) => !keep.includes(id)).map(([id]) => id), flags: Object.fromEntries(xs) };
}

/** A `Reading` for Lean's `quiet`: the sampler's sample and the holders other than my own tokens. */
export function readingOf(status, mine = []) {
  const s = status.sample;
  return { time: s.time, loadCenti: s.loadCenti, mem: s.mem, ramMB: s.ramMB, compressorMB: s.compressorMB, holders: (status.holders ?? []).filter((h) => !mine.includes(h.token)).length, queued: (status.queue ?? []).length };
}

/** The numbers of a reading worth keeping in a result file (no owners, no tokens). */
export const brief = (r) => ({ time: r.time, load: r.loadCenti / 100, availMB: availMB(r.mem), press: r.mem.press, comprMBPerMin: r.mem.comprMBPerMin, swapOutMBPerMin: r.mem.swapOutMBPerMin, holders: r.holders, queued: r.queued ?? 0 });

/** Read the sampler once (`fw slot status --json`, about 0.4 s). `cwd` is the worktree. */
export async function readMachine({ cwd, mine = [] } = {}) {
  const { stdout } = await exec('pnpm', ['-s', 'fw', 'slot', 'status', '--json'], { cwd, maxBuffer: 8 << 20, timeout: 60000 });
  return readingOf(JSON.parse(stdout), mine);
}

/** Wait until the machine is quiet (Lean `quiet`) or `waitMs` has passed; returns the last reading. */
export async function waitQuiet({ read, waitMs = 120000, everyMs = 5000, wait = sleep, now = Date.now }) {
  const t0 = now();
  let r = await read();
  while (!quiet(r) && now() - t0 < waitMs) { await wait(everyMs); r = await read(); }
  return r;
}

/**
 * One pass: wait for quiet, read the window, read the machine again, let Lean's `judge` decide. A window the quiet rule refuses
 * is not run when the machine never became quiet, and its values are dropped when the machine was loud during it.
 * @returns {{decision:string, phase?:string, why?:string[], before:object, after:object|null, value:any}}
 */
export async function measurePass({ read, run, waitMs, everyMs, wait, now }) {
  const before = await waitQuiet({ read, waitMs, everyMs, wait, now });
  if (!quiet(before)) { const d = judge(before, before); return { ...d, before: brief(before), after: null, value: null }; }
  const value = await run();
  const after = await read();
  const d = judge(before, after);
  return { ...d, before: brief(before), after: brief(after), value: d.decision === 'accept' ? value : null };
}

/**
 * Passes until every cell (window x arm) has `passes` accepted, arms interleaved by `orderFor` per round, at most `maxRounds` rounds
 * and until `deadlineMs`. `readWindow(arm, win, round)` returns the value; a throw is recorded as an error row and `onError` may repair.
 */
export async function runCells({ engine, arms, windows = WINDOWS, passes = Q.minPasses, maxRounds = 3 * Q.minPasses, deadlineMs = Infinity, read, readWindow, onError = async () => {}, onRow = () => {}, maxErrors = 6, waitMs, everyMs, wait, now = Date.now, log = () => {} }) {
  const rows = [];
  const got = (a, w) => rows.filter((x) => x.arm === a && x.window === w && x.decision === 'accept').length;
  let errors = 0;
  for (let round = 0; round < maxRounds && now() < deadlineMs; round++) {
    let ran = false;
    for (const a of orderFor(arms.map((x) => x.id), round)) {
      for (const w of windows) {
        if (got(a, w) >= passes || now() >= deadlineMs) continue;
        ran = true;
        const t0 = now();
        let p;
        try {
          p = await measurePass({ read, run: () => readWindow(a, w, round), waitMs, everyMs, wait, now });
        } catch (e) {
          errors++;
          const er = { engine, arm: a, window: w, round, decision: 'error', message: String(e.message).slice(0, 200) };
          rows.push(er); onRow(er);
          log(`${engine} ${a} ${w} round ${round}: error (${e.message})`);
          if (errors > maxErrors) throw e;
          await onError(e);
          continue;
        }
        const { value, ...rest } = p;
        const row = { engine, arm: a, window: w, round, ...rest, ...(value ?? {}), ms: now() - t0 };
        rows.push(row); onRow(row);
        log(`${engine} ${a} ${w} round ${round}: ${p.decision}${p.phase ? ` (${p.phase}: ${p.why.join(',')})` : ''} ${got(a, w)}/${passes} in ${row.ms} ms`);
      }
    }
    if (!ran) break;
  }
  return rows;
}

const med = (l) => (l.length ? pct(50, l) : null);
const tally = (rs) => ({ before: rs.filter((r) => r.decision === 'refuse' && r.phase === 'before').length, after: rs.filter((r) => r.decision === 'refuse' && r.phase === 'after').length, stale: rs.filter((r) => r.decision === 'stale').length, error: rs.filter((r) => r.decision === 'error').length });

/** Per window x arm: accepted pass count, refusal counts and medians of the accepted passes, each verdict against `base` (Lean `outcome`). */
export function summarize(rows, { base = 'base' } = {}) {
  const key = (r) => `${r.engine}|${r.window}|${r.arm}`;
  const cells = new Map();
  for (const r of rows) { if (!cells.has(key(r))) cells.set(key(r), []); cells.get(key(r)).push(r); }
  const out = [];
  for (const [k, rs] of cells) {
    const [engine, window, arm] = k.split('|');
    const ok = rs.filter((r) => r.decision === 'accept');
    const basePasses = (cells.get(`${engine}|${window}|${base}`) ?? []).filter((r) => r.decision === 'accept');
    const per = (f) => ok.map(f);
    const perBase = (f) => basePasses.map(f);
    const withEv = ok.filter((r) => r.profile);
    out.push({
      engine, window, arm, passes: ok.length, refused: tally(rs),
      long: med(per((r) => r.stat.long)), skipped: med(per((r) => r.stat.skipped)), p50: med(per((r) => r.stat.p50)), p95: med(per((r) => r.stat.p95)), mx: med(per((r) => r.stat.mx)),
      paintHund: med(withEv.map((r) => r.profile.paintHund)), compositeN: med(withEv.map((r) => r.profile.compositeN)), eventPasses: withEv.length,
      vsBaseLong: arm === base ? null : outcome(per((r) => r.stat.long), perBase((r) => r.stat.long)),
      vsBaseSkipped: arm === base ? null : outcome(per((r) => r.stat.skipped), perBase((r) => r.stat.skipped)),
    });
  }
  return out.sort((a, b) => (a.engine + a.window).localeCompare(b.engine + b.window) || a.arm.localeCompare(b.arm));
}

/** The window value of a recorder result: the cadence stat of Lean's `stat` over the rAF intervals (tenths of ms). */
export function cadenceOf(ts, intervals) {
  const ivs = intervals(ts);
  return { frames: ts.length, ivs, stat: stat(ts.length, ivs) };
}

export { whys };
