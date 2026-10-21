import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ARMS, armById, recordArgs } from '../src/xctrace/arms.mjs';
import { sweepYs, zonePlan } from '../src/xctrace/scroll.mjs';

test('arm ids are unique and every arm builds an xctrace record command', () => {
  assert.equal(new Set(ARMS.map((a) => a.id)).size, ARMS.length);
  for (const a of ARMS) {
    const args = recordArgs(a, { udid: 'U', out: 'o.trace' });
    assert.deepEqual(args.slice(0, 2), ['xctrace', 'record']);
    assert.ok(args.includes('--all-processes'));
    assert.ok(args.includes('--no-prompt'));
    assert.equal(args[args.indexOf('--output') + 1], 'o.trace');
  }
});

test('a sim arm targets the device, a host arm does not', () => {
  assert.ok(recordArgs(armById('hitches'), { udid: 'U', out: 'o' }).includes('U'));
  assert.ok(!recordArgs(armById('hitches-host'), { udid: 'U', out: 'o' }).includes('--device'));
});

test('template and instruments are passed as given', () => {
  const h = recordArgs(armById('hitches'), { udid: 'U', out: 'o' });
  assert.equal(h[h.indexOf('--template') + 1], 'Animation Hitches');
  const s = recordArgs(armById('signposts'), { udid: 'U', out: 'o' });
  assert.ok(!s.includes('--template'));
  assert.deepEqual(s.filter((x, i) => s[i - 1] === '--instrument'), ['os_signpost', 'Points of Interest']);
});

test('unknown arm is refused with the known list', () => {
  assert.throws(() => armById('nope'), /known: hitches/);
});

test('sweeps end exactly on the last position and zones cover the first and last screen', () => {
  assert.deepEqual(sweepYs(0, 100, 40), [0, 40, 80, 100]);
  assert.deepEqual(sweepYs(5, 5, 40), [5]);
  const p = zonePlan({ vh: 800, maxY: 5000 }, 400);
  assert.deepEqual([p.A[0], p.A.at(-1)], [0, 799]);
  assert.deepEqual([p.B[0], p.B.at(-1)], [4201, 5000]);
  const short = zonePlan({ vh: 800, maxY: 300 }, 100);
  assert.deepEqual([short.A.at(-1), short.B[0], short.B.at(-1)], [300, 0, 300]);
});
