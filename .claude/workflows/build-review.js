export const meta = {
  name: 'build-review',
  description: 'Build one task (own worktree or a named one), then its adversarial review, with the fixed team preamble',
  whenToUse: 'Every build task the lead starts, one run per task so each finishes (and lands) on its own: args = { task: { id, role, prompt, lean?, worktree?, unit?, limits?, findings?, report? }, voice? } (report + worktree: lead resume path, review only, no build; report is a path or the report object inline; docs/team/tools/build-review.md)',
  phases: [{ title: 'Build' }, { title: 'Review' }, { title: 'Polish' }],
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
- Heavy local runs share one queue (docs/team/tools/slot.md) and each heavy command routes itself through it: run \`pnpm -s fw slot run --kind check --cache -- sh lean/scripts/check.sh\` and \`pnpm -s fw slot run --kind test --cache -- pnpm --filter <package> test\`, one per tool call (never chained with && or ;), on a clean committed tree; a bare \`sh lean/scripts/check.sh\` or package \`test\` also queues itself (no cache) and runs directly inside a slot or on CI. Dry lands: \`pnpm -s fw slot run --kind land --cache -- pnpm -s fw land <your branch> --task <id> --dry\`; Simulator work holds \`pnpm -s fw slot acquire --kind sim --lease <s>\` (then renew, release) instead of scripts/sim-lock.sh.
- Report \`dry\` exactly as the last VERDICT line printed by the dry land without --allow (never a line with --allow notes); list every file outside the task's writes in \`open\`.
- Lean tasks: run sh lean/scripts/check.sh at your final commit; it must be green (the land queue refuses on any stage, the axiom check included).
- Never edit docs/team/work-graph.json (lead only): list any write outside your task's graph writes in your report.
- Before the dry land, after merging main, run \`pnpm -s fw plan lint docs/team/work-graph.json\` in your worktree (main's graph against your build tree) and list every writesClosure error line it prints in \`open\`.
- Hand back only after merging main and running \`pnpm -s fw slot run --kind land --cache -- pnpm -s fw land <your branch> --task <id> --dry\`; its last line must be \`VERDICT dry <id>\` (exit 0). Put that line in \`dry\`. Any other kind: fix it first (docs/team/tools/land.md).
- Report \`items\`: one per deliverable of the pinned unit and one per prior finding, each {id, status, evidence}. status: done (evidence = path:line or path:a-b, or run:<github run id>), pending (evidence = run:<id> of a run still going; also list it in \`runs\` as {id, branch, state: running|complete|failed} (branch = the ci/* branch the run is on)), dispatch (a run only the lead can start; evidence = the exact command), followUp (outside the unit), undelivered (say why in open). A done item without a file:line or a run id is sent back. Then run \`pnpm -s fw review ready --report <json file> --task <id>\` (report = {items, runs, dry}), put its last VERDICT line in \`gate\`, and on returnToBuilder fix what it names and run it again before you hand back.
- Write docs/team/handoffs/<task>.md before you finish. End with the StructuredOutput call.`

const ITEM = { type: 'object', properties: { id: { type: 'string' }, status: { type: 'string', enum: ['done', 'pending', 'dispatch', 'followUp', 'undelivered'] }, evidence: { type: 'string' } }, required: ['id', 'status', 'evidence'] }
const RUN = { type: 'object', properties: { id: { type: 'string' }, branch: { type: 'string' }, state: { type: 'string', enum: ['running', 'complete', 'failed'] } }, required: ['id', 'branch', 'state'] }
const BUILD = { type: 'object', properties: { branch: { type: 'string' }, commit: { type: 'string' }, summary: { type: 'string' }, files: { type: 'array', items: { type: 'string' } }, open: { type: 'array', items: { type: 'string' } }, items: { type: 'array', items: ITEM }, runs: { type: 'array', items: RUN }, dry: { type: 'string' }, gate: { type: 'string' } }, required: ['branch', 'commit', 'summary', 'files'] }
// the gate agent returns the printed line; the script routes on the word after the id (no decision lives in this file)
const GATE = { type: 'object', properties: { line: { type: 'string' } }, required: ['line'] }
// severity (Lean Fw.Plan.ReviewReady.Sev): blocker refuses; fix-before-land is text the lead applies, then a checker re-checks it; follow-up is later work.
// accept comes from the last line of `fw review verdict` (Lean strictVerdict until the medium-only audit; then verdictOf: accept iff no blocker).
// Polish stage (task polish-in-flow): classes, scopes and cut verdicts are Lean (Fw.Plan.Polish via `fw polish`); this file passes text along.
const OUT = { type: 'object', properties: { line: { type: 'string' }, out: { type: 'string' } }, required: ['line'] }
const EDITS = { type: 'object', properties: { edited: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' } }, required: ['edited'] }
const CUTS = { type: 'object', properties: { cuts: { type: 'array', items: { type: 'object', properties: { path: { type: 'string' }, old: { type: 'string' }, new: { type: 'string' } }, required: ['path', 'old', 'new'] } } }, required: ['cuts'] }
const VERDICT = { type: 'object', properties: { accept: { type: 'boolean' }, verdictLine: { type: 'string' }, findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'fix-before-land', 'follow-up'] }, where: { type: 'string' }, what: { type: 'string' } }, required: ['severity', 'where', 'what'] } } }, required: ['accept', 'findings'] }

// One task per run: the lead is notified when a run ends, so a bundled run holds an accepted task until its slowest
// neighbour finishes (user feedback 2026-10-21).
const tasks = args && args.task ? [args.task] : (args && args.tasks) || []
const voice = (args && args.voice) || ''
if (tasks.length !== 1) throw new Error(`build-review: one task per run (got ${tasks.length}); start one run per task`)
const t = tasks[0]

// Checkpoint rule (task builder-checkpoint): a builder that stops without a report still leaves a state the lead can restart from.
const CHECKPOINT = (id) => `Checkpoint rule: write docs/team/handoffs/${id}.md right after your first CI push, and update it after each CI run finishes and before any wait longer than 10 minutes. First lines: your branch, your worktree path, the last commit sha, every CI run id with its state, what is verified, what is open. Commit it with your work. The lead restarts from this file if you end without a report.`

const scope = (t) => [
  t.unit ? `Pinned unit of decision: ${t.unit}. Items below it are follow-ups.` : '',
  t.limits ? `Accepted limits: ${t.limits}` : '',
  t.findings ? `Prior review findings (read every one; apply each exact fix or say why not): ${t.findings}` : '',
].filter(Boolean).join('\n')

// Lead resume path (task build-review-report-resume): args.task.report (a builder report JSON path) with args.task.worktree skips the build
// stage. One runner agent reads the report and reruns the dry land in the worktree; the exact last VERDICT line (any kind) replaces the report's dry field.
const RESUME = { type: 'object', properties: { report: BUILD, line: { type: 'string' } }, required: ['report', 'line'] }
const RESUME_DRY = { type: 'object', properties: { line: { type: 'string' } }, required: ['line'] }
const resumeDry = (r) => {
  const ms = r && typeof r.line === 'string' ? [...r.line.matchAll(/VERDICT \S+ [^\n]*/g)] : []
  return ms.length ? ms[ms.length - 1][0].trim() : (r && typeof r.line === 'string' ? r.line : '')
}
const resumed = async () => {
  // An inline report object is used as is: a runner echoing a large report dropped its items (wf_8aa275ef).
  const inline = typeof t.report === 'object'
  const r = await agent(`Resume of task ${t.id}: no build round. Run in the worktree ${t.worktree} (never cd outside it) with PATH="$HOME/.nvm/versions/node/v24.22.0/bin:$PATH", logging to your scratchpad file resume-${t.id}.log (agents/runner.md).
${inline ? '' : `Step 1: read the builder report JSON at ${t.report} and return it unchanged as report (branch, commit, summary, files, open, items, runs, dry).\n`}Step 2: from the worktree run exactly: pnpm -s fw slot run --kind land --cache -- pnpm -s fw land "$(git rev-parse --abbrev-ref HEAD)" --task ${t.id} --dry (no --allow). The branch is the worktree's own, from git rev-parse; never type it by hand. Return the last VERDICT line it printed (any kind), verbatim and whole, as line; do not edit, shorten or interpret it.`,
    { label: `resume-dry:${t.id}`, phase: 'Build', agentType: 'runner', schema: inline ? RESUME_DRY : RESUME })
  const rep = inline ? t.report : r && r.report
  return r && rep && typeof rep === 'object' ? { ...rep, dry: resumeDry(r) } : null
}
// A builder that ends without StructuredOutput makes agent({schema}) throw (incident inc-builder-no-result): treat it as the no-result record.
const attempt = async (f) => { try { return await f() } catch (e) { return null } }
const b = t.report && t.worktree
  ? await attempt(resumed)
  : await attempt(() => agent(`Task ${t.id}.${t.worktree ? ` Work only in ${t.worktree}.` : ''}\n${t.prompt}\n${scope(t)}\n\n${voice}\n\n${CHECKPOINT(t.id)}\n\n${PREAMBLE}`,
    { label: `build:${t.id}`, phase: 'Build', agentType: t.role, schema: BUILD, ...(t.worktree ? {} : { isolation: 'worktree' }) }))
// Builder with no structured result (it ended or crashed without StructuredOutput; incident inc-builder-no-result): hand the lead the place to
// restart from and skip every later stage. Branch and worktree path are in the handoff file the checkpoint rule made it write.
if (!b || typeof b.branch !== 'string' || typeof b.commit !== 'string') {
  return [{ task: t.id, worktree: t.worktree || 'isolated worktree: see git worktree list and the first lines of the handoff', branch: (b && b.branch) || 'see the handoff, or git branch --list "worktree-*"', handoff: `docs/team/handoffs/${t.id}.md`, state: 'no-result' }]
}
// Evidence gate (task review-flow-v2): fwcore decides (`fw review ready`, Lean Fw.Plan.ReviewReady). Only the answer `review` spends an
// Opus review; dispatch, wait and returnToBuilder return the build to the lead with the gate lines. The builder's own `gate` line is not trusted.
const report = JSON.stringify({ items: b.items || [], runs: b.runs || [], dry: b.dry || '' })
const g = await agent(`Run this in the main checkout (the parent of the path that git rev-parse --path-format=absolute --git-common-dir prints; fwcore is built there) with PATH="$HOME/.nvm/versions/node/v24.22.0/bin:$PATH", logging to your scratchpad file gate-${t.id}.log (agents/runner.md).
Step 1: the builder's report is the JSON below. For each run id in its runs array, read that run's state yourself: pnpm -s fw ci state <run id> --branch <its runs[].branch> (it prints "<id> running|complete|failed|unknown" from gh run list; never gh api, never gh run view). Replace every runs[].state with what it printed and ignore the builder's state field; an id that prints unknown gets state "failed". Also read the id of every item whose evidence is "run:<id>" with status pending the same way, and add it to runs if the builder left it out.
Step 2: write the corrected report JSON, and nothing else, to its own new file gate-${t.id}.json in your scratchpad with one heredoc (never append to it, never reuse the log file), check it with node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' <file>, then run: pnpm -s fw review ready --report <that file> --task ${t.id}. If the JSON check fails, rewrite the file once from the report below (wf_ffc0cfbf piped its log into --report).
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
const adv = await agent(`Adversarial review of task ${t.id}: branch ${b.branch} at ${b.commit} (read-only). Builder: ${b.summary}\nTask: ${t.prompt}\n${scope(t)}\nBuilder items: ${JSON.stringify(b.items || [])}\nBuilder runs: ${JSON.stringify(b.runs || [])}\nBuilder dry-land line: ${b.dry}. Gate line: ${g.line}. Re-check both yourself, and the run states the builder reports, before you trust them (pnpm -s fw slot run --kind land --cache -- pnpm -s fw land ${b.branch} --task ${t.id} --dry; pnpm -s fw review ready; pnpm -s fw ci state <run id> --branch <its runs[].branch>).\nRun the tests yourself, in the builder's worktree (git worktree list) with the same \`pnpm -s fw slot run --kind <k> --cache -- <command>\` lines the preamble gives builders: on the unchanged clean tree (and, for the dry land, the same main) they replay the builder's recorded passing result, same argv, exit code and VERDICT lines; any change runs them afresh. Grade each finding: blocker (the unit is wrong, unproved or undelivered), fix-before-land (exact text the lead can apply), follow-up (outside the pinned unit or an accepted limit). Write the findings as JSON to a scratch file and run pnpm -s fw review verdict --findings <file> --task ${t.id}; return its last line as verdictLine and accept = whether it says accept.`,
  { label: `adv:${t.id}`, phase: 'Review', agentType: 'reviewer', schema: VERDICT })
const onlyFixes = !!adv && (adv.findings || []).every((f) => f.severity === 'fix-before-land' || f.severity === 'follow-up')
if (!adv || (!adv.accept && !onlyFixes)) return [{ task: t.id, build: b, gate: ready, adv }]

// Polish: comment-sicko on the code and shell files of the diff, slop-checker cuts on its prose, both judged by Lean before
// anything is committed; skip-class files (generated, golden, snapshot) are never handed to an agent and edits to them are restored.
const MAIN = `Run in the main checkout (the parent of the path that git rev-parse --path-format=absolute --git-common-dir prints) with PATH="$HOME/.nvm/versions/node/v24.22.0/bin:$PATH", logging to your scratchpad file`
const run1 = (label, cmd, input) => agent(`${MAIN} ${label}-${t.id}.log (agents/runner.md). Run exactly: ${cmd}${input ? ` <<'JSON'\n${input}\nJSON` : ''}\nReturn its last VERDICT line as line and its whole stdout as out, verbatim: every path exactly as printed (absolute, never shortened to ~ or a placeholder), no log path.`,
  { label: `${label}:${t.id}`, phase: 'Polish', agentType: 'runner', schema: OUT })
const verdictWord = (r, kind) => {
  const ms = r && typeof r.line === 'string' ? [...r.line.matchAll(new RegExp(`VERDICT ${kind} ${idRe} (\\S+)`, 'g'))] : []
  return ms.length ? ms[ms.length - 1][1] : 'error'
}
const plan = await run1('polish-plan', `pnpm -s fw polish plan --branch ${b.branch} --task ${t.id}`)
const stages = verdictWord(plan, 'polish-plan')
if (stages === 'none' || stages === 'error') return [{ task: t.id, build: b, gate: ready, adv, polish: { stages, plan: plan ? plan.line : null } }]
const outLines = (plan.out || '').split('\n')
// plan lines: `worktree <absolute dir>`, `class <class> <mark> <relative path>`, `comments <mark> <absolute path>` (mark from Lean
// `mark`: # for shell and YAML, -- for Lean, // for TS) and `prose <absolute path>`. The runner may redact the absolute prefix
// (incident inc-polish-main-checkout: `<worktree>/...` sent comment-sicko into the main checkout), so every path is rebuilt here
// from the worktree line and the relative class paths, and polish stops when the worktree line is not a worktree.
const wtLine = outLines.find((l) => l.startsWith('worktree '))
const wt = wtLine ? wtLine.slice(9).trim() : ''
if (!/^\/.+\/\.claude\/worktrees\/[^/]+$/.test(wt)) return [{ task: t.id, build: b, gate: ready, adv, polish: { stages: 'error', plan: `polish-plan printed no worktree path (got "${wt}")` } }]
const rels = outLines.filter((l) => l.startsWith('class ')).map((l) => l.split(' ').slice(3).join(' '))
const relOf = (p) => rels.find((r) => p === r || p.endsWith(`/${r}`))
// comments lines: `comments <mark> <relative path> lines <lo-hi,lo-hi|none>`, the branch's own changed lines plus a margin (Lean
// Fw.Plan.Polish.reach, incident inc-polish-file-scope); `fw polish commit` restores any edit outside them.
const comments = outLines.filter((l) => l.startsWith('comments ')).map((l) => {
  const [mark, ...rest] = l.slice(9).split(' ')
  const at = rest.lastIndexOf('lines')
  return [mark, relOf((at < 0 ? rest : rest.slice(0, at)).join(' ')), at < 0 ? 'none' : rest.slice(at + 1).join('')]
}).filter(([, r]) => r).map(([mark, r, lines]) => `${wt}/${r} (comment mark ${mark}; edit only comments on lines ${lines}; any edit outside those lines is reverted)`)
const prose = outLines.filter((l) => l.startsWith('prose ')).map((l) => relOf(l.slice(6))).filter(Boolean).map((r) => `${wt}/${r}`)
const sicko = comments.length ? await agent(`Comment review of task ${t.id} (branch ${b.branch}) in the worktree ${wt}. Edit comments only, in these files and these line ranges only (the lines the builder changed, plus a margin), each with the comment mark its language uses (a shell or YAML file is never Lean or TS):\n${comments.join('\n')}\nNever edit a file outside ${wt} (the main checkout above all). Apply .claude/agents/comment-sicko.md. Edit with the Edit tool only, never sed -i or any command that writes a file. Never commit, never run git commands that write. Return the absolute paths you edited.`,
  { label: `comment-sicko:${t.id}`, phase: 'Polish', agentType: 'comment-sicko', schema: EDITS }) : null
const strays = sicko && sicko.edited ? sicko.edited.filter((p) => !p.startsWith(`${wt}/`)) : []
if (strays.length) return [{ task: t.id, build: b, gate: ready, adv, polish: { stages, edited: sicko.edited, strays, commit: 'not run: comment-sicko edited files outside the worktree; the lead restores them' } }]
const slop = prose.length ? await agent(`Prose review of task ${t.id} (branch ${b.branch}) against .claude/skills/no-slop/SKILL.md, in these files only:\n${prose.join('\n')}\nReturn each cut as {path, old, new}: old is an exact substring that occurs once in the file, new its shorter text. Keep every number, commit, path:line, status word and identifier; Lean refuses a cut that drops one (Fw.Plan.Polish.cutSafe).`,
  { label: `slop:${t.id}`, phase: 'Polish', agentType: 'slop-checker', schema: CUTS }) : null
const cuts = slop && slop.cuts && slop.cuts.length ? await run1('polish-cuts', `pnpm -s fw polish cuts --branch ${b.branch} --task ${t.id} --cuts - --apply yes`, JSON.stringify({ cuts: slop.cuts })) : null
const commit = await run1('polish-commit', `pnpm -s fw polish commit --branch ${b.branch} --task ${t.id}`)
const committed = verdictWord(commit, 'polish-commit')
// the polish commit lands only through the same dry land as the build; a failing line goes back to the lead with the result
const dry = committed === 'committed' ? await run1('polish-dry', `pnpm -s fw slot run --kind land --cache -- pnpm -s fw land ${b.branch} --task ${t.id} --dry`) : null
// a failed commit is reported with its reason and the `cleanup:` line fw polish commit prints (the worktree is clean again, Lean Fw.Plan.Polish.settle)
const failed = committed === 'error' || committed === 'refused'
const outTail = failed && commit && typeof commit.out === 'string' ? commit.out.split('\n').filter((l) => l.trim()).slice(-12).join('\n') : null
const cleanup = outTail ? (outTail.split('\n').filter((l) => l.startsWith('cleanup')).pop() || 'cleanup: none printed; the lead checks the worktree') : null
return [{ task: t.id, build: b, gate: ready, adv, polish: { stages, edited: sicko ? sicko.edited : [], cuts: cuts ? cuts.line : null, commit: committed, ...(failed ? { reason: outTail, cleanup } : {}), dry: dry ? dry.line : null } }]
