// Generates or checks src/scope.gen.json from Lean (Fw.Gate.ScopeGen.scopeText). Glue only: every scope decision and
// its proof is in lean/Fw/Gate/Scope.lean. Lean modules under Fw/ may not define a root `main` (the math view imports
// all of them), so the compiled `fwcore sweepsgen --scope` (lean/SweepsgenMain.lean) runs it; `scopegenInterpreted` is the old
// two-line `lake env lean --run` driver (about 100 s: the interpreter).
//   node scripts/scopegen.mjs            regenerate src/scope.gen.json
//   node scripts/scopegen.mjs --check    exit 1 when src/scope.gen.json differs from the Lean bytes
// Needs a built lean/ (`cd lean && lake build`).
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const LEAN = resolve(PKG, '../../lean');
export const SCOPE_GEN = join(PKG, 'src/scope.gen.json');

/** Run Fw.Gate.ScopeGen.run with `args`; returns { status, stdout, stderr }. `lake build fwcore` first (a no-op when the
 *  binary is current, so a stale binary cannot vouch for new Lean sources), then the compiled `fwcore sweepsgen --scope`. */
export function scopegen(args) {
  const b = spawnSync('lake', ['build', 'fwcore'], { cwd: LEAN, encoding: 'utf8', maxBuffer: 1 << 26 });
  if (b.error) throw b.error;
  if (b.status !== 0) return { status: b.status, stdout: b.stdout, stderr: `lake build fwcore failed:\n${b.stdout}${b.stderr}` };
  const r = spawnSync(join(LEAN, '.lake/build/bin/fwcore'), ['sweepsgen', '--scope', ...args], { cwd: LEAN, encoding: 'utf8', maxBuffer: 1 << 26 });
  if (r.error) throw r.error;
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

/** The interpreted route (`lean --run` over a two-line driver): the same `run`, about 100 s under load. Kept for a tree
 *  where the binary cannot be built; the test never uses it. */
export function scopegenInterpreted(args) {
  const dir = mkdtempSync(join(tmpdir(), 'scopegen-'));
  try {
    const driver = join(dir, 'ScopeGenDriver.lean');
    writeFileSync(driver, 'import Fw.Gate.ScopeGen\ndef main (args : List String) : IO UInt32 := Fw.Gate.ScopeGen.run args\n');
    const r = spawnSync('lake', ['env', 'lean', '--run', driver, ...args], { cwd: LEAN, encoding: 'utf8', maxBuffer: 1 << 26 });
    if (r.error) throw r.error;
    return { status: r.status, stdout: r.stdout, stderr: r.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const r = scopegen(['--check', SCOPE_GEN]);
    process.stderr.write(r.stderr);
    process.exit(r.status ?? 1);
  }
  const r = scopegen([]);
  if (r.status !== 0) { process.stderr.write(r.stderr); process.exit(r.status ?? 1); }
  writeFileSync(SCOPE_GEN, r.stdout);
  console.error(`scopegen: wrote ${SCOPE_GEN}`);
}
