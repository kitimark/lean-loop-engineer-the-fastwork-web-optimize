import test from 'node:test';
import assert from 'node:assert/strict';
import { Script } from 'node:vm';
import { parseVariant } from '../src/variants.mjs';
import { harnessSource } from '../src/harness.mjs';
import { framesOf } from '../src/reduce.mjs';

const S = (rc, sr, ls, extra = {}) => ({ rc, sr, ls, si: 0, lf: rc, lu: 0, cu: 0, ...extra });

test('parseVariant: base, flags in any order, normalised name', () => {
  assert.deepEqual(parseVariant('live'), { name: 'live', vt: false, warm: false, trace: false });
  assert.deepEqual(parseVariant('vt-trace-warm'), { name: 'vt-warm-trace', vt: true, warm: true, trace: true });
});

test('parseVariant: rejects unknown bases and flags', () => {
  assert.throws(() => parseVariant('cold'), /live or vt/);
  assert.throws(() => parseVariant('vt-fast'), /unknown flag/);
});

test('harnessSource: every variant compiles as a script and carries its parts', () => {
  for (const o of [{}, { warm: true }, { vt: true }, { vt: true, trace: true, warm: true }, { trace: true }]) {
    const s = harnessSource(o);
    new Script(s); // throws on a syntax error
    assert.equal(s.includes('window.__fwVt = {'), !!o.vt);
    assert.equal(s.includes('window.__fwEv = ev'), !!o.trace);
  }
});

test('framesOf: trace counters become ev_<name> deltas, zero-filled over all frames', () => {
  const a = { ...S(0, 0, 0), ev: { raf: 1 } };
  const b = { ...S(2, 2, 5), ev: { raf: 3, timeout900: 1 } };
  const c = { ...S(4, 4, 5), ev: { raf: 5, timeout900: 1 } };
  const f = framesOf([{ k: 0, y: 0, b: a, mids: [] }, { k: 1, y: 50, b, mids: [] }], c);
  assert.equal(f[0].counts.ev_raf, 2);
  assert.equal(f[0].counts.ev_timeout900, 1);
  assert.equal(f[1].counts.ev_timeout900, 0);
});
