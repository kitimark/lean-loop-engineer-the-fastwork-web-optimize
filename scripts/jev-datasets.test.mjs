// Tests of scripts/jev-datasets.mjs on synthetic fixtures only (no real ledger, journal, run list or event log).
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { GOLDEN, buildD1, buildD2, buildD3, buildD4, fableClassLines, leaks, loadRules, localNames, logTail, redact, run, summarize } from './jev-datasets.mjs'

const golden = readFileSync(GOLDEN, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
const rules = loadRules()
// Synthetic personal-looking values are assembled at run time so this file holds no literal the privacy scrub would flag.
const HOME = ['/Us', 'ers/'].join('')
const LINUXHOME = ["/ho", "me/"].join("")
const ENC = ['-Us', 'ers-'].join('')
const LAN = ['192', '168', '1', '20'].join('.')
const TEN = ['10', '0', '0', '7'].join('.')
const SCRATCH = ['/private/tmp/claude', '501/'].join('-')
const SID = ['00000000', '0000', '4000', '8000', '000000000001'].join('-')
const AID = ['a0123', '456789abcdef'].join('')
const DEVICE = ['0000', '8110-001A2B3C4D5E6F70'].join('')
const of = (k) => golden.filter((r) => r.kind === k)

test('golden: hash and split', () => {
  assert.ok(of('hash').length >= 8)
  for (const r of of('hash')) {
    assert.equal(rules.fnv1a(r.id), r.hash, r.id)
    assert.equal(rules.heldOut(r.id), r.heldOut, r.id)
  }
})

test('golden: d1, severity, fable, applies, apply', () => {
  for (const r of of('d1')) assert.equal(rules.d1Label(r.class), r.label, r.class)
  assert.ok(of('severity').length >= 30)
  for (const r of of('severity')) {
    const got = rules.severity(r.text)
    assert.equal(got ? got[0] : null, r.grade, r.text)
    assert.equal(got ? got[1] : null, r.tier, r.text)
    assert.equal(got ? rules.inUnit(got[0]) : null, r.inUnit, r.text)
  }
  for (const r of of('fable')) assert.equal(rules.fableRegrade(r.line), r.regrade, r.line)
  for (const r of of('applies')) assert.equal(rules.regradeApplies(r.findings, r.parsed), r.ok)
  for (const r of of('apply')) assert.equal(rules.applyRegrade(r.orig, r.regrade), r.label)
})

test('golden: phrases, ci causes (all 64 fact combinations), alert triage (all 30)', () => {
  for (const r of of('phrase')) {
    assert.equal(rules.infraSig(r.text), r.infra, r.text)
    assert.equal(rules.codeSig(r.text), r.code, r.text)
  }
  assert.equal(of('ci').length, 64)
  for (const r of of('ci')) assert.equal(rules.ciCause(r.facts), r.cause, JSON.stringify(r.facts))
  assert.equal(of('alert').length, 30)
  for (const r of of('alert')) assert.equal(rules.alertTriage(r.audience, r.end, r.restartText), r.triage)
})

test('redact: home paths, emails, ids, addresses, tokens, names, scratch paths', () => {
  const names = ['alice', 'Bob']
  const cases = [
    [`see ${HOME}alice/src/x.ts and ${LINUXHOME}carol/y`, [`${HOME}alice`, 'carol']],
    [`dash dir ${ENC}alice-source-proj`, [`${ENC}alice`]],
    ['mail alice.b@example.com now', ['@example.com']],
    [`session ${SID} ok`, [SID.slice(0, 8)]],
    [`agent ${AID} stopped`, [AID]],
    [`host ${LAN} and ${TEN}`, [LAN, TEN]],
    ['token ghp_abcdefghijklmnop1234 end', ['ghp_abcdefgh']],
    [`written to ${SCRATCH}${ENC}alice-x/${SID}/scratchpad/f.md`, [SCRATCH.slice(13, 24), 'alice']],
    ['Bob said ALICE owns it; malice stays', ['Bob', 'ALICE']],
    [`device ${DEVICE}`, [DEVICE.slice(0, 8)]],
  ]
  for (const [text, gone] of cases) {
    const out = redact(text, names)
    for (const g of gone) assert.ok(!out.includes(g), `${g} left in: ${out}`)
    assert.deepEqual(leaks(out, names), [], out)
  }
  assert.equal(redact('malice stays', names), 'malice stays')
  assert.equal(redact('version 156.0.8078.4 and sha 538f723064ef9ab6', names), 'version 156.0.8078.4 and sha 538f723064ef9ab6')
  assert.deepEqual(leaks(`${HOME}carol/x`), ['home'])
})

test('localNames: only the local part of the e-mail, never its domain', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'jev-names-'))
  const cfg = path.join(dir, 'gitconfig')
  writeFileSync(cfg, '[user]\n\tname = Zed Quux\n\temail = zed.quux@example.com\n')
  const saved = process.env.GIT_CONFIG_GLOBAL
  process.env.GIT_CONFIG_GLOBAL = cfg
  try {
    const names = localNames()
    assert.ok(names.includes('Zed') && names.includes('Quux') && names.includes('zed'), names.join())
    assert.ok(!names.includes('example') && !names.includes('com'), names.join())
    assert.equal(redact('see github.com and example.com', names), 'see github.com and example.com')
  } finally {
    if (saved === undefined) delete process.env.GIT_CONFIG_GLOBAL
    else process.env.GIT_CONFIG_GLOBAL = saved
  }
})

test('buildD1: labels by ledger class, unknown class unlabelled, leaking row withheld', () => {
  const ledger = { incidents: [
    { id: 'inc-a', title: 'A wait loop', symptom: `stuck for ${HOME}alice/x`, cause: 'c', mistakeClass: 'c-orphan-wait' },
    { id: 'inc-b', title: 'B', symptom: 's', cause: 'c', mistakeClass: 'c-made-up' },
    { id: 'inc-c', title: 'C', symptom: 's', cause: 'c', mistakeClass: 'c-quota' },
  ] }
  const { rows, withheld } = buildD1(rules, ledger, ['alice'])
  assert.equal(withheld, 0)
  assert.deepEqual(rows.map((r) => r.label), ['c-orphan-wait', null, 'c-quota'])
  assert.ok(rows[0].symptom.includes('~') && !rows[0].symptom.includes('alice'))
  assert.ok(rows.every((r) => r.split === (rules.heldOut(r.id) ? 'heldOut' : 'calibration')))
  assert.deepEqual(summarize(rows).labels, { 'c-orphan-wait': 1, 'c-quota': 1, unlabelled: 1 })
})

test('fableClassLines finds classification lines only', () => {
  const advice = ['# Fable: t', '## Findings', '1. blocker, real defect. x', 'R2-4 (G_6): reviewer error here', '- F3 low: real but low value',
    'Note: something', '| 2 | medium | real, low value | y |', 'plain text that is real'].join('\n')
  assert.equal(fableClassLines(advice).length, 4)
})

function journalFixture(root) {
  const wfs = path.join(root, 'workflows')
  const mk = (wf, entries, agents) => {
    mkdirSync(path.join(wfs, wf), { recursive: true })
    writeFileSync(path.join(wfs, wf, 'journal.jsonl'), entries.map((e) => JSON.stringify(e)).join('\n') + '\n')
    for (const [id, prompt] of Object.entries(agents)) {
      writeFileSync(path.join(wfs, wf, `agent-${id}.jsonl`), JSON.stringify({ type: 'user', message: { role: 'user', content: prompt } }) + '\n' + '{"x":1}\n')
    }
  }
  const prompt = (unit) => `header\n  Task: Graph task t1. Do things in ${HOME}alice/repo.\n  Pinned unit of decision: ${unit}. Items below it are follow-ups.\n  Accepted limits: no live run.\n  Run the tests.`
  const f = (sev, what) => ({ severity: sev, where: 'a.ts:1', what })
  mk('wf_r1', [
    { type: 'started', agentId: 'a1111111111111111', label: 'adv:t1' },
    { type: 'result', agentId: 'a1111111111111111', result: { accept: false, findings: [f('blocker', 'one'), f('high', 'two'), f('medium', 'three'), f('low (follow-up)', 'four')] } },
  ], { a1111111111111111: prompt('the unit') })
  return { wfs, mk, prompt, f }
}

test('buildD2: severity grades, tiers, in-unit, unit and limits parsed, no agent id or home path in rows', async () => {
  const root = mkdtempSync(path.join(tmpdir(), 'jevd2-'))
  const { wfs } = journalFixture(root)
  const { readJournals } = await import('./jev-datasets.mjs')
  const { rows, reviews } = buildD2(rules, readJournals(wfs), ['alice'])
  assert.equal(reviews, 1)
  assert.deepEqual(rows.map((r) => [r.label, r.tier, r.inUnit]), [
    ['blocker', 'exact', true], ['blocker', 'legacy', true], [null, null, null], ['follow-up', 'legacy', false]])
  assert.equal(rows[0].unit, 'the unit. Items below it are follow-ups.')
  assert.equal(rows[0].limits, 'no live run.')
  assert.ok(rows[0].taskText.includes('~') && !rows[0].taskText.includes('alice'))
  assert.equal(rows[0].id, 't1#wf_r1#f1')
  assert.equal(rows[0].round, 1)
  assert.ok(JSON.stringify(rows).search(/a1111111111111111/) < 0)
})

test('buildD2: a Fable advice with as many classification lines as findings regrades by position, otherwise none', async () => {
  const root = mkdtempSync(path.join(tmpdir(), 'jevd2f-'))
  const { wfs, mk } = journalFixture(root)
  const advice = (n) => ['## Findings', ...Array.from({ length: n }, (_, i) => `${i + 1}. ${i === 1 ? 'reviewer error' : i === 2 ? 'real, low value' : 'real defect'}`)].join('\n')
  const { readJournals } = await import('./jev-datasets.mjs')
  await new Promise((r) => setTimeout(r, 20))
  mk('wf_fa', [{ type: 'started', agentId: 'a2222222222222222', label: 'fable:t1' }, { type: 'result', agentId: 'a2222222222222222', result: advice(4) }], {})
  let out = buildD2(rules, readJournals(wfs), [])
  assert.deepEqual(out.rows.map((r) => r.label), ['blocker', null, 'follow-up', 'follow-up'])
  assert.deepEqual(out.rows.map((r) => r.labelSource), ['reviewer', 'fable:wf_fa', 'fable:wf_fa', 'reviewer'])
  assert.equal(out.rows[2].regrade, 'follow-up')
  mk('wf_fa', [{ type: 'started', agentId: 'a2222222222222222', label: 'fable:t1' }, { type: 'result', agentId: 'a2222222222222222', result: advice(3) }], {})
  out = buildD2(rules, readJournals(wfs), [])
  assert.deepEqual(out.rows.map((r) => r.labelSource), ['reviewer', 'reviewer', 'reviewer', 'reviewer'])
  assert.equal(out.fableStats.skipped, 1)
})

test('logTail strips prefixes and keeps the end', () => {
  const raw = ['job\tstep\t2026-10-17T14:55:44.0002520Z first', 'job\tstep\t2026-10-17T14:55:45.0000000Z ', 'job\tstep\t2026-10-17T14:55:46.0000000Z last'].join('\n')
  assert.equal(logTail(raw, 5), 'first\nlast')
  assert.equal(logTail(raw, 1), 'last')
})

test('buildD3: infra, flake, ours, uncovered, unread log', () => {
  const t0 = '2026-10-19T12:00:00Z'
  const fl = (id, wf, sha, at, conclusion = 'failure') => ({ databaseId: id, workflowName: wf, headSha: sha, headBranch: 'ci/x', event: 'push', createdAt: at, displayTitle: 'T', conclusion })
  const failures = [
    fl(1, 'lean', 's1', '2026-10-20T00:00:00Z'), // infra log
    fl(2, 'lean', 's2', '2026-10-20T00:00:00Z'), // same sha passed, code log
    fl(3, 'lean', 's3', '2026-10-20T00:00:00Z'), // code log, nothing passed
    fl(4, 'lean', 's4', '2026-10-01T00:00:00Z'), // before the success window
    fl(5, 'lean', 's5', '2026-10-20T00:00:00Z'), // log not read
    fl(6, 'lean', 's6', '2026-10-20T00:00:00Z'), // no phrase
  ]
  const successes = [{ databaseId: 9, workflowName: 'lean', headSha: 's2', createdAt: t0, conclusion: 'success' }, { databaseId: 10, workflowName: 'other', headSha: 's3', createdAt: t0, conclusion: 'success' }]
  const logs = { 1: 'curl: ECONNRESET', 2: 'AssertionError: x', 3: 'error TS2322', 4: 'AssertionError', 6: 'exit code 1' }
  const win = buildD3(rules, failures, successes, logs, { successLimit: 2 })
  assert.deepEqual(win.rows.map((r) => r.label), ['infra', 'flake', 'ours', null, null, null])
  assert.equal(win.rows[3].facts.covered, false)
  const all = buildD3(rules, failures, successes, logs, { successLimit: 1000 })
  assert.equal(all.rows[3].label, 'ours')
  assert.deepEqual(summarize(win.rows).labels, { flake: 1, infra: 1, ours: 1, unlabelled: 3 })
})

test('buildD4: audience decides, otherwise how the step ended', () => {
  const post = (step, seq, extra = {}) => ({ type: 'step.post', step, seq, title: 'Agent main needs input', actor: 'script', ...extra })
  const events = [
    post('alert-1', 1), { type: 'step.done', step: 'alert-1', seq: 2, actor: 'user' },
    post('alert-2', 3), { type: 'step.cancel', step: 'alert-2', seq: 4, actor: 'lead' },
    post('alert-3', 5, { title: 'Agent main stopped; the lead restarts it' }), { type: 'step.cancel', step: 'alert-3', seq: 6, actor: 'script' },
    post('alert-4', 7, { audience: 'lead' }),
    post('alert-5', 8, { audience: 'user' }), { type: 'step.cancel', step: 'alert-5', seq: 9, actor: 'script' },
    post('alert-6', 10), { type: 'step.done', step: 'alert-6', seq: 11, actor: 'script', note: 'resolved automatically' },
    post('alert-7', 12),
    { type: 'step.post', step: 'ask-x', seq: 13, title: 'not an alert' },
  ]
  const { rows } = buildD4(rules, events, [])
  assert.deepEqual(rows.map((r) => r.label), ['ask-user', 'ignore', 'mitigate', 'mitigate', 'ask-user', 'mitigate', null])
  assert.deepEqual(rows.map((r) => r.end), ['user-acted', 'lead-cancelled', 'script-cancelled', 'open', 'script-cancelled', 'auto-resolved', 'open'])
})

test('run: end to end on fixtures writes the sets and counts, redacted, nothing else', async () => {
  const root = mkdtempSync(path.join(tmpdir(), 'jevrun-'))
  const { wfs } = journalFixture(root)
  writeFileSync(path.join(root, 'ledger.json'), JSON.stringify({ incidents: [{ id: 'i1', title: 't', symptom: 's', cause: 'c', mistakeClass: 'c-quota' }] }))
  writeFileSync(path.join(root, 'events.jsonl'), JSON.stringify({ type: 'step.post', step: 'alert-1', seq: 1, title: 'x', audience: 'user' }) + '\n')
  mkdirSync(path.join(root, 'runs'))
  writeFileSync(path.join(root, 'runs', 'runs-failure.json'), JSON.stringify([{ databaseId: 5, workflowName: 'lean', headSha: 'z', headBranch: 'b', event: 'push', createdAt: '2026-10-20T00:00:00Z', displayTitle: 'T', conclusion: 'failure' }]))
  writeFileSync(path.join(root, 'runs', 'runs-success.json'), '[]')
  mkdirSync(path.join(root, 'logs'))
  writeFileSync(path.join(root, 'logs', '5.txt'), `AssertionError at ${HOME}carol/x`)
  const out = path.join(root, 'out')
  const res = await run(['--out', out, '--ledger', path.join(root, 'ledger.json'), '--journals', wfs, '--events', path.join(root, 'events.jsonl'),
    '--runs-dir', path.join(root, 'runs'), '--logs-dir', path.join(root, 'logs'), '--no-gh'])
  assert.deepEqual(res.counts.d1.labels, { 'c-quota': 1 })
  assert.equal(res.counts.d2.rows, 4)
  assert.deepEqual(res.counts.d3.labels, { ours: 1 })
  assert.deepEqual(res.counts.d4.labels, { 'ask-user': 1 })
  const d3 = readFileSync(path.join(out, 'd3.jsonl'), 'utf8')
  assert.ok(d3.includes('AssertionError at ~') && !d3.includes('carol'))
  assert.equal(JSON.parse(readFileSync(path.join(out, 'counts.json'), 'utf8')).counts.d1.rows, 1)
})
