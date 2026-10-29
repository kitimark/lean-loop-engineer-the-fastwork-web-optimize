import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import {
  ConditionOwner, DROP, OWNER_PY, PIN, blockValid, clearWait, closeAct, conditionSet, endVerdict, laneGates, lanesRun, mayKill, pinGate, pinTarget, pinWhy,
  profileListed, profileOf, psInfo, recoverAct, stopAct, visitOk, whyPin, conditionSetDrop, droppedClear, endVerdictDrop, fallbackAct, recoverActD, termGate,
} from '../src/device-thermal-pin.mjs';
import { fakeWorld, mkOwner } from './pin-world.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/thermal.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the golden has every pinned kind', () => {
  for (const k of ['pinconsts', 'profile', 'pin', 'lanes', 'visit', 'blockvalid', 'stop', 'close', 'end', 'recover', 'clearwait', 'kill']) assert.ok(of(k).length > 0, k);
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
    assert.equal(endVerdict(e.target, e.ownerGone, e.acked, e.back), e.end, JSON.stringify(e));
    assert.equal(conditionSet(e.ownerGone, e.acked), e.conditionSet);
    if (e.end !== 'stuck' && e.end !== 'unconfirmed') assert.equal(e.conditionSet, false);
    if (e.conditionSet) assert.ok(e.end === 'stuck' || e.end === 'unconfirmed', JSON.stringify(e));
    if (e.ownerGone && !e.acked) assert.equal(e.end, 'unconfirmed');
  }
  for (const r of of('recover')) assert.equal(recoverAct(r.hasRecord, r.alive, r.acked), r.act, JSON.stringify(r));
  assert.equal(recoverAct(true, false, false), 'clearCycle');
  assert.equal(recoverAct(false, false, false), 'nothing');
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
    assert.equal(w.spawned[0].cmd, '/fake/python');
    assert.deepEqual(w.spawned[0].args, ['-c', OWNER_PY, 'ThermalSerious']);
    assert.equal(w.spawned[0].opts.detached, true);
    assert.ok(!OWNER_PY.includes('native') && !OWNER_PY.includes('SIGKILL'));
    assert.ok(OWNER_PY.indexOf('ci.clear()') < OWNER_PY.indexOf('ci.list()') && OWNER_PY.indexOf('ci.list()') < OWNER_PY.indexOf('fw-pin cleared'), 'clear, a reply, then the acknowledgement');
    assert.ok(OWNER_PY.includes('userspace_tunnel.establish_userspace_rsd'));
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
    assert.equal(r.acked, true);
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
    assert.equal(r.acked, false, 'a killed owner never confirmed its clear');
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

test('an owner a crashed run left behind is stopped by the next run; an acknowledged record is left alone', async () => {
  const w = fakeWorld();
  const first = mkOwner(w);
  try {
    await first.owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const again = new ConditionOwner({ dir: first.dir, ...w.opts });
    assert.equal(await again.recover(), true);
    assert.deepEqual(w.signals, ['SIGTERM']);
    assert.equal(w.spawned.length, 1);
    const third = new ConditionOwner({ dir: first.dir, ...w.opts });
    assert.equal(await third.recover(), false);
    assert.equal(w.signals.length, 1);
  } finally { rmSync(first.dir, { recursive: true, force: true }); }
});

test('an owner that ended without confirming its clear gets one set-and-clear cycle at the next run', async () => {
  const w = fakeWorld();
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    w.procs.clear();
    const next = new ConditionOwner({ dir, ...w.opts });
    assert.equal(await next.recover(), true);
    assert.equal(w.spawned.length, 2);
    assert.deepEqual(w.spawned[1].args, ['-c', OWNER_PY, 'ThermalSerious']);
    assert.deepEqual(w.signals, ['SIGTERM']);
    const rec = JSON.parse(readFileSync(join(dir, 'pin-owner.json'), 'utf8'));
    assert.equal(rec.acked, true);
    assert.equal(await new ConditionOwner({ dir, ...w.opts }).recover(), false);
    assert.equal(w.spawned.length, 2);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a clear cycle whose owner does not confirm is an error, not a pass', async () => {
  const w = fakeWorld({ ackOnTerm: false });
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    w.procs.clear();
    await assert.rejects(new ConditionOwner({ dir, ...w.opts }).recover(), /did not confirm/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
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


test('USB-drop rules match the Lean golden', () => {
  const d = of('dropconsts')[0];
  assert.equal(DROP.setWaitMaxS, d.setWaitMaxS);
  assert.equal(DROP.sessionWaitS, d.sessionWaitS);
  assert.ok(of('term').length >= 10 && of('enddrop').length >= 100 && of('recoverd').length >= 10 && of('fallback').length >= 10);
  for (const t of of('term')) assert.equal(termGate(t.alive, t.setAcked, t.waitedS), t.gate, JSON.stringify(t));
  for (const e of of('enddrop')) {
    assert.equal(endVerdictDrop(e.target, e.usbDropped, e.ownerGone, e.acked, e.before, e.back), e.end, JSON.stringify(e));
    assert.equal(conditionSetDrop(e.target, e.usbDropped, e.ownerGone, e.acked, e.before, e.back), e.conditionSet, JSON.stringify(e));
    if (e.end === 'clearedDrop') assert.ok(e.usbDropped && e.ownerGone && !e.acked && droppedClear(e.target, e.before, e.back));
  }
  for (const r of of('recoverd')) assert.equal(recoverActD(r.hasRecord, r.alive, r.acked, r.dropped), r.act, JSON.stringify(r));
  for (const f of of('fallback')) assert.equal(fallbackAct(f.sessionAlive, f.sent, f.sinceS), f.act, JSON.stringify(f));
});

test('stop waits for the owner to acknowledge its set before the first SIGTERM', async () => {
  const w = fakeWorld({ heldAfterS: 20 });
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious', before: 'Nominal' });
    const t0 = w.t;
    const r = await owner.stop();
    assert.deepEqual(w.signals, ['SIGTERM']);
    assert.ok((w.t - t0) / 1000 >= 20, 'the signal went out only after the held line');
    assert.equal(r.acked, true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('an owner that never acknowledges its set is signalled after the bound and its clear stays unconfirmed', async () => {
  const w = fakeWorld({ heldAfterS: Infinity, ackOnTerm: false });
  const lines = [];
  const { dir } = mkOwner(w);
  const owner = new ConditionOwner({ dir, ...w.opts, log: (l) => lines.push(l) });
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious' });
    const t0 = w.t;
    const r = await owner.stop();
    assert.deepEqual(w.signals, ['SIGTERM']);
    assert.ok((w.t - t0) / 1000 >= DROP.setWaitMaxS);
    assert.equal(r.acked, false);
    assert.ok(lines.some((l) => /did not acknowledge its set/.test(l)));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('recover: an owner that died on a USB drop while the phone reads its pre-pin state needs no clear cycle', async () => {
  const w = fakeWorld();
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious', before: 'Nominal' });
    w.procs.clear();
    w.log += 'userspace tunnel transport closed (device disconnected?); tearing down\n';
    const next = new ConditionOwner({ dir, ...w.opts });
    assert.equal(await next.recover({ read: () => 'Nominal' }), false);
    assert.equal(w.spawned.length, 1, 'no clear cycle');
    assert.deepEqual(w.signals, []);
    const rec = JSON.parse(readFileSync(join(dir, 'pin-owner.json'), 'utf8'));
    assert.equal(rec.usbDropped, true);
    assert.equal(rec.stoppedBy, 'recover-dropped');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('recover: a USB drop with the phone still hot, or unreadable, or without a drop in the log still runs the clear cycle', async () => {
  for (const [read, dropLine] of [[() => 'Serious', true], [() => null, true], [() => 'Nominal', false]]) {
    const w = fakeWorld();
    const { dir, owner } = mkOwner(w);
    try {
      await owner.start({ profile: 'ThermalSerious', target: 'Serious', before: 'Nominal' });
      w.procs.clear();
      if (dropLine) w.log += 'userspace tunnel transport closed (device disconnected?); tearing down\n';
      const next = new ConditionOwner({ dir, ...w.opts });
      assert.equal(await next.recover({ read }), true);
      assert.equal(w.spawned.length, 2);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  }
});

test('a drop line from an earlier owner in the same log does not count for a new owner', async () => {
  const w = fakeWorld();
  w.log = 'userspace tunnel transport closed (device disconnected?); tearing down\n';
  const { dir, owner } = mkOwner(w);
  try {
    await owner.start({ profile: 'ThermalSerious', target: 'Serious', before: 'Nominal' });
    assert.equal(owner.usbDropped(), false);
    w.log += 'ConnectionTerminatedError: The DTX service channel is closed.\n';
    assert.equal(owner.usbDropped(), true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
