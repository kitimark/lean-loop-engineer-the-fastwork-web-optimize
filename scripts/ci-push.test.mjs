// node --test scripts/ci-push.test.mjs (task ci-own-trigger)
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { loadIntent } from '../.github/scripts/changed-inputs.mjs';
import { asksExactly, lanesFor, parseArgs, probeNotes, pushOk, requestMessage } from './ci-push.mjs';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const golden = loadIntent(root).lanes;

test('parseArgs: branch must be ci/<name>; lanes required; unknown flags refused', () => {
  assert.deepEqual(parseArgs(['--branch', 'ci/x', '--lanes', 'wktr, lean']), { branch: 'ci/x', lanes: ['wktr', 'lean'], dry: false, partial: false });
  assert.equal(parseArgs(['--branch', 'ci/x', '--lanes', 'none', '--dry']).dry, true);
  assert.throws(() => parseArgs(['--branch', 'main', '--lanes', 'lean']), /ci\/<name>/);
  assert.throws(() => parseArgs(['--branch', 'ci/x']), /--lanes is required/);
  assert.throws(() => parseArgs(['--branch', 'ci/x', '--lanes', 'lean', '--force']), /unknown argument/);
});

test('lanesFor: golden names only; none alone is the empty request', () => {
  assert.deepEqual(lanesFor(golden, ['wktr', 'lean']).map((l) => l.file), ['wktr.yml', 'lean.yml']);
  assert.deepEqual(lanesFor(golden, ['none']), []);
  assert.throws(() => lanesFor(golden, ['wktr2']), /unknown lane wktr2/);
});

test('requestMessage asks for exactly the requested lanes (as the guard reads it)', () => {
  for (const names of [['wktr'], ['wktr-fixtures'], ['lean', 'webkit-sim'], ['none']]) {
    const lanes = lanesFor(golden, names);
    assert.ok(asksExactly(golden, lanes, requestMessage(golden, lanes)), names.join(','));
  }
  const lean = lanesFor(golden, ['lean']);
  assert.ok(asksExactly(golden, lean, 'fix a typo')); // no intent: only the default lane
  assert.ok(!asksExactly(golden, lanesFor(golden, ['wktr']), 'fix a typo'));
  // round 2: lean is always wanted, so naming it changes nothing; naming another lane does
  assert.ok(asksExactly(golden, lanesFor(golden, ['wktr']), 'x [ci:wktr] [ci:lean]'));
  assert.ok(!asksExactly(golden, lanesFor(golden, ['wktr']), 'x [ci:wktr] [ci:difftest]'));
  assert.ok(asksExactly(golden, lanesFor(golden, ['none']), 'fix a typo'));
  assert.equal(requestMessage(golden, []), 'ci: request [ci:none]');
});

test('the CLI refuses a push that would start nothing, and pushes with the request commit otherwise', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-push-'));
  try {
    const cfg = ['-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false'];
    const up = join(dir, 'up.git');
    const work = join(dir, 'work');
    execFileSync('git', ['init', '-q', '--bare', '-b', 'main', up]);
    // a checkout that holds the two CI goldens (the guard reads the lanes and the inputs from the checkout)
    const gold = join(work, 'packages/contracts/golden/ci');
    mkdirSync(gold, { recursive: true });
    for (const f of ['intent.jsonl', 'triggers.jsonl']) copyFileSync(join(root, 'packages/contracts/golden/ci', f), join(gold, f));
    const g = (...a) => execFileSync('git', [...cfg, ...a], { cwd: work, encoding: 'utf8' }).trim();
    g('init', '-q', '-b', 'main');
    g('remote', 'add', 'origin', up);
    g('add', '.');
    g('commit', '-q', '-m', 'root');
    g('push', '-q', 'origin', 'HEAD:refs/heads/main');
    const cli = (...a) => {
      try { return { code: 0, out: execFileSync('node', [join(root, 'scripts/ci-push.mjs'), ...a], { cwd: work, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }) }; }
      catch (e) { return { code: e.status, out: `${e.stdout}${e.stderr}` }; }
    };
    // nothing changed against main: refused
    const r1 = cli('--branch', 'ci/t', '--lanes', 'lean');
    assert.equal(r1.code, 2, r1.out);
    // a Lean change: lean starts, wktr is skipped (its inputs unchanged); the request commit is added and pushed
    mkdirSync(join(work, 'lean', 'Fw'), { recursive: true });
    writeFileSync(join(work, 'lean', 'Fw', 'CiPushProbe.lean'), '-- probe\n');
    g('add', '.');
    g('commit', '-q', '-m', 'probe');
    // round 4: wktr would be skipped, so its wait could never pass; refused without --partial (Lean pushOk)
    const full = cli('--branch', 'ci/t', '--lanes', 'lean,wktr', '--dry');
    assert.equal(full.code, 2, full.out);
    assert.match(full.out, /requested lane\(s\) wktr would not start/);
    const dry = cli('--branch', 'ci/t', '--lanes', 'lean,wktr', '--partial', '--dry');
    assert.equal(dry.code, 0, dry.out);
    assert.match(dry.out, /START lean/);
    assert.match(dry.out, /skip  wktr/);
    const r2 = cli('--branch', 'ci/t', '--lanes', 'lean,wktr', '--partial');
    assert.equal(r2.code, 0, r2.out);
    assert.equal(g('log', '-1', '--format=%s', 'HEAD'), 'ci: request [ci:lean] [ci:wktr]');
    assert.equal(g('ls-remote', 'origin', 'refs/heads/ci/t').split(/\s+/)[0], g('rev-parse', 'HEAD'));
    // the same request again: HEAD is already the tip, a push would create no run, so it is refused
    assert.equal(cli('--branch', 'ci/t', '--lanes', 'lean,wktr').code, 2);
    // a docs-only commit on top: the tip decides on the whole branch, so lean still starts (Lean tip_history_free)
    writeFileSync(join(work, 'notes.md'), 'x\n');
    g('add', '.');
    g('commit', '-q', '-m', 'docs');
    const r3 = cli('--branch', 'ci/t', '--lanes', 'lean', '--dry');
    assert.equal(r3.code, 0, r3.out);
    assert.match(r3.out, /START lean/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('pushOk equals the Lean push vectors (every preview of at most 3 lanes, with and without --partial)', () => {
  const rows = loadIntent(root).push.rows;
  assert.equal(rows.length, 170);
  for (const [part, ps, ok] of rows) {
    const plan = ps.map(([named, run]) => ({ implicit: !named, run }));
    assert.equal(pushOk(part, plan), ok, JSON.stringify([part, ps]));
  }
  assert.equal(parseArgs(['--branch', 'ci/x', '--lanes', 'wktr', '--partial']).partial, true);
});

test('probeNotes: a [trajectory] line without the lane token is reported, a refused line stops the push', () => {
  const g = loadIntent(root).lanes;
  const line = '[trajectory fw=hero.exit:scoped widths=390,1280 engines=both]';
  assert.deepEqual(probeNotes(g, `ci: m\n\n${line}`, `ci: m\n\n${line}`).refuse, false);
  assert.match(probeNotes(g, `ci: m\n\n${line}`, `ci: m\n\n${line}`).notes[0], /not \[ci:trajectory-probe\]/);
  assert.deepEqual(probeNotes(g, `ci: m\n\n[ci:trajectory-probe]\n${line}`, 'x').notes, []);
  assert.deepEqual(probeNotes(g, 'ci: m\n\n[ci:trajectory-probe]', 'x').notes, []);
  const bad = probeNotes(g, 'ci: m\n\n[ci:trajectory-probe]\n[trajectory fw=a:b preset=x]', 'x');
  assert.equal(bad.refuse, true);
  assert.match(bad.notes[0], /refused/);
  assert.match(probeNotes(g, 'ci: request [ci:trajectory-probe]', `[ci:trajectory-probe]\n${line}`).notes[0], /request commit/);
});
