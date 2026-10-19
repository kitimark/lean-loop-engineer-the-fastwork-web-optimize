// Run: node --test test/port-fonts.test.mjs (from apps/site). Check 5 of the port completeness gate (Fw.Port.Fonts): the twin in
// scripts/port/fonts.mjs replays every Lean case of packages/contracts/golden/port/fonts.jsonl. With FW_PORT_FONTS_ENGINE
// (chromium | playwright-webkit) set, two synthetic page pairs are loaded in that browser through the same page function the
// built-page run uses: a port whose pain.notes falls back to Google Sans fails, and a port that draws the same fonts passes.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { check, excl, goldenCases, loaded, units } from '../../../scripts/port/fonts.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const cases = goldenCases();
const engineName = process.env.FW_PORT_FONTS_ENGINE;

test('the exclusions the check runs with are the Lean ones', () => {
  assert.ok(cases.length > 0);
  const shape = (l) => l.map(({ check: c, sec, key }) => ({ check: c, sec, key }));
  for (const c of cases) assert.deepEqual(shape(c.excl), shape(excl), c.name);
});

test('units, loaded faces and verdicts equal the Lean cases', () => {
  for (const c of cases) {
    assert.deepEqual(units(c.excl, c.rewrite.leaves), c.units, c.name);
    assert.deepEqual(loaded(c.excl, c.rewrite.faces), c.loaded, c.name);
    const v = check(c.excl, c.orig, c.rewrite);
    assert.deepEqual(v.missing, c.missing, c.name);
    assert.deepEqual(v.extra, c.extra, c.name);
    assert.deepEqual(v.missingFaces, c.missingFaces, c.name);
    assert.deepEqual(v.extraFaces, c.extraFaces, c.name);
    assert.equal(v.pass, c.pass, c.name);
  }
});

test('the Lean cases cover a fallback family, weight, style, a lost face and an extra face', () => {
  const by = (n) => cases.find((c) => c.name === n);
  assert.equal(by('same').pass, true);
  assert.equal(by('countdown text and white space differ').pass, true);
  assert.equal(by('the excluded family loads').pass, true);
  for (const n of ['pain.notes falls back to Google Sans', 'countdown weight differs', 'accent style differs', 'a leaf appears twice', 'the italic face is not loaded', 'an extra face is loaded'])
    assert.equal(by(n).pass, false, n);
});

const FACES = `@font-face{font-family:"Google Sans";font-weight:400 700;src:url(/f/google.woff2) format("woff2")}
@font-face{font-family:"Playpen Sans Start Selling";font-weight:400 600;src:url(/f/playpen.woff2) format("woff2")}
body{font-family:"Google Sans",sans-serif;margin:0}`;
const origPage = `<!doctype html><meta charset="utf-8"><style>${FACES}</style><p>Hello world</p>
<section class="pain"><div class="pain-sticky"><div class="pain-canvas" style="font-family:'Playpen Sans Start Selling',sans-serif">A sticky note</div></div></section>`;
const portPage = (notesFamily) => `<!doctype html><meta charset="utf-8"><style>${FACES}</style><p>Hello world</p>
<section data-fw="pain"><div data-fw="pain-notes" style="font-family:'${notesFamily}',sans-serif">A sticky note</div></section>`;

test('in a browser, a port whose pain.notes falls back to Google Sans fails and one with the same fonts passes', { skip: !engineName && 'FW_PORT_FONTS_ENGINE unset', timeout: 120000 }, async () => {
  const { LAUNCHERS } = await import('../../../packages/visual-diff/src/engines.mjs');
  const { fontsAtProbes } = await import('../../../packages/visual-diff/src/fonts.mjs');
  const { startServer, snapshotRoot } = await import('../../../packages/gate-breakpoints/src/serve.mjs');
  const gen = JSON.parse(readFileSync(path.join(repo, 'apps/site/src/breakpoints.gen.json'), 'utf8'));
  const probes = ['desk-1512', 'touch-401'].map((id) => gen.matrix.probes.find((p) => p.id === id));
  assert.ok(probes.every(Boolean));
  const snap = snapshotRoot();
  const tmp = mkdtempSync(path.join(tmpdir(), 'port-fonts-'));
  const dirs = {};
  for (const [name, html] of [['orig', origPage], ['good', portPage('Playpen Sans Start Selling')], ['bad', portPage('Google Sans')]]) {
    dirs[name] = path.join(tmp, name);
    mkdirSync(path.join(dirs[name], 'f'), { recursive: true });
    writeFileSync(path.join(dirs[name], 'index.html'), html);
    copyFileSync(path.join(snap, '_app/immutable/assets/google-sans-latin-normal.BbZhqv4U.woff2'), path.join(dirs[name], 'f/google.woff2'));
    copyFileSync(path.join(snap, 'selling/fonts/playpen-sans-latin.woff2'), path.join(dirs[name], 'f/playpen.woff2'));
  }
  const servers = { orig: await startServer(dirs.orig), good: await startServer(dirs.good), bad: await startServer(dirs.bad) };
  const engine = await LAUNCHERS[engineName]();
  try {
    const run = (port) => fontsAtProbes({
      engine, probes, concurrency: 1,
      targets: { real: false, orig: { origin: servers.orig.origin, path: '/' }, rewrite: { origin: servers[port].origin, path: '/' } },
    });
    const good = await run('good');
    assert.deepEqual(good.map((r) => [r.id, r.pass, r.error ?? null]), probes.map((p) => [p.id, true, null]));
    const bad = await run('bad');
    for (const r of bad) {
      assert.equal(r.pass, false, r.id);
      assert.deepEqual(r.missing.map((u) => [u.sec, u.text, u.family]), [['pain.notes', 'A sticky note', 'Playpen Sans Start Selling']], r.id);
      assert.deepEqual(r.extra.map((u) => [u.sec, u.text, u.family]), [['pain.notes', 'A sticky note', 'Google Sans']], r.id);
      assert.deepEqual(r.missingFaces.map((t) => t[0]), ['Playpen Sans Start Selling'], r.id);
      assert.deepEqual(r.extraFaces, [], r.id);
    }
  } finally {
    await engine.close();
    await Promise.all(Object.values(servers).map((s) => s.close()));
    rmSync(tmp, { recursive: true, force: true });
  }
});
