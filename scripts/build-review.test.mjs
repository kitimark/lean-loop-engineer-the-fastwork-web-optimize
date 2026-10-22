// Runs .claude/workflows/build-review.js with a stub agent: a builder that returns nothing ends the run with a 'no-result' record.
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
