// The node twin of Fw.Ci.Trigger.pushProbe against the Lean golden (`probe` lines of triggers.jsonl).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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
