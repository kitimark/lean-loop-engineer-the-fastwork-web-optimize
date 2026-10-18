// The committed part footprint (packages/contracts/golden/parts/footprint.gen.json) equals a fresh extraction of
// src/parts; lean/scripts/check.sh then checks that Lean's FootprintData prints the same JSON.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

describe('part footprint', () => {
  it('footprint.gen.json is fresh', () => {
    const script = fileURLToPath(new URL('../scripts/part-footprint.mjs', import.meta.url));
    const r = spawnSync(process.execPath, [script, '--check'], { encoding: 'utf8' });
    expect(r.stderr).toBe('');
    expect(r.status).toBe(0);
  });
});
