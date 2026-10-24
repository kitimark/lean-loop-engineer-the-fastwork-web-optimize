import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { joinedLines, run } from './lint-check-sh.mjs';

const ok = `job "a" cmd  # note job "x"\n  job "b" cmd\nserial "c" cmd\n`;
const joined = `  job "sup-measure golden check" sh -c "x"  job "node-budget golden check" lake env lean --check\n`;

test('one call per line, and a call named inside a comment, are clean', () => {
  assert.deepEqual(joinedLines(ok), []);
  assert.deepEqual(joinedLines('# job "a" then job "b"\n'), []);
});

test('two calls on one line are flagged with the line number', () => {
  assert.deepEqual(joinedLines(`job "a" x\n${joined}`), [2]);
  assert.deepEqual(joinedLines('serial "a" x; job "b" y\n'), [1]);
});

test('the check.sh of this checkout has no joined line', () => {
  assert.equal(run(), 0);
});

test('run exits 1 on a file with a joined line', () => {
  const d = mkdtempSync(join(tmpdir(), 'fw-lint-check-sh-'));
  try {
    const f = join(d, 'check.sh');
    writeFileSync(f, joined);
    assert.equal(run(f), 1);
  } finally { rmSync(d, { recursive: true, force: true }); }
});
