// Generates or checks packages/contracts/golden/gate/settle.jsonl from Lean (Fw.Gate.Settle.goldenText). Glue only: the
// settled predicate, the wait policy and their proofs are in lean/Fw/Gate/Settle.lean. Lean modules under Fw/ define no
// root `main`, so this writes a two-line driver to a temp dir and runs it with `lake env lean --run`.
//   node scripts/settlegen.mjs            regenerate the golden file
//   node scripts/settlegen.mjs --check    exit 1 when the file differs from the Lean bytes
// Needs a built lean/ (`cd lean && lake build Fw.Gate.Settle`).
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const LEAN = resolve(PKG, '../../lean');
export const SETTLE_GOLDEN = resolve(PKG, '../contracts/golden/gate/settle.jsonl');

/** Run Fw.Gate.Settle.run with `args`; returns { status, stdout, stderr }. */
export function settlegen(args) {
  const dir = mkdtempSync(join(tmpdir(), 'settlegen-'));
  try {
    const driver = join(dir, 'SettleGenDriver.lean');
    writeFileSync(driver, 'import Fw.Gate.Settle\ndef main (args : List String) : IO UInt32 := Fw.Gate.Settle.run args\n');
    const r = spawnSync('lake', ['env', 'lean', '--run', driver, ...args], { cwd: LEAN, encoding: 'utf8', maxBuffer: 1 << 26 });
    if (r.error) throw r.error;
    return { status: r.status, stdout: r.stdout, stderr: r.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const r = settlegen(['--check', SETTLE_GOLDEN]);
    process.stderr.write(r.stderr);
    process.exit(r.status ?? 1);
  }
  const r = settlegen([]);
  if (r.status !== 0) { process.stderr.write(r.stderr); process.exit(r.status ?? 1); }
  writeFileSync(SETTLE_GOLDEN, r.stdout);
  console.error(`settlegen: wrote ${SETTLE_GOLDEN}`);
}
