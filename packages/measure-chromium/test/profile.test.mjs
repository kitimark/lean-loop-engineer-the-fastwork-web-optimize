import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseProfile, replayOk, replayEvents, HARD_CAP, PINNED, DIRS, parseKind, dropOk, keep, problem, userAgent, runnable, readOk, cftPlatform, cftExe, cftUrl } from '../src/profile.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const dir = join(here, '../profiles');
const golden = readFileSync(join(here, '../../contracts/golden/device/session.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const wire = readFileSync(join(here, '../../contracts/golden/measure/profile.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const read = (f) => JSON.parse(readFileSync(join(dir, f), 'utf8'));

test('every committed profile loads', () => {
  const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
  assert.ok(files.includes('user-fixture.json') && files.includes('swipe-touch-v1.json'));
  for (const f of files) assert.equal(parseProfile(read(f)).profile.id, f.replace(/\.json$/, ''), f);
});

test('every file sits in the directory of its kind', () => {
  for (const [kind, sub] of Object.entries(DIRS)) {
    const d = join(here, '..', sub);
    const files = readdirSync(d).filter((f) => f.endsWith('.json'));
    assert.ok(files.length > 0, sub);
    for (const f of files) {
      const r = parseProfile(JSON.parse(readFileSync(join(d, f), 'utf8')));
      assert.equal(r.profile.id, f.replace(/\.json$/, ''), f);
      assert.equal(r.kind, kind, `${sub}/${f}`);
    }
  }
});

test('kind, dropFlags, css and user agent agree with the Lean golden', () => {
  const c = wire.find((l) => l.kind === 'consts');
  assert.deepEqual(PINNED, c.pinned);
  assert.deepEqual(DIRS, c.dirs);
  assert.deepEqual([userAgent(true), userAgent(false)], [c.ua.mobile, c.ua.desktop]);
  const n = { parseKind: 0, dropOk: 0, keep: 0, wire: 0, runnable: 0, readOk: 0, cft: 0 };
  for (const g of wire) {
    if (g.kind === 'parseKind') assert.equal(parseKind(g.in), g.out, JSON.stringify(g));
    if (g.kind === 'dropOk') assert.equal(dropOk(g.drop), g.ok, JSON.stringify(g));
    if (g.kind === 'keep') assert.deepEqual(keep(g.args, g.drops), g.out, JSON.stringify(g));
    if (g.kind === 'wire') {
      assert.equal(problem(g.wire), g.problem, JSON.stringify(g));
      assert.equal(DIRS[g.wire.kind], g.dir);
      assert.equal(userAgent(g.wire.mobile), g.ua);
    }
    if (g.kind === 'runnable') assert.equal(runnable(g.profile, g.mode), g.ok, JSON.stringify(g));
    if (g.kind === 'readOk') assert.equal(readOk(g.inProfiles, g.inProbes, g.declared), g.ok, JSON.stringify(g));
    if (g.kind === 'cft') {
      const p = cftPlatform(g.os, g.arch);
      assert.equal(p, g.platform, JSON.stringify(g));
      assert.equal(p === null ? null : cftExe(p), g.exe);
      assert.equal(p === null ? null : cftUrl('156.0.8078.47', p), g.url);
    }
    if (g.kind in n) n[g.kind]++;
  }
  assert.ok(n.parseKind >= 5 && n.dropOk >= 10 && n.keep >= 6 && n.wire >= 9 && n.runnable === 4 && n.readOk === 8 && n.cft >= 8, JSON.stringify(n));
});

test('the loader refuses what Lean refuses', () => {
  const base = read('desktop-1280.json');
  const edit = (f) => { const p = structuredClone(base); f(p); return p; };
  assert.throws(() => parseProfile(edit((p) => { p.dropFlags = ['--lang']; })), /dropInCounts/);
  assert.throws(() => parseProfile(edit((p) => { p.probe = { variants: [{ id: 'a' }] }; })), /variantsInCounts/);
  assert.throws(() => parseProfile(edit((p) => { p.kind = 'probe'; p.dropFlags = ['--enable-begin-frame-control']; })), /badDrop/);
  assert.throws(() => parseProfile(edit((p) => { p.css = ''; })), /emptyCss/);
  assert.throws(() => parseProfile(edit((p) => { p.kind = 'Probe'; })), /kind must be/);
  assert.equal(parseProfile(edit((p) => { p.kind = 'probe'; p.dropFlags = ['--lang']; })).kind, 'probe');
});

test('replayOk agrees with the Lean loader lines', () => {
  const cases = golden.filter((l) => l.kind === 'loader');
  assert.ok(cases.length >= 9);
  for (const g of cases) assert.equal(replayOk(g.w10, g.h10, g.cap, g.strokes), g.ok, JSON.stringify(g));
  assert.equal(golden.find((l) => l.kind === 'consts').maxReplayFrames, HARD_CAP);
});

test('the fixture replay: strokes in tenth px, one event per frame', () => {
  const { profile, strokes } = parseProfile(read('user-fixture.json'));
  assert.equal(profile.input.mode, 'replay');
  assert.equal(strokes.length, 5);
  const ev = replayEvents(strokes);
  assert.equal(ev.length, strokes.at(-1).f0 + strokes.at(-1).path.length);
  const n = ev.filter((e) => e !== undefined).length;
  assert.equal(n, strokes.reduce((a, s) => a + s.path.length, 0));
  const first = strokes[0];
  assert.equal(ev[first.f0].type, 'touchStart');
  assert.equal(ev[first.f0 + 1].type, 'touchMove');
  assert.equal(ev[first.f0 + first.path.length - 1].type, 'touchEnd');
  assert.deepEqual([ev[first.f0].x * 10, ev[first.f0].y * 10], first.path[0]);
});

test('a replay profile that cannot be replayed is refused with a reason', () => {
  const base = read('user-fixture.json');
  const edit = (f) => { const p = structuredClone(base); f(p); return p; };
  assert.throws(() => parseProfile(edit((p) => { p.input.strokes = []; })), /refused/);
  assert.throws(() => parseProfile(edit((p) => { p.input.strokes[0].path[1] = [9999, 10]; })), /refused/);
  assert.throws(() => parseProfile(edit((p) => { p.input.strokes[1].f0 = 1; })), /refused/);
  assert.throws(() => parseProfile(edit((p) => { p.input.maxFrames = 100; })), /refused/);
  assert.throws(() => parseProfile(edit((p) => { delete p.input.strokes; })), /input\.strokes/);
  assert.throws(() => parseProfile(edit((p) => { p.segments.push({ name: 'again', until: 'script' }); })), /exactly one/);
  assert.throws(() => parseProfile(edit((p) => { p.input.mode = 'touch'; })), /needs input\.mode "replay"/);
  assert.throws(() => parseProfile(edit((p) => { delete p.viewport; })), /viewport/);
});

test('the load diagnostics of run.mjs sit behind FW_LOAD_TRACE, the crash exit does not', () => {
  const src = readFileSync(join(here, '../src/run.mjs'), 'utf8');
  const open = src.indexOf('if (process.env.FW_LOAD_TRACE) {');
  assert.ok(open > 0, 'the FW_LOAD_TRACE block exists');
  let depth = 0, close = open;
  for (let i = src.indexOf('{', open); i < src.length; i++) {
    if (src[i] === '{') depth++;
    if (src[i] === '}' && --depth === 0) { close = i; break; }
  }
  // stockRun (the stock-Chrome crash probe) needs target discovery to see the crash; the rule covers the counts path only.
  const stockOpen = src.indexOf('async function stockRun(');
  let stockClose = stockOpen;
  for (let i = src.indexOf('{', stockOpen), d = 0; stockOpen >= 0 && i < src.length; i++) {
    if (src[i] === '{') d++;
    if (src[i] === '}' && --d === 0) { stockClose = i; break; }
  }
  for (const marker of ['Target.setDiscoverTargets', 'Page.lifecycleEvent', 'Runtime.exceptionThrown', 'Runtime.consoleAPICalled', 'Page.frameNavigated', 'Target.targetInfoChanged']) {
    const at = [...src.matchAll(new RegExp(`'${marker.replace('.', '\\.')}'`, 'g'))].map((m) => m.index);
    const counts = at.filter((i) => i < stockOpen || i > stockClose);
    assert.ok(counts.length > 0 && counts.every((i) => i > open && i < close), `${marker} only inside the FW_LOAD_TRACE block`);
  }
  assert.ok(src.indexOf('FW_RENDERER_CRASH') < open, 'the renderer-crash exit is outside the flag block');
});

test('profile people-o-hover carries the text-wrap workaround and the open-card probe', () => {
  const p = parseProfile(read('people-o-hover.json')).profile;
  assert.equal(p.css, read('desktop-1280.json').css);
  assert.equal(p.cardProbe.selector, '[role="tooltip"]');
});
