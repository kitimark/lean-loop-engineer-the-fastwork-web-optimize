// The replay driver on synthetic fixtures: a WebDriver double (a phone whose page sees the events WebKit's touch source makes), a mock
// HTTP WebDriver for the client, and the command line. No phone, no browser.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as R from '../src/device-replay.mjs';
import { wdClient, replayPass, runSession, doubleWd, checkRecord, startRecorderJs, recorderSeconds } from '../src/device-replay-wd.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/replay.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const profile = lines.find((l) => l.kind === 'profile' && l.profile).profile;
const zone = (() => { const z = lines.find((l) => l.kind === 'zoneLoop'); return { maxY10: z.maxY10, frames: z.frames, t0: z.t0 }; })();
const noSleep = async () => {};

test('a pass on the double: the compiled actions reach the page as the source swipes', async () => {
  const cap = {};
  const r = await replayPass({ wd: doubleWd(cap), caps: {}, url: 'http://x.invalid/', profile, sleep: noSleep, settleMs: 0, pollMs: 0 });
  assert.equal(r.matches, true);
  assert.equal(r.rep.length, profile.swipes.length);
  assert.ok(r.perSwipe.every((c) => c.swipe));
  assert.equal(cap.payload.actions[0].parameters.pointerType, 'touch');
  assert.deepEqual(cap.payload, R.w3c(R.compile(profile)));
  assert.ok(cap.payload.actions[0].actions.every((a) => a.type !== 'pause' && a.type !== 'pointerMove' ? true : a.duration <= 16));
});

test('a replay that lost an event is refused, naming the conjunct', async () => {
  const wd = doubleWd();
  const perform = wd.perform;
  wd.perform = async (sid, payload) => { // the phone drops the last touchmove of the first swipe
    const acts = payload.actions[0].actions;
    let i = acts.findIndex((a) => a.type === 'pointerUp');
    while (acts[i].type !== 'pointerMove') i--;
    acts.splice(i, 1);
    return perform(sid, payload);
  };
  const r = await replayPass({ wd, caps: {}, url: 'http://x.invalid/', profile, sleep: noSleep, settleMs: 0, pollMs: 0 });
  assert.equal(r.matches, false);
  assert.equal(r.perSwipe[0].swipe, false);
});

test('a session runs every kind, the arm order rotating per repeat', async () => {
  const order = [];
  const wd = doubleWd();
  const url = wd.url;
  wd.url = async (sid, u) => { order.push(u); return url(sid, u); };
  const arms = [{ name: 'a', url: 'a' }, { name: 'b', url: 'b' }];
  const r = await runSession({ wd, caps: {}, arms, base: profile, kinds: ['recorded', 'fast-fling', 'zone-hero', 'cold'], reps: 2, gen: { n: 3, gap: 40000, reps: 1, zone }, settleMs: 0, pollMs: 0, sleep: noSleep });
  assert.equal(r.passes.length, 4 * 2 * 2);
  assert.deepEqual(order.slice(0, 4), ['a', 'b', 'b', 'a'], 'rep 0 starts with arm a, rep 1 with arm b');
  assert.ok(r.passes.every((p) => p.matches), JSON.stringify(r.passes.filter((p) => !p.matches).map((p) => p.profile)));
});

test('a session skips a kind the recording has no swipe for', async () => {
  const logs = [];
  const r = await runSession({ wd: doubleWd(), caps: {}, arms: [{ name: 'a', url: 'a' }], base: profile, kinds: ['zone-finish', 'recorded'], reps: 1, gen: { n: 1, gap: 1000, reps: 1, zone: { ...zone, frames: [[0, 0]] } }, settleMs: 0, pollMs: 0, sleep: noSleep, log: (s) => logs.push(s) });
  assert.equal(r.passes.length, 1);
  assert.ok(logs.some((s) => s.includes('zone-finish')));
});

test('the recorder script and its length', () => {
  const js = startRecorderJs(20);
  assert.ok(js.includes('window.__wkRec = undefined') && js.includes('addEventListener'));
  assert.equal(recorderSeconds(R.compile(profile)), Math.ceil(R.actsMs(R.compile(profile)) / 1000) + 8);
});

test('the WebDriver client speaks W3C over HTTP', async () => {
  const seen = [];
  const srv = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      seen.push([req.method, req.url, body ? JSON.parse(body) : null]);
      const value = req.url === '/session' ? { sessionId: 'S1', capabilities: {} } : req.url.endsWith('/execute/sync') ? 7 : null;
      if (req.url.includes('/boom')) { res.writeHead(404).end(JSON.stringify({ value: { error: 'no such window', message: 'gone' } })); return; }
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ value }));
    });
  });
  await new Promise((ok) => srv.listen(0, '127.0.0.1', ok));
  try {
    const wd = wdClient(`http://127.0.0.1:${srv.address().port}`);
    const sid = await wd.newSession({ browserName: 'Safari' });
    assert.equal(sid, 'S1');
    await wd.url(sid, 'http://y.invalid/');
    assert.equal(await wd.execute(sid, 'return 7'), 7);
    const payload = R.w3c(R.compile(profile));
    await wd.perform(sid, payload);
    await wd.release(sid);
    await wd.quit(sid);
    assert.deepEqual(seen[0][2], { capabilities: { alwaysMatch: { browserName: 'Safari' } } });
    assert.deepEqual(seen.find((s) => s[1].endsWith('/actions') && s[0] === 'POST')[2], payload);
    assert.deepEqual(seen.map((s) => s[0] + ' ' + s[1].replace('/S1', '/_')).slice(0, 6), ['POST /session', 'POST /session/_/url', 'POST /session/_/execute/sync', 'POST /session/_/actions', 'DELETE /session/_/actions', 'DELETE /session/_']);
    await assert.rejects(() => wd.url('S1/boom', 'x'), /no such window/);
  } finally { await new Promise((ok) => srv.close(ok)); }
});

test('checkRecord on a record of the source itself', () => {
  const ev = R.simulateEvents(R.compile(profile));
  const rec = { frames: { t: [0, 16.7], y: [0, 0], p: { hero: [0, 0], people: [0, 0], fade: [0, 0] } }, maxY: 5000, viewport: { w: 390, h: 844, dpr: 3 }, zoom: { frames: 0, min: 1, max: 1 },
    touches: ev.map(([t, ph, x, y]) => [1000 + t, ph, x, y, ph === 'e' ? 0 : 1]) };
  assert.equal(checkRecord({ rec, profile }).matches, true);
});

test('command line: compile and plan on synthetic files', () => {
  const dir = mkdtempSync(join(tmpdir(), 'replay-cli-'));
  const pfile = join(dir, 'p.json');
  writeFileSync(pfile, JSON.stringify(profile));
  const cli = join(here, '../src/device-replay-cli.mjs');
  const c = spawnSync('node', [cli, 'compile', '--profile', pfile, '--out', join(dir, 'a.json')], { encoding: 'utf8' });
  assert.equal(c.status, 0, c.stderr);
  const out = JSON.parse(c.stdout);
  assert.ok(out.maxTickMs <= 16 && out.tickMax === 16);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, 'a.json'), 'utf8')).w3c, R.w3c(R.compile(profile)));
  const p = spawnSync('node', [cli, 'plan', '--kinds', 'recorded,cold', '--reps', '2', '--arms', '2'], { encoding: 'utf8' });
  assert.deepEqual(p.stdout.trim().split('\n'), ['recorded rep 0 arms 0,1', 'recorded rep 1 arms 1,0', 'cold rep 0 arms 0,1', 'cold rep 1 arms 1,0']);
  const bad = spawnSync('node', [cli, 'nope'], { encoding: 'utf8' });
  assert.equal(bad.status, 2);
});
