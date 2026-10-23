import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const src = readFileSync(new URL('../.claude/workflows/build-review.js', import.meta.url), 'utf8').replace(/^export const meta = /m, 'const meta = ')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const run = (agent, args) => new AsyncFunction('agent', 'args', src)(agent, args)
const task = { id: 'demo-task', role: 'console-builder', prompt: 'do it' }

for (const [name, result] of [['null', null], ['no branch or commit', { summary: 'x', files: [] }]]) {
  test(`builder result ${name}: no-result record, no later stage`, async () => {
    const labels = []
    const out = await run(async (_p, o) => { labels.push(o.label); return result }, { task })
    assert.deepEqual(labels, ['build:demo-task'])
    assert.equal(out[0].state, 'no-result')
    assert.equal(out[0].task, 'demo-task')
    assert.equal(out[0].handoff, 'docs/team/handoffs/demo-task.md')
    assert.ok(out[0].worktree && out[0].branch)
  })
}

test('named worktree is returned; the builder prompt carries the checkpoint rule', async () => {
  let prompt = ''
  const out = await run(async (p) => { prompt = p; return null }, { task: { ...task, worktree: '/w/x' } })
  assert.equal(out[0].worktree, '/w/x')
  assert.match(prompt, /Checkpoint rule: write docs\/team\/handoffs\/demo-task\.md right after your first CI push/)
  assert.match(prompt, /before any wait longer than 10 minutes/)
})

test('builder that ends without StructuredOutput (agent throws): no-result record', async () => {
  const labels = []
  const out = await run(async (_p, o) => { labels.push(o.label); throw new Error('no StructuredOutput') }, { task })
  assert.deepEqual(labels, ['build:demo-task'])
  assert.equal(out[0].state, 'no-result')
  assert.equal(out[0].handoff, 'docs/team/handoffs/demo-task.md')
})

test('builder preamble: dry exactly as printed without --allow; out-of-list files in open', async () => {
  let prompt = ''
  await run(async (p) => { prompt = p; return null }, { task })
  assert.match(prompt, /Report `dry` exactly as the last VERDICT line printed by the dry land without --allow/)
  assert.match(prompt, /list every file outside the task's writes in `open`/)
})

test('builder preamble: plan lint on the build tree before the dry land; writesClosure errors in open', async () => {
  let prompt = ''
  await run(async (p) => { prompt = p; return null }, { task })
  const lint = prompt.indexOf('run `pnpm -s fw plan lint docs/team/work-graph.json` in your worktree')
  assert.ok(lint > 0)
  assert.ok(lint < prompt.indexOf('Hand back only after merging main and running'))
  assert.match(prompt, /list every writesClosure error line it prints in `open`/)
})

const report = { branch: 'b1', commit: 'c1', summary: 's', files: ['f'], dry: 'VERDICT dry demo-task (with --allow x)', items: [], runs: [] }
const resumeTask = { ...task, worktree: '/w/x', report: '/w/x/report.json' }

test('resume path: no build stage; runner reruns the dry; its last VERDICT line replaces dry; gate follows', async () => {
  const calls = []
  const out = await run(async (p, o) => {
    calls.push({ label: o.label, type: o.agentType, p })
    if (o.label.startsWith('resume-dry')) return { report, line: 'noise\nVERDICT dry demo-task (with --allow y)\nVERDICT dry demo-task' }
    if (o.label.startsWith('gate')) return { line: 'VERDICT review-ready demo-task returnToBuilder' }
    throw new Error('unexpected ' + o.label)
  }, { task: resumeTask })
  assert.deepEqual(calls.map((c) => c.label), ['resume-dry:demo-task', 'gate:demo-task'])
  assert.equal(calls[0].type, 'runner')
  assert.match(calls[0].p, /\/w\/x\/report\.json/)
  assert.match(calls[0].p, /--task demo-task --dry \(no --allow\)/)
  assert.match(calls[0].p, /fw land "\$\(git rev-parse --abbrev-ref HEAD\)" --task demo-task/)
  assert.equal(out[0].build.dry, 'VERDICT dry demo-task')
  assert.match(calls[1].p, /"dry":"VERDICT dry demo-task"\}/)
  assert.equal(out[0].gate, 'returnToBuilder')
})

test('resume path: a later refusal line wins over an earlier VERDICT dry line', async () => {
  const out = await run(async (p, o) => {
    if (o.label.startsWith('resume-dry')) return { report, line: 'VERDICT dry demo-task\nREFUSED: scope x\nVERDICT scope demo-task' }
    if (o.label.startsWith('gate')) return { line: 'VERDICT review-ready demo-task returnToBuilder' }
    throw new Error('unexpected ' + o.label)
  }, { task: resumeTask })
  assert.equal(out[0].build.dry, 'VERDICT scope demo-task')
  assert.equal(out[0].gate, 'returnToBuilder')
})

test('resume path: runner without a report returns the no-result record', async () => {
  const out = await run(async () => null, { task: resumeTask })
  assert.equal(out[0].state, 'no-result')
  assert.equal(out[0].worktree, '/w/x')
})

test('report without worktree does not resume: normal build runs', async () => {
  const labels = []
  await run(async (_p, o) => { labels.push(o.label); return null }, { task: { ...task, report: '/r.json' } })
  assert.deepEqual(labels, ['build:demo-task'])
})

const polishRun = (planOut, edited) => {
  const calls = []
  const done = run(async (p, o) => {
    calls.push({ label: o.label, p })
    if (o.label.startsWith('resume-dry')) return { report, line: 'VERDICT dry demo-task' }
    if (o.label.startsWith('gate')) return { line: 'VERDICT review-ready demo-task review' }
    if (o.label.startsWith('adv')) return { accept: true, findings: [], verdictLine: 'VERDICT review-verdict demo-task accept' }
    if (o.label.startsWith('polish-plan')) return { line: 'VERDICT polish-plan demo-task comments', out: planOut }
    if (o.label.startsWith('comment-sicko')) return { edited }
    if (o.label.startsWith('polish-commit')) return { line: 'VERDICT polish-commit demo-task committed', out: '' }
    if (o.label.startsWith('polish-dry')) return { line: 'VERDICT dry demo-task', out: '' }
    throw new Error('unexpected ' + o.label)
  }, { task: { ...resumeTask, worktree: '/r/.claude/worktrees/wf_a' } })
  return done.then((out) => ({ out, calls }))
}

test('polish: a redacted comments path is rebuilt from the worktree line and the class path', async () => {
  const plan = 'worktree /r/.claude/worktrees/wf_a\nclass code -- lean/Fw/A.lean\ncomments -- lean/Fw/A.lean lines 5-12,40-44\nVERDICT polish-plan demo-task comments'
  const { out, calls } = await polishRun(plan, ['/r/.claude/worktrees/wf_a/lean/Fw/A.lean'])
  const sicko = calls.find((c) => c.label.startsWith('comment-sicko'))
  assert.match(sicko.p, /\/r\/\.claude\/worktrees\/wf_a\/lean\/Fw\/A\.lean \(comment mark --; edit only comments on lines 5-12,40-44;/)
  assert.doesNotMatch(sicko.p, /<worktree>/)
  assert.equal(out[0].polish.commit, 'committed')
})

test('polish: no worktree line stops polish before comment-sicko', async () => {
  const { out, calls } = await polishRun('class code -- lean/Fw/A.lean\ncomments -- <worktree>/lean/Fw/A.lean', [])
  assert.ok(!calls.some((c) => c.label.startsWith('comment-sicko')))
  assert.equal(out[0].polish.stages, 'error')
})

test('polish: an edit outside the worktree stops before the polish commit', async () => {
  const plan = 'worktree /r/.claude/worktrees/wf_a\nclass code -- lean/Fw/A.lean\ncomments -- /r/.claude/worktrees/wf_a/lean/Fw/A.lean'
  const { out, calls } = await polishRun(plan, ['/r/lean/Fw/A.lean'])
  assert.ok(!calls.some((c) => c.label.startsWith('polish-commit')))
  assert.deepEqual(out[0].polish.strays, ['/r/lean/Fw/A.lean'])
})

test('gate agent reads a run state with the run branch; the RUN schema carries branch', () => {
  assert.match(src, /const RUN = \{[^\n]*branch: \{ type: 'string' \}/)
  assert.match(src, /\{id, branch, state: running\|complete\|failed\} \(branch = the ci\/\* branch the run is on\)/)
  assert.match(src, /pnpm -s fw ci state <run id> --branch <its runs\[\]\.branch>/)
  assert.match(src, /const RUN = \{[^\n]*required: \['id', 'branch', 'state'\]/)
})

test('the adversarial reviewer gets the runs and reads each with its branch', () => {
  assert.match(src, /Builder runs: \$\{JSON\.stringify\(b\.runs \|\| \[\]\)\}/)
  assert.match(src, /pnpm -s fw ci state <run id> --branch <its runs\[\]\.branch>\)\./)
})
