// What the lead needs to start a captured feel session: the plan text, the build command, the read-only phone probe, the
// ask for a failed start, the length estimate. The rules are the Lean ones in lean/Fw/Device/Feel.lean (probeOf, failOf,
// estimateS, Probe.ask, Fail.ask); this file follows the golden packages/contracts/golden/device/feel.jsonl (TS stand-in of
// those rules, golden-checked in test/device-feel-plan.test.mjs). The probe only reads: it changes no setting on the phone.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ARMS, FEEL, FEEL_ROWS, LOOK_ARMS, SAME_ARMS, planOf, searchOf } from './device-feel.mjs';
import { canonSearch } from '../../contracts/src/flag-key.mjs';

const ESTIMATE = FEEL_ROWS('estimate')[0];
const ASKS = FEEL_ROWS('probeAsk')[0].asks;
const FAIL_ASKS = Object.freeze(Object.fromEntries(FEEL_ROWS('fail').map((r) => [r.fail, r.ask])));

export const visitCount = (seed) => planOf(seed).length;
export const estimateS = (visits) => ESTIMATE.fixedS + visits * ESTIMATE.visitS;
export const estimateMin = (visits) => Math.ceil(estimateS(visits) / 60);

export function probeOf(f) {
  if (!f.listed) return 'notListed';
  if (!f.paired) return 'notPaired';
  if (!f.connected) return 'notConnected';
  if (!f.usb) return 'notUsb';
  if (f.lock === 'locked') return 'locked';
  if (f.lock === 'unknown') return 'lockUnknown';
  return 'ready';
}
export const askOf = (code) => (code === 'ready' ? '' : ASKS[code]);

/** The user-side cause named in the text of a `feel start` error (Lean `failOf`), and what to ask. */
export function failOf(msg) {
  if (msg.includes('phone is locked')) return 'locked';
  if (msg.includes('not on USB')) return 'notUsb';
  if (msg.includes('listed no tabs') || msg.includes('0 of 0 tabs')) return 'webInspector';
  return 'other';
}
export const failAsk = (msg) => FAIL_ASKS[failOf(msg)];

/** The arms' `?fw=` configs for `apps/site/scripts/build.mjs`, generated from the arm list (no second copy). */
export const buildCommand = () => `node scripts/build.mjs --engine aot --configs none ${ARMS.filter((a) => a.flags.length > 0).map((a) => `--config '${searchOf(a.flags)}'`).join(' ')}`;

/** Arms the built site lacks: the same rule as `armHashes`, on a parsed configs.json. */
export const missingArms = (configs) => ARMS.filter((a) => {
  const h = configs.bySearch[canonSearch(searchOf(a.flags))];
  return !(h && configs.byHash[h]);
});

const sh = (cmd, args, timeoutMs) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error };
};

/**
 * Facts for `probeOf`, read-only: `devicectl list devices` (the one physical measurement phone, its pairing and transport),
 * `idevice_id -l` (on USB) and `devicectl device info lockState`. `connected` is a reachable transport (wired or network);
 * `tunnelState` is not used because the list shows `disconnected` for a paired phone that is simply idle (INFERRED from a
 * saved list). `run` and `lock` are injected for tests.
 */
export function readFacts({ model, os, run = sh, lock = null } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-feel-probe-'));
  try {
    const file = join(dir, 'devices.json');
    const r = run('xcrun', ['devicectl', 'list', 'devices', '--json-output', file], 60000);
    const none = { listed: false, paired: false, connected: false, usb: false, lock: 'unknown' };
    if (r.status !== 0) return { facts: none, udid: null };
    const all = JSON.parse(readFileSync(file, 'utf8')).result.devices;
    const m = all.filter((d) => d.hardwareProperties?.reality === 'physical' && d.hardwareProperties?.marketingName === model && d.deviceProperties?.osVersionNumber === os);
    if (m.length !== 1) return { facts: none, udid: null };
    const udid = m[0].hardwareProperties.udid;
    const c = m[0].connectionProperties ?? {};
    const usb = run('idevice_id', ['-l']).stdout.split('\n').map((x) => x.trim()).includes(udid);
    const facts = { listed: true, paired: c.pairingState === 'paired', connected: typeof c.transportType === 'string' && c.transportType !== '', usb, lock: 'unknown' };
    if (probeOf({ ...facts, lock: 'unlocked' }) === 'ready') facts.lock = (lock ?? readLockState)(udid, run);
    return { facts, udid };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

function readLockState(udid, run) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-feel-lock-'));
  try {
    const file = join(dir, 'lock.json');
    const r = run('xcrun', ['devicectl', 'device', 'info', 'lockState', '--device', udid, '--json-output', file], 60000);
    if (r.status !== 0) return 'unknown';
    const pr = JSON.parse(readFileSync(file, 'utf8'))?.result?.passcodeRequired;
    return pr === true ? 'locked' : pr === false ? 'unlocked' : 'unknown';
  } catch { return 'unknown'; } finally { rmSync(dir, { recursive: true, force: true }); }
}

export function probe(opts) {
  const { facts } = readFacts(opts);
  const code = probeOf(facts);
  return { code, ask: askOf(code), facts };
}

const cmdLine = (dir, tail) => `node src/device-cli.mjs feel ${tail} --dir ${dir}`;

/** The plan for the lead: arms, visits, estimate, commands. Names appear here for the lead; the person never sees them. */
export function feelPlanText({ seed, dir, site }) {
  const plan = planOf(seed);
  const same = plan.filter((v) => v.group === 'same');
  const look = plan.filter((v) => v.group === 'look');
  const n = plan.length;
  const lines = [
    `feel session plan, seed ${seed} (order index ${seed % FEEL.nSame})`,
    `arms: ${ARMS.length} (${SAME_ARMS.length} same-look blind, ${LOOK_ARMS.length} labelled look arms)`,
    `visits: ${n} (${same.length} blind, ${look.length} labelled)`,
    `estimate: about ${estimateMin(n)} min (${estimateS(n)} s = ${ESTIMATE.fixedS} s fixed + ${n} x ${ESTIMATE.visitS} s); an estimate from the dry run, not a measurement`,
    'blind order (lead only):',
    ...same.map((v) => `  ${v.label} = ${v.id} [${v.flags.join(',') || 'no flags'}]`),
    'look arms (labelled, shown once each):',
    ...look.map((v) => `  ${v.label} = ${v.id} [${v.flags.join(',')}]: ${v.text}`),
    `serve: ${site}  dir: ${dir}  pin: Serious  capture: on`,
    'commands (from packages/measure-webkit; the script never runs next):',
    `  ${cmdLine(dir, 'next')}`,
    `  ${cmdLine(dir, 'rate <label> <1-5>')}`,
    `  ${cmdLine(dir, 'status [--reveal]')}`,
    `  ${cmdLine(dir, 'stop')}`,
    `  recovery if the session was killed: node src/device-cli.mjs pin-stop --dir ${dir}`,
  ];
  return lines.join('\n');
}
