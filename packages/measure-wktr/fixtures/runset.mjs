// The run-set rule of the WKTR variance note (task wktr-serial-baseline), declared before any count is computed.
// A run of the wktr-fixtures workflow is a baseline run when ALL hold: conclusion success; the fixtures job ran (not skipped by the
// guard) and its wktr-fix-classes artifact has 9 passes in each of the 13 cells; and its lane diff touches no measurement code.
// The lane diff of a run is the files changed from the merge base of its sha with the last first-parent commit of main created
// before the run, to its sha. Measurement code is what runs in the fixture job or reduces and classes its counts (isMeasurement).
// TS stand-in: this path predicate has no Lean spec yet (listed in the handoff).
//   node runset.mjs '<id>|<sha>|<created ISO>' ...      prints the lane diff files that are measurement code, per run
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

/** Measurement code: the WKTR package except its tests, README and the variance analysis; the class and layout Lean modules; the lane workflow. */
export function isMeasurement(p) {
  return (/^packages\/measure-wktr\//.test(p) && !/^packages\/measure-wktr\/(test\/|README\.md|fixtures\/variance\.mjs|fixtures\/runset\.mjs)/.test(p)) ||
    /^lean\/Fw\/Measure\/(Classes|WktrLayout)\.lean$/.test(p) ||
    p === '.github/workflows/wktr-fixtures.yml';
}

/** The measurement files among the files of a lane diff (a run is in the set iff this is empty). */
export const measurementFiles = (files) => files.filter(isMeasurement);

const git = (...a) => execFileSync('git', a, { encoding: 'utf8', maxBuffer: 1 << 26 }).trim();

/** The lane diff files of a run: merge base of sha with the newest first-parent main commit before `at`, to sha. */
export function laneDiff(sha, at, main = 'main') {
  const base = git('merge-base', sha, git('rev-list', '-1', '--first-parent', `--before=${at}`, main));
  return { base, files: git('diff', '--name-only', base, sha).split('\n').filter(Boolean) };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  for (const a of process.argv.slice(2)) {
    const [id, sha, at] = a.split('|');
    const d = laneDiff(sha, at);
    const m = measurementFiles(d.files);
    console.log(`${id} ${sha.slice(0, 7)} base ${d.base.slice(0, 8)} lane files ${d.files.length} measurement ${m.length ? m.join(' ') : '-'} -> ${m.length ? 'out' : 'in'}`);
  }
}
