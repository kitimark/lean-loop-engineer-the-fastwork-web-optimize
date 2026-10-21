#!/usr/bin/env node
// jev-datasets: labelled replay sets D1..D4 for the Jev trial, built from our own history. No Jev call, no write outside
// the output directory (default .cache/jev/, gitignored). Label rules and the id-hash split are Lean (Fw.Oracle.Labels);
// this file replays them from packages/contracts/golden/oracle/labels.jsonl and is checked against that golden by
// scripts/jev-datasets.test.mjs. TS stand-ins (no Lean source): the redaction below, the parsing of journals, run lists,
// logs and events, and the Fable classification-line finder.
// Usage: node scripts/jev-datasets.mjs [--sets d1,d2,d3,d4] [--out <dir>] [--logs-max 150] [--journals <workflows dir>]
//        [--events <events.jsonl>] [--ledger <ledger.json>] [--runs-dir <dir with runs-failure.json, runs-success.json>]
//        [--logs-dir <log cache>] [--no-gh: no gh call, cached logs only]
import { execFileSync } from 'node:child_process'
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
export const GOLDEN = path.join(here, '..', 'packages', 'contracts', 'golden', 'oracle', 'labels.jsonl')

// ---------------------------------------------------------------- Lean rules replayed from the golden

const lowerAscii = (s) => s.replace(/[A-Z]/g, (c) => c.toLowerCase())
const trimWs = (s) => s.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '')

/** The label rules, built from the golden rows (the constants come from Lean, the functions replay Fw.Oracle.Labels). */
export function makeRules(rows) {
  const one = (k) => {
    const r = rows.find((x) => x.kind === k)
    if (!r) throw new Error(`golden has no ${k} row`)
    return r
  }
  const split = one('split')
  const classes = one('classes').ids
  const words = one('words')
  const fphr = one('fable-phrases')
  const cphr = one('ci-phrases')
  const hasPhrase = (phrases, text) => {
    const t = lowerAscii(text)
    return phrases.some((p) => t.includes(lowerAscii(p)))
  }
  const fnv1a = (id) => {
    let h = split.offset
    for (const b of Buffer.from(id, 'utf8')) h = Math.imul(h ^ b, split.prime) >>> 0
    return h
  }
  const heldOut = (id) => fnv1a(id) % split.mod === 0
  const lowerTrim = (s) => trimWs(lowerAscii(s))
  const wordGrade = (w) => (words.table.find((p) => p[0] === w) ?? [null, null])[1]
  /** [grade, tier] or null */
  const severity = (s) => {
    const l = lowerTrim(s)
    const g = l.includes(words.followTag) ? 'follow-up' : wordGrade(/^[A-Za-z-]*/.exec(l)[0])
    return g === null ? null : [g, words.exact.includes(l) ? 'exact' : 'legacy']
  }
  const inUnit = (g) => g !== 'follow-up'
  const fableRegrade = (line) => (hasPhrase(fphr.dismiss, line) ? 'dismissed' : hasPhrase(fphr.lowValue, line) ? 'follow-up' : null)
  const regradeApplies = (nFindings, nParsed) => nParsed > 0 && nFindings === nParsed
  const applyRegrade = (orig, rg) => (rg === null ? orig : rg === 'dismissed' ? null : rg)
  const d1Label = (c) => (classes.includes(c) ? c : null)
  const ciCause = (f) => {
    if (!f.failure || !f.logKnown) return null
    if (f.infraSig && !f.codeSig) return 'infra'
    if (!f.covered) return null
    if (f.passedSameSha) return 'flake'
    if (f.codeSig && !f.infraSig) return 'ours'
    return null
  }
  const alertTriage = (aud, end, restartText) => {
    if (aud === 'user') return 'ask-user'
    if (aud === 'lead') return 'mitigate'
    if (end === 'user-acted') return 'ask-user'
    if (end === 'auto-resolved') return 'mitigate'
    if (end === 'lead-cancelled') return 'ignore'
    if (end === 'script-cancelled') return restartText ? 'mitigate' : null
    return null
  }
  return {
    classes, fnv1a, heldOut, severity, inUnit, fableRegrade, regradeApplies, applyRegrade, d1Label, ciCause, alertTriage,
    infraSig: (t) => hasPhrase(cphr.infra, t), codeSig: (t) => hasPhrase(cphr.code, t), hasPhrase,
  }
}

export const loadRules = (golden = GOLDEN) => makeRules(readFileSync(golden, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)))

// ---------------------------------------------------------------- redaction (TS stand-in)

const RULES = [
  [/\/private\/tmp\/claude-\d+\/[^\s"'`)\]]*/g, '<scratch>'],
  [/\/tmp\/claude-\d+\/[^\s"'`)\]]*/g, '<scratch>'],
  [/(?:\/Users\/|\/home\/|\\Users\\)[^/\\\s"'`:,;)\]}<>]+/g, '~'],
  [/-Users-[A-Za-z0-9_.]+/g, '-Users-<user>'],
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/g, '<email>'],
  [/\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/g, '<uuid>'],
  [/\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b/g, '<device>'],
  [/\ba[0-9a-f]{16}\b/g, '<agent>'],
  [/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, '<ip>'],
  [/\b(?:ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|xoxb-|xoxp-|sk-|sk_)[A-Za-z0-9_-]{8,}/g, '<token>'],
  [/\bAKIA[0-9A-Z]{8,}/g, '<token>'],
  [/Bearer [A-Za-z0-9._+/=-]{8,}/g, '<token>'],
]

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** Names of this machine's user, read at run time and never written: the login and the words of git's user.name and email. */
export function localNames() {
  const out = new Set()
  const add = (w) => { if (w && w.length >= 3) out.add(w) }
  try { add(os.userInfo().username) } catch { /* no passwd entry */ }
  for (const k of ['user.name', 'user.email']) {
    try {
      const v = execFileSync('git', ['config', k], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
      const w = k === 'user.email' ? v.split('@')[0] : v
      for (const x of w.split(/[^A-Za-z0-9]+/)) add(x)
    } catch { /* unset */ }
  }
  return [...out]
}

const nameRe = (names) => (names.length ? new RegExp(`(?<![A-Za-z0-9])(?:${names.map(esc).join('|')})(?![A-Za-z0-9])`, 'gi') : null)

/** The text with home paths, emails, ids, addresses, tokens and the given user names replaced by placeholders. */
export function redact(text, names = []) {
  let t = String(text ?? '')
  for (const [re, to] of RULES) t = t.replace(re, to)
  const nr = nameRe(names)
  return nr ? t.replace(nr, '<user>') : t
}

/** What still looks personal after redaction: empty for a clean text. */
export function leaks(text, names = []) {
  const found = []
  const probe = [
    ['home', /(?:\/Users\/|\/home\/|\\Users\\)(?!~)\S|-Users-(?!<user>)\S/],
    ['email', /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}/],
    ['uuid', /\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/],
    ['agent', /\ba[0-9a-f]{16}\b/],
    ['ip', /\b(?:\d{1,3}\.){3}\d{1,3}\b/],
    ['scratch', /\/(?:private\/)?tmp\/claude-\d+/],
  ]
  for (const [k, re] of probe) if (re.test(text)) found.push(k)
  const nr = nameRe(names)
  if (nr && nr.test(text)) found.push('name')
  return found
}

const cap = (s, n) => (s.length > n ? `${s.slice(0, n)} [truncated]` : s)

/** One text cell: redacted and capped; null when something personal survives (the row is then withheld). */
function cell(text, max, names) {
  if (text === null || text === undefined) return { v: null, ok: true }
  const v = cap(redact(text, names), max)
  return { v, ok: leaks(v, names).length === 0 }
}

/** Redact the string fields of a row; withheld = some cell still leaks. */
function cleanRow(fields, names) {
  const out = {}
  let ok = true
  for (const [k, [text, max]] of Object.entries(fields)) {
    const c = cell(text, max, names)
    out[k] = c.v
    ok = ok && c.ok
  }
  return { out, ok }
}

// ---------------------------------------------------------------- row assembly

const addSplit = (rules, row) => ({ ...row, split: rules.heldOut(row.id) ? 'heldOut' : 'calibration' })

/** D1 rows: incident mistake class. */
export function buildD1(rules, ledger, names = []) {
  const rows = []
  let withheld = 0
  for (const inc of ledger.incidents ?? []) {
    const { out, ok } = cleanRow({ title: [inc.title, 400], symptom: [inc.symptom, 1500], cause: [inc.cause, 1500] }, names)
    if (!ok) { withheld++; continue }
    rows.push(addSplit(rules, { id: String(inc.id), set: 'd1', ...out, label: rules.d1Label(inc.mistakeClass), labelSource: 'ledger' }))
  }
  return { rows, withheld }
}

/** Fable classification lines: item marker plus a classification word. */
const ITEM = /^\s*(?:[-*]\s+|\|\s*)?(?:\d+[.)]|[A-Za-z]{1,3}\d+(?:-\d+)?\b|\d+\s*\|)/
const CLASSWORD = /\breal\b|reviewer error|rule noise/i
export const fableClassLines = (advice) => String(advice ?? '').split('\n').filter((l) => ITEM.test(l) && CLASSWORD.test(l))

const readFirstLine = (file) => {
  const fd = openSync(file, 'r')
  try {
    const buf = Buffer.alloc(1 << 16)
    let acc = ''
    for (;;) {
      const n = readSync(fd, buf, 0, buf.length, null)
      if (n === 0) break
      acc += buf.toString('utf8', 0, n)
      const i = acc.indexOf('\n')
      if (i >= 0) return acc.slice(0, i)
    }
    return acc
  } finally {
    closeSync(fd)
  }
}

const section = (prompt, head, stop) => {
  const i = prompt.indexOf(head)
  if (i < 0) return null
  const rest = prompt.slice(i + head.length)
  const j = rest.search(stop)
  return (j < 0 ? rest : rest.slice(0, j)).trim()
}

const birth = (f) => { const s = statSync(f); return s.birthtimeMs || s.mtimeMs }

/** Every journal under the workflows directory: { wf, born, labels, results }. */
export function readJournals(dir) {
  const out = []
  if (!existsSync(dir)) return out
  for (const wf of readdirSync(dir)) {
    const jf = path.join(dir, wf, 'journal.jsonl')
    if (!existsSync(jf)) continue
    const labels = {}
    const results = []
    for (const l of readFileSync(jf, 'utf8').split('\n')) {
      if (!l) continue
      let j
      try { j = JSON.parse(l) } catch { continue }
      if (j.type === 'started') labels[j.agentId] = j.label
      else if (j.type === 'result') results.push(j)
    }
    out.push({ wf, dir: path.join(dir, wf), born: birth(jf), labels, results })
  }
  return out
}

/** D2 rows: review finding severity and in-unit, from adv:<task> results; Fable regrades by position. */
export function buildD2(rules, journals, names = []) {
  const reviews = []
  for (const jr of journals) {
    for (const r of jr.results) {
      const label = jr.labels[r.agentId] ?? ''
      if (!label.startsWith('adv:') || !r.result || typeof r.result !== 'object') continue
      let prompt = ''
      try { prompt = JSON.parse(readFirstLine(path.join(jr.dir, `agent-${r.agentId}.jsonl`))).message.content } catch { /* transcript gone */ }
      if (typeof prompt !== 'string') prompt = JSON.stringify(prompt)
      reviews.push({ task: label.slice(4), wf: jr.wf, born: jr.born, accept: r.result.accept, findings: r.result.findings ?? [], prompt })
    }
  }
  const byTask = new Map()
  for (const rv of reviews) byTask.set(rv.task, [...(byTask.get(rv.task) ?? []), rv])
  for (const list of byTask.values()) list.sort((a, b) => a.born - b.born).forEach((rv, i) => { rv.round = i + 1 })

  const regrades = new Map() // `${wf}|${task}|${i}` -> { regrade, source }
  const fableStats = { advices: 0, applied: 0, skipped: 0, regrades: 0 }
  for (const jr of journals) {
    for (const r of jr.results) {
      const label = jr.labels[r.agentId] ?? ''
      if (!label.startsWith('fable:') || typeof r.result !== 'string') continue
      fableStats.advices++
      const task = label.slice(6)
      const prior = (byTask.get(task) ?? []).filter((rv) => rv.born <= jr.born && rv.accept === false)
      const target = prior[prior.length - 1]
      const lines = fableClassLines(r.result)
      if (!target || !rules.regradeApplies(target.findings.length, lines.length)) { fableStats.skipped++; continue }
      fableStats.applied++
      lines.forEach((line, i) => {
        const rg = rules.fableRegrade(line)
        if (rg !== null) {
          regrades.set(`${target.wf}|${task}|${i}`, { regrade: rg, source: `fable:${jr.wf}` })
          fableStats.regrades++
        }
      })
    }
  }

  const rows = []
  let withheld = 0
  for (const rv of reviews) {
    const unit = section(rv.prompt, 'Pinned unit of decision:', /\n\s*Accepted limits:/)
    const limits = section(rv.prompt, 'Accepted limits:', /\n/)
    const task = section(rv.prompt, 'Task:', /\n\s*Pinned unit of decision:/)
    rv.findings.forEach((f, i) => {
      const sev = rules.severity(String(f.severity ?? ''))
      const rg = regrades.get(`${rv.wf}|${rv.task}|${i}`)
      const base = sev ? sev[0] : null
      const label = rules.applyRegrade(base, rg ? rg.regrade : null)
      const { out, ok } = cleanRow({
        task: [rv.task, 120], what: [f.what, 1500], where: [f.where, 400], severityText: [f.severity, 160],
        unit: [unit, 900], limits: [limits, 700], taskText: [task, 700],
      }, names)
      if (!ok) { withheld++; return }
      rows.push(addSplit(rules, {
        id: `${rv.task}#${rv.wf}#f${i + 1}`, set: 'd2', ...out, round: rv.round, hasUnit: unit !== null,
        label, inUnit: label === null ? null : rules.inUnit(label), tier: sev ? sev[1] : null,
        labelSource: rg ? rg.source : 'reviewer', regrade: rg ? rg.regrade : null,
      }))
    })
  }
  return { rows, withheld, fableStats, reviews: reviews.length }
}

/** The text of a failed-job log reduced to what shows the cause: no timestamp or step prefix, the last lines only. */
export function logTail(raw, lines = 40) {
  const keep = String(raw ?? '').split('\n').map((l) => l.replace(/^[^\t]*\t[^\t]*\t/, '').replace(/^\d{4}-\d\d-\d\dT[\d:.]+Z\s?/, ''))
  return keep.filter((l) => l.trim()).slice(-lines).join('\n')
}

/** D3 rows: CI failure cause from run lists and (a bounded sample of) failed-job log tails. */
export function buildD3(rules, failures, successes, logs, { successLimit = 1000, names = [] } = {}) {
  const passed = new Set(successes.map((s) => `${s.workflowName}|${s.headSha}`))
  const oldest = successes.length ? Math.min(...successes.map((s) => Date.parse(s.createdAt))) : Infinity
  const rows = []
  let withheld = 0
  for (const f of failures) {
    const tail = logs[String(f.databaseId)]
    const logKnown = typeof tail === 'string'
    const infraSig = logKnown && rules.infraSig(tail)
    const codeSig = logKnown && rules.codeSig(tail)
    const facts = {
      failure: f.conclusion === 'failure', logKnown,
      covered: successes.length < successLimit || Date.parse(f.createdAt) >= oldest,
      passedSameSha: passed.has(`${f.workflowName}|${f.headSha}`), infraSig, codeSig,
    }
    const { out, ok } = cleanRow({
      workflow: [f.workflowName, 80], branch: [f.headBranch, 120], event: [f.event, 40], title: [f.displayTitle, 300], logTail: [logKnown ? tail : null, 3000],
    }, names)
    if (!ok) { withheld++; continue }
    rows.push(addSplit(rules, {
      id: `run-${f.databaseId}`, set: 'd3', ...out, facts, label: rules.ciCause(facts), labelSource: 'lean-rule',
    }))
  }
  return { rows, withheld }
}

/** D4 rows: console alert steps, labelled by who the step was for and how it ended. */
export function buildD4(rules, events, names = []) {
  const rows = []
  let withheld = 0
  for (const p of events.filter((e) => e.type === 'step.post' && String(e.step ?? '').startsWith('alert-'))) {
    const later = events.filter((e) => e.step === p.step && e.seq > p.seq && (e.type === 'step.done' || e.type === 'step.cancel'))
    const last = later[later.length - 1]
    const end = !last ? 'open'
      : last.type === 'step.done' ? (last.actor === 'user' ? 'user-acted' : 'auto-resolved')
        : last.actor === 'lead' ? 'lead-cancelled' : 'script-cancelled'
    const aud = p.audience === 'user' || p.audience === 'lead' ? p.audience : 'unset'
    const restartText = /lead restarts/i.test(p.title ?? '')
    const { out, ok } = cleanRow({ title: [p.title, 400], body: [p.body ?? null, 1500] }, names)
    if (!ok) { withheld++; continue }
    rows.push(addSplit(rules, {
      id: String(p.step), set: 'd4', ...out, audience: aud, end, restartText, label: rules.alertTriage(aud, end, restartText), labelSource: 'lean-rule',
    }))
  }
  return { rows, withheld }
}

/** Counts per label, labelled and held-out sizes. */
export function summarize(rows) {
  const labels = {}
  let labelled = 0
  let heldOut = 0
  let heldOutLabelled = 0
  for (const r of rows) {
    const k = r.label ?? 'unlabelled'
    labels[k] = (labels[k] ?? 0) + 1
    if (r.label !== null) labelled++
    if (r.split === 'heldOut') { heldOut++; if (r.label !== null) heldOutLabelled++ }
  }
  return { rows: rows.length, labelled, heldOut, heldOutLabelled, labels: Object.fromEntries(Object.entries(labels).sort()) }
}

// ---------------------------------------------------------------- I/O glue (gh, files)

const gh = (args, timeout = 120000) => execFileSync('gh', args, { encoding: 'utf8', maxBuffer: 1 << 28, timeout })

/** Failed-job log tails for a bounded sample of failures (id-hash order), cached under the output directory; stops at the first rate-limit error. */
const realLogs = (rulesObj, failures, max, cacheDir, allowFetch) => {
  mkdirSync(cacheDir, { recursive: true })
  const sample = [...failures].sort((a, b) => rulesObj.fnv1a(String(a.databaseId)) - rulesObj.fnv1a(String(b.databaseId))).slice(0, max)
  const logs = {}
  let fetched = 0
  let stopped = null
  for (const f of sample) {
    const cf = path.join(cacheDir, `${f.databaseId}.txt`)
    if (existsSync(cf)) { logs[String(f.databaseId)] = readFileSync(cf, 'utf8'); continue }
    if (stopped || !allowFetch) continue
    try {
      const tail = logTail(gh(['run', 'view', String(f.databaseId), '--log-failed'], 90000))
      writeFileSync(cf, tail)
      logs[String(f.databaseId)] = tail
      fetched++
    } catch (e) {
      const msg = String(e.stderr ?? e.message)
      if (/403|rate limit/i.test(msg)) stopped = 'rate limit'
    }
  }
  return { logs, sampleSize: sample.length, fetched, stopped }
}

const arg = (argv, k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d }

function mainCheckout() {
  const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], { encoding: 'utf8' }).trim()
  return path.dirname(common)
}

export async function run(argv) {
  const sets = (arg(argv, '--sets', 'd1,d2,d3,d4')).split(',')
  const out = path.resolve(arg(argv, '--out', '.cache/jev'))
  const logsMax = Number(arg(argv, '--logs-max', '150'))
  const main = mainCheckout()
  const rules = loadRules()
  const names = localNames()
  mkdirSync(out, { recursive: true })
  const counts = {}
  const gaps = []
  const write = (name, rows) => writeFileSync(path.join(out, `${name}.jsonl`), rows.map((r) => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : ''))

  if (sets.includes('d1')) {
    const ledger = JSON.parse(readFileSync(arg(argv, '--ledger', path.join(main, 'docs/team/incidents/ledger.json')), 'utf8'))
    const { rows, withheld } = buildD1(rules, ledger, names)
    write('d1', rows)
    counts.d1 = { ...summarize(rows), withheld }
  }
  if (sets.includes('d2')) {
    const dir = arg(argv, '--journals', null)
    const proj = path.join(os.homedir(), '.claude', 'projects', main.replace(/\//g, '-'))
    const dirs = dir ? [dir] : existsSync(proj) ? readdirSync(proj).map((s) => path.join(proj, s, 'subagents', 'workflows')) : []
    const journals = dirs.flatMap((d) => readJournals(d))
    const { rows, withheld, fableStats, reviews } = buildD2(rules, journals, names)
    write('d2', rows)
    counts.d2 = { ...summarize(rows), withheld, reviews, fable: fableStats, exactTierRows: rows.filter((r) => r.tier === 'exact').length }
    if (!journals.length) gaps.push('d2: no workflow journals found')
  }
  if (sets.includes('d3')) {
    const runsDir = arg(argv, '--runs-dir', null)
    let failures
    let successes
    if (runsDir) {
      failures = JSON.parse(readFileSync(path.join(runsDir, 'runs-failure.json'), 'utf8'))
      successes = JSON.parse(readFileSync(path.join(runsDir, 'runs-success.json'), 'utf8'))
    } else if (argv.includes('--no-gh')) {
      failures = []
      successes = []
      gaps.push('d3: --no-gh and no --runs-dir, no run lists')
    } else {
      const fields = 'databaseId,conclusion,workflowName,headSha,headBranch,event,attempt,createdAt,displayTitle'
      failures = JSON.parse(gh(['run', 'list', '--status', 'failure', '--limit', '1000', '--json', fields]))
      successes = JSON.parse(gh(['run', 'list', '--status', 'success', '--limit', '1000', '--json', fields]))
    }
    const cacheDir = path.resolve(arg(argv, '--logs-dir', path.join(out, 'd3-logs')))
    const lg = realLogs(rules, failures, logsMax, cacheDir, !argv.includes('--no-gh'))
    const { rows, withheld } = buildD3(rules, failures, successes, lg.logs, { names })
    write('d3', rows)
    counts.d3 = { ...summarize(rows), withheld, failures: failures.length, successes: successes.length, logsRead: Object.keys(lg.logs).length, logSample: lg.sampleSize, logsFetchedNow: lg.fetched, stoppedBy: lg.stopped }
    if (lg.stopped) gaps.push(`d3: log fetch stopped by ${lg.stopped}`)
  }
  if (sets.includes('d4')) {
    const evp = arg(argv, '--events', path.join(main, '.fw-console/events.jsonl'))
    const events = existsSync(evp) ? readFileSync(evp, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean) : []
    const { rows, withheld } = buildD4(rules, events, names)
    write('d4', rows)
    counts.d4 = { ...summarize(rows), withheld, events: events.length }
    if (!events.length) gaps.push('d4: no console event log')
  }
  writeFileSync(path.join(out, 'counts.json'), JSON.stringify({ counts, gaps }, null, 2) + '\n')
  return { counts, gaps, out }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { counts, gaps, out } = await run(process.argv.slice(2))
  for (const [k, v] of Object.entries(counts)) console.log(`${k}: ${JSON.stringify(v)}`)
  for (const g of gaps) console.log(`gap: ${g}`)
  console.log(`written under ${path.relative(process.cwd(), out) || '.'}`)
}
