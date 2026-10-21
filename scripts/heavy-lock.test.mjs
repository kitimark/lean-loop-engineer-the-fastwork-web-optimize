// Replays the Lean-written golden (packages/contracts/golden/sched/heavy.jsonl) against heavy-lock.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DEFAULT_PARAMS, decide, prune } from './heavy-lock.mjs';

const golden = readFileSync(new URL('../packages/contracts/golden/sched/heavy.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((l) => JSON.parse(l));

for (const c of golden) {
  test(c.name, () => {
    if (c.request.op === 'sched.heavy') {
      const r = c.request;
      assert.deepEqual(decide(r.params, r.obs, r.running, r.rank, r.waitedS), c.response);
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

// ---- the shell around the verdict (I/O glue, run for real in a scratch repo) ----

const script = new URL('./heavy-lock.mjs', import.meta.url).pathname;
const startOf = (pid) => Math.floor(Date.parse(execFileSync('ps', ['-o', 'lstart=', '-p', String(pid)], { encoding: 'utf8' }).trim()) / 1000);

function scratch() {
  const d = mkdtempSync(path.join(tmpdir(), 'fwheavy-'));
  execFileSync('git', ['init', '-q'], { cwd: d });
  return d;
}
const run = (d, args, env = {}) =>
  spawnSync('node', [script, 'run', '--', ...args], { cwd: d, encoding: 'utf8', env: { ...process.env, FW_HEAVY_HELD: '', ...env } });

test('an idle machine runs the job and leaves no holder or ticket behind', () => {
  const d = scratch();
  try {
    const r = run(d, ['sh', '-c', 'exit 3']);
    assert.equal(r.status, 3);
    const root = path.join(d, '.git/fw-heavy');
    assert.deepEqual(readdirSync(path.join(root, 'holders')), []);
    assert.deepEqual(readdirSync(path.join(root, 'queue')), []);
  } finally { rmSync(d, { recursive: true, force: true }); }
});

test('after the wait limit the job is refused with exit 75 and the reason, not run anyway (Lean verdict_timeout_never_admits)', () => {
  const d = scratch();
  try {
    const hd = path.join(d, '.git/fw-heavy/holders');
    mkdirSync(hd, { recursive: true });
    for (const pid of [process.pid, process.ppid]) writeFileSync(path.join(hd, `${pid}.json`), JSON.stringify({ pid, start: startOf(pid), kind: 'test' }));
    const marker = path.join(d, 'ran');
    const r = run(d, ['sh', '-c', `touch ${marker}`], { FW_HEAVY_MAX_WAIT_S: '0', FW_HEAVY_CAP: '2' });
    assert.equal(r.status, 75);
    assert.match(r.stderr, /heavy-lock: waited \d+ s \(limit 0 s\), .* not running the job/);
    assert.equal(existsSync(marker), false);
    assert.deepEqual(readdirSync(path.join(d, '.git/fw-heavy/queue')), []);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
