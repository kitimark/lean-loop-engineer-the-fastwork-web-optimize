import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isLocalRelative, mainCheckout, rawResolveIn } from '../src/device-raw-dir.mjs';

const src = join(dirname(fileURLToPath(import.meta.url)), '..', 'src');
const git = (cwd, ...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...a], { cwd, encoding: 'utf8' });

// inc-raw-in-worktree: a worktree is removed after its land, with every ignored file in it, so raw lanes go to the main checkout.
test('a relative .local path resolves against the main checkout, any other path against the cwd', () => {
  assert.equal(rawResolveIn('/m', '.local/phone/r1'), '/m/.local/phone/r1');
  assert.equal(rawResolveIn('/m', './.local/phone'), '/m/.local/phone');
  assert.equal(rawResolveIn('/m', '.local'), '/m/.local');
  assert.equal(rawResolveIn('/m', '.local/phone', 'summary.json'), '/m/.local/phone/summary.json');
  assert.equal(rawResolveIn('/m', '/abs/.local/x'), '/abs/.local/x');
  assert.equal(rawResolveIn('/m', 'research/out'), join(process.cwd(), 'research/out'));
  assert.equal(rawResolveIn('/m', '.localx/y'), join(process.cwd(), '.localx/y'));
  assert.equal(rawResolveIn('/m', 'a/.local/y'), join(process.cwd(), 'a/.local/y'));
  assert.ok(isLocalRelative('.local/x') && !isLocalRelative('/m/.local/x') && !isLocalRelative(undefined));
});

test('device CLIs route every path through the raw-dir resolver', () => {
  for (const f of ['device-cli.mjs', 'device-push-cli.mjs', 'device-replay-cli.mjs']) {
    const s = readFileSync(join(src, f), 'utf8');
    assert.match(s, /import \{ rawResolve as resolve \} from '\.\/device-raw-dir\.mjs';/, f);
    assert.doesNotMatch(s, /import \{[^}]*\bresolve\b[^}]*\} from 'node:path'/, f);
  }
});

test('from a worktree, mainCheckout is the main checkout and the push CLI reads .local there', () => {
  const t = realpathSync(mkdtempSync(join(tmpdir(), 'rawdir')));
  try {
    const main = join(t, 'main'), wt = join(t, 'wt');
    mkdirSync(main);
    git(main, 'init', '-q', '-b', 'main');
    git(main, 'commit', '-q', '--allow-empty', '-m', 'i');
    git(main, 'worktree', 'add', '-q', '-b', 'wtb', wt);
    assert.equal(mainCheckout(main), main);
    assert.equal(mainCheckout(wt), main);
    assert.equal(mainCheckout(t), t);
    mkdirSync(join(main, '.local', 'phone', 'r1'), { recursive: true });
    writeFileSync(join(main, '.local', 'phone', 'r1', 'state.json'),
      JSON.stringify({ visits: [{ index: 1, arm: 'a', status: 'lost', attempts: 2, faults: [] }] }));
    execFileSync('node', [join(src, 'device-push-cli.mjs'), 'reduce', '--dir', '.local/phone/r1', '--out', 'out'], { cwd: wt, encoding: 'utf8' });
    const summary = JSON.parse(readFileSync(join(wt, 'out', 'summary.json'), 'utf8'));
    assert.deepEqual(summary.notRun.map((v) => v.index), [1]);
    assert.throws(() => readFileSync(join(wt, '.local', 'phone', 'r1', 'state.json')));
  } finally { rmSync(t, { recursive: true, force: true }); }
});
