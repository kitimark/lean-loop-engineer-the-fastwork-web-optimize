// Phase 0 of the runner fixes the property lists as the union of several scans, so a timer-driven part gives every shard the
// same list (merge-gate compares headers byte for byte; WebKit run 39057342983 failed on hero.accent).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { SCAN_EXTRA, SCAN_GAP_MS, unionDeclared } from '../src/declared.mjs';

const scan = (declared, count = 1) => ({ 'hero.accent': { accent: { count, declared, items: [] } }, hero: { h1: { count: 1, declared: ['color'], items: [] } } });

test('the union does not depend on which instant a scan fell on', () => {
  const idle = scan(['color', 'opacity']);
  const moving = scan(['color', 'opacity', 'transition-delay', 'transition-duration']);
  const a = unionDeclared([idle, moving, idle]);
  const b = unionDeclared([moving, idle, idle]);
  const c = unionDeclared([idle, idle, moving]);
  assert.deepEqual(a, b);
  assert.deepEqual(a, c);
  assert.deepEqual(a['hero.accent'].accent.declared, ['color', 'opacity', 'transition-delay', 'transition-duration']);
  assert.deepEqual(a.hero.h1.declared, ['color']);
});

test('the union is sorted, deduplicated and keeps the largest count; inputs are not changed', () => {
  const x = scan(['b', 'a'], 1);
  const y = scan(['c', 'a'], 3);
  const u = unionDeclared([x, y]);
  assert.deepEqual(u['hero.accent'].accent.declared, ['a', 'b', 'c']);
  assert.equal(u['hero.accent'].accent.count, 3);
  assert.deepEqual(x['hero.accent'].accent.declared, ['b', 'a']);
  assert.throws(() => unionDeclared([]));
});

test('the scans cover the longest timer period (3050 ms of the hero.accent chain) and the runner uses them', () => {
  assert.ok((SCAN_EXTRA * SCAN_GAP_MS) >= 3050);
  assert.ok(SCAN_GAP_MS * 2 <= 900, 'the shortest state (900 ms) is sampled at least twice');
  const run = readFileSync(join(import.meta.dirname, '..', 'src', 'run.mjs'), 'utf8');
  assert.match(run, /declared\[site\] = unionDeclared\(scans\)/);
});
