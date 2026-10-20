// The switch of the images-at-drawn-size arm (src/images/switch.mjs): default arm leaves the base rewrite alone, the drawn arm answers
// the table's image URLs with the copy for the probe's width and DPR and passes everything else to the base.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { drawnFile, loadDrawn } from '../src/images/arm.mjs';
import { armFromEnv, drawnRewrite } from '../src/images/switch.mjs';

const m = loadDrawn();
const [url, entry] = Object.entries(m.images).find(([, e]) => e.dprs['3']?.some((r) => r.file)) ?? [];

test('armFromEnv: unset and default are the default arm, drawn is drawn, a typo throws', () => {
  assert.equal(armFromEnv({}), 'default');
  assert.equal(armFromEnv({ FW_IMAGES_ARM: '' }), 'default');
  assert.equal(armFromEnv({ FW_IMAGES_ARM: 'default' }), 'default');
  assert.equal(armFromEnv({ FW_IMAGES_ARM: 'drawn' }), 'drawn');
  assert.throws(() => armFromEnv({ FW_IMAGES_ARM: 'Drawn' }), /expected drawn or default/);
});

test('drawnRewrite: the default arm is the base itself', () => {
  const base = () => '/x';
  assert.equal(drawnRewrite({ arm: 'default', width: 430, dpr: 3, base }), base);
  assert.equal(drawnRewrite({ arm: 'default', width: 430, dpr: 3 }), null);
  assert.throws(() => drawnRewrite({ arm: 'other', width: 1, dpr: 1 }), /expected drawn or default/);
});

test('drawnRewrite: the drawn arm serves the table copy for (width, dpr) and the base for any other URL', () => {
  assert.ok(url, 'the table has an image with a copy at DPR 3');
  const base = (p, q) => (p === '/index.html' ? `/h${q}.html` : null);
  const rw = drawnRewrite({ arm: 'drawn', width: 430, dpr: 3, base });
  const want = drawnFile(m, url, 430, 3);
  assert.equal(rw(url, ''), want ?? null);
  assert.equal(rw('/index.html', '?a=1'), '/h?a=1.html');
  assert.equal(rw('/not-in-the-table.png', ''), null);
  // the copies are not committed (they are built into the gitignored served dist), so the table is checked against itself: every
  // row names a copy that the table lists with a size and a hash
  for (const r of entry.dprs['3'].filter((x) => x.file)) assert.ok(m.files[r.file]?.sha256, r.file);
});
