// Every anchors.json `prepare` step has a kind that run.mjs runs. A step of another kind used to be skipped silently, and its
// part was compared on a page that never reached the state (gate-shard-balance round 2, run 39114796757: 0 original nodes).
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadAnchors } from '../src/spec.mjs';
import { PREPARE_KINDS } from '../src/run.mjs';

test('every prepare step has a kind the runner runs', () => {
  const anchors = loadAnchors();
  let steps = 0;
  for (const [pid, p] of Object.entries(anchors.parts ?? anchors)) {
    for (const [site, list] of Object.entries(p.prepare ?? {})) for (const st of list) {
      steps++;
      assert.ok(PREPARE_KINDS.includes(st.kind), `${pid}.prepare.${site}: kind ${JSON.stringify(st.kind)}`);
    }
  }
  assert.ok(steps >= 2, 'morph.countdown and morph.columns mount the original panel');
});

test('a mount step on one arm has a mount step on the other: both arms are read after the same scroll history', () => {
  // The original recomputes the pain notes' base positions when its content-visibility section first renders after a resize; a rewrite
  // that never scrolled keeps the old ones (CI run 39130842197: pain.notes note x in 125 sweep stops). Overlay steps open and close
  // again, so they leave no history; a mount step scrolls away and back, which does.
  const anchors = loadAnchors();
  for (const [pid, p] of Object.entries(anchors.parts ?? anchors)) {
    const mounts = (site) => (p.prepare?.[site] ?? []).filter((st) => st.kind === 'mount').length;
    assert.equal(mounts('orig') > 0, mounts('rewrite') > 0, `${pid}: mount steps on one arm only`);
  }
});
