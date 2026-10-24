import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseCost, COST_MODES } from '../src/lag/costmode.mjs';

const cli = join(dirname(fileURLToPath(import.meta.url)), '../src/lag/cli.mjs');

test('the three modes map to the probe options', () => {
  assert.deepEqual(COST_MODES, ['off', 'on', 'only']);
  assert.deepEqual(parseCost('off'), { cost: false, costOnly: false });
  assert.deepEqual(parseCost('on'), { cost: true, costOnly: false });
  assert.deepEqual(parseCost('only'), { cost: true, costOnly: true });
});

test('anything else throws', () => {
  for (const bad of ['', 'ON', 'true', 'yes', 'no', 'both', 'off,on', undefined, null]) assert.throws(() => parseCost(bad), /--cost must be one of off\|on\|only/, String(bad));
});

test('the CLI refuses a bad value before it opens a session', () => {
  const r = spawnSync(process.execPath, [cli, 'run', '--cost', 'bogus'], { encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /--cost must be one of off\|on\|only, got "bogus"/);
});

test('the workflow offers the same three modes, quoted (YAML 1.1 reads bare off and on as booleans)', () => {
  const yml = readFileSync(join(dirname(cli), '../../../../.github/workflows/webkit-sim.yml'), 'utf8');
  assert.match(yml, /\n {6}cost:\n(?: {8}.*\n)*? {8}options: \['off', 'on', only\]\n {8}default: 'off'\n/);
  assert.match(yml, /lag\/cli\.mjs run --passes "\$PASSES" --cost "\$COST" /);
  assert.match(yml, /PASSES: \$\{\{ \(contains\(github\.event\.head_commit\.message, '\[swap-freeze\]'\) \|\| contains\(github\.event\.head_commit\.message, '\[swap-accent\]'\)\) && '1' \|\| '2' \}\}/);
  assert.match(yml, /ACCENT: \$\{\{ contains\(github\.event\.head_commit\.message, '\[swap-accent\]'\) && '--accent' \|\| '' \}\}/);
  assert.match(yml, /\$SWAP \$ACCENT \$FREEZE --keep/);
  assert.match(yml, /'\[swap-accent\]'\) && 'hero\.accent:draw-nolayout' \|\|/);
});
