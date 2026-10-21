// Replays the Lean-written golden (packages/contracts/golden/sched/heavy.jsonl) against heavy-lock.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { DEFAULT_PARAMS, decide, prune } from './heavy-lock.mjs';

const golden = readFileSync(new URL('../packages/contracts/golden/sched/heavy.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((l) => JSON.parse(l));

for (const c of golden) {
  test(c.name, () => {
    if (c.request.op === 'sched.heavy') {
      const r = c.request;
      assert.deepEqual(decide(r.params, r.obs, r.running, r.rank), c.response);
    } else {
      const r = c.request;
      assert.deepEqual({ holders: prune(r.live, r.holders) }, c.response);
    }
  });
}

test('default params equal the Lean defaults used by the golden', () => {
  const first = golden.find((c) => c.request.op === 'sched.heavy' && c.name === 'idle machine admits');
  assert.deepEqual(first.request.params, DEFAULT_PARAMS);
});
