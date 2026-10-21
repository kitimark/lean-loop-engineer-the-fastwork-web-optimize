// Replays the Lean golden (Fw.Ci.Steps, packages/contracts/golden/ci/steps.jsonl) through the TS stand-ins of
// scripts/ci-steps-lint.mjs, and runs the lint on the real tree.
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkJob, coverage, labelOf, lint, loadGolden, readSteps } from './ci-steps-lint.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const g = loadGolden(root);
const of = (kind) => g.all.filter((l) => l.kind === kind);

test('golden label lines', () => {
  assert.ok(of('label').length >= 5);
  for (const l of of('label')) assert.equal(labelOf(l.stepName, l.uses), l.label, l.name);
});

test('golden case lines (checkJob)', () => {
  assert.ok(of('case').length >= 10);
  for (const c of of('case')) {
    const row = g.rows.find((r) => r.file === c.file && r.job === c.job);
    assert.deepEqual(checkJob(row, c.steps), c.problems, c.name);
  }
});

test('golden coverage lines', () => {
  assert.ok(of('coverage').length >= 5);
  for (const c of of('coverage')) assert.deepEqual(coverage(g.rows, c.file, c.found), c.problems, c.name);
});

test('every row ends with the upload, then the telemetry or nothing', () => {
  for (const r of g.rows) {
    const kinds = r.post.map((p) => p.kind);
    assert.ok(kinds.includes('upload'), `${r.file}/${r.job}`);
    assert.ok(kinds.indexOf('upload') >= kinds.indexOf('collect'), `${r.file}/${r.job}`);
  }
});

test('the real tree equals the allowlist', () => {
  const r = lint(root);
  assert.deepEqual(r.problems, []);
  assert.deepEqual(r.flagged, g.flagged);
  assert.deepEqual(r.flagged, g.rows.filter((x) => x.teardown).map((x) => `${x.file}/${x.job}`));
});

test('readSteps reads label, if and timeout', () => {
  const lines = [
    'jobs:', '  j:', '    runs-on: macos-26', '    steps:',
    '      - name: A step', '        if: ${{ always() }}   # note', '        timeout-minutes: 3',
    '        run: |', '          echo hi', '',
    '      # comment', '      - uses: actions/upload-artifact@abc # v7', '        with:', '          name: x', '',
  ];
  const s = readSteps(lines, { name: 'j', at: 1, end: lines.length });
  assert.deepEqual(s, [
    { label: 'A step', ifText: '${{ always() }}', timeout: '3' },
    { label: 'actions/upload-artifact', ifText: null, timeout: null },
  ]);
});
