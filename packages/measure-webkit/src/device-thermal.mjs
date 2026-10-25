import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const THERMAL_NAMES = Object.freeze(['Nominal', 'Fair', 'Serious', 'Critical']);
export const TEMP_MARGIN_C = 2;
export const COOL_S = 300;
export const POLL_S = 60;
export const PAUSE_MAX_S = 3600;
export const THERMAL_SOURCE = 'xctrace Thermal State instrument over USB (system thermal state); battery temperature is the proxy';

export const thermalOfName = (s) => (THERMAL_NAMES.includes(s) ? s : null);

export const lockOf = (passcodeRequired) => (passcodeRequired === true ? 'locked' : passcodeRequired === false ? 'unlocked' : 'unknown');

export function gate(state, tempC, firstC) {
  if (state === null || state === undefined) return 'unreadable';
  if (state !== 'Nominal') return 'thermal';
  return typeof tempC === 'number' && typeof firstC === 'number' && firstC + TEMP_MARGIN_C <= tempC ? 'battery' : 'go';
}

export const preflight = (lock, state, tempC, firstC) => (lock === 'locked' ? 'locked' : gate(state, tempC, firstC));

export function passesRun(verdicts) {
  let n = 0;
  for (const v of verdicts) { if (v !== 'go') break; n++; }
  return n;
}

export const blockPasses = (readings, firstC) => passesRun(readings.map((r) => gate(r.state, r.tempC, firstC)));

export const calmFrom = (pausedS, readings) => readings.reduce((c, r) => (r.verdict === 'go' ? c : r.atS), pausedS);

export function resume(nowS, pausedS, readings) {
  const last = readings[readings.length - 1];
  return last !== undefined && last.verdict === 'go' && COOL_S <= Math.max(0, nowS - calmFrom(pausedS, readings));
}

export const pauseOver = (pausedS, nowS) => pausedS + PAUSE_MAX_S <= nowS;

export const VERDICT_TEXT = Object.freeze({
  go: 'thermal state nominal',
  locked: 'the phone is locked (devicectl lockState reports a passcode is required): unlock it and keep it awake',
  thermal: 'the phone thermal state is not Nominal',
  battery: `the battery temperature is ${TEMP_MARGIN_C} C or more above the session's first readout`,
  unreadable: 'the thermal state could not be read',
});

export function parseThermalXml(xml) {
  const names = new Map();
  for (const m of xml.matchAll(/<thermal-state\s+[^>]*?id="(\d+)"[^>]*>([A-Za-z]+)<\/thermal-state>/g)) names.set(m[1], m[2]);
  const rows = [...xml.matchAll(/<row>([\s\S]*?)<\/row>/g)].map((m) => m[1]);
  for (let i = rows.length - 1; i >= 0; i--) {
    const el = /<thermal-state\s+([^>]*?)(?:\/>|>([A-Za-z]*)<\/thermal-state>)/.exec(rows[i]);
    if (!el) continue;
    const ref = /ref="(\d+)"/.exec(el[1]);
    const name = el[2] ?? (ref ? names.get(ref[1]) : undefined);
    return thermalOfName(name ?? '');
  }
  return null;
}

const sh = (cmd, args, timeoutMs) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
};

export function readLock(udid, { run = sh } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-lock-'));
  try {
    const file = join(dir, 'lock.json');
    const r = run('xcrun', ['devicectl', 'device', 'info', 'lockState', '--device', udid, '--json-output', file], 60000);
    if (r.status !== 0) return 'unknown';
    const pr = JSON.parse(readFileSync(file, 'utf8'))?.result?.passcodeRequired;
    return lockOf(typeof pr === 'boolean' ? pr : null);
  } catch { return 'unknown'; } finally { rmSync(dir, { recursive: true, force: true }); }
}

export function readThermal(udid, { run = sh, tries = 2 } = {}) {
  const t0 = Date.now();
  let error = null, lock = 'unknown';
  for (let i = 0; i < tries; i++) {
    lock = readLock(udid, { run });
    const dir = mkdtempSync(join(tmpdir(), 'fw-therm-'));
    try {
      const trace = join(dir, 't.trace');
      const rec = run('xcrun', ['xctrace', 'record', '--instrument', 'Thermal State', '--device', udid, '--all-processes', '--time-limit', '1s', '--output', trace, '--no-prompt'], 90000);
      if (rec.status !== 0) { error = `xctrace record exit ${rec.status ?? rec.error?.code ?? 'none'}`; continue; }
      const exp = run('xcrun', ['xctrace', 'export', '--input', trace, '--xpath', '/trace-toc/run[1]/data/table[@schema="device-thermal-state-intervals"]'], 60000);
      if (exp.status !== 0) { error = `xctrace export exit ${exp.status ?? 'none'}`; continue; }
      const state = parseThermalXml(exp.stdout);
      if (state) return { state, lock, error: null, ms: Date.now() - t0 };
      error = 'the thermal-state table has no readable row';
    } finally { rmSync(dir, { recursive: true, force: true }); }
  }
  return { state: null, lock, error, ms: Date.now() - t0 };
}
