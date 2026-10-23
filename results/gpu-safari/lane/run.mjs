// The lane command:
//   node results/gpu-safari/lane/run.mjs sim <nav|morph|pain|all> [--out <dir>] [--shots <dir>]   capture in the Simulator, then reduce
//   node results/gpu-safari/lane/run.mjs mac <nav|morph|pain|all> [--out <dir>] [--shots <dir>]   the same on macOS Safari (needs a visible, unlocked display; inside a `measure` slot)
//   node results/gpu-safari/lane/run.mjs reduce <shots dir of one zone> <zone> [--out <dir>]      reduce an earlier capture again
// `sim` needs a `sim` slot held by the caller (pnpm -s fw slot acquire --kind sim). A local run is paired evidence, never a result alone.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { captureZone } from './sim-capture.mjs';
import { captureZoneMac } from './mac-capture.mjs';
import { reduceArm, armsOfZone } from './reduce.mjs';
import { CI_PAIRS } from './ci-pairs.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..', '..');
const arg = (n, d) => { const i = process.argv.indexOf(n); return i > 0 ? process.argv[i + 1] : d; };
const [, , mode, which = 'all', zoneArg] = process.argv;
if (mode !== 'sim' && mode !== 'mac' && mode !== 'reduce') { console.error('usage: run.mjs sim|mac <nav|morph|pain|all> | run.mjs reduce <shots dir> <zone>'); process.exit(2); }
const out = resolve(arg('--out', join(ROOT, 'results', 'gpu-safari')));
const shotsRoot = resolve(arg('--shots', join(process.env.TMPDIR || '/tmp', 'fw-gpu-safari-shots')));
const siteDir = join(ROOT, 'apps', 'site', 'dist', 'aot');
mkdirSync(out, { recursive: true });

function emit({ cap, zone, shotsDir, run, lane = 'ios-simulator-on-mac' }) {
  for (const arm of armsOfZone(zone)) {
    const r = reduceArm({ cap, arm, shotsDir, run });
    const file = join(out, lane === 'macos-safari' ? `mac-${arm.id}.json` : `${arm.id}.json`);
    writeFileSync(file, JSON.stringify({
      schema: 'fw.gpu-safari/1', lane, run, zone, session: cap.session, flip: cap.flip,
      ci: CI_PAIRS[arm.id] ?? null, ...r,
    }, null, 1) + '\n');
    console.error(`wrote ${file}: ${r.states.map((s) => `${s.id}=${JSON.stringify(s.grade)}`).join(' ')}`);
  }
}

if (mode === 'reduce') {
  const shotsDir = resolve(which);
  const run = basename(dirname(shotsDir));
  emit({ cap: JSON.parse(readFileSync(join(shotsDir, 'capture.json'), 'utf8')), zone: zoneArg, shotsDir, run });
} else {
  const run = `gpu-safari-${mode}-${new Date().toISOString().replace(/[:.]/g, '-')}`;
  for (const zone of which === 'all' ? ['nav', 'morph', 'pain'] : [which]) {
    const shotsDir = join(shotsRoot, run, zone);
    let cap;
    try {
      cap = await (mode === 'sim' ? captureZone : captureZoneMac)({ zone, siteDir, shotsDir });
    } catch (e) {
      if (mode !== 'mac') throw e;
      // an arm the harness cannot drive is reported with its reason, not faked
      const file = join(out, 'mac-safari-refusal.json');
      writeFileSync(file, JSON.stringify({ schema: 'fw.gpu-safari-refusal/1', lane: 'macos-safari', run, zone, reason: e.message }, null, 1) + '\n');
      console.error(`macOS Safari lane refused: ${e.message}\nwrote ${file}`);
      process.exit(3);
    }
    writeFileSync(join(shotsDir, 'capture.json'), JSON.stringify(cap));
    emit({ cap, zone, shotsDir, run, lane: mode === 'sim' ? 'ios-simulator-on-mac' : 'macos-safari' });
  }
}
process.exit(0);
