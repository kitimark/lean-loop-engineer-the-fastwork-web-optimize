import { readFileSync } from 'node:fs';
import { freemem, loadavg } from 'node:os';
import { resolve } from 'node:path';
import { PKG } from './serve.mjs';

// Ready, wait and fault rules of the flip-cell and look readings.
// Lean: lean/Fw/Parts/MorphGeomReady.lean. Golden lines verifyReady, verifyWait, verifyAttempts, verifyNext, verifyErr, verifyCells and
// verifyLimits of packages/contracts/golden/morph-geom-timed.jsonl (replayed by test/bounded.test.mjs).

export const GOLDEN = resolve(PKG, '../contracts/golden/morph-geom-timed.jsonl');

export function loadLimits(path = GOLDEN) {
  const line = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).find((l) => l.fn === 'verifyLimits');
  if (!line) throw new Error(`no verifyLimits line in ${path}`);
  return line.out;
}

export const LIMITS = loadLimits();

const sideLoaded = (o) => o.loaded === o.imgs;
const sideSettled = (o) => o.running === 0;
export const cellReady = (want, base, flag) =>
  flag.cols === want && flag.imgs === base.imgs && sideLoaded(base) && sideLoaded(flag) && sideSettled(base) && sideSettled(flag);

export const waitStep = (elapsed, limit, ready) => (ready ? 'read' : limit <= elapsed ? 'late' : 'poll');

const firstReading = (names) => {
  for (const n of names) if (n !== 'fault') return n === 'pass';
  return null;
};
export const cellOutcome = (max, names) => {
  const r = firstReading(names.slice(0, max));
  return r === true ? 'pass' : r === false ? 'fail' : 'exhausted';
};
export const retryNext = (n, max, name) => (name !== 'fault' ? 'done' : n < max ? 'again' : 'stop');
/** Lean `errKind`: only the harness limit and Playwright's timeout are stalls (faults); any other error is a page or harness defect. */
export const errKind = (name) => (name === 'LimitError' || name === 'TimeoutError' ? 'stall' : 'defect');
export const cellsPass = (outcomes) => outcomes.every((o) => o === 'pass');
export const cellsKept = (outcomes) => outcomes.every((o) => o !== 'exhausted');

/** A page call that outlived its named limit. It is a fault, never a reading. */
export class LimitError extends Error {
  constructor(name, ms) {
    super(`${name}: no answer in ${ms} ms`);
    this.name = 'LimitError';
    this.limit = name;
    this.ms = ms;
  }
}

/** Race `work` (a promise or a function returning one) against a named limit; the loser's late rejection is swallowed. */
export function bound(name, ms, work) {
  const p = Promise.resolve(typeof work === 'function' ? work() : work);
  p.catch(() => {});
  let timer;
  const late = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new LimitError(name, ms)), ms);
  });
  return Promise.race([p, late]).finally(() => clearTimeout(timer));
}

/** `page.evaluate` under the call limit. */
export const call = (name, page, fn, arg) => bound(name, LIMITS.callMs, () => page.evaluate(fn, arg));

/** Close a page or browser under the close limit; a close that hangs or throws is dropped (the process exit kills the browser). */
export const closeBounded = async (name, closable) => {
  if (!closable) return;
  try {
    await bound(name, LIMITS.closeMs, () => closable.close());
  } catch {
    // dropped on purpose: the close ran out of time or the target was already gone
  }
};

/** Runs in the page: what it shows of the morph columns, and the CSS transitions still running. */
export function observeCell() {
  const cols = [...document.querySelectorAll('[data-fw="morph-columns"] > div')].filter((c) => getComputedStyle(c).display !== 'none');
  const imgs = cols.flatMap((c) => [...c.querySelectorAll('img')]);
  return {
    cols: cols.length,
    imgs: imgs.length,
    loaded: imgs.filter((i) => i.complete && i.naturalWidth > 0).length,
    running: typeof CSSTransition === 'undefined' ? 0 : document.getAnimations().filter((a) => a instanceof CSSTransition && a.playState === 'running').length,
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Poll both pages until `cellReady` or the ready limit (Lean `waitStep`): `read` once ready, `late` after the limit. The caller
 * reads and judges either way; `late` only notes that the wait ran out.
 */
export async function waitCell(base, flag, want, { limitMs = LIMITS.readyMs, pollMs = LIMITS.pollMs } = {}) {
  const t0 = Date.now();
  for (;;) {
    const b = await call('ready: base page', base, observeCell);
    const f = await call('ready: flag page', flag, observeCell);
    const elapsed = Date.now() - t0;
    const step = waitStep(elapsed, limitMs, cellReady(want, b, f));
    if (step !== 'poll') return { step, waitedMs: elapsed, base: b, flag: f };
    await sleep(pollMs);
  }
}

/** Why and when a cell attempt failed to read: kept in the output so a stall is explained next time. */
export const faultNote = (name, n, err) => ({
  cell: name,
  attempt: n,
  error: `${err && err.name ? err.name : 'Error'}: ${String(err && err.message ? err.message : err).split('\n')[0]}`,
  loadavg: loadavg().map((x) => Math.round(x * 100) / 100),
  freeMb: Math.round(freemem() / 1048576),
  at: new Date().toISOString(),
});

/**
 * One cell: `attempt(n)` returns `{ ok, value }` (a reading) or throws (a fault). Only stalls (`errKind`) are faults; any other error is a defect and rejects at once. Faults are retried up to the Lean attempt limit
 * after `onFault` (which drops the pages); the first reading decides, so a failing reading is never retried into a pass.
 * Returns the Lean outcome (`pass`, `fail`, `exhausted`), the value of the reading and the fault notes.
 */
export async function takeCell(name, attempt, { max = LIMITS.attempts, onFault = async () => {} } = {}) {
  const names = [];
  const faults = [];
  let value = null;
  for (let n = 1; ; n++) {
    let kind;
    try {
      const r = await attempt(n);
      kind = r.ok ? 'pass' : 'fail';
      value = r.value;
    } catch (err) {
      if (errKind(err && err.name) !== 'stall') throw err;
      kind = 'fault';
      faults.push(faultNote(name, n, err));
      process.stderr.write(`fault ${name} attempt ${n} of ${max}: ${faults[faults.length - 1].error}\n`);
      await onFault(err, n);
    }
    names.push(kind);
    if (retryNext(n, max, kind) !== 'again') return { outcome: cellOutcome(max, names), value, faults, attempts: n };
  }
}
