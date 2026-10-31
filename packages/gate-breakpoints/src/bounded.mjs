import { readFileSync } from 'node:fs';
import { freemem, loadavg } from 'node:os';
import { resolve } from 'node:path';
import { PKG } from './serve.mjs';

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
export const errKind = (name) => (name === 'LimitError' || name === 'TimeoutError' ? 'stall' : 'defect');
export const cellsPass = (outcomes) => outcomes.every((o) => o === 'pass');
export const cellsKept = (outcomes) => outcomes.every((o) => o !== 'exhausted');

export class LimitError extends Error {
  constructor(name, ms) {
    super(`${name}: no answer in ${ms} ms`);
    this.name = 'LimitError';
    this.limit = name;
    this.ms = ms;
  }
}

export function bound(name, ms, work) {
  const p = Promise.resolve(typeof work === 'function' ? work() : work);
  p.catch(() => {});
  let timer;
  const late = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new LimitError(name, ms)), ms);
  });
  return Promise.race([p, late]).finally(() => clearTimeout(timer));
}

export const call = (name, page, fn, arg) => bound(name, LIMITS.callMs, () => page.evaluate(fn, arg));

export const closeBounded = async (name, closable) => {
  if (!closable) return;
  try {
    await bound(name, LIMITS.closeMs, () => closable.close());
  } catch {
  }
};

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

export const faultNote = (name, n, err) => ({
  cell: name,
  attempt: n,
  error: `${err && err.name ? err.name : 'Error'}: ${String(err && err.message ? err.message : err).split('\n')[0]}`,
  loadavg: loadavg().map((x) => Math.round(x * 100) / 100),
  freeMb: Math.round(freemem() / 1048576),
  at: new Date().toISOString(),
});

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
