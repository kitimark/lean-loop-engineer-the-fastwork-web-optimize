// Every source file parses. summary.mjs is only run by CI's merge job, so a syntax error there (an unescaped backtick
// inside a template literal, 5f76d6e) broke breakpoint-gate on main without failing any unit test.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

const src = join(import.meta.dirname, '..', 'src');

test('every src/*.mjs passes node --check', () => {
  for (const f of readdirSync(src).filter((n) => n.endsWith('.mjs'))) {
    const r = spawnSync(process.execPath, ['--check', join(src, f)], { encoding: 'utf8' });
    assert.equal(r.status, 0, `${f}: ${r.stderr}`);
  }
});
