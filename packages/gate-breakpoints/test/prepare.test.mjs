// One lazy-mount mechanism: anchors.json `prepare` steps, run by page.mjs prepareInPage after the ready wait.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadAnchors } from '../src/spec.mjs';
import * as page from '../src/page.mjs';

const src = (f) => readFileSync(join(import.meta.dirname, '..', 'src', f), 'utf8');

test('every prepare step names scrollNear, waitFor and why, for an arm that exists', () => {
  const covered = [];
  for (const [pid, spec] of Object.entries(loadAnchors().parts)) {
    assert.equal(spec.prime, undefined, `${pid}: no separate prime key; use prepare`);
    if (!spec.prepare) continue;
    covered.push(pid);
    for (const [arm, steps] of Object.entries(spec.prepare)) {
      assert.ok(['orig', 'rewrite'].includes(arm), `${pid}: arm ${arm}`);
      assert.ok(steps.length > 0, pid);
      for (const st of steps) {
        for (const k of ['scrollNear', 'waitFor', 'why']) assert.equal(typeof st[k], 'string', `${pid}.${k}`);
        assert.deepEqual(Object.keys(st).sort(), ['scrollNear', 'waitFor', 'why'], `${pid}: only the three keys`);
      }
    }
  }
  for (const pid of ['morph.countdown', 'morph.columns', 'morph.panel']) assert.ok(covered.includes(pid), `${pid} prepares`);
});

test('the harness has a single lazy-mount route', () => {
  const run = src('run.mjs');
  assert.ok(!/ORIG_PREPARE|mountPanel|primeOrig|lateIds/.test(run + src('page.mjs')));
  assert.equal(typeof page.prepareInPage, 'function');
  assert.equal(page.mountPanel, undefined);
  assert.equal(page.primeOrig, undefined);
  assert.equal((run.match(/prepareInPage/g) ?? []).length, 2, 'imported once, called once');
  // the steps run once after waitReady, before any collection
  assert.ok(run.indexOf('waitReady, {') < run.indexOf('prepareInPage, {'));
});
