// The committed part footprint (packages/contracts/golden/parts/footprint.gen.json) equals a fresh extraction of
// src/parts; lean/scripts/check.sh then checks that Lean's FootprintData prints the same JSON.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

type Access = { part: string; file: string; line: number; op: string; name: string; owner: string; ctx: string };
const golden = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../../packages/contracts/golden/parts/footprint.gen.json', import.meta.url)), 'utf8'),
) as { accesses: Access[] };

describe('part footprint', () => {
  it('footprint.gen.json is fresh', () => {
    const script = fileURLToPath(new URL('../scripts/part-footprint.mjs', import.meta.url));
    const r = spawnSync(process.execPath, [script, '--check'], { encoding: 'utf8' });
    expect(r.stderr).toBe('');
    expect(r.status).toBe(0);
  });

  it.each([
    ['morph.tween/waapi.driver.ts', 'setStyle', '?', 'nav'],
    ['morph.tween/waapi.driver.ts', 'setStyle', '?', 'platform'],
    ['engine.scene/index.tsx', 'setStyle', '?', 'morph.columns'],
    ['commission.typing/driver.ts', 'setContent', 'textContent', 'commission.typing'],
    ['platform/Visuals.tsx', 'setContent', 'textContent', 'platform'],
    ['nav/index.tsx', 'setAttr', 'tabindex', 'nav'],
  ])('%s writes %s %s on %s', (file, op, name, owner) => {
    expect(golden.accesses.some((a) => a.file === file && a.op === op && a.name === name && a.owner === owner)).toBe(true);
  });
});
