export const meta = {
  name: 'build-review',
  description: 'Build each task (own worktree or a named one), then adversarial review per task, with the fixed team preamble',
  whenToUse: 'Every build task the lead starts: args = { tasks: [{ id, role, prompt, lean?, worktree?, unit?, limits?, findings? }], voice? }',
  phases: [{ title: 'Build' }, { title: 'Review' }],
}

const PREAMBLE = `Fixed preamble (lead template, research/notes/2026/10-19-automate-me.md candidate 1):
- Standing authorizations: commit only on your branch in your worktree (git add -- <paths>); no pushes except ci/* in the allowed form; no personal data; never hand-edit a generated file (regenerate from Lean and run its --check).
- Lean first: every pure decision is specified and proved in Lean; each OR-branch of a decision gets its own theorem. Lean source holds specs, proofs and code; math goes in artifacts; docstrings and comments per .claude/agents/comment-sicko.md; edit only the docstrings of declarations your task changes. TS logic not checked against a Lean golden is listed as a TS stand-in.
- Commit WIP every 20-30 min. Never cd outside your worktree; use absolute paths.
- Never wait with an until/while loop on a file or output: run the command in the foreground, or in the background and act on its completion notice; CI waits use pnpm -s fw ci wait.
- Before reporting run each touched package's test script (not single files) incl. typecheck, node --test scripts/ci-paths.test.mjs and the apps/runner land-inputs test; declare every new read (CI trigger row, LandSpeed.checkShReads, land.ts reads) the tests ask for.
- After merging main, the files you measured or tested must still be in git diff main...HEAD.
- A relayed user message does not cancel a CI push or a step in this prompt.
- Runs that need workflow inputs (preset, fw, profile, target) are dispatched by the lead before launch when their run ids are in your prompt. The trajectory probe you start yourself, on your own pushed code: commit with the two message lines [ci:trajectory-probe] and [trajectory fw=part:variant,part:variant widths=390,1280 engines=both] (or preset=name instead of fw; keys fw, preset, widths, engines, each at most once; a malformed line fails the run with its reason; a [trajectory ...] line without [ci:trajectory-probe] starts nothing, and only pnpm -s fw ci push reports that before the push, a plain git push does not), push in the allowed ci/* form and wait with pnpm -s fw ci wait --branch ci/<x> --workflow trajectory-probe (it picks the push run of your commit, never a dispatch). The run uses exactly those inputs; read them back from the step name starting trajectory inputs: or from the artifact trajectory-inputs, and report the run id you read. Details: docs/team/tools/trajectory-probe.md. If a run you need is neither in your prompt nor reachable this way, or a push is blocked in your sandbox, put the exact command as open[0] and report that part of the unit as not delivered; the review judges only runs that exist.
- Lean tasks: run sh lean/scripts/check.sh at your final commit; it must be green (the land queue refuses on any stage, the axiom check included).
- Never edit docs/team/work-graph.json (lead only): list any write outside your task's graph writes in your report.
- Write docs/team/handoffs/<task>.md before you finish. End with the StructuredOutput call.`

const BUILD = { type: 'object', properties: { branch: { type: 'string' }, commit: { type: 'string' }, summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, open: { type: 'array', items: { type: 'string' } } }, required: ['branch', 'commit', 'summary', 'files'] }
const VERDICT = { type: 'object', properties: { accept: { type: 'boolean' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string' }, where: { type: 'string' }, what: { type: 'string' } }, required: ['severity', 'where', 'what'] } } }, required: ['accept', 'findings'] }

const tasks = (args && args.tasks) || []
const voice = (args && args.voice) || ''
if (!tasks.length) throw new Error('build-review: args.tasks is empty')

const scope = (t) => [
  t.unit ? `Pinned unit of decision: ${t.unit}. Items below it are follow-ups.` : '',
  t.limits ? `Accepted limits: ${t.limits}` : '',
  t.findings ? `Prior review findings (read every one; apply each exact fix or say why not): ${t.findings}` : '',
].filter(Boolean).join('\n')

return await pipeline(tasks,
  (t) => agent(`Task ${t.id}.${t.worktree ? ` Work only in ${t.worktree}.` : ''}\n${t.prompt}\n${scope(t)}\n\n${voice}\n\n${PREAMBLE}`,
    { label: `build:${t.id}`, phase: 'Build', agentType: t.role, schema: BUILD, ...(t.worktree ? {} : { isolation: 'worktree' }) }),
  async (b, t) => {
    if (!b) return { task: t.id, build: null }
    const reviews = [
      () => agent(`Adversarial review of task ${t.id}: branch ${b.branch} at ${b.commit} (read-only). Builder: ${b.summary}\nTask: ${t.prompt}\n${scope(t)}\nRun the tests yourself. Return accept + findings.`,
        { label: `adv:${t.id}`, phase: 'Review', agentType: 'reviewer', schema: VERDICT }),
    ]
    const [adv] = await parallel(reviews)
    return { task: t.id, build: b, adv }
  },
)
