// The node twin of Fw.Ci.Trigger.pushProbe against the Lean golden (`probe` lines of triggers.jsonl).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { pushProbe } from './trajectory-line.mjs';

const lines = readFileSync(new URL('../../packages/contracts/golden/ci/triggers.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'probe');

test('the golden has probe cases of every decision', () => {
  assert.ok(lines.length >= 50);
  for (const k of ['run', 'notAsked', 'needsLane', 'refused']) assert.ok(lines.some((l) => l.result.kind === k), k);
});

test('pushProbe equals Lean on every golden line', () => {
  for (const l of lines) assert.deepEqual(pushProbe(l.lane, l.msg), l.result, `${JSON.stringify(l.msg)} lane=${l.lane}`);
});

test('the workflow carries the debug key from the commit line to the probe steps and to the mac leg, and no repo file requests a recorder', () => {
  const wf = readFileSync(new URL('../workflows/trajectory-probe.yml', import.meta.url), 'utf8');
  assert.match(wf, /debug: \$\{\{ steps\.p\.outputs\.debug \}\}/);
  assert.equal((wf.match(/FW_DEBUG: \$\{\{ needs\.site\.outputs\.debug \}\}/g) ?? []).length, 2); // probe and probe-apple
  assert.match(wf, /if: \$\{\{ \(github\.event_name == 'workflow_dispatch' \|\| needs\.site\.outputs\.debug != ''\) && needs\.site\.outputs\.apple_n != '0' \}\}/);
  assert.equal(existsSync(new URL('../../packages/gate-breakpoints/src/trajectory/debug.requests.json', import.meta.url)), false);
});

test('the line of the phase 1 run asks for the nav recorder and nothing else changes', () => {
  const r = pushProbe(true, '[ci:trajectory-probe]\n[trajectory fw=morph.tween:waapi widths=1280 engines=playwright-webkit debug=nav-transition]');
  assert.deepEqual(r, { kind: 'run', engines: 'playwright-webkit', fw: 'morph.tween:waapi', preset: '', widths: '1280', debug: 'nav-transition' });
  assert.equal(pushProbe(true, '[trajectory debug=other]').kind, 'refused');
  assert.equal(pushProbe(true, '[ci:trajectory-probe]').debug, '');
});
