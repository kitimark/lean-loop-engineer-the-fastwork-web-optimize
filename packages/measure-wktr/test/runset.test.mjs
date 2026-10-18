// The run-set rule (fixtures/runset.mjs): which lane-diff files count as measurement code.
import test from 'node:test';
import assert from 'node:assert/strict';
import { isMeasurement, measurementFiles } from '../fixtures/runset.mjs';

test('measurement code is the lane package, the class and layout modules and the workflow', () => {
  for (const p of ['packages/measure-wktr/src/cli.mjs', 'packages/measure-wktr/fixtures/control/index.html', 'packages/measure-wktr/fixtures/summarize.mjs',
    'lean/Fw/Measure/Classes.lean', 'lean/Fw/Measure/WktrLayout.lean', '.github/workflows/wktr-fixtures.yml']) assert.ok(isMeasurement(p), p);
});

test('tests, notes, other lanes and the variance analysis are not measurement code', () => {
  for (const p of ['packages/measure-wktr/test/variance.test.mjs', 'packages/measure-wktr/fixtures/variance.mjs', 'packages/measure-wktr/README.md',
    'packages/measure-webkit/src/sim.mjs', 'lean/Fw/Measure/Retry.lean', 'research/notes/2026/10-18-x.md', '.github/workflows/webkit-sim.yml']) assert.ok(!isMeasurement(p), p);
  assert.deepEqual(measurementFiles(['docs/a.md', 'packages/measure-wktr/src/wktr.mjs']), ['packages/measure-wktr/src/wktr.mjs']);
});
