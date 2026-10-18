// One preparation mechanism: anchors.json `prepare` steps (kind "mount" or "overlay"), run by page.mjs prepareInPage.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadAnchors } from '../src/spec.mjs';
import * as page from '../src/page.mjs';

const src = (f) => readFileSync(join(import.meta.dirname, '..', 'src', f), 'utf8');
const KEYS = {
  mount: ['kind', 'scrollNear', 'waitFor', 'why'],
  overlay: ['close', 'gone', 'kind', 'ready', 'trigger', 'why'],
};

test('every prepare step has a known kind with exactly its keys, for an arm that exists', () => {
  const covered = [];
  for (const [pid, spec] of Object.entries(loadAnchors().parts)) {
    assert.equal(spec.prime, undefined, `${pid}: no separate prime key; use prepare`);
    if (!spec.prepare) continue;
    covered.push(pid);
    for (const [arm, steps] of Object.entries(spec.prepare)) {
      assert.ok(['orig', 'rewrite'].includes(arm), `${pid}: arm ${arm}`);
      assert.ok(steps.length > 0, pid);
      for (const st of steps) {
        assert.ok(KEYS[st.kind], `${pid}: kind ${st.kind}`);
        assert.deepEqual(Object.keys(st).sort(), KEYS[st.kind], `${pid}: keys of ${st.kind}`);
        for (const k of KEYS[st.kind]) assert.equal(typeof st[k], 'string', `${pid}.${k}`);
      }
    }
  }
  for (const pid of ['morph.countdown', 'morph.columns', 'morph.panel', 'overlays.drawer', 'overlays.signup']) assert.ok(covered.includes(pid), `${pid} prepares`);
});

test('overlay parts prepare both arms (the rewrite has its own trigger)', () => {
  const { parts } = loadAnchors();
  for (const pid of ['overlays.drawer', 'overlays.signup']) {
    assert.ok(parts[pid].prepare.orig && parts[pid].prepare.rewrite, pid);
    assert.ok([...parts[pid].prepare.orig, ...parts[pid].prepare.rewrite].every((st) => st.kind === 'overlay'), pid);
  }
});

test('the harness has a single preparation route', () => {
  const run = src('run.mjs');
  const all = run + src('page.mjs');
  assert.ok(!/ORIG_PREPARE|mountPanel|primeOrig|lateIds|openOverlay|closeOverlay|\bPREPARE\b/.test(all));
  assert.equal(typeof page.prepareInPage, 'function');
  for (const f of ['mountPanel', 'primeOrig', 'openOverlay', 'closeOverlay']) assert.equal(page[f], undefined, f);
  assert.equal((run.match(/import \{[^}]*prepareInPage/g) ?? []).length, 1);
  assert.ok(run.indexOf('waitReady, {') < run.indexOf("stage: 'ready'"));
});

test('parts without a prepare step are collected before any mount runs (fresh-load state)', () => {
  const run = src('run.mjs');
  const early = run.indexOf('pick([...mountIds, ...overlayIds], false)');
  assert.ok(early > 0);
  assert.ok(early < run.indexOf("stage: 'ready'"), 'early parts first, mounts after');
  assert.ok(early < run.indexOf("stage: 'open'"), 'early parts before overlays too');
});
