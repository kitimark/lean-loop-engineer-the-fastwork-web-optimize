import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const action = readFileSync(`${root}/.github/actions/gate-engine/action.yml`, 'utf8');
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

test('branch-only writers are the gate writers that are neither land nor a seeder', () => {
  const t = rows('ci/triggers.jsonl').find((r) => r.kind === 'table');
  const key = (w) => `${w.file}/${w.job}/${w.cache}`;
  const want = t.cacheWriters.filter((w) => t.gateCaches.includes(w.cache) && w.file !== 'land.yml'
    && !t.seeders.some((s) => s.file === w.file && s.job === w.job)).map(key).sort();
  assert.deepEqual(t.branchOnly.map(key).sort(), want);
  assert.ok(want.length > 0);
});
