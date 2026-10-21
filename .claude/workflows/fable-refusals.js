export const meta = {
  name: 'fable-refusals',
  description: 'Fable investigates each refused build-review task (verify findings, retro, fix list or split), then an adversarial check that returns the corrected spec',
  whenToUse: 'After a build-review run with refused reviews: args = { tasks: [{ id, branch, worktree, findings, prompt, round }], out, context? }',
  phases: [{ title: 'Investigate' }, { title: 'Check' }],
}

// The check returns the corrected spec (the next round's fix list, pinned unit and accepted limits), not an accept bit: the bit was 0 in every
// run and carried no signal. An empty corrections list means Fable's advice stands.
const SPEC = { type: 'object', properties: { spec: { type: 'string' }, corrections: { type: 'array', items: { type: 'object', properties: { where: { type: 'string' }, what: { type: 'string' }, why: { type: 'string' } }, required: ['where', 'what', 'why'] } } }, required: ['spec', 'corrections'] }
const tasks = (args && args.tasks) || []
const out = args && args.out
const context = (args && args.context) || ''
if (!tasks.length || !out) throw new Error('fable-refusals: args.tasks and args.out are required')

const ctx = (t) => `Task ${t.id}, review round ${t.round ?? 0} refused. Branch ${t.branch} (worktree ${t.worktree}: read-only for you; use git -C, never cd into it). Refused review findings: ${t.findings}. The task as given to the builder: ${t.prompt}
Review-loop rule (CLAUDE.md, Team): after a 2nd refusal the lead runs a retro and a closed final design round (allowlist over deny-list, identity over inference, one canonical source, each unit decided on its own) with listed accepted limits; a 3rd refusal splits the task; when forensics refute a task's premise, close it as a finding and re-plan. ${context}`

return await pipeline(tasks,
  (t) => agent(`You are Fable. ${ctx(t)}

Investigate why the review did not accept this task and how to fix it. (1) For every finding: verify it yourself against the code, the snapshot (snapshot/site/, the unmodified original) and upstream source where relevant (cite file:line); classify it as real defect, real but low value, or reviewer error / rule noise. (2) Root cause: was the task prompt wrong or underspecified, did the builder miss part of it, did a premise fall, or did the reviewer probe beyond the pinned unit? (3) The fix: an exact, ordered fix list for the next round, the pinned unit of decision, and the accepted limits the reviewer judges against; or, if the refusal count or a fallen premise calls for it, a split (what lands now, what becomes a follow-up task with its scope). Keep it to what the next round needs; no new mechanism unless a finding requires one, and say why. Write ${out}/fable-${t.id}.md (<= 70 lines, plain style, CONFIRMED/INFERRED tags, no Fastwork code beyond a few words, no SVG path data, no home paths) and return it in full.`,
    { label: `fable:${t.id}`, phase: 'Investigate', model: 'fable' }),
  async (advice, t) => {
    const check = await agent(`Adversarial check (read-only) of Fable's advice on refused task ${t.id}. ${ctx(t)}

Verify at least 6 of Fable's classifications against the code and the snapshot (cite). Check that the fix list resolves every real finding, that the pinned unit and accepted limits are honest (nothing the task claims is left undecided without being listed), and that any split leaves nothing a downstream claim depends on. Refute anything wrong. Return the corrected spec as spec (the complete ordered fix list, the pinned unit of decision and the accepted limits, ready to paste into the next round's prompt; keep Fable's text where it is right) and each change you made to Fable's advice as corrections {where, what, why}.

FABLE:
${advice}`, { label: `check:${t.id}`, phase: 'Check', agentType: 'reviewer', schema: SPEC })
    return { task: t.id, advice, check }
  },
)
