import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { allowed, changed } from '../src/earn-frames-compare.mjs';
import { TS, pageHtml } from '../src/earn-frames.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const row = readFileSync(join(here, '../../contracts/golden/parts/nav.earn.webkit.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((g) => g.fn === 'frameBound').out;
const img = (w, h, fill) => ({ width: w, height: h, data: new Uint8ClampedArray(w * h * 4).fill(fill) });

test('allowed counts equal the Lean golden', () => {
  assert.equal(allowed(1280), row.allowed1280);
  assert.equal(allowed(390), row.allowed390);
});

test('changed counts pixels above the Lean threshold only', () => {
  const a = img(2, 2, 0);
  const b = img(2, 2, 0);
  b.data[0] = row.threshold;
  b.data[4] = row.threshold + 1;
  assert.deepEqual(changed(a, b, row.threshold), { count: 1, max: row.threshold + 1 });
  assert.equal(changed(a, img(3, 2, 0)).count, Infinity);
});

test('the page holds the real nav css with the variant class only on the logical arm', () => {
  assert.match(pageHtml('logical', 'x.woff2'), /class="nav is-hero-pill is-hero-chrome-ready is-earn-logical"/);
  assert.doesNotMatch(pageHtml('faithful', 'x.woff2'), /is-earn-logical"/);
  assert.match(pageHtml('faithful', 'x.woff2'), /padding-inline-start 0\.68s/);
  assert.ok(!pageHtml('faithful', 'x.woff2').includes(':global('));
  assert.equal(TS[0], 0);
});
