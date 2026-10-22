import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dedupArms } from './device-session.mjs';
import { resolveFlags } from './device-arms.mjs';
import { orderFor } from '../../gate-breakpoints/src/smooth/schedule.mjs';
import { judge, quiet, whys, availMB, stat, outcome, pct, baselineFloor, simFloor, ceilCenti, Q } from './safari-local-reduce.mjs';

const exec = promisify(execFile);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const ARM_SEARCH = Object.freeze({ base: '', hx: '?fw=hero.exit:threaded', mp: '?fw=morph.panel:const-bounds', pf: '?fw=platform:fade-threaded' });
export const ARM_LABEL = Object.freeze({ orig: 'original snapshot', base: 'rewrite default', hx: 'hero.exit:threaded', mp: 'morph.panel:const-bounds', pf: 'platform:fade-threaded' });
export const WINDOWS = Object.freeze(['hero', 'end']);
export const ZONE_OF = Object.freeze({ hero: 'hero', end: 'finish' });

export function localArms(siteDir, root) {
  const xs = Object.entries(ARM_SEARCH).map(([id, s]) => [id, resolveFlags(s, root)]);
  const keep = dedupArms(xs);
  const arms = [{ id: 'orig', site: 'orig', tree: { dir: null }, search: '' }, ...keep.map((id) => ({ id, site: 'rewrite', tree: { dir: siteDir, search: ARM_SEARCH[id] }, search: ARM_SEARCH[id] }))];
  return { arms, dropped: xs.filter(([id]) => !keep.includes(id)).map(([id]) => id), flags: Object.fromEntries(xs) };
}

export function readingOf(status, mine = []) {
  const s = status.sample;
  return { time: s.time, loadCenti: s.loadCenti, mem: s.mem, ramMB: s.ramMB, compressorMB: s.compressorMB, holders: (status.holders ?? []).filter((h) => !mine.includes(h.token)).length, queued: (status.queue ?? []).length };
}

export const brief = (r) => ({ time: r.time, load: r.loadCenti / 100, availMB: availMB(r.mem), press: r.mem.press, comprMBPerMin: r.mem.comprMBPerMin, swapOutMBPerMin: r.mem.swapOutMBPerMin, holders: r.holders, queued: r.queued ?? 0 });

export async function readMachine({ cwd, mine = [] } = {}) {
  const { stdout } = await exec('pnpm', ['-s', 'fw', 'slot', 'status', '--json'], { cwd, maxBuffer: 8 << 20, timeout: 60000 });
  return readingOf(JSON.parse(stdout), mine);
}

const needFloor = (fl) => { if (!Number.isInteger(fl) || fl < 0) throw new Error('no idle floor: take a baseline first (takeBaseline), no pass runs without one'); return fl; };

export async function takeBaseline({ read, boot = null, everyMs = 10000, waitMs = 600000, wait = sleep, now = Date.now, log = () => {} }) {
  const t0 = now();
  const all = [];
  for (;;) {
    all.push(await read());
    const win = all.slice(-Q.baseMinSamples);
    const floorCenti = boot == null ? baselineFloor(win) : simFloor(boot, win);
    if (floorCenti !== null) { log(`idle floor ${floorCenti / 100} (ceiling ${ceilCenti(floorCenti) / 100}) from ${win.length} readings`); return { floorCenti, readings: win.map(brief) }; }
    if (now() - t0 >= waitMs) { log(`no steady idle floor in ${Math.round((now() - t0) / 1000)} s`); return { floorCenti: null, readings: win.map(brief) }; }
    await wait(everyMs);
  }
}

export async function waitQuiet({ read, floorCenti, waitMs = 120000, everyMs = 5000, wait = sleep, now = Date.now }) {
  needFloor(floorCenti);
  const t0 = now();
  let r = await read();
  while (!quiet(r, floorCenti) && now() - t0 < waitMs) { await wait(everyMs); r = await read(); }
  return r;
}

export async function measurePass({ read, run, floorCenti, waitMs, everyMs, wait, now, pass = null }) {
  if (pass && !(await pass.start())) throw new Error('the slot gave no exclusive pass: other holders stayed live');
  try { return await passBody({ read, run, floorCenti, waitMs, everyMs, wait, now }); } finally { if (pass) await pass.stop(); }
}

async function passBody({ read, run, floorCenti, waitMs, everyMs, wait, now }) {
  const before = await waitQuiet({ read, floorCenti, waitMs, everyMs, wait, now });
  if (!quiet(before, floorCenti)) { const d = judge(before, before, floorCenti); return { ...d, before: brief(before), after: null, value: null }; }
  const value = await run();
  const after = await read();
  const d = judge(before, after, floorCenti);
  return { ...d, before: brief(before), after: brief(after), value: d.decision === 'accept' ? value : null };
}

export async function runCells({ engine, arms, windows = WINDOWS, passes = Q.minPasses, maxRounds = 3 * Q.minPasses, deadlineMs = Infinity, read, floorCenti, pass = null, readWindow, onError = async () => {}, onRow = () => {}, maxErrors = 6, waitMs, everyMs, wait, now = Date.now, log = () => {} }) {
  needFloor(floorCenti);
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
          p = await measurePass({ read, floorCenti, pass, run: () => readWindow(a, w, round), waitMs, everyMs, wait, now });
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

export function cadenceOf(ts, intervals) {
  const ivs = intervals(ts);
  return { frames: ts.length, ivs, stat: stat(ts.length, ivs) };
}

export { whys };
