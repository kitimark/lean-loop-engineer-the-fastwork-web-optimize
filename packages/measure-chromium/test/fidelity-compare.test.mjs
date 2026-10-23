import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const COMPARE = join(here, '../src/fidelity-compare.mjs');
const view = (docH, partH, extra = {}) => ({ width: 430, height: 932, crash: false, error: null, docH, parts: { a: { n: 1, height: partH }, b: { n: 1, height: 100 } }, leaves: [{ sec: 'a', text: 'x', lines: 2, family: 'F' }], uncovered: [[9733, 1]], totalCps: 10, ...extra });
const file = (variant, views, set) => ({ schema: 'fw.font-fidelity/1', variant, browser: 'test', platform: 'test', views, ...(set ? { set } : {}) });

function run(files) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-fid-'));
  mkdirSync(join(dir, 'x'));
  for (const [name, j] of Object.entries(files)) writeFileSync(join(dir, 'x', name), JSON.stringify(j));
  const r = spawnSync(process.execPath, [COMPARE, `--dir=${dir}`, '--pick-views=m430'], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return { choice: JSON.parse(readFileSync(join(dir, 'fidelity-choice.json'), 'utf8')), text: readFileSync(join(dir, 'fidelity-summary.md'), 'utf8') };
}

test('the comparison picks the nearest layout, drops a crashed set, and ties go to fewer .notdef then fewer packages', () => {
  const ref = file('webkit-mac', { m430: view(6000, 500) });
  const files = {
    'fidelity-webkit-mac.json': ref,
    'fidelity-none-r1.json': file('none', { m430: view(5000, 400, { crash: true }) }, { name: 'none', pkgs: [] }),
    'fidelity-lib-r1.json': file('lib', { m430: view(5300, 450, { systemCovered: [] }) }, { name: 'lib', pkgs: ['fonts-liberation'] }),
    'fidelity-near-r1.json': file('near', { m430: view(6000, 500, { systemCovered: [] }) }, { name: 'near', pkgs: ['fonts-liberation', 'a'] }),
    'fidelity-near2-r1.json': file('near2', { m430: view(6000, 500, { systemCovered: [9733] }) }, { name: 'near2', pkgs: ['fonts-liberation', 'a', 'b'] }),
  };
  const { choice, text } = run(files);
  assert.equal(choice.pick, 'near2', 'equal distance, fewer .notdef wins over fewer packages');
  assert.deepEqual(choice.excluded, ['none']);
  const lib = choice.scores.find((s) => s.name === 'lib');
  assert.equal(lib.dist, 700 + 50);
  assert.match(text, /\*\*Pick: near2\*\*/);
});

test('with no usable candidate the pick is none', () => {
  const { choice } = run({
    'fidelity-webkit-mac.json': file('webkit-mac', { m430: view(6000, 500) }),
    'fidelity-none-r1.json': file('none', { m430: view(5000, 400, { crash: true }) }, { name: 'none', pkgs: [] }),
  });
  assert.equal(choice.pick, null);
});
