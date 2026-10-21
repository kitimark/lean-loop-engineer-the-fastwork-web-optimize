export const meta = {
  name: 'build-review',
  description: 'Build one task (own worktree or a named one), then its adversarial review, with the fixed team preamble',
  whenToUse: 'Every build task the lead starts, one run per task so each finishes (and lands) on its own: args = { task: { id, role, prompt, lean?, worktree?, unit?, limits?, findings? }, voice? }',
  phases: [{ title: 'Build' }, { title: 'Review' }],
}

const PREAMBLE = `Fixed preamble (lead template, research/notes/2026/10-19-automate-me.md candidate 1):
- Standing authorizations: commit only on your branch in your worktree (git add -- <paths>); no pushes except ci/* in the allowed form; no personal data; never hand-edit a generated file (regenerate from Lean and run its --check).
- Lean first: every pure decision is specified and proved in Lean; each OR-branch of a decision gets its own theorem. Lean source holds specs, proofs and code; math goes in artifacts; docstrings and comments per .claude/agents/comment-sicko.md; edit only the docstrings of declarations your task changes. TS logic not checked against a Lean golden is listed as a TS stand-in.
- Commit WIP every 20-30 min. Never cd outside your worktree; use absolute paths.
- Teardown: start every long-lived helper (servers, watchers, browsers, lake serve, background builds) in its own process group (setsid, or spawn with detached:true), note its pid, and stop it (TERM the group, then confirm) before you report; a helper you leave running is a leftover that pnpm -s fw reap --stop will later stop by identity.
- Never wait with an until/while loop on a file or output: run the command in the foreground, or in the background and act on its completion notice; CI waits use pnpm -s fw ci wait.
- Before reporting run each touched package's test script (not single files) incl. typecheck, node --test scripts/ci-paths.test.mjs and the apps/runner land-inputs test; declare every new read (CI trigger row, LandSpeed.checkShReads, land.ts reads) the tests ask for.
- After merging main, the files you measured or tested must still be in git diff main...HEAD.
- A relayed user message does not cancel a CI push or a step in this prompt.
- Runs that need workflow inputs (preset, fw, profile, target) are dispatched by the lead before launch when their run ids are in your prompt. The trajectory probe you start yourself, on your own pushed code: commit with the two message lines [ci:trajectory-probe] and [trajectory fw=part:variant,part:variant widths=390,1280 engines=both diagnostic] (or preset=name instead of fw; keys fw, preset, widths, engines and the bare word diagnostic, each at most once; a widths subset needs the bare word diagnostic; omit widths for a verdict run; a malformed line fails the run with its reason; a [trajectory ...] line without [ci:trajectory-probe] starts nothing, and only pnpm -s fw ci push reports that before the push, a plain git push does not), push in the allowed ci/* form and wait with pnpm -s fw ci wait --branch ci/<x> --workflow trajectory-probe (it picks the push run of your commit, never a dispatch). The run uses exactly those inputs; read them back from the step name starting trajectory inputs: or from the artifact trajectory-inputs, and report the run id you read. Details: docs/team/tools/trajectory-probe.md. If a run you need is neither in your prompt nor reachable this way, or a push is blocked in your sandbox, put the exact command as open[0] and report that part of the unit as not delivered; the review judges only runs that exist.
- Lean tasks: run sh lean/scripts/check.sh at your final commit; it must be green (the land queue refuses on any stage, the axiom check included).
- Never edit docs/team/work-graph.json (lead only): list any write outside your task's graph writes in your report.
- Hand back only after merging main and running \`pnpm -s fw land <your branch> --task <id> --dry\`; its last line must be \`VERDICT dry <id>\` (exit 0). Put that line in \`dry\`. Any other kind: fix it first (docs/team/tools/land.md).
- Report \`items\`: one per deliverable of the pinned unit and one per prior finding, each {id, status, evidence}. status: done (evidence = path:line or path:a-b, or run:<github run id>), pending (evidence = run:<id> of a run still going; also list it in \`runs\` as {id, state: running|complete|failed}), dispatch (a run only the lead can start; evidence = the exact command), followUp (outside the unit), undelivered (say why in open). A done item without a file:line or a run id is sent back. Then run \`pnpm -s fw review ready --report <json file> --task <id>\` (report = {items, runs, dry}), put its last VERDICT line in \`gate\`, and on returnToBuilder fix what it names and run it again before you hand back.
- Write docs/team/handoffs/<task>.md before you finish. End with the StructuredOutput call.`

const ITEM = { type: 'object', properties: { id: { type: 'string' }, status: { type: 'string', enum: ['done', 'pending', 'dispatch', 'followUp', 'undelivered'] }, evidence: { type: 'string' } }, required: ['id', 'status', 'evidence'] }
const RUN = { type: 'object', properties: { id: { type: 'string' }, state: { type: 'string', enum: ['running', 'complete', 'failed'] } }, required: ['id', 'state'] }
// items, runs, dry and gate are what the Lean gate (Fw.Plan.ReviewReady, `fw review ready`) reads. They are optional in the schema so an old-style
// handback still parses; the gate then sends it back (no items, no dry line).
const BUILD = { type: 'object', properties: { branch: { type: 'string' }, commit: { type: 'string' }, summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, open: { type: 'array', items: { type: 'string' } }, items: { type: 'array', items: ITEM }, runs: { type: 'array', items: RUN }, dry: { type: 'string' }, gate: { type: 'string' } }, required: ['branch', 'commit', 'summary', 'files'] }
// the gate agent returns the printed line; the script routes on the word after the id (no decision lives in this file)
const GATE = { type: 'object', properties: { line: { type: 'string' } }, required: ['line'] }
// severity (Lean Fw.Plan.ReviewReady.Sev): blocker refuses; fix-before-land is text the lead applies, then a checker re-checks it; follow-up is later work.
// accept comes from the last line of `fw review verdict` (Lean strictVerdict until the medium-only audit; then verdictOf: accept iff no blocker).
const VERDICT = { type: 'object', properties: { accept: { type: 'boolean' }, verdictLine: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'fix-before-land', 'follow-up'] }, where: { type: 'string' }, what: { type: 'string' } }, required: ['severity', 'where', 'what'] } } }, required: ['accept', 'findings'] }

// One task per run: the lead is notified when a run ends, so a bundled run holds an accepted task until its slowest
// neighbour finishes (user feedback 2026-10-21).
const tasks = args && args.task ? [args.task] : (args && args.tasks) || []
const voice = (args && args.voice) || ''
if (tasks.length !== 1) throw new Error(`build-review: one task per run (got ${tasks.length}); start one run per task`)
const t = tasks[0]

const scope = (t) => [
  t.unit ? `Pinned unit of decision: ${t.unit}. Items below it are follow-ups.` : '',
  t.limits ? `Accepted limits: ${t.limits}` : '',
  t.findings ? `Prior review findings (read every one; apply each exact fix or say why not): ${t.findings}` : '',
].filter(Boolean).join('\n')

const b = await agent(`Task ${t.id}.${t.worktree ? ` Work only in ${t.worktree}.` : ''}\n${t.prompt}\n${scope(t)}\n\n${voice}\n\n${PREAMBLE}`,
  { label: `build:${t.id}`, phase: 'Build', agentType: t.role, schema: BUILD, ...(t.worktree ? {} : { isolation: 'worktree' }) })
if (!b) return [{ task: t.id, build: null }]
// Evidence gate (task review-flow-v2): fwcore decides (`fw review ready`, Lean Fw.Plan.ReviewReady). Only the answer `review` spends an
// Opus review; dispatch, wait and returnToBuilder return the build to the lead with the gate lines. The builder's own `gate` line is not trusted.
// Run states are read by the gate agent itself, by run id (`fw ci state <id>`, one `gh run list`; never the builder's state field).
const report = JSON.stringify({ items: b.items || [], runs: b.runs || [], dry: b.dry || '' })
const g = await agent(`Run this in the main checkout (the parent of the path that git rev-parse --path-format=absolute --git-common-dir prints; fwcore is built there) with PATH="$HOME/.nvm/versions/node/v24.22.0/bin:$PATH", logging to your scratchpad file gate-${t.id}.log (agents/runner.md).
Step 1: the builder's report is the JSON below. For each run id in its runs array, read that run's state yourself: pnpm -s fw ci state <run id> (it prints "<id> running|complete|failed|unknown" from gh run list; never gh api, never gh run view). Replace every runs[].state with what it printed and ignore the builder's state field; an id that prints unknown gets state "failed". Also read the id of every item whose evidence is "run:<id>" with status pending the same way, and add it to runs if the builder left it out.
Step 2: pass the corrected report to: pnpm -s fw review ready --report - --task ${t.id} <<'REPORT' (heredoc body = the corrected report JSON).
Return its last VERDICT line as line (and any "item ..." or "fwcore:" lines above it as detail). The exit code (0 review, 21 wait, 22 dispatch, 23 returnToBuilder) goes with the line; do not interpret it.\nReport:\n${report}`,
  { label: `gate:${t.id}`, phase: 'Review', agentType: 'runner', schema: GATE })
// the last VERDICT line of the answer decides and must carry this task's id (escaped: ids hold - and .);
// runners append "Log: <path>" after it (wf_d2d71389 was sent back on a review-ready line)
const idRe = t.id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
// runners also put the line mid-text ('exit=0 | VERDICT ... review (note)', wf_73b9728f); the last match decides
const all = g && typeof g.line === 'string' ? [...g.line.matchAll(new RegExp(`VERDICT review-ready ${idRe} (review|wait|dispatch|returnToBuilder)\\b`, 'g'))] : []
const m = all.length ? all[all.length - 1] : null
const ready = m ? m[1] : 'returnToBuilder'
if (ready !== 'review') return [{ task: t.id, build: b, gate: ready, gateLine: g ? g.line : null, adv: null }]
const adv = await agent(`Adversarial review of task ${t.id}: branch ${b.branch} at ${b.commit} (read-only). Builder: ${b.summary}\nTask: ${t.prompt}\n${scope(t)}\nBuilder items: ${JSON.stringify(b.items || [])}\nBuilder dry-land line: ${b.dry}. Gate line: ${g.line}. Re-check both yourself, and the run states the builder reports, before you trust them (pnpm -s fw land ${b.branch} --task ${t.id} --dry; pnpm -s fw review ready; pnpm -s fw ci state <run id>).\nRun the tests yourself. Grade each finding: blocker (the unit is wrong, unproved or undelivered), fix-before-land (exact text the lead can apply), follow-up (outside the pinned unit or an accepted limit). Write the findings as JSON to a scratch file and run pnpm -s fw review verdict --findings <file> --task ${t.id}; return its last line as verdictLine and accept = whether it says accept.`,
  { label: `adv:${t.id}`, phase: 'Review', agentType: 'reviewer', schema: VERDICT })
return [{ task: t.id, build: b, gate: ready, adv }]
