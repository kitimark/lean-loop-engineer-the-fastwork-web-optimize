// Generates or checks packages/contracts/golden/gate/freeze.jsonl from Lean (Fw.Gate.Freeze.goldenText). Glue only: the
// settled predicate, the wait policy and their proofs are in lean/Fw/Gate/Freeze.lean. Lean modules under Fw/ define no
// root `main`, so this writes a two-line driver to a temp dir and runs it with `lake env lean --run`.
//   node scripts/freezegen.mjs            regenerate the golden file
//   node scripts/freezegen.mjs --check    exit 1 when the file differs from the Lean bytes
// Needs a built lean/ (`cd lean && lake build Fw.Gate.Freeze`).
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const LEAN = resolve(PKG, '../../lean');
export const FREEZE_GOLDEN = resolve(PKG, '../contracts/golden/gate/freeze.jsonl');

/** Run Fw.Gate.Freeze.run with `args`; returns { status, stdout, stderr }. */
export function freezegen(args) {
  const dir = mkdtempSync(join(tmpdir(), 'freezegen-'));
  try {
    const driver = join(dir, 'FreezeGenDriver.lean');
    writeFileSync(driver, 'import Fw.Gate.Freeze\ndef main (args : List String) : IO UInt32 := Fw.Gate.Freeze.run args\n');
    const r = spawnSync('lake', ['env', 'lean', '--run', driver, ...args], { cwd: LEAN, encoding: 'utf8', maxBuffer: 1 << 26 });
    if (r.error) throw r.error;
    return { status: r.status, stdout: r.stdout, stderr: r.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const r = freezegen(['--check', FREEZE_GOLDEN]);
    process.stderr.write(r.stderr);
    process.exit(r.status ?? 1);
  }
  const r = freezegen([]);
  if (r.status !== 0) { process.stderr.write(r.stderr); process.exit(r.status ?? 1); }
  writeFileSync(FREEZE_GOLDEN, r.stdout);
  console.error(`freezegen: wrote ${FREEZE_GOLDEN}`);
}
