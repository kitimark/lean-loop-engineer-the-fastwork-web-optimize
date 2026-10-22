import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { makeGuard, dirMB, assertOwnDir, sweepStale, pidAlive, userTempDir, isKtrace } from '../src/xctrace/guard.mjs';
import { attempt } from '../src/xctrace/attempt.mjs';

const own = () => mkdtempSync(join(tmpdir(), 'fw-guard-test-'));
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

const fast = () => { const t0 = Date.now(); return () => t0 + (Date.now() - t0) * 1000; };

test('a child runs in its own group with TMPDIR inside the work dir, and the work dir holds all it wrote', async () => {
  const w = own();
  try {
    const g = makeGuard({ workDir: join(w, 'work'), everyMs: 5, now: fast() });
    const r = await g.exec('sh', ['-c', 'echo "$TMPDIR"; echo x > "$TMPDIR/instruments1.ktrace"'], { limitS: 5 });
    assert.equal(r.out.trim(), g.tmpDir);
    assert.ok(g.tmpDir.startsWith(join(w, 'work')));
    assert.ok(existsSync(join(g.tmpDir, 'instruments1.ktrace')));
    g.wipe();
    assert.deepEqual(readdirSync(g.tmpDir), []);
  } finally { rmSync(w, { recursive: true, force: true }); }
});

test('a child that writes into the user temp folder (the confstr dir, not TMPDIR) is counted and only its new kernel traces are wiped', async () => {
  const w = own(), u = own();
  try {
    writeFileSync(join(u, 'instruments-old.ktrace'), 'old');
    writeFileSync(join(u, 'other.txt'), 'x');
    const g = makeGuard({ workDir: join(w, 'work'), userTmp: u, everyMs: 5 });
    const script = `echo big > "${u}/instruments-new.ktrace"; mkdir "${u}/instruments-dir.ktrace"; echo y > "${u}/instruments-dir.ktrace/f"; echo z > "${u}/keep.txt"; sleep 0.1`;
    await g.exec('sh', ['-c', script], { limitS: 5 });
    assert.deepEqual(g.leaked().map((p) => p.slice(u.length + 1)).sort(), ['instruments-dir.ktrace', 'instruments-new.ktrace']);
    g.wipe();
    assert.deepEqual(readdirSync(u).sort(), ['instruments-old.ktrace', 'keep.txt', 'other.txt']);
    assert.deepEqual(g.leaked(), []);
  } finally { rmSync(w, { recursive: true, force: true }); rmSync(u, { recursive: true, force: true }); }
});

test('when the parent is lost, the orphan cleanup wipes the new kernel trace in the user temp folder', async () => {
  const w = own(), u = own();
  try {
    let ppid = 1000;
    const g = makeGuard({ workDir: join(w, 'work'), userTmp: u, everyMs: 5, ppid: 1000, getPpid: () => ppid });
    await g.exec('sh', ['-c', `echo x > "${u}/instruments-x.ktrace"`], { limitS: 5 });
    assert.deepEqual(readdirSync(u), ['instruments-x.ktrace']);
    const done = new Promise((res) => g.watchParent(() => { g.wipe(); res(); }, 5));
    ppid = 1;
    await done;
    assert.deepEqual(readdirSync(u), []);
  } finally { rmSync(w, { recursive: true, force: true }); rmSync(u, { recursive: true, force: true }); }
});

test('kernel traces in the user temp folder count toward the size cap', async () => {
  const w = own(), u = own();
  try {
    const g = makeGuard({ workDir: join(w, 'work'), userTmp: u, everyMs: 5, sizeMB: (p) => (p.endsWith('.ktrace') ? 13000 : 0) });
    const r = await g.exec('sh', ['-c', `echo x > "${u}/instruments-1.ktrace"; sleep 300`], { limitS: 600 });
    assert.ok(r.killed && r.killed.traceMB > 12288, 'killed on the user-folder trace alone');
  } finally { rmSync(w, { recursive: true, force: true }); rmSync(u, { recursive: true, force: true }); }
});

test('the user temp folder is read from getconf, and a kernel trace is told by its name', () => {
  assert.equal(userTempDir(() => '/var/folders/x/T/\n'), '/var/folders/x/T/');
  assert.equal(userTempDir(() => { throw new Error('no getconf'); }), null);
  assert.ok(isKtrace('instruments5ab.ktrace') && !isKtrace('foo.ktrace') && !isKtrace('instruments.trace'));
});

test('the work dir may not be inside the temp folder', () => {
  assert.throws(() => assertOwnDir(join(tmpdir(), 'x')), /inside the temp folder/);
  assert.throws(() => assertOwnDir(tmpdir()), /inside the temp folder/);
  assert.equal(assertOwnDir('/Users/x/results/.xctrace/work-1', ['/var/folders/a/T']), '/Users/x/results/.xctrace/work-1');
});

test('a command that runs past its limit and the grace is killed with everything in its group', async () => {
  const w = own();
  try {
    const g = makeGuard({ workDir: join(w, 'work'), everyMs: 5, now: fast() });
    const r = await g.exec('sh', ['-c', 'trap "" INT; sleep 300 & echo $! > helper.pid; sleep 300'], { limitS: 0 });
    assert.ok(r.interrupted, 'interrupted at the grace');
    assert.ok(r.killed, 'killed at the hard deadline');
    assert.ok(r.killed.elapsedS >= 120);
    const helper = Number(readFileSyncOr(join(g.workDir, 'helper.pid')));
    await new Promise((res) => setTimeout(res, 100));
    assert.ok(helper > 0 && !alive(helper), 'the helper in the group is dead');
  } finally { rmSync(w, { recursive: true, force: true }); }
});
const readFileSyncOr = (p) => { try { return readFileSync(p, 'utf8'); } catch { return '0'; } };

test('a command whose files grow past the size cap is killed', async () => {
  const w = own();
  try {
    let mb = 0;
    const g = makeGuard({ workDir: join(w, 'work'), everyMs: 5, sizeMB: () => (mb += 6000) });
    const r = await g.exec('sleep', ['300'], { limitS: 600 });
    assert.ok(r.killed && r.killed.traceMB > 12288);
    assert.equal(r.interrupted, false);
  } finally { rmSync(w, { recursive: true, force: true }); }
});

test('a command is killed when its parent is gone, and nothing starts after that', async () => {
  const w = own();
  try {
    let ppid = 100;
    const g = makeGuard({ workDir: join(w, 'work'), ppid: 100, getPpid: () => ppid, everyMs: 5 });
    const p = g.exec('sleep', ['300'], { limitS: 600 });
    setTimeout(() => { ppid = 1; }, 60);
    const r = await p;
    assert.ok(r.killed && r.killed.parentAlive === false, 'killed because the parent is gone');
    assert.ok(r.killed.elapsedS < 5);
    await assert.rejects(() => g.exec('sleep', ['1'], { limitS: 1 }), /parent process is gone/);
  } finally { rmSync(w, { recursive: true, force: true }); }
});

test('watchParent fires once when the parent is gone', async () => {
  const w = own();
  try {
    let ppid = 5, fired = 0;
    const g = makeGuard({ workDir: join(w, 'work'), ppid: 5, getPpid: () => ppid, everyMs: 5 });
    g.watchParent(() => { fired++; }, 5);
    await new Promise((r) => setTimeout(r, 30));
    assert.equal(fired, 0);
    ppid = 1;
    await new Promise((r) => setTimeout(r, 40));
    assert.equal(fired, 1);
  } finally { rmSync(w, { recursive: true, force: true }); }
});

test('killAll stops the live groups', async () => {
  const w = own();
  try {
    const g = makeGuard({ workDir: join(w, 'work'), everyMs: 1000 });
    const p = g.exec('sleep', ['300'], { limitS: 600 });
    await new Promise((r) => setTimeout(r, 80));
    g.killAll();
    const r = await p;
    assert.equal(r.code, 'SIGKILL');
  } finally { rmSync(w, { recursive: true, force: true }); }
});

test('dirMB counts every file under the dir', () => {
  const w = own();
  try {
    mkdirSync(join(w, 'a'));
    writeFileSync(join(w, 'a', 'f'), Buffer.alloc(3 * 1048576 + 1));
    writeFileSync(join(w, 'g'), 'x');
    assert.equal(dirMB(w), 4);
    assert.equal(dirMB(join(w, 'none')), 0);
  } finally { rmSync(w, { recursive: true, force: true }); }
});

test('sweepStale removes work dirs of probes that are gone and keeps live ones', () => {
  const w = own();
  try {
    mkdirSync(join(w, 'work-111')); mkdirSync(join(w, 'work-222')); mkdirSync(join(w, 'other'));
    const gone = sweepStale(w, (pid) => pid === 222);
    assert.deepEqual(gone, ['work-111']);
    assert.deepEqual(readdirSync(w).sort(), ['other', 'work-222']);
    assert.ok(pidAlive(process.pid));
  } finally { rmSync(w, { recursive: true, force: true }); }
});

const fakeGuard = (events, { room = true } = {}) => ({
  workDir: '/w', roomOk: () => room, wipe: () => events.push('wipe'),
  exec: async (cmd, args) => {
    events.push(`exec ${args[0]}`);
    if (args[0] === 'record') return { code: 0, out: '', err: '', interrupted: false, killed: null, maxMB: 7 };
    if (args.includes('--toc')) return { code: 0, out: '<run number="1"><table schema="hitches"/></run>', err: '' };
    return { code: 0, out: '<row/><row/>', err: '' };
  },
});

test('attempt records only while a slot is held, and always wipes the work dir', async () => {
  const ev = [];
  await assert.rejects(() => attempt({ guard: fakeGuard(ev), lease: null, target: 't', template: 'Animation Hitches', recordArgs: [], during: async () => {}, limitS: 1, settleMs: 0 }), /slot is held/);
  assert.deepEqual(ev, [], 'nothing ran without a slot');
  const ok = await attempt({ guard: fakeGuard(ev), lease: { token: 'x' }, target: 't', template: 'Animation Hitches', recordArgs: ['--attach', '1'], during: async () => { ev.push('during'); }, limitS: 1, settleMs: 0 });
  assert.equal(ok.recorded, true);
  assert.equal(ok.hitchRows, 2);
  assert.deepEqual(ev.slice(0, 2), ['exec record', 'during']);
  assert.equal(ev.at(-1), 'wipe');
});

test('attempt wipes the work dir when an export fails, and records nothing without disk room', async () => {
  const ev = [];
  const g = fakeGuard(ev);
  const bad = { ...g, exec: async (c, a) => { if (a.includes('--toc')) throw new Error('boom'); return g.exec(c, a); } };
  await assert.rejects(() => attempt({ guard: bad, lease: { token: 'x' }, target: 't', template: 'Animation Hitches', recordArgs: [], during: async () => {}, limitS: 1, settleMs: 0 }), /boom/);
  assert.equal(ev.at(-1), 'wipe');
  const ev2 = [];
  const r = await attempt({ guard: fakeGuard(ev2, { room: false }), lease: { token: 'x' }, target: 't', template: 'Animation Hitches', recordArgs: [], during: async () => {}, limitS: 1, settleMs: 0 });
  assert.equal(r.recorded, false);
  assert.match(r.skipped, /free disk/);
  assert.deepEqual(ev2, [], 'no recording started');
});

test('the recorder always gets a time limit', async () => {
  const seen = [];
  const g = { ...fakeGuard([]), exec: async (c, a, o) => { seen.push([a, o]); return fakeGuard([]).exec(c, a); } };
  await attempt({ guard: g, lease: { token: 'x' }, target: 't', template: 'Metal System Trace', recordArgs: ['--all-processes'], during: async () => {}, limitS: 6, settleMs: 0 });
  const [args, opt] = seen[0];
  assert.equal(args[args.indexOf('--time-limit') + 1], '6s');
  assert.equal(opt.limitS, 6);
  assert.ok(args.includes('--no-prompt'));
});
