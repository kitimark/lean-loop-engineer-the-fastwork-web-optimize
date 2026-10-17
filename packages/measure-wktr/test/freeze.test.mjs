import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fwcoreBin, call } from '../../measure-chromium/src/fwcore.mjs';
import { freezeRuns } from '../src/freeze.mjs';

let haveCore = true;
try { fwcoreBin(); } catch { haveCore = false; }
const skip = haveCore ? false : 'fwcore binary not built (set FW_CORE_BIN or lake build fwcore)';

const meta = (pass) => ({ lane: 'wktr', pass, variant: 'live', vt: false, trace: false, warm: false, step: 50, frames: 2, settleMs: 6000, header: 'h',
  archive: { revision: 'r', commit: 'c', sha256: 'aa' }, device: { name: 'iPhone 17', runtime: '26.5', runtimeBuild: 'B1' },
  page: { innerWidth: 402, innerHeight: 820, dpr: 2, docH: 100, maxY: 80 } });
// type "steady" is identical in every pass; type "noisy" differs by 1 in one frame; type "wild" differs in many frames
const counts = (pass, wildShift) => ({ schema: 'fw.wktr.scroll/1', meta: meta(pass), frames: Array.from({ length: 12 }, (_, n) => ({
  n, phase: 'scroll', scrollY: n * 50, counts: { steady: 2, noisy: 3 + (n === 4 && pass === 2 ? 1 : 0), wild: 5 + ((n + wildShift) % 7) } })) });

function makeRun(root, id, wildShift) {
  const dir = join(root, id);
  const files = [];
  for (const job of ['wktr-j1', 'wktr-j2']) {
    mkdirSync(join(dir, job), { recursive: true });
    for (const pass of [1, 2]) { const c = counts(pass, wildShift + (job === 'wktr-j2' ? 1 : 0) + pass); files.push(c); writeFileSync(join(dir, job, `counts-live-${pass}.json`), JSON.stringify(c)); }
  }
  mkdirSync(join(dir, 'wktr-classes'), { recursive: true });
  writeFileSync(join(dir, 'wktr-classes', 'run.txt'), `workflow run ${id}, attempt 1, sha abc123, variants live\n`);
  writeFileSync(join(dir, 'wktr-classes', 'runners.jsonl'), JSON.stringify({ imageVersion: 'v1' }) + '\n' + JSON.stringify({ imageVersion: 'v1' }) + '\n');
  const [r] = call([{ op: 'measure.classify', mode: 'frames', kMax: 4, tMax: 24, runs: files.map((c) => ({ frames: c.frames })) }]);
  writeFileSync(join(dir, 'wktr-classes', 'classes-live-all.json'), JSON.stringify(r.classes));
  return dir;
}

test('freezeRuns: worst class over three workflow runs, from fwcore', { skip }, () => {
  const root = mkdtempSync(join(tmpdir(), 'fw-wktr-freeze-'));
  try {
    const dirs = [makeRun(root, '101', 0), makeRun(root, '102', 3), makeRun(root, '103', 5)];
    const f = freezeRuns(dirs);
    assert.equal(f.schema, 'fw.wktr.classes.frozen/1');
    const p = f.profiles.live;
    assert.deepEqual(p.workflowRuns, ['101', '102', '103']);
    assert.equal(p.types.steady.class, 'deterministic');
    assert.equal(p.types.noisy.class, 'stable');
    assert.equal(p.types.wild.class, 'quarantined');
    assert.deepEqual(p.countsFilesPerRun, [4, 4, 4]);
    assert.equal(p.image, 'aa/B1');
    assert.throws(() => freezeRuns(dirs.slice(0, 2)), /3|least/i);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
