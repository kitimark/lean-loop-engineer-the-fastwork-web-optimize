// Conformance of the part-page driver decisions: Lean Fw.Site.StageMode goldens (packages/contracts/golden/parts/stage-mode.jsonl)
// through src/stage-mode.mjs, and the wiring in src/run.mjs and the chromium-counts workflow plan.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { accepts, gateSize, planSearch, scrollRead, viewportGate, onlySearch } from '../src/stage-mode.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const rows = readFileSync(join(HERE, '../../contracts/golden/parts/stage-mode.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => rows.filter((r) => r.kind === k);
const size = ([w, h]) => ({ w, h });

test('the golden carries the contract premise and the pinned-y scope', () => {
  const [p] = of('premise');
  assert.equal(p.premise, 'declared-rows-unverified');
  assert.equal(p.yFollowsPlan, false);
  assert.ok(of('plan').length > 40 && of('accept').length > 100 && of('read').length > 100);
});

test('planSearch equals every plan row, and the planned search of a part page parses to the profile environment', () => {
  for (const r of of('plan')) {
    assert.equal(planSearch(r.query, size(r.profile)), r.search, r.query);
    assert.equal(onlySearch(r.query), r.only, r.query);
    if (r.only && r.search !== null && r.parsed.kind === 'ok') assert.deepEqual(r.parsed.env, [0, r.profile[0], r.profile[1]], r.query);
  }
});

test('accepts equals every accept row', () => {
  for (const r of of('accept')) {
    assert.equal(accepts(r.query, size(r.profile), { mode: r.mode, hydrated: r.hydrated, errors: r.errors, stage: r.stage, missing: r.missing }), r.accept, JSON.stringify(r));
  }
});

test('scrollRead and viewportGate equal every read row', () => {
  for (const r of of('read')) {
    assert.equal(scrollRead(r.query), r.scrollRead, r.query);
    const f = { pinned: size(r.pinned), real: size(r.real), client: size(r.client) };
    assert.equal(viewportGate(size(r.profile), f), r.faithful, JSON.stringify(r));
    assert.deepEqual(gateSize(f), size(r.gateSize));
  }
});

test('the 645x1398 overflow frame is refused on a stage page though pinned and client sizes equal the profile', () => {
  const row = of('read').find((r) => r.query.includes('only=hero') && r.pinned.join() === '430,932' && r.client.join() === '430,932' && r.real.join() === '645,1398');
  assert.ok(row);
  assert.equal(row.faithful, false);
  assert.equal(viewportGate({ w: 430, h: 932 }, { pinned: { w: 430, h: 932 }, client: { w: 430, h: 932 }, real: { w: 645, h: 1398 } }), false);
});

test('the CLI prints the planned search and refuses a typed stage', () => {
  const cli = join(HERE, '../src/stage-mode.mjs');
  assert.equal(execFileSync('node', [cli, 'plan', '?only=hero', '430', '932']).toString(), '?only=hero&stage=vw:430,vh:932');
  assert.equal(execFileSync('node', [cli, 'plan', '?fw=a:b', '430', '932']).toString(), '?fw=a:b');
  assert.throws(() => execFileSync('node', [cli, 'plan', '?only=hero&stage=y:1', '430', '932'], { stdio: 'pipe' }));
  assert.throws(() => execFileSync('node', [cli, 'plan', '?only=hero', '0', '932'], { stdio: 'pipe' }));
});

test('every profile viewport is a valid stage size (1..10000)', () => {
  const dir = join(HERE, '../profiles');
  for (const f of readdirSync(dir)) {
    const v = JSON.parse(readFileSync(join(dir, f), 'utf8')).viewport;
    assert.ok(v.width >= 1 && v.width <= 10000 && v.height >= 1 && v.height <= 10000, f);
  }
});

test('run.mjs gates on the real frame size captured before the page pins it, and records pinned, client and gate sizes', () => {
  const src = readFileSync(join(HERE, '../src/run.mjs'), 'utf8');
  assert.ok(src.includes('__fwRealSize'), 'native getter capture');
  for (const k of ['innerWidthPx:', 'innerHeightPx:', 'clientWidthPx:', 'clientHeightPx:', 'gateSize:', 'pinnedInnerWidthPx:']) assert.ok(src.includes(k), k);
  assert.ok(src.includes('real: { w: geo.real?.w ?? -1'), 'the gate reads the real size');
});

test('run.mjs wires the decisions: accepts, scrollRead, viewportGate, no direct mode check left', () => {
  const src = readFileSync(join(HERE, '../src/run.mjs'), 'utf8');
  assert.ok(src.includes("from './stage-mode.mjs'"));
  for (const k of ['accepts(SEARCH', 'scrollRead(SEARCH', 'viewportGate(profileSize']) assert.ok(src.includes(k), k);
  assert.ok(!src.includes("rewrite.mode !== 'hydrate'"), 'the mode check is the Lean decision');
  assert.ok(!src.includes('var __fwStepResult = scrollY'), 'the scroll read is the Lean decision');
});

test('the counts workflow plan takes the search from stage-mode.mjs', () => {
  const y = readFileSync(join(HERE, '../../../.github/workflows/chromium-counts.yml'), 'utf8');
  assert.ok(y.includes('node packages/measure-chromium/src/stage-mode.mjs plan'));
  assert.ok(y.includes('            packages/measure-chromium/src\n'), 'sparse checkout of the plan job');
});

test('the counts workflow plan takes runs 2..10, the Lean request rule (classify needs a directory per artifact, so two or more)', () => {
  const y = readFileSync(join(HERE, '../../../.github/workflows/chromium-counts.yml'), 'utf8');
  assert.ok(y.includes('[ "$RUNS" -lt 2 ] || [ "$RUNS" -gt 10 ]'));
  const lean = readFileSync(join(HERE, '../../../lean/Fw/Store/Layout.lean'), 'utf8');
  assert.ok(lean.includes('"runs: must be 2 to 10"'));
});
