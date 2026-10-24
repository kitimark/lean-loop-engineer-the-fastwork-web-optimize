import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const dot = ['.git', 'hub'].join('');
const action = readFileSync(`${root}/${dot}/actions/gate-engine/action.yml`, 'utf8');
const rows = (file) => readFileSync(`${root}/packages/contracts/golden/${file}`, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));

const caseLine = action.split('\n').map((l) => l.trim()).filter((l) => /^case "\$\{GITHUB_REF_NAME:-\}" in /.test(l));

test('the action has exactly one ref case', () => {
  assert.equal(caseLine.length, 1);
});

test('the shell case gives the golden save on every ref row', () => {
  const refs = rows('ops/gate-engine-timing.jsonl').filter((r) => r.kind === 'ref');
  assert.ok(refs.length >= 6);
  for (const r of refs) {
    const out = execFileSync('bash', ['-c', `${caseLine[0]}; echo $save`], { env: { PATH: process.env.PATH, GITHUB_REF_NAME: r.ref }, encoding: 'utf8' }).trim();
    assert.equal(out, String(r.save), `ref ${r.ref}`);
  }
});

test('every save step of the action asks for the keys step save output', () => {
  const steps = action.split(/\n    - name: /).filter((s) => /actions\/cache\/save@/.test(s));
  assert.equal(steps.length, 3);
  for (const s of steps) assert.match(s, /steps\.keys\.outputs\.save == 'true'/);
});

test('restore classes of the golden follow the ref rule', () => {
  const all = rows('ops/gate-engine-timing.jsonl');
  const refs = new Map(all.filter((r) => r.kind === 'ref').map((r) => [r.ref, r.save]));
  const checked = all.filter((r) => r.kind === 'restoreCase' || r.kind === 'leg');
  assert.ok(checked.length >= 8);
  for (const c of checked) {
    const saves = refs.has(c.ref) ? refs.get(c.ref) : !c.ref.startsWith('ci/land-');
    const want = c.hit ? 'restored' : saves ? 'firstSave' : c.mainHolds ? 'keyMiss' : 'missingRestore';
    assert.equal(c.class, want, `${c.kind} ${c.ref}`);
  }
});

test('branch-only writers are the gate writers that are neither land nor a seeder', () => {
  const t = rows('ci/triggers.jsonl').find((r) => r.kind === 'table');
  const key = (w) => `${w.file}/${w.job}/${w.cache}`;
  const want = t.cacheWriters.filter((w) => t.gateCaches.includes(w.cache) && w.file !== 'land.yml'
    && !t.seeders.some((s) => s.file === w.file && s.job === w.job)).map(key).sort();
  assert.deepEqual(t.branchOnly.map(key).sort(), want);
  assert.ok(want.length > 0);
});
