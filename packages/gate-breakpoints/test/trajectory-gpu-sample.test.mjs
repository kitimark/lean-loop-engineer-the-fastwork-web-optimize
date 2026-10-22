import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { carouselSample } from '../src/trajectory/cells-gpu-page.mjs';
import { ratOf } from '../src/trajectory/cells-gpu.mjs';

const golden = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/trajectory-gpu.jsonl', import.meta.url)), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => golden.filter((l) => l.kind === k);
const num = (s) => Number(ratOf(s).n) / Number(ratOf(s).d);

// Frame j of the scripted page fires at times[j] and the container then reads reads[j] (milli-px width); frames past the script tick on at 17 ms and keep moving.
async function drive({ reads, times, args }) {
  let j = -1, now = times[0];
  const at = (a) => (j < a.length ? a[Math.max(j, 0)] : 1e6 + j);
  const rect = (w) => ({ x: 0, y: 0, width: w / 1000, height: 0 });
  const cont = { getBoundingClientRect: () => rect(0), get children() { return [{ getBoundingClientRect: () => rect(at(reads)) }]; } };
  const scene = { scrollIntoView() {} };
  Object.assign(globalThis, {
    document: { querySelector: (s) => (s === 'scene' ? scene : cont) },
    performance: { now: () => now },
    requestAnimationFrame: (cb) => { j++; now = j < times.length ? times[j] : times.at(-1) + 17 * (j - times.length + 1); queueMicrotask(cb); },
  });
  try {
    return await carouselSample({ scene: 'scene', cont: 'cont', withMeta: true, ...args });
  } finally {
    delete globalThis.document; delete globalThis.performance; delete globalThis.requestAnimationFrame;
  }
}

test('carouselSample settles after 6 equal frames once moved or at the cap, as the Lean settle golden', async () => {
  const cases = of('settle');
  assert.equal(cases.length, 7);
  for (const l of cases) {
    const reads = [l.prev[0], l.prev[0], ...l.frames.map((f) => f.v[0])];
    const times = [-17, 0, ...l.frames.map((f) => num(f.t))];
    const r = await drive({ reads, times, args: { ms: 0, still: l.still, settleMs: num(l.cap) } });
    const ran = l.consumed === l.frames.length && !l.quiet;
    if (ran) assert.ok(r.consumed >= l.consumed, l.name);
    else assert.equal(r.consumed, l.consumed, l.name);
    assert.equal(r.settleQuiet, l.quiet, l.name);
  }
});

test('carouselSample stops recording after 6 equal frames past the window or at the cap, as the Lean tail golden', async () => {
  const cases = of('tail');
  assert.equal(cases.length, 4);
  for (const l of cases) {
    const reads = [0, 0, ...l.frames.map((f) => f.v[0])];
    const times = [900, 1000, ...l.frames.map((f) => 1000 + num(f.t))];
    const r = await drive({ reads, times, args: { ms: num(l.ms), still: l.still, settleMs: 0, tailMs: num(l.cap) } });
    assert.equal(r.rows.length, l.rows, l.name);
    assert.equal(r.tailQuiet, l.quiet, l.name);
  }
});

test('without withMeta the sampler returns the rows array, so the raw shape is unchanged', async () => {
  let now = 0;
  const rect = { x: 0, y: 0, width: 1, height: 1 };
  const el = { getBoundingClientRect: () => rect, children: [{ getBoundingClientRect: () => rect }], scrollIntoView() {} };
  Object.assign(globalThis, {
    document: { querySelector: () => el },
    performance: { now: () => now },
    requestAnimationFrame: (cb) => { now += 17; queueMicrotask(cb); },
  });
  try {
    const rows = await carouselSample({ scene: 's', cont: 'c', ms: 0, settleMs: 0, tailMs: 1500, still: 2 });
    assert.ok(Array.isArray(rows));
    assert.equal(rows.length, 3);
    assert.deepEqual(rows[0], { t: 17, v: [0, 0, 1000, 1000] });
  } finally {
    delete globalThis.document; delete globalThis.performance; delete globalThis.requestAnimationFrame;
  }
});
