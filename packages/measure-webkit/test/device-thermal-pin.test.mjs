import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import {
  ConditionOwner, PIN, blockValid, clearWait, closeAct, conditionSet, endVerdict, laneGates, lanesRun, mayKill, pinGate, pinTarget, pinWhy,
  profileListed, profileOf, psInfo, stopAct, visitOk, whyPin,
} from '../src/device-thermal-pin.mjs';
import { fakeWorld, mkOwner } from './pin-world.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/thermal.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the golden has every pinned kind', () => {
  for (const k of ['pinconsts', 'profile', 'pin', 'lanes', 'visit', 'blockvalid', 'stop', 'close', 'end', 'clearwait', 'kill']) assert.ok(of(k).length > 0, k);
});

test('constants and profile ids match Lean; Critical and Nominal are never induced', () => {
  const [c] = of('pinconsts');
  for (const k of ['pinWaitMaxS', 'pinPollS', 'stopGraceS', 'killGraceS', 'clearWaitMaxS']) assert.equal(PIN[k], c[k], k);
  for (const p of of('profile')) {
    assert.equal(pinTarget(p.state), p.pinTarget, p.state);
    assert.equal(profileOf(p.state), p.profile, p.state);
  }
  assert.equal(profileOf('Serious'), 'ThermalSerious');
});

test('every pinned reading gets the Lean reason and verdict', () => {
  for (const g of of('pin')) {
    const state = g.state;
    assert.equal(pinWhy(g.target, g.held, g.lock, state, g.entered, g.waitedS), g.why, JSON.stringify(g));
    assert.equal(pinGate(g.target, g.held, g.lock, state, g.entered, g.waitedS), g.verdict, JSON.stringify(g));
    assert.equal(whyPin(g.why), g.verdict);
  }
});

test('no reading runs a lane unless the owner holds the condition and the reported state is the target; Critical always stops', () => {
  const goes = of('pin').filter((g) => g.verdict === 'go');
  assert.ok(goes.length > 0);
  for (const g of goes) { assert.equal(g.held, true); assert.equal(g.state, g.target); assert.notEqual(g.lock, 'locked'); }
  for (const g of of('pin').filter((x) => x.state === 'Critical')) assert.equal(g.verdict, 'stop', JSON.stringify(g));
  for (const g of of('pin').filter((x) => x.held === false)) assert.notEqual(g.verdict, 'go');
  for (const g of of('pin').filter((x) => x.verdict === 'wait')) assert.ok(g.waitedS < PIN.pinWaitMaxS);
});

test('lanes and visits match Lean: the first reading that is not go ends the run', () => {
  for (const l of of('lanes')) {
    const rs = l.readings.map((r) => ({ held: r.held, lock: r.lock, state: r.state }));
    assert.deepEqual(laneGates(l.target, rs), l.verdicts, JSON.stringify(l));
    assert.equal(lanesRun(laneGates(l.target, rs)), l.lanes, JSON.stringify(l));
  }
  for (const v of of('visit')) assert.equal(visitOk(v.verdicts), v.ok, JSON.stringify(v));
  for (const b of of('blockvalid')) assert.equal(blockValid(b.target, b.states), b.valid, JSON.stringify(b));
  assert.equal(blockValid('Serious', ['Serious', 'Critical']), false);
  assert.equal(blockValid('Serious', ['Serious', 'Fair']), false);
});

test('stopping the owner matches Lean: TERM first, KILL only after the grace, never a signal for a gone process', () => {
  for (const s of of('stop')) assert.equal(stopAct(s.alive, s.sent, s.sinceS), s.act, JSON.stringify(s));
  for (const s of of('stop').filter((x) => x.sent === 'none')) assert.notEqual(s.act, 'kill');
  for (const s of of('stop').filter((x) => x.alive === false)) assert.equal(s.act, 'done');
});

test('a session never ends with the condition set: close, end and clear rules match Lean', () => {
  for (const c of of('close')) {
    assert.equal(closeAct(c.phase), c.close, c.phase);
    if (c.mayBeAlive) assert.equal(c.close, 'stopOwner');
  }
  for (const e of of('end')) {
    assert.equal(endVerdict(e.target, e.ownerGone, e.back), e.end, JSON.stringify(e));
    assert.equal(conditionSet(e.ownerGone), e.conditionSet);
    if (e.end !== 'stuck') assert.equal(e.conditionSet, false);
  }
  for (const w of of('clearwait')) assert.equal(clearWait(w.target, w.back, w.waitedS), w.wait, JSON.stringify(w));
  for (const k of of('kill')) assert.equal(mayKill(k.recPid, k.curPid, k.recStart, k.curStart), k.ok, JSON.stringify(k));
});

test('profileListed finds the id in group ThermalCondition only', () => {
  const list = [{ identifier: 'SlowNetworkCondition', profiles: [{ identifier: 'ThermalSerious' }] }, { identifier: 'ThermalCondition', profiles: [{ identifier: 'ThermalFair' }, { identifier: 'ThermalSerious' }] }];
  assert.equal(profileListed(list, 'ThermalSerious'), true);
  assert.equal(profileListed(list.slice(0, 1), 'ThermalSerious'), false);
  assert.equal(profileListed(JSON.stringify(list), 'ThermalCritical'), false);
  assert.equal(profileListed({}, 'ThermalSerious'), false);
});

test('psInfo reads the state letter and the start time of a live process', () => {
  const me = psInfo(process.pid);
  assert.ok(me && me.start.length > 10 && !me.stat.startsWith('Z'));
  assert.equal(psInfo(2 ** 22 + 12345), null);
});

test('the owner starts one detached userspace process for the listed profile and records its pid and start time', async () => {
  const w = fakeWorld();
  const { dir, owner } = mkOwner(w);
  try {
    const rec = await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    assert.deepEqual(w.runs[0], ['developer', 'dvt', 'condition', 'list', '--userspace']);
    assert.equal(w.spawned.length, 1);
    assert.deepEqual(w.spawned[0].args, ['developer', 'dvt', 'condition', 'set', 'ThermalSerious', '--userspace']);
    assert.equal(w.spawned[0].opts.detached, true);
    assert.ok(!w.spawned[0].args.includes('--native'));
    assert.equal(rec.pid, 4000);
    assert.equal(rec.start, 'start-4000');
    assert.equal(JSON.parse(readFileSync(join(dir, 'pin-owner.json'), 'utf8')).pid, 4000);
    assert.equal(owner.alive(), true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a profile that condition list does not show starts nothing; a list failure starts nothing', async () => {
  const w = fakeWorld();
  const { dir, owner } = mkOwner(w);
  try {
    await assert.rejects(owner.start({ profile: 'ThermalCritical', target: 'Critical' }), /no ThermalCritical/);
    assert.equal(w.spawned.length, 0);
    const w2 = fakeWorld({ listOk: false });
    const o2 = mkOwner(w2);
    await assert.rejects(o2.owner.start({ profile: 'ThermalSerious', target: 'Serious' }), /condition list exited 1/);
    assert.equal(w2.spawned.length, 0);
    rmSync(o2.dir, { recursive: true, force: true });
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('stop sends SIGTERM and nothing else when the owner exits on it', async () => {
  const w = fakeWorld();
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const r = await owner.stop();
    assert.deepEqual(w.signals, ['SIGTERM']);
    assert.equal(r.gone, true);
    assert.equal(owner.phase, 'stopped');
    assert.equal(owner.alive(), false);
    assert.ok(JSON.parse(readFileSync(join(dir, 'pin-owner.json'), 'utf8')).stoppedAt);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('stop escalates to SIGKILL after the grace and reports stuck when even that does not end it', async () => {
  const w = fakeWorld({ dieOn: ['SIGKILL'] });
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const t0 = w.t;
    const r = await owner.stop();
    assert.deepEqual(w.signals, ['SIGTERM', 'SIGKILL']);
    assert.equal(r.gone, true);
    assert.ok((w.t - t0) / 1000 >= PIN.stopGraceS);
    const w2 = fakeWorld({ dieOn: [] });
    const o2 = mkOwner(w2);
    await o2.owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const r2 = await o2.owner.stop();
    assert.equal(r2.gone, false);
    assert.deepEqual(w2.signals, ['SIGTERM', 'SIGKILL']);
    assert.equal(o2.owner.phase, 'stopping');
    rmSync(o2.dir, { recursive: true, force: true });
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a signal goes only to the process with the recorded pid and start time', async () => {
  const w = fakeWorld();
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    w.procs.set(4000, 'another-start');
    assert.equal(owner.alive(), false);
    const r = await owner.stop();
    assert.deepEqual(w.signals, []);
    assert.equal(r.gone, true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('an owner a crashed run left behind is stopped by the next run; a stale record is closed without a signal', async () => {
  const w = fakeWorld();
  const first = mkOwner(w);
  try {
    await first.owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const again = new ConditionOwner({ dir: first.dir, ...w.opts });
    assert.equal(await again.recover(), true);
    assert.deepEqual(w.signals, ['SIGTERM']);
    const third = new ConditionOwner({ dir: first.dir, ...w.opts });
    assert.equal(await third.recover(), false);
    assert.equal(w.signals.length, 1);
    const { dir: d2, owner: o2 } = mkOwner(w);
    await o2.start({ profile: 'ThermalSerious', target: 'Serious' });
    w.procs.clear();
    const o3 = new ConditionOwner({ dir: d2, ...w.opts });
    assert.equal(await o3.recover(), false);
    assert.equal(w.signals.length, 1);
    assert.ok(JSON.parse(readFileSync(join(d2, 'pin-owner.json'), 'utf8')).stoppedAt);
    rmSync(d2, { recursive: true, force: true });
  } finally { rmSync(first.dir, { recursive: true, force: true }); }
});

test('no signal is ever SIGINT', async () => {
  const w = fakeWorld({ dieOn: ['SIGKILL'] });
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    await owner.stop();
    assert.ok(w.signals.every((s) => s === 'SIGTERM' || s === 'SIGKILL'));
    assert.equal(existsSync(join(dir, 'pin-owner.log')), true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

