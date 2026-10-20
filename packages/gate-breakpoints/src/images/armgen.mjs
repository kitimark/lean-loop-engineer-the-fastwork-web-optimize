// Generates or checks packages/contracts/golden/measure/image-arm.jsonl from Lean (Fw.Measure.ImageArm.goldenText, driver
// lean/scripts/ImageArmGolden.lean). Glue only: the snapping rule, the reach of a 1:1 copy, the part decision and the decoded saving
// are in lean/Fw/Measure/ImageArm.lean.
//   node src/images/armgen.mjs            regenerate the golden file
//   node src/images/armgen.mjs --check    exit 1 when the file differs from the Lean bytes
// Needs a built lean/ (`cd lean && lake build Fw.Measure.ImageArm`).
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const LEAN = resolve(HERE, '../../../../lean');
export const ARM_GOLDEN = resolve(HERE, '../../../contracts/golden/measure/image-arm.jsonl');

/** Run the Lean driver with `args`; returns { status, stdout, stderr }. */
export function armgen(args) {
  const r = spawnSync('lake', ['env', 'lean', '--run', 'scripts/ImageArmGolden.lean', ...args], { cwd: LEAN, encoding: 'utf8', maxBuffer: 1 << 26 });
  if (r.error) throw r.error;
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const r = armgen(['--check', ARM_GOLDEN]);
    process.stderr.write(r.stderr);
    process.exit(r.status ?? 1);
  }
  const r = armgen([]);
  if (r.status !== 0) { process.stderr.write(r.stderr); process.exit(r.status ?? 1); }
  writeFileSync(ARM_GOLDEN, r.stdout);
  console.error(`armgen: wrote ${ARM_GOLDEN}`);
}
