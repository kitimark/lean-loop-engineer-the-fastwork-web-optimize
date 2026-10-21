// The node twin of Fw.Ci.Trigger.pushProbe against the Lean golden (`probe` lines of triggers.jsonl).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { appleRuns, dispatch, dispatchIn, pushProbe, whyText } from './trajectory-line.mjs';

const lines = readFileSync(new URL('../../packages/contracts/golden/ci/triggers.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'probe');

const dispatchGolden = readFileSync(new URL('../../packages/contracts/golden/gate/trajectory-dispatch.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'in');

const apple = readFileSync(new URL('../../packages/contracts/golden/ci/triggers.jsonl', import.meta.url), 'utf8')
  .trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'apple');

test('appleRuns equals Lean on every golden line, and the golden has each branch', () => {
  assert.ok(apple.length >= 40);
  for (const l of apple) assert.equal(appleRuns(l.event, l.msg, l.appleN), l.run, `${l.event} ${JSON.stringify(l.msg)} n=${l.appleN}`);
  const on = apple.filter((l) => l.run);
  assert.ok(on.some((l) => l.event === 'workflow_dispatch'));
  assert.ok(on.some((l) => l.event === 'push' && /\[frames:/i.test(l.msg)));
  assert.ok(on.some((l) => l.event === 'push' && l.msg.includes('debug=nav-transition')));
  assert.ok(apple.some((l) => l.event === 'push' && l.appleN === 2 && !l.run));
  assert.ok(apple.every((l) => l.appleN !== 0 || !l.run));
});

test('the golden has probe cases of every decision', () => {
  assert.ok(lines.length >= 50);
  for (const k of ['run', 'notAsked', 'needsLane', 'refused']) assert.ok(lines.some((l) => l.result.kind === k), k);
});

test('pushProbe equals Lean on every golden line', () => {
  for (const l of lines) assert.deepEqual(pushProbe(l.lane, l.msg), l.result, `${JSON.stringify(l.msg)} lane=${l.lane}`);
});

test('the workflow carries the debug key from the commit line to the probe steps and to the mac leg, and no repo file requests a recorder', () => {
  const wf = readFileSync(new URL('../workflows/trajectory-probe.yml', import.meta.url), 'utf8');
  assert.match(wf, /debug: \$\{\{ steps\.p\.outputs\.debug \}\}/);
  assert.equal((wf.match(/FW_DEBUG: \$\{\{ needs\.site\.outputs\.debug \}\}/g) ?? []).length, 2); // probe and probe-apple
  assert.match(wf, /apple_run: \$\{\{ steps\.p\.outputs\.apple_run \}\}/);
  assert.match(wf, /probe-apple:\n    needs: \[site\]\n    if: \$\{\{ needs\.site\.outputs\.apple_run == 'true' \}\}/); // the rule is Lean's appleRuns, not the `if:`
  assert.match(wf, /node \.github\/scripts\/trajectory-line\.mjs apple/);
  assert.equal(existsSync(new URL('../../packages/gate-breakpoints/src/trajectory/debug.requests.json', import.meta.url)), false);
});

test('the line of the phase 1 run asks for the nav recorder and nothing else changes', () => {
  const r = pushProbe(true, '[ci:trajectory-probe]\n[trajectory fw=morph.tween:waapi widths=1280 engines=playwright-webkit debug=nav-transition diagnostic]');
  assert.deepEqual(r, { kind: 'run', engines: 'playwright-webkit', fw: 'morph.tween:waapi', preset: '', widths: '1280', debug: 'nav-transition', diagnostic: true });
  assert.equal(pushProbe(true, '[trajectory debug=other]').kind, 'refused');
  assert.equal(pushProbe(true, '[ci:trajectory-probe]').debug, '');
});

test('dispatchIn (the twin of Lean Dispatch.dispatchIn) equals the Lean golden for both marks on every widths input', () => {
  assert.ok(dispatchGolden.length >= 50);
  for (const l of dispatchGolden) {
    const d = dispatchIn(l.mark, l.input);
    if (l.decision === 'accepted') assert.deepEqual(d, { kind: 'accepted', widths: l.widths }, `${l.mark} ${JSON.stringify(l.input)}`);
    else assert.deepEqual(d, { kind: 'refused', why: l.why }, `${l.mark} ${JSON.stringify(l.input)}`);
  }
  for (const why of ['badInput', 'scopedVerdict']) assert.ok(dispatchGolden.some((l) => l.why === why), why);
  // the lists of widths (no string input reaches the empty list or a repeat): empty, outside the lane, repeated, complete, every subset
  const lists = readFileSync(new URL('../../packages/contracts/golden/gate/trajectory-dispatch.jsonl', import.meta.url), 'utf8')
    .trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'list');
  assert.ok(lists.some((l) => l.why === 'emptyWidths') && lists.some((l) => l.in.length === 2 && l.in[0] === l.in[1] && l.why === 'badInput'));
  for (const l of lists) {
    const d = dispatch(l.mark, l.in);
    assert.deepEqual(d, l.decision === 'accepted' ? { kind: 'accepted', widths: l.widths } : { kind: 'refused', why: l.why }, `${l.mark} ${JSON.stringify(l.in)}`);
  }
});

test('the push line: a width subset needs the diagnostic word, all four widths do not, and the refusal text is the Dispatch text', () => {
  const lane = (l) => pushProbe(true, `[trajectory ${l}]`);
  const hint = '; add the word diagnostic to the line for a run read by hand';
  assert.deepEqual(lane('widths=390,641'), { kind: 'refused', why: whyText('scopedVerdict', '390,641') + hint });
  assert.match(lane('widths=390,641').why, /walks all four widths \(390,640,641,1280\).*add the word diagnostic/);
  assert.equal(lane('widths=390,641 diagnostic').kind, 'run');
  assert.equal(lane('widths=390,641 diagnostic').diagnostic, true);
  assert.equal(lane('widths=1280,390,640,641').kind, 'run');
  assert.equal(lane('widths=1280,390,640,641').diagnostic, false);
  assert.equal(lane('diagnostic').widths, '');
  assert.equal(lane('widths=800 diagnostic').why, whyText('badInput', '800'));
  assert.equal(lane('diagnostic diagnostic').why, "key 'diagnostic' given twice");
  assert.equal(lane('diagnostic=true').why, 'diagnostic is a bare word, not diagnostic=...');
  for (const w of ['390', '640,1280', '390,641,1280']) assert.equal(lane(`widths=${w}`).kind, 'refused', w);
  // every run the golden starts without the word walks all four widths
  for (const l of lines.filter((x) => x.result.kind === 'run' && !x.result.diagnostic)) {
    assert.equal(dispatchIn('verdict', l.result.widths).kind, 'accepted', l.msg);
    assert.equal(dispatchIn('verdict', l.result.widths).widths.length, 4, l.msg);
  }
});

const dispatchStep = (env) => spawnSync(process.execPath, [new URL('./trajectory-line.mjs', import.meta.url).pathname], { env: { PATH: process.env.PATH, EVENT: 'workflow_dispatch', ...env }, encoding: 'utf8' });

test('the workflow_dispatch inputs follow the same rule: a widths subset needs diagnostic=true', () => {
  const sub = dispatchStep({ WIDTHS: '390,641', DIAGNOSTIC: 'false' });
  assert.equal(sub.status, 1);
  assert.match(sub.stderr, /refused: widths 390,641 is a subset.*all four widths \(390,640,641,1280\).*diagnostic input to true/);
  assert.equal(dispatchStep({ WIDTHS: '390,641' }).status, 1);
  const ok = dispatchStep({ WIDTHS: '390,641', DIAGNOSTIC: 'true' });
  assert.equal(ok.status, 0);
  assert.match(ok.stdout, /widths=390,641\n/);
  assert.match(ok.stdout, /diagnostic=true\n/);
  assert.equal(dispatchStep({ WIDTHS: '', DIAGNOSTIC: 'false' }).status, 0);
  assert.equal(dispatchStep({ WIDTHS: '1280,641,640,390' }).status, 0);
  assert.equal(dispatchStep({ WIDTHS: '800', DIAGNOSTIC: 'true' }).status, 1);
});

test('the workflow declares the boolean diagnostic input and checks the rule in the step that reads the inputs, before the build', () => {
  const wf = readFileSync(new URL('../workflows/trajectory-probe.yml', import.meta.url), 'utf8');
  assert.match(wf, /\n      diagnostic:\n(        .*\n)*?        type: boolean\n        default: false\n/);
  assert.match(wf, /DIAGNOSTIC: \$\{\{ inputs\.diagnostic && 'true' \|\| 'false' \}\}/);
  assert.ok(wf.indexOf('DIAGNOSTIC:') < wf.indexOf('Plan the probe'), 'the rule runs before the plan and the build');
});
