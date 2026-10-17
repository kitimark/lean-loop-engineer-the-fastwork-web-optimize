// Build gate: src/breakpoints.gen.json must equal, byte for byte, what `lake exe breakgen` prints.
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lean = path.resolve(root, '../../lean');
const file = path.join(root, 'src/breakpoints.gen.json');
const r = spawnSync('lake', ['exe', 'breakgen', '--check', file], { cwd: lean, stdio: 'inherit' });
if (r.error && r.error.code === 'ENOENT') {
  console.error('breakpoints check: `lake` not found. Install Lean (brew install elan-init), build lean/, then run `pnpm gen:breakpoints`.');
  process.exit(1);
}
if (r.status !== 0) {
  console.error('breakpoints check FAILED: src/breakpoints.gen.json differs from `lake exe breakgen`. Run `pnpm --filter @fw/site gen:breakpoints` (build lean first) and commit the result.');
  process.exit(1);
}
