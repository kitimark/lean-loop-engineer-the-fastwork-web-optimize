import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { ARMS, FEEL, FEEL_ROWS, LOOK_ARMS, SAME_ARMS, planOf, searchOf } from '../src/device-feel.mjs';
import { askOf, buildCommand, estimateMin, estimateS, failAsk, failOf, feelPlanText, missingArms, probeOf, readFacts, visitCount } from '../src/device-feel-plan.mjs';

const row = (k) => FEEL_ROWS(k)[0];

test('probeOf equals the Lean grid over every combination of the five facts', () => {
  const codes = row('probe').codes;
  let k = 0;
  for (const listed of [false, true]) for (const paired of [false, true]) for (const connected of [false, true]) for (const usb of [false, true]) {
    for (const lock of ['locked', 'unlocked', 'unknown']) assert.equal(probeOf({ listed, paired, connected, usb, lock }), codes[k++]);
  }
  assert.equal(k, codes.length);
  assert.equal(codes.filter((c) => c === 'ready').length, 1);
});

test('every failed probe has an ask from the Lean golden, a ready probe has none', () => {
  for (const c of new Set(row('probe').codes)) {
    if (c === 'ready') assert.equal(askOf(c), '');
    else assert.ok(askOf(c).length > 10, c);
  }
  assert.equal(askOf('locked'), row('probeAsk').asks.locked);
});

test('failOf and its ask equal the Lean golden for the logged start failures', () => {
  for (const r of FEEL_ROWS('fail')) {
    assert.equal(failOf(r.msg), r.fail, r.msg);
    assert.equal(failAsk(r.msg), r.ask);
  }
  assert.match(failAsk('phone proxy listed no tabs in 20 s'), /Web Inspector/);
});

test('the estimate and the visit count equal the Lean golden', () => {
  const e = row('estimate');
  assert.equal(e.visits, FEEL.repeats * FEEL.nSame + LOOK_ARMS.length);
  for (let seed = 0; seed < 7; seed++) assert.equal(visitCount(seed), e.visits);
  assert.equal(estimateS(e.visits), e.totalS);
  assert.equal(estimateMin(e.visits), e.minutes);
  assert.equal(estimateS(0), e.fixedS);
});

test('the build command is generated from the arms: one config per arm with flags, none for base', () => {
  const cmd = buildCommand();
  const configs = [...cmd.matchAll(/--config '([^']*)'/g)].map((m) => m[1]);
  assert.deepEqual(configs, ARMS.filter((a) => a.flags.length > 0).map((a) => searchOf(a.flags)));
  assert.equal(configs.length, ARMS.length - 1);
  assert.ok(cmd.startsWith('node scripts/build.mjs --engine aot --configs none '));
});

test('missingArms names the arms a built site lacks', () => {
  const full = { bySearch: { '': 'h0' }, byHash: { h0: 'index.html' } };
  ARMS.filter((a) => a.flags.length > 0).forEach((a, i) => { full.bySearch[searchOf(a.flags)] = `h${i + 1}`; full.byHash[`h${i + 1}`] = `c/h${i + 1}.html`; });
  assert.deepEqual(missingArms(full), []);
  delete full.byHash.h2;
  assert.deepEqual(missingArms(full).map((a) => a.id), [SAME_ARMS[2].id]);
});

test('the plan text names arm count, visit count, estimate and the commands, and no command opens an arm by itself', () => {
  const t = feelPlanText({ seed: 5, dir: '.local/phone/d-feel2', site: 's' });
  assert.match(t, new RegExp(`arms: ${ARMS.length} \\(${SAME_ARMS.length} same-look blind, ${LOOK_ARMS.length} labelled`));
  assert.match(t, new RegExp(`visits: ${planOf(5).length} `));
  assert.match(t, new RegExp(`about ${row('estimate').minutes} min`));
  for (const a of LOOK_ARMS) assert.ok(t.includes(a.text));
  assert.ok(t.includes('feel rate <label> <1-5> --dir .local/phone/d-feel2'));
  assert.ok(t.split('\n').length < 60);
});

// readFacts with a fake `run`: a pure read of three commands, never a write.
function fakeRun(devices, { usb = true, lock = { passcodeRequired: false } } = {}) {
  const calls = [];
  const run = (cmd, args) => {
    calls.push([cmd, ...args]);
    const out = args[args.indexOf('--json-output') + 1];
    if (cmd === 'idevice_id') return { status: 0, stdout: usb ? 'UDID-1\n' : '', stderr: '' };
    if (args.includes('list')) { writeFileSync(out, JSON.stringify({ result: { devices } })); return { status: 0, stdout: '', stderr: '' }; }
    if (args.includes('lockState')) { writeFileSync(out, JSON.stringify({ result: lock })); return { status: 0, stdout: '', stderr: '' }; }
    return { status: 1, stdout: '', stderr: '' };
  };
  return { run, calls };
}
const phone = (over = {}) => ({ hardwareProperties: { reality: 'physical', marketingName: 'M', udid: 'UDID-1' }, deviceProperties: { osVersionNumber: '1' }, connectionProperties: { pairingState: 'paired', transportType: 'wired', tunnelState: 'disconnected' }, ...over });
const read = (devices, o) => { const f = fakeRun(devices, o); return { ...readFacts({ model: 'M', os: '1', run: f.run }), calls: f.calls }; };

test('readFacts: a paired, wired, listed, unlocked phone is ready, and only read commands ran', () => {
  const r = read([phone()]);
  assert.equal(probeOf(r.facts), 'ready');
  assert.deepEqual(r.calls.map((c) => c.slice(0, 4).join(' ')), ['xcrun devicectl list devices', 'idevice_id -l', 'xcrun devicectl device info']);
  assert.ok(r.calls.every((c) => !/\b(set|install|launch|copy|terminate|process|sysdiagnose)\b/.test(c.join(' '))));
});

test('readFacts: each missing fact gives its own probe code', () => {
  assert.equal(probeOf(read([]).facts), 'notListed');
  assert.equal(probeOf(read([phone(), phone()]).facts), 'notListed');
  assert.equal(probeOf(read([phone({ connectionProperties: { pairingState: 'unpaired', transportType: 'wired' } })]).facts), 'notPaired');
  assert.equal(probeOf(read([phone({ connectionProperties: { pairingState: 'paired' } })]).facts), 'notConnected');
  assert.equal(probeOf(read([phone()], { usb: false }).facts), 'notUsb');
  assert.equal(probeOf(read([phone()], { lock: { passcodeRequired: true } }).facts), 'locked');
  assert.equal(probeOf(read([phone()], { lock: {} }).facts), 'lockUnknown');
  const sim = phone({ hardwareProperties: { reality: 'simulated', marketingName: 'M', udid: 'UDID-1' } });
  assert.equal(probeOf(read([sim]).facts), 'notListed');
});

// The script, against a stub CLI: what it asks, what it starts, and that it never opens an arm.
const SCRIPT = new URL('../../../scripts/feel-session.sh', import.meta.url).pathname;
const STUB = `import { appendFileSync, existsSync, readFileSync } from 'node:fs';
const [, , , sub] = process.argv;
const log = process.env.STUB_LOG, mode = process.env.STUB_MODE;
appendFileSync(log, sub + '\\n');
if (sub === 'plan') { console.log('stub plan'); process.exit(Number(process.env.STUB_PLAN_RC ?? 0)); }
if (sub === 'build-cmd') { console.log('true'); process.exit(0); }
if (sub === 'probe') { if (mode === 'locked') { console.log('probe: locked\\nThe iPhone is locked: unlock it and keep it awake.'); process.exit(3); } console.log('probe: ready'); process.exit(0); }
if (sub === 'ask') { console.log('stub ask'); process.exit(0); }
if (sub === 'status') process.exit(readFileSync(log, 'utf8').split('\\n').includes('start') ? 0 : 1);
if (sub === 'start') { if (mode === 'dies') { console.error('error: phone proxy listed no tabs'); process.exit(1); } setTimeout(() => {}, 30000); }
`;
function runScript(mode, extra = []) {
  const d = mkdtempSync(join(tmpdir(), 'feel-script-'));
  const stub = join(d, 'stub.mjs');
  writeFileSync(stub, STUB);
  const logFile = join(d, 'calls.txt');
  const r = spawnSync('sh', [SCRIPT, '--seed', '4', '--date', '2026-01-02', ...extra], {
    encoding: 'utf8', timeout: 60000,
    env: { ...process.env, FEEL_CLI: `node ${stub}`, FEEL_MAIN: d, FEEL_WAIT_S: '10', FEEL_POLL_S: '1', STUB_LOG: logFile, STUB_MODE: mode },
  });
  const calls = existsSync(logFile) ? readFileSync(logFile, 'utf8').split('\n').filter(Boolean) : [];
  const pidFile = join(d, '.local/phone/2026-01-02-feel2-start.log.pid');
  if (existsSync(pidFile)) { try { process.kill(Number(readFileSync(pidFile, 'utf8')), 'SIGTERM'); } catch {} }
  const out = { ...r, calls, d };
  return out;
}

test('script: a locked phone prints the ask, exits 3 and starts nothing', () => {
  const r = runScript('locked');
  assert.equal(r.status, 3);
  assert.match(r.stdout, /The iPhone is locked/);
  assert.ok(!r.calls.includes('start'));
  rmSync(r.d, { recursive: true, force: true });
});

test('script: a ready phone starts the session once, in the background, and never runs next', () => {
  const r = runScript('ready');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.calls.filter((c) => c === 'start'), ['start']);
  assert.ok(!r.calls.includes('next') && !r.calls.includes('rate'));
  assert.match(r.stdout, /running \(pid \d+, pin Serious, capture on\)/);
  assert.ok(r.calls.indexOf('probe') < r.calls.indexOf('start'));
  rmSync(r.d, { recursive: true, force: true });
});

test('script: a start that ends early prints the log tail and the ask and exits 1', () => {
  const r = runScript('dies');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /listed no tabs/);
  assert.match(r.stderr, /stub ask/);
  rmSync(r.d, { recursive: true, force: true });
});

test('script: --plan stops before the probe; missing arms exit 4 and name the build', () => {
  const p = runScript('ready', ['--plan']);
  assert.equal(p.status, 0);
  assert.ok(!p.calls.includes('probe') && !p.calls.includes('start'));
  rmSync(p.d, { recursive: true, force: true });
  const d = mkdtempSync(join(tmpdir(), 'feel-script-'));
  const stub = join(d, 'stub.mjs');
  writeFileSync(stub, STUB);
  const r = spawnSync('sh', [SCRIPT, '--seed', '4', '--date', '2026-01-02'], { encoding: 'utf8', timeout: 60000, env: { ...process.env, FEEL_CLI: `node ${stub}`, FEEL_MAIN: d, STUB_LOG: join(d, 'c.txt'), STUB_MODE: 'ready', STUB_PLAN_RC: '4' } });
  assert.equal(r.status, 4);
  assert.ok(!readFileSync(join(d, 'c.txt'), 'utf8').includes('probe'));
  rmSync(d, { recursive: true, force: true });
});
