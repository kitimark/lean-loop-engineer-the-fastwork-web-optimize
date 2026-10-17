---
id: 2026-10-17-event-automation-design
kind: note
title: "An automated console for v2: event sourcing, agents never hand-write status"
status: review
created: 2026-10-17
updated: 2026-10-17
authors: [agent:automation-designer]
topics: [console, events, hooks, lean, automation]
links:
  plan: docs/plan/PLAN.md (rev 3; read only, not edited)
  notes:
    - research/kickoff/05-lean-proofs-and-backend.md
    - research/kickoff/06-architecture-and-tooling.md
    - research/kickoff/07-claude-code-agent-teams.md
    - research/kickoff/08-chat-forensics/README.md
  lean_scratch: research/kickoff/10-automation-and-proof/lean-scratch/02-events/Console.lean (v1 of the sketch) and ConsoleV2.lean (after verification)
  v1: ../fastwork-com-web-optimize @ eae1bb9 (read only)
---

# An automated console for v2: event sourcing, agents never hand-write status

**What you asked for:** in v1, agents had to update parts of the console by hand. v2 should automate that, prove as
much as it can in Lean, and show every theorem as a math equation you can read.

**Status words:** CONFIRMED = checked against a doc, source or file today (cited). MEASURED = a number from v1 data,
with the command that reproduces it. INFERRED = a design choice or expectation that a spike or test must still check.

> **Verification fixes (2026-10-17).** A verification pass found five design faults in the first version of this
> note; all are fixed below and in `lean-scratch/02-events/ConsoleV2.lean` (MEASURED: builds on Lean 4.35.0, 362
> lines, 18 theorems, 7 `#guard` examples, no `sorry`; axioms ⊆ {propext, Classical.choice, Quot.sound}).
> (1) A rejected event was marked *seen*, so a fact that arrived early could never be applied: the reconciler's
> re-send with the same key was a duplicate. Keys are now marked seen **only on acceptance**. (2) `landed` was a git
> fact that the reducer could refuse, so main could hold a commit the console called "not landed". Landing is now a
> decision `landRequested` (gated by `ready`) plus a fact `landed` that is never refused and raises `violation`
> when it has no accepted request; main lives in a console-api-owned bare repo. (3) Review was forgeable: `actor` is
> a role, not an identity. Reviews now carry `signedBy`, the reducer refuses a review by the card's owner or any of
> its builders, and identity comes from a PreToolUse capability hook (§6.4). (4) Some idempotency keys mixed
> identity with version (usage, device, hooks); §6.2 separates them. (5) The manual-input list, `next` and
> staleness disagreed with notes 01 and 03; §4.4 and §5 now use the merged catalogue. Numbers that differed across
> the notes are reconciled in the rev-5 delta (`docs/plan/rev5-delta.md`, "Canonical numbers").

## 0. Answer first

1. **Nobody writes status.** Every console view (stage, owner, next action, ETA, needs-you, staleness) is a pure
   function of one append-only event log: `view = f(project(log))`. Agents have **no write path** to the log or the
   state. They can only (a) be observed, by Claude Code hooks, git and file and device watchers, or (b) send a
   *request* through `pnpm fw`, which console-api checks and then carries out itself.
2. **Facts come from processes agents do not control.** "Screen passed" is written by the console-api job that ran
   the screen. "Built" and "landed" come from git. "Device verdict" comes from `fwcore verdict` over the device job's
   data. An agent that *claims* a screen pass is rejected (proved: `unauthorized_rejected`). **What is unforgeable
   today is facts and your decisions only.** Lead and reviewer *roles* on the CLI socket are claims; they become
   unforgeable only once the PreToolUse capability hook in §6.4 binds them to Claude Code's agent identity (planned,
   SPK-t). Independently of that, a review by the card's owner or any of its builders is refused by the reducer
   (`review_independent`, MEASURED in `ConsoleV2.lean`).
3. **Hooks are for speed, reconcilers are for correctness.** Each fact has a primary producer (a hook) and a
   reconciler that re-reads the source of truth (git refs, the artifact store, transcripts, usbmuxd). Both build the
   same idempotency key **from fields both of them can see** (§6.2; never an emitter-side counter), so a fact seen
   twice counts once (proved: `apply_idem`). A key is marked seen only when its event is accepted, so a fact that
   arrived too early is applied when the reconciler re-sends it (MEASURED `#guard` in `ConsoleV2.lean`; the general
   `reorder_converges` theorem is still to prove). For git facts from agent commits the reconciler is the **only**
   producer (§3.2). A lost hook event only delays the console.
4. **The reducer is Lean.** `apply : State × Event → State` and the view functions live in `fwcore` (new module
   `Fw/Spec/Console`, which takes over rev 3's later-tier `Stage`/`Step`). The fixed sketch `ConsoleV2.lean` (362
   lines) **builds today on Lean 4.35.0 with 18 theorems, 7 `#guard` examples, no `sorry`, and only the standard
   axioms** (MEASURED, §8). It includes the landing rule over *every* replayed log: a card that is landed **without a
   violation** had approval, a passing screen, an independent review and (if needed) a device verdict at the landed
   commit (`land_requires`). A landing without an accepted request is never hidden: it is recorded as landed **and**
   flagged `violation` (an incident on your needs-you list). The production module merges these semantics with note
   03's data structures (HashMap/HashSet, `modifyGet`).
5. **The remaining manual inputs are one merged catalogue** (§5, based on note 01 §5): your step answers, proposal
   decisions, priority list, session bookings and decision answers; the lead's approve, land request, drop and
   rulings; the owner's card open, park (with a typed predicate), wait-on-agent and hand-back result; the reviewer's
   verdict; and an optional note of at most 200 characters that is shown but never read by the reducer. Each is a
   typed command that the reducer can reject, never a file edit. v1's derivable `waiting-on` values and stage words
   are gone. v1's `next` (the agent's *plan text*) is not derivable; it moves into the card text, and the console's
   own column is renamed **next action** (the next console command), which is a different thing.
6. **Math view (§7):** every theorem is written as an equation next to its Lean name, for example
   `δ(δ(s,e),e) = δ(s,e)` (applying an event twice equals applying it once). A build check keeps the two in sync.

## 1. What v1 made agents maintain by hand (MEASURED)

v1 already had an event-ish store per tool, but agents fed it by hand at every transition. CLAUDE.md told every agent
to "report your workstream's state at every transition, when a wait starts or ends, and on resume" (v1 `CLAUDE.md`
l.383-390; `tools/status.mjs` l.6-8).

| What agents did by hand | v1 count | Reproduce (v1 repo @ eae1bb9 unless noted) |
|---|---|---|
| Status-board history entries (all rows) | **4,384** entries on 296 rows: 3,883 `set`, 289 `created`, 138 `priority`, 74 `sync` | `jq '[.[].history[]] \| length' console/status.json`; `jq -r '[.[].history[].action] \| group_by(.) \| map("\(.[0]) \(length)") \| .[]' console/status.json` |
| Fields typed into those entries | `note` 4,133; `state` 2,820; `waitingOn` 2,221; `next` 1,977; `resumeOn` 322 | `jq -r '[.[].history[] \| .changes \| keys[]] \| group_by(.) \| map("\(.[0]) \(length)") \| .[]' console/status.json` |
| ... of which written by the lead | 615 `set` entries (the largest single writer) | `jq -r '[.[].history[] \| select(.action=="set") \| .by] \| group_by(.) \| map({k:.[0],n:length}) \| sort_by(-.n) \| .[0]' console/status.json` |
| Distinct Bash calls `tools/status.mjs set` | **4,914** canonical (note 03's command: `grep -Ec 'status\.mjs set'` over the 105,638 unique Bash tool-use ids). The command in this row finds only a **subset**, 2,754 (about 56 %), because its regex needs the path in the first 40 characters | `rg --no-messages -N -o -g '*.jsonl' '"id":"toolu_[A-Za-z0-9]+","name":"Bash","input":\{"command":"[^"]{0,40}tools/(status\|console\|finding\|incident)\.mjs [a-z]+' ~/.claude/projects/<v1-project-dir>/ \| sed -E 's/.*"id":"(toolu_[A-Za-z0-9]+)".*tools\/([a-z]+)\.mjs ([a-z]+)$/\1 \2 \3/' \| sort -u \| awk '{print $2" "$3}' \| sort \| uniq -c \| sort -rn` |
| Other hand calls to console tools (same command) | `console thread` 1,190, `console proposal` 351, `finding post` 266, `incident update` 234, `console wait` 180, `incident open` 137, `console post` 83, `console progress` 74, `console ack` 53 | same |
| Step part acks by agents (agents told the console "ready / recording / done" for the parts they drove) | 252 `ack` history entries over 166 steps (6 of them have a null state, which is why note 01 counts 246) | `jq -r '[.history[]?.action // empty] \| .[]' console/steps/C-*.json \| sort \| uniq -c` |
| Agent messages about board rows | 496 SendMessage calls mention `status.mjs set`, "board row" or "status row" | `grep -c -E 'status\.mjs set\|board row\|status row' .local/v1-chat-digest/out/sendmessage.jsonl` (this repo; local data) |

Context from the earlier notes: 575 board writes a day and 8 stale-board incidents [01 §B.3]; 55 status nags and 39
crossed messages [08]; `status.mjs` grew `stale`, `check`, `sync` and `seed` subcommands only to repair hand-written
rows (`tools/status.mjs` l.53-69). The lead ran `status.mjs sync` after every landing (74 times) because landings
did not update rows by themselves.

Board size note: this table reads the export `console/status.json` (4,384 entries on 296 rows). Note 01 reads the
live mirror `$M/status/*.json` (4,412 entries on 299 rows). The live store is canonical: it is the store agents
actually wrote, while the committed export is an older copy with 3 fewer rows (INFERRED from the counts). Both keep
at most 100 history entries per row, and 8 rows hit that cap, so the true total is a little higher (note 01 §1.1).

**Reading (INFERRED):** most of v1's manual work recorded things a machine already knew, such as the commit landed,
the step was answered, the agent was waiting on the queue, or the Chrome slot was held. The free-text `note` and
`next` fields carried most of the new information: **4,140 entries** carry `note` or `next` (865 carry nothing
else; MEASURED: `jq '[.[].history[]|select(.changes|(has("note") or has("next")))]|length' console/status.json`).
The earlier figure 6,110 added the two field counts and so double-counted entries with both. Not all of the rest is
derivable either: "waiting on agent X for an answer or artifact" (255 writes) and "parked until X" (218) do not
follow from the card stage, so §5 keeps typed commands for them. Narrative goes into the card text and notes
(content), not into status (state).

## 2. The principle: three kinds of input, one writer

| Kind | Example | Who produces it | Can an agent cause it? |
|---|---|---|---|
| **Observed fact** | commit `s1` on branch `exp/foo`; `main` moved to `s1`; the subagent stopped; the phone detached; an artifact with key `k` was stored | hooks, git, watchers, transcript tailer, console-api's own jobs | Only indirectly, by doing the real thing (committing, stopping). It cannot *assert* the fact |
| **Request** | "screen card X", "land card X", "open card Y" | `pnpm fw` (CLI, sandboxed) → console-api socket | Yes. The reducer accepts or rejects it, and the *outcome* is an observed fact made by console-api |
| **Decision** | your step answer, proposal choice, priority list; the reviewer's verdict; the lead's approval | console-web (you), `pnpm fw` (lead, reviewer) | Only the role the authority table (`may`, §4.3) allows. Your decisions only from console-web with a token agents cannot read (§6.4) |

**One writer.** console-api is the only process that appends to `events.jsonl` (rev 3 §2.2 already says so). Every
input above reaches it as a message; it stamps `seq`, `ts` and `actor`, appends, fsyncs, then applies the reducer.

## 3. (a) Event producers, each verified

### 3.1 `pnpm fw` (requests; console-api runs the work)

`fw` never writes a file of console state. Each verb sends one request line to console-api's Unix socket and prints
the reducer's answer (accepted, or rejected with its reason).

| Verb | Request event | Who may send | What console-api then does, and the fact it emits |
|---|---|---|---|
| `fw card open <slug> --part --class --k` | `card.open` | owner, lead, you | registers the card; the file watcher hashes `card.md` (§3.5) |
| `fw card approve <slug>` | `card.approve` | lead, you | checks that the card text (with predictions) was registered before any screen data |
| `fw run …` / `fw screen <slug>` | `job.request {kind: counts \| screen}` | any agent | queues the job; the job emits `job.started`, `artifact.stored {key, sha256}`, `screen.result {card, sha, pass, perEngine}` with actor `script` |
| `fw gate [--part]` | `job.request {kind: gate}` | any agent | runs the gate in console-api's runner, not in the agent's shell, and emits `gate.result {sha, pass, failing[]}` |
| `fw device <slug>` | `job.request {kind: device}` | owner | queues for the next booked session; posts the preflight step itself; emits `device.result` and `verdict.result` (from `fwcore verdict`) |
| `fw review <slug> --sha --accept\|--reject --reasons` | `review.verdict {signedBy}` | reviewer | the reducer accepts it only if `sha` = the card's current build head **and** `signedBy` (the verified agent identity, §6.4) is neither the card's owner nor any agent that built a commit on it |
| `fw land <slug>` | `land.request` (a decision) | lead | accepted only if the card is land-ready; console-api then does the ff-only merge into **its own bare repo** (§3.2); the **git reconciler** emits the fact `landed` |

This makes rev 3's rule "agents never hold the phone; long runs live in console-api" (§3.2) the general rule: work
whose result is a fact runs in console-api. v1's runners died with their agent (I-221, I-240, I-256 [08]).

### 3.2 Git facts (observed by console-api's reconciler; git hooks only as a poke)

CONFIRMED against https://git-scm.com/docs/githooks (read 2026-10-17):
- **`reference-transaction`** takes one argument, the state: `preparing`, `prepared`, `committed` or `aborted`. It
  reads one line per ref update on stdin, `<old-value> SP <new-value> SP <ref-name> LF`. "The exit status of the hook
  is ignored for any state except for the 'preparing' and 'prepared' states." **Use (revised):** only in
  console-api's own bare repo, where console-api itself runs the fast-forward, so the hook runs in console-api's
  process and not in an agent's sandbox: in state `committed`, a line for `refs/heads/main` → a poke to the
  reconciler, which emits `landed`. It cannot block anything.
- **`post-commit`** "takes no parameters ... and cannot affect the outcome of git commit". In agent worktrees it may
  only touch the poke file (below); it is not a producer.
- **`post-merge`** takes a squash flag, does not run when the merge fails on conflicts, and the page does not say
  whether a fast-forward triggers it. **Not used**: `reference-transaction` covers ff-only landings exactly.
- Hooks live in `$GIT_DIR/hooks` or `core.hooksPath`. Linked worktrees share the common directory's hooks (INFERRED:
  check with `git rev-parse --git-path hooks` inside a worktree on Day 1).

**Git hooks are not a producer for agent commits (corrected after verification).** Git hooks run *inside the
committing process*, so for an agent's commit they run in that agent's Bash sandbox, not outside it as Claude Code
hooks do (CONFIRMED by the two docs together). Such a hook cannot write the state directory (`denyWrite`) and must
not use the CLI socket, which can never produce `git` facts. `git -c core.hooksPath=/dev/null commit` also skips
every hook. So:
- **The git reconciler in console-api is the primary and only producer of `built` and `landed`** (§3.7). It polls the
  refs every few seconds and also reacts to FSEvents on the ref files and reflogs. An optional git hook may only touch
  a "poke" file inside the worktree to make the reconciler look sooner; it carries no data.
- **Main is physically unwritable by agents.** The sandbox lets sandboxed commands in a linked worktree write the
  shared `.git` so that `git commit` can update refs (CONFIRMED, sandboxing doc, "Git worktrees"); only `hooks/` and
  `config` stay denied. An agent could therefore run `git update-ref refs/heads/main …` or `git branch -f main` in a
  shared repo. In v2 the **landing branch `main` lives in a bare repo owned by console-api**, outside every
  worktree's common directory and inside the sandbox's `denyWrite` set. Agents hand over branches only through
  `fw land`, and console-api fetches the branch and fast-forwards its own `main`. SPK-t checks that
  `git update-ref refs/heads/main` from a sandboxed worktree fails against that repo.
- If a landing still appears without an accepted `land.request` (the bare repo was bypassed, or you pushed by hand),
  the reducer records it as landed **and** sets `violation` (an incident on needs-you). It never refuses the fact,
  because a console that refuses facts shows a wrong board (v1's lesson, `status-board.md:74`).

### 3.3 Claude Code hooks (observed facts about agents)

CONFIRMED against https://code.claude.com/docs/en/hooks, read 2026-10-17. The documented events are `SessionStart`,
`Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`,
`PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`,
`SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`,
`ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`,
`PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult` and `SessionEnd`.

**Common input fields** (every event): `session_id`, `prompt_id` (absent before the first prompt), `transcript_path`,
`cwd`, `scratchpad_dir`, `permission_mode` (not every event), `hook_event_name`. `effort` (`{level}`) is present
only "for events within a tool-use context", not on every event. Inside a subagent or in-process teammate the input
also carries **`agent_id`** ("Unique identifier for the subagent or in-process teammate the hook fires in") and
**`agent_type`** (the agent's name, e.g. `"Explore"`). `agent_id` exists **only** for subagents and in-process
teammates; split-pane teammates are separate sessions (INFERRED), so agent liveness is keyed on
`(session_id, agent_id?)`, never on `agent_id` alone. The doc warns that
`transcript_path` "is written asynchronously and may lag", so `last_assistant_message` is the source for a final
reply.

| Hook (matcher) | Payload fields used (verbatim names) | Event it emits | v1 problem it removes |
|---|---|---|---|
| `SessionStart` (`startup\|resume\|clear\|compact\|fork`) | `source`, `model`, `agent_type`; on resume or fork `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd` | `agent.session {source, coldWake}` | cold wakes cost 24 % of $ [08 §3] |
| `SubagentStart` (agent type) | `agent_id`, `agent_type` | `agent.started` | the hand-kept roster; "who is alive" questions |
| `SubagentStop` (agent type) | `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `stop_hook_active` | `agent.stopped` + usage summary (tailer reads `agent_transcript_path`) | rows left "working" after their agent died |
| `TeammateIdle` (no matcher) | `teammate_name`, `agent_id` (v2.1.290+; may be absent); `team_name` is deprecated | `agent.idle` | the wake gap: 214 matches of I-274 [08] |
| `TaskCreated` / `TaskCompleted` (no matcher) | `task_id`, `task_subject`, `task_description?`, `teammate_name?`, `agent_id?` | `task.created` / `task.completed` | hand-posted progress |
| `PostToolUseFailure` (`Bash`) | `tool_name`, `tool_input`, `tool_use_id`, `error`, `is_interrupt`, `duration_ms` | `tool.failed {class}` (counted per role, never shown one by one) | 3,046 isolation refusals went unseen for days [08] |
| `PreCompact` / `PostCompact` (`manual\|auto`) | `trigger`, `custom_instructions` / `compact_summary` | `agent.compacted` | the naming rule lost at compaction; 125 lead compactions [08] |
| `Notification` (`permission_prompt\|idle_prompt\|agent_needs_input`) | `message`, `title?`, `notification_type` | `attention.needed {kind}` → a needs-you row "approve the prompt in the terminal" | approvals that waited unseen |
| `StopFailure` (`rate_limit\|overloaded\|billing_error`…) | `error`, `error_details?` | `agent.blocked {error}` → one banner | the weekly limit stopped the lead plus up to 5 agents, 3 times [08] |
| `SessionEnd` | `reason` | `agent.session.end` (best effort only: SessionEnd hooks have a default 1.5 s timeout, and in `-p` mode async hooks still running at teardown are killed, "outcome cancelled"; CONFIRMED) | — |
| `WorktreeRemove` (no matcher) | `worktree_path` | `worktree.removed` | stale worktree rows |

**Deliberately not used as producers:**
- `WorktreeCreate`: a hook here "replaces that default git behavior" and must return the path (CONFIRMED), so it is
  not a passive observer. `git worktree add` run through Bash does not trigger it either.
- `PostToolUse` on every tool: too chatty; the transcript tailer gives the same usage data. The one exception is a
  `PostToolUse` hook matched on `Bash` and filtered to `pnpm fw *`, used only for the audit join in §6.4.
- `type: "http"` hooks: they would POST straight to console-api, but "Non-2xx status: non-blocking error. Connection
  failure: non-blocking error" (CONFIRMED). The event is then lost silently. A command hook with a spool (below) is
  used instead.

**Transport (corrected after verification).** One small, unit-tested emitter `.claude/hooks/emit.mjs` handles every
observer hook. It runs **synchronously and fast** (target under 100 ms; a unit test enforces it) and **prints nothing
to stdout**: an async hook's stdout JSON (`additionalContext`, `systemMessage`) is delivered to Claude on the next
turn (CONFIRMED), and a sync hook's stdout JSON is also parsed for decision fields (INFERRED from the hooks doc's
JSON-output section), so the emitter must stay silent. It (1) builds the
event with a key made from payload fields the reconciler can also see (§6.2), (2) writes it to the **spool**,
`<state>/spool/<pid>-<n>.json`, by an atomic rename, and exits. It does not wait on the socket; console-api drains
the spool at start, on FSEvents, and every 5 s. **Agent end is not taken from `SessionEnd`** (it can be cut off, see
the table): an agent counts as ended at the latest of `SubagentStop` and the reconciler's transcript-idle check. Hooks run outside the Bash sandbox "with your full access" (CONFIRMED, sandboxing doc), so they
can write the state directory and agents' shells cannot. `.claude/hooks` is a protected path for sandboxed commands,
and `Edit(/.claude/**)` is already `ask` in rev 3 §8.3, so an agent cannot quietly change the producers.

Duplicate config is safe: "If you define the same handler in more than one settings file, it runs once"
(CONFIRMED). All matching hooks run in parallel, with no documented order, which is why order comes from console-api's
`seq` and never from hooks.

### 3.4 Transcript tailing (usage)

A console-api watcher tails `~/.claude/projects/<project>/<session>.jsonl` and `<session>/subagents/**/agent-*.jsonl`
(paths CONFIRMED in [07 §8]) with a byte-offset cursor per file. It emits `usage {agent, model, in, out, cacheRead,
cacheWrite5m, cacheWrite1h}` per assistant stream record. Because several stream records share one `message.id` and
the **last** one is authoritative (the dedupe fix of rev 3 §8.3), this is an **upsert**, not a keyed fact: the event
is `usage.set {messageId, …}` with key `usage:<message.id>:<byteOffset>`, and the reducer keeps the last record per
`messageId` (last writer wins). Theorem to add: the usage state equals "last record per id" over any log
(`usage_last_wins`). The plain "first key wins" rule would have kept the first, incomplete record. This replaces `pnpm fw usage` runs
by an agent. The `SubagentStop` hook only nudges the tailer to flush that agent's file now.

### 3.5 File watchers (`results/`, artifact store, cards)

- **Artifact store** (`<git-common-dir>/fw/artifacts`): on a new file, console-api re-hashes it and emits
  `artifact.stored {key, sha256, bytes}`. A file whose hash does not match its key gives `artifact.corrupt`, which is
  an incident, never a result. Jobs already emit this event; the watcher is the reconciler for it.
- **Cards** (`results/experiments/*/card.md`): on change, the watcher parses the frontmatter with zod and emits
  `card.text {card, sha256, hasPrediction, k}`. The reducer can then enforce rev 3 §9.2 "prediction present before any
  data": `card.approve` is rejected unless a `card.text` with `hasPrediction = true` exists, and a `screen.result` with
  a `seq` earlier than the first such `card.text` marks the card `postdiction`. This replaces a rule agents had to
  remember with an ordering check on `seq`.
- **Notes and reviews** (`research/notes/**`, `results/**/review.md`): `doc.changed {path, sha256}`, used only to link
  content from rows.

Implementation: `@parcel/watcher` or `fs.watch` with a full rescan every 60 s, because macOS FSEvents can coalesce
changes (INFERRED; the rescan is the reconciler).

### 3.6 Device watcher (no LLM)

Ported from v1 `tools/usblink.mjs` and `tools/lib/usbmux.mjs`, which already read usbmuxd's device list over
`/var/run/usbmuxd` and classify `ok / unplugged / usb-lost / proxy-stale / proxy-down / unknown` (v1 `usblink.mjs`
l.7-15). In v2 it runs inside console-api and polls every 5 s:
- usbmuxd: the attached list and the attach number. A `Listen` subscription would push changes; it is INFERRED to work
  with Apple's daemon, so keep the poll.
- `ios_webkit_debug_proxy` on `:9221/json`, WDA `GET /status`, lock state and thermal state.

It emits `device.state {lane, state, attach, prevSeq}` **only on change**, keyed on the *transition*
`dev:<lane>:<prevSeq>→<state>` (`prevSeq` = the seq of the lane's previous accepted state). The earlier key
`dev:<lane>:<state>:<attach>` repeated when a state flapped on one attach (ok → proxy-stale → ok), so the second `ok`
was dropped as a duplicate and the console showed proxy-stale for good. The reducer also treats "same state as now"
as a no-op, so a re-sent transition is harmless. A state that
needs your hands posts one step (`step.posted`, actor `script`) and cancels it itself when the state recovers. v1 left
one re-plug waiting 11 h 41 min [08]; v2 still needs your hands for that, but no agent needs to notice it first.

### 3.7 Scheduled scripts (no LLM) and reconcilers

| Script (in console-api) | Every | Emits |
|---|---|---|
| git reconciler (the **only** git producer): compare `git for-each-ref refs/heads` in every worktree's repo and in console-api's bare `main` repo with the last observed values | 2-10 s, on FSEvents for refs and reflogs, and on a poke file | `built` / `landed`, keyed `git:<ref>:<old>:<new>` |
| spool drain | 5 s | the spooled events |
| artifact rescan | 60 s | `artifact.stored` for any file not yet in the log |
| transcript rescan (cursor check) | 60 s | missed `usage` |
| stall check: an agent with a finished background task and no hook event for N min | 60 s | `agent.stalled` → one wake message (rev 3 §8.5) |
| digest | per card stage change | nothing; it renders from the log |

There is no `tick` event for staleness: age is computed at read time as `now - lastAt` (§4.4), so time needs no
writes. A `tick {now}` event is used only where time must *change* state (lease expiry, rev 3's device queue), as in
the sketch's `Lease.step` (`05-lean-sketch/Fw/Spec/Lease.lean` l.33-60).

## 4. (b) The projection

### 4.1 The event envelope (zod is the source of truth; Lean mirrors it)

```ts
// packages/contracts/src/event.ts
export const Actor = z.enum(['user', 'lead', 'owner', 'reviewer', 'script', 'git', 'hook']);
export const EventEnvelope = z.object({
  v: z.literal(1),                      // envelope version; body versions are in `type`, e.g. "screen.result@1"
  key: z.string().min(8),               // idempotency key, fixed by the producer at emit time (§6.2)
  seq: z.number().int().nonnegative(),  // assigned by console-api; the only order
  ts: z.number().int(),                 // console-api receive time, ms, monotone (§6.3)
  pts: z.number().int().optional(),     // producer time, diagnostics only
  actor: Actor,                         // stamped by console-api from the channel, never from the payload
  src: z.object({ kind: z.enum(['cli', 'cc-hook', 'git-hook', 'watcher', 'job', 'web']),
                  session: z.string().optional(), agentId: z.string().optional(),
                  agentType: z.string().optional(), toolUseId: z.string().optional() }),
  type: z.string(),                     // "card.open@1", "screen.result@1", ...
  body: z.unknown(),                    // validated per type by a discriminated union
});
```

The Lean mirror is `Fw.Console.Event` (`key`, `ts`, `actor`, `body`) in the sketch, with `Body` as an inductive type
with one constructor per accepted type. `fwcore samples` emits golden JSON for each constructor, and zod must parse
it byte for byte. That is rev 3's existing TL2 contract test (§5.2), extended to events.

### 4.2 Storage

- **Location: outside the repo and outside `.git`.** For example `~/.fw-console/<repo-id>/{events.jsonl,
  snapshots/, spool/, run/cli.sock, secret/}`. **Not** `<git-common-dir>/fw/`: in a linked worktree the sandbox
  "allows writes to the main repository's shared `.git` directory so commands such as `git commit` can update refs"
  (CONFIRMED, sandboxing doc). An agent's sandboxed script could therefore write there.
- `events.jsonl` is append-only, one JSON line per event, written as: append, then `fsync`, then apply. On restart,
  console-api loads the newest snapshot `state@<seq>.json` whose reducer hash matches, then replays the tail.
- Snapshots are sound because `project(L₁ ⧺ L₂) = foldl δ (project L₁) L₂`. This is theorem `project_append`
  (§7). A snapshot is just `project L₁`.
- Git gets daily *exports* (`results/console/<date>.events.jsonl.gz`, no personal data) for the write-up, never the
  live file.

### 4.3 The reducer

`δ = apply : State × Event → State` (Lean, `fwcore` op `console.apply`, plus `console.replay` for whole logs):

```
apply s e =
  if key(e) ∈ seen(s) then s                           -- duplicate: no-op
  else if check s e = ok then
         (accept s e) with seen := key(e) :: seen(s)   -- valid: change state, remember the key
  else s                                               -- invalid: no change at all; console-api logs the
                                                       --   refusal next to the event, not in the state
```

(Corrected after verification. The first version also marked a *rejected* key as seen, so an early fact could never
be applied when re-sent: MEASURED with the log opened, approved, `screened(s1)` keyed `job:J:result` (refused, no
head yet), `built(s1)`, the same `screened(s1)` again: stage stuck at `screen` in `Console.lean`, `review` in
`ConsoleV2.lean`.)

- `check` first applies the **authority table** `may : Actor → Body → Bool` (who may cause what: for example only
  `script` may emit `screened` and `swiped`, only `git` may emit `built` and `landed`, only `lead` or `user` may emit
  `landRequested`, only `user` may emit `stepAnswered`). It then applies the per-type rules: the card exists; the
  step is still open; the sha equals the build head; the reviewer is independent. **A `landed` fact for a known card
  is never refused** (`landed_fact_accepted`); if it has no accepted request for that sha, or the card is not ready,
  it sets `violation`.
- **Evidence is keyed by commit.** A card stores `head`, `screenAt`, `reviewAt` and `deviceAt` as shas. A new `built`
  sets `head` and clears the rest, so any rebuild voids old evidence automatically. In v1 this was a manual "re-run
  the screen after a rebuild" habit.
- Rejected events stay in the log with their reason. The console shows them in a "refused" list per card, and the
  `fw` CLI prints the reason at once.
- Performance: a Node → Lean round trip costs **17.6 µs** (MEASURED in note 03 with `bench-roundtrip.mjs`); note 05
  measured ≈141 µs with the same method (child_process + readline) on a different binary and payload, and the gap is
  not explained yet (INFERRED: JSON codec and payload size). Either way, 100,000 events replay in under a second in
  note 03's benchmark (0.28-0.54 s). This sketch keeps `seen` as a list (O(n) per event, O(n²) per replay); the
  production module uses note 03's HashSet and `modifyGet`, and the 100k benchmark is re-run on the merged reducer.

### 4.4 Every console view is a formula (nobody writes it)

| Column | Definition | Where it is computed |
|---|---|---|
| **stage** | `stage(c)`: `land` if landed; else `question` if not approved; `build` if no head; `screen` if `screenAt ≠ head`; `review` if `reviewAt ≠ head`; `device` if the card needs the device and `deviceAt ≠ head`; else `landReady` | Lean `stage` |
| **owner** (whose move) | a table by stage: question → lead (approve); build → the card's owner agent; screen → `script` (shows queue position); review → reviewer; device → you if a step is open, else the device queue; landReady → lead (`fw land`) | Lean (planned total function; not yet in the sketch) |
| **next action** | the exact next console command or button for that stage, e.g. "`fw review exp-a --sha s1`", or "Answer step C-12 (swipe A/B)". This is **not** v1's `next` (an agent's plan text, e.g. "build the exact variant, then counts in Chrome and the Simulator"); plan text lives in the card | Lean (planned string table) |
| **needs-you** | `∃` open step for this card ∨ a proposal awaiting your decision ∨ an unresolved `attention.needed` (permission prompt) ∨ the card is in `device` with no booked session | Lean `needsYou` (+ two extra sources) |
| **age / stale** | one definition, shared with note 01 T6: `stale_λ(c, t) ⟺ t − last(c) ≥ λ_c ∧ liveWaits(c) = ∅`. `λ_c` is **frozen when the card enters its stage**: p90 of that stage's past durations in the log at that moment (default 2 h until 5 samples). Freezing matters: if λ were recomputed from the whole log at read time, a row could stop being stale with no event on it (MEASURED counterexample with last(c) = 5: stale at λ = 10, now = 20, since 15 ≥ 10; λ moves to 20; not stale at now = 21, since 16 < 20). A row with a live wait or queue entry is never stale (`stale_live`). Amber at `λ_c`, red at `2λ_c` | Lean `stale` (λ_c and liveWaits are inputs) |
| **owner alive** | `now − lastAt(agent)`, where `lastAt(agent)` is the last hook event for that agent, keyed `(session_id, agent_id?)` | Lean (planned; agents are not yet in the sketch's `State`) |
| **ETA** | `queuePos × median(job duration) + median(remaining time in stage)`, from the log, with the sample count shown | TS `packages/model` (fitted numbers stay in TS, rev 3 §3.3) |

Under rev 3 §8.5 the owner had to send `waiting-for: lead|device|user` with a hand-back. Waiting on the lead to
*land*, on the device or on you is now derived: an owner is waiting whenever its card's stage belongs to someone
else. Two kinds of waiting are **not** derivable and stay typed commands (§5): waiting on another agent for an answer
or artifact (`fw wait --on agent:<id> --for <kind>`), and waiting on a lead *ruling* (`decision.requested`).

**The UI** (console-web, shadcn `DataTable` + SSE) has no editable status fields. Each cell has a "why" popover that
lists the events (seq, type, actor, age) that produced it, so "what does this mean" questions (25 in v1 [08]) are
answered by the provenance. The only forms are the commands in §5. The reducer's refusal reason appears inline under
the form.

## 5. (c) The only manual inputs

**One catalogue.** The first version of this section listed 13 inputs, note 01 §5 listed a different set, and note
03 kept `note` events: three catalogues. The rev-5 catalogue is **note 01 §5 (23 rows)**, which merges all three. In
short:
- **you** (console-web only): step answer and cancel, proposal decision, priority list, session booking, decision
  answer, best-build pick when several candidates remain, thread posts and "answered / not answered";
- **lead**: card approve, land request, drop, lead rulings (`decision.answer` with `on: lead`), queue move;
- **owner**: card open, park with a typed predicate, wait on another agent, ask the lead for a ruling, hand-back
  result, an optional note;
- **reviewer**: review verdict (refused unless the reviewer is independent of the card);
- **any agent**: job requests (screen, gate, run, device), knowledge-base and bug commands.

Each is a typed command (zod on the way in, `check` in Lean at apply time). None is a file edit. The optional note
(≤ 200 characters) is **shown but never read by the reducer**, so it cannot change any derived field (`says_inert`
in note 01, `note_preserves_needsYou` in note 03).

**Content is not state.** The card text, review text and notes are files in git. The console links them by hash
(`card.text`, `doc.changed`) and never copies them into state. v1's `next` (the agent's plan text) has no state
equivalent: plan text goes into the card, and the console's **next action** column (§4.4) is derived.

## 6. (d) Failure modes, and how each is handled and tested

### 6.1 Summary

| Failure | Handling | Guarantee | Test |
|---|---|---|---|
| **Lost event** (hook crashed, socket down, SessionEnd cut at 1.5 s, async hook killed at teardown in `-p` mode) | the emitter writes the spool synchronously; reconcilers re-derive facts from the sources of truth (git refs, artifact files, transcripts, usbmuxd) every 2-60 s; agent end = the latest of `SubagentStop` and the transcript-idle check, never `SessionEnd` alone | eventual: a lost *fact* comes back within one reconcile period. A lost *decision* cannot happen: console-web waits for the reducer's ack before it shows "saved" | drop-k fault-injection replays converge to the same state after one reconcile pass |
| **Duplicate event** (retry, hook plus reconciler, spool replay) | idempotency key built from fields both producers see (§6.2), checked in `apply` | `δ(δ(s,e),e) = δ(s,e)` (`apply_idem`, proved for the v2 reducer); re-delivery of an *accepted* event is a no-op | proved; plus fast-check: random duplication leaves `project` unchanged |
| **Hook failure** (non-zero exit, timeout) | observers are non-blocking by design: they exit 0 after a fast spool write, and "Exit codes other than 0 or 2 are non-blocking errors" (CONFIRMED); a short `timeout` caps a stuck emitter. Only `spawn-guard` uses `"onFailure": "block"` (v2.1.295+, CONFIRMED) | a hook bug never blocks an agent; the reconciler covers its facts | `emit.mjs` unit tests (no socket, full disk, bad JSON) |
| **Clock skew** (container, Simulator or worktree processes; a wall-clock jump) | order = `seq` only; `ts` = console-api's clock made monotone (`max(prevTs, now)`); `pts` kept for diagnostics, alarm when `\|pts − ts\| > 5 s` for local producers; spooled events take `ts = clamp(pts, prevTs, now)` | `lastAt` never decreases (`lastAt_mono`); staleness is monotone in `now` (`stale_mono`) | proved; a golden log with a backwards wall clock |
| **Out-of-order facts** (e.g. `screened` for `s1` before `built s1` was seen) | refused as "stale sha" and logged; **the key is not marked seen**, so the reconciler's re-send with the same key is applied once `built` is in (corrected; the first sketch marked refused keys seen, and the card stayed stuck, MEASURED) | a refusal changes nothing (`reject_keeps`: δ(s,e) = s); the `ooo` `#guard` in `ConsoleV2.lean` reaches stage `review`. The general theorem `reorder_converges` (a permutation within the per-subject causal order gives the same π, after one reconcile pass) is **not proved yet** | reorder fault injection (G3) |
| **Crash between append and apply** | append and fsync, then apply; on restart, replay from the last snapshot | `project_append` | `kill -9` loop test |
| **Torn last line** | on start, a final line that does not parse is cut back to the last `\n` and logged as an incident with its bytes | — | write-truncation test |
| **Schema change** | `type@n` versions; pure **upcasters** `n → n+1` in `packages/contracts`; the log is never rewritten; snapshots carry the reducer and upcaster hashes and are dropped on mismatch (full replay) | old logs replay under new code | every `type@n` has a golden fixture; upcast → zod parse → `fwcore` accept, in TL2 |
| **Agent forges a role** on the CLI socket | see §6.4: a PreToolUse capability hook binds the request to Claude Code's agent identity before console-api accepts it (planned, SPK-t) | facts and your decisions cannot be forged (proved for the reducer; the channel stamping is an L3 premise). Lead and reviewer roles are unforgeable only once the capability hook is in. A review by the card's owner or builder is refused whatever role is claimed (`review_independent`) | spoof tests: a CLI `screened` or `stepAnswered` is refused (`unauthorized_rejected`, `only_user_answers`); a builder's self-review is refused (`#guard` in `ConsoleV2.lean`); a request without a valid capability is refused (adapter test) |
| **Landing outside the console** (an agent moves main, or you push by hand) | main lives in console-api's bare repo (§3.2); the `landed` fact is never refused | `landed ∧ ¬violation ⟹ ready` (`land_requires`); a landing without an accepted request sets `violation` and raises an incident | `rogue` `#guard` in `ConsoleV2.lean`; SPK-t: `git update-ref refs/heads/main` from a sandboxed worktree fails |
| **console-api down** | producers spool; `fw` prints "console offline, request not sent" and exits 3 (it never queues a decision silently) | nothing is lost except requests, and those are retried by hand | — |

### 6.2 Idempotency keys (fixed at emit time, persisted with the spooled record)

| Producer | Key | Why it dedupes across producers |
|---|---|---|
**Rule (after verification): a key names one fact's identity, never its version.** Where a value can change for
the same identity, the event is an upsert with its own last-writer-wins theorem, not a keyed fact.

| Producer | Key | Why it dedupes across producers |
|---|---|---|
| git reconciler (the only git producer, §3.2) | `git:<ref>:<old>:<new>` | one ref transition is one fact |
| artifact (job or rescan) | `art:<artifactKey>` | content addressed |
| transcript | `usage.set` keyed `usage:<message.id>:<byteOffset>`; the reducer keeps the **last** record per `message.id` | identity = message id, version = stream position; `usage_last_wins` (to prove): the usage state equals the last record per id over any log |
| Claude Code hook | `cc:<session_id>:<hook_event_name>:<agent_id \| tool_use_id \| prompt_id>` | built only from payload fields the reconciler also sees (session id, event name, agent or tool-use id); **no emitter counter** (`pseq` could not be recomputed by the reconciler, and a counter shared by parallel hook processes would need a lock). Events that repeat for the same ids (e.g. `TeammateIdle`) add the transcript's last-entry uuid, which the reconciler can also read |
| device watcher | `dev:<lane>:<prevSeq>→<state>` | a *transition* is one fact; ok → proxy-stale → ok gives two distinct keys. The reducer also ignores "same state as now" |
| job runner | `job:<jobId>:<phase>` | one result per job phase |
| CLI and web commands | `cmd:<uuid>`, made by the client and reused on retry | a double-click or retry is one command |

### 6.3 Why order and time come from console-api alone

Producers run in different processes and clocks: Linux containers, the Simulator, worktree shells and the phone. If
the reducer used producer time, two machines could disagree about which event came first. It uses `seq` instead, so
replay is exactly reproducible. Time enters only as data (`ts`), as in rev 3 §5.1 ("Time is data").

### 6.4 "Agents have no write path to console state": how it is enforced

1. **Location.** State lives in `~/.fw-console/<repo-id>/`, outside every working directory and outside `.git` (§4.2).
   The Bash sandbox's default write scope is "the working directory, a per-user temp directory, and directories
   you've added", and the scope reaches child processes: "all commands running inside the sandbox, including their
   child processes, respect them" (CONFIRMED, sandboxing doc).
2. **Deny rules for the built-in file tools**, which run outside the sandbox and follow permission rules instead:
   ```jsonc
   "permissions": { "deny": [ "Edit(~/.fw-console/**)", "Write(~/.fw-console/**)", "Read(~/.fw-console/secret/**)" ] },
   "sandbox": {
     "enabled": true,
     "allowUnsandboxedCommands": false,                 // no dangerouslyDisableSandbox retry
     "filesystem": { "denyWrite": ["~/.fw-console"], "denyRead": ["~/.fw-console/secret"] },
     "network":    { "allowUnixSockets": ["~/.fw-console/run/cli.sock"] }   // the only door: requests
   }
   ```
   The permissions doc says why the sandbox is needed: Read and Edit deny rules "don't apply to ... arbitrary
   subprocesses that read or write files indirectly, like a Python or Node script that opens files itself. For
   OS-level enforcement ... enable the sandbox" (CONFIRMED). Path anchors `~/` and `//` are CONFIRMED for permission
   rules. The same `~` form in `sandbox.filesystem.*` is also CONFIRMED (sandboxing doc: "`~/.kube` is relative to
   your home directory").
3. **No `excludedCommands` for `pnpm fw`.** `fw` lives in each agent's worktree and can be edited there, so running
   it unsandboxed would hand an agent full access. Docker, the device drivers and the land merge run inside
   console-api, which is started by you, not by an agent.
4. **Your authority.** console-web gets a session token from `~/.fw-console/<repo-id>/secret/web.token`, which is
   read-denied to agents (both rules above). Only requests that carry it can produce `actor = user`. The CLI socket
   can never produce `user`, `script` or `git`.
5. **Role claims on the CLI socket** (lead, owner, reviewer) are **bound to identity before acceptance**, not
   audited afterwards (corrected; the first version only audited them, so a builder could claim `reviewer` and
   review its own work, MEASURED with the original sketch: stage `landReady`). Design:
   - A synchronous `PreToolUse(Bash)` hook matched to `pnpm fw *` runs outside the sandbox and can return
     `updatedInput` (CONFIRMED, hooks doc). It appends a single-use capability
     `--cap HMAC(secret, agent_type ‖ tool_use_id ‖ sha256(cmd))`. The secret is read-denied to agents.
   - console-api verifies the capability, maps `agent_type` to the role table, and stamps `signedBy` (the agent's
     identity) on the event. A request without a valid, unused capability is refused.
   - Independently of the role, the reducer refuses a review whose `signedBy` owns the card or built any commit on it
     (`review_independent`, proved in `ConsoleV2.lean`).
   - **What is unforgeable today**: facts (`script`, `git`) and your decisions (`user`). Lead and reviewer roles
     become unforgeable once the capability hook passes SPK-t; until then they are claims.
6. **A code gate.** Only `apps/console-api/src/store/**` may import the event-store module (a grep gate in MVP,
   dependency-cruiser later). This takes up rev 3's §2.2 rule "one writer".
7. **Fallback if SPK-t fails** (the sandbox breaks builds or tests): run console-api as a separate macOS user under
   launchd, with the state directory at mode 0700 owned by that user. That gives OS-level separation without the
   sandbox, at the cost of a one-time setup step for you.

8. **Main is not in any agent's repo.** The landing branch lives in console-api's bare repo inside the state
   directory (§3.2). Agents push or hand over their branch through `fw land`; only console-api fast-forwards main.

New spike: **SPK-t** (named SPK-q in the first version of this note; renamed because PLAN rev 4 uses SPK-q for the styling-neutrality baseline). With the sandbox on, `allowUnixSockets` set to the CLI socket and `allowUnsandboxedCommands:
false`: (a) a named worktree subagent can run `pnpm fw gate`, the tests and `git commit` with zero refusals (with
SPK-o); (b) `node -e "fs.appendFileSync(<state>/events.jsonl, 'x')"` from that agent fails; (c) the Write tool on
the state directory is denied; (d) `pnpm fw screen` reaches the socket; (e) `git update-ref refs/heads/main …` and
`git branch -f main` against console-api's bare repo fail from a sandboxed worktree; (f) the PreToolUse capability
hook adds `--cap` and console-api refuses a request with a missing, wrong or reused capability; (g) `emit.mjs`
finishes in under 100 ms and prints nothing.

### 6.5 Testing: golden replays

| Test | What | Pass condition |
|---|---|---|
| G0 Lean examples | `#guard` lines in `Fw/Spec/Console.lean` (7 in `ConsoleV2.lean`: the land-ready path, an out-of-order screen applied on re-send, a rogue landing flagged as violation, the normal land path, a land request on an unready card refused, a builder's self-review refused, duplicates as no-ops) | `lake build` |
| G1 v1 replay | converter `fw v1:events` maps v1's `console/status.json` history (4,384 entries), `console/steps/*.json` (166 steps; post, start, ack, answer, cancel) and v1's `git log main` into v2 events with synthetic keys. Replay and compare the **derived** stage with v1's **hand** state at each moment, through a mapping of v1's 15 states onto v2 stages | measures what automation fixes: the share of v1 hand states that contradicted git or the steps at the time (the cases `status.mjs check` and `stale` existed for). This is a measurement, not a pass/fail gate |
| G2 enforcer precision | the staleness alarm and `agent.stalled` replayed over G1's log | ≥ 90 % precision before any alarm reaches you (rev 3 §2.2 rule) |
| G3 fault injection | take a golden log and duplicate, drop then reconcile, reorder within a subject, truncate the last line, or skew `pts` | final state equals the fault-free state (drop and reorder: after one reconcile pass). The reorder line is INFERRED until `reorder_converges` is proved; it was **false** for the first sketch (refused keys were marked seen) and holds for the `ooo` example in `ConsoleV2.lean` |
| G4 contracts | zod ⇄ Lean golden fixture per `type@n`; upcasters | byte-equal round trip |
| G5 oracle | until Day 9 a TS reducer runs Days 4-8. fast-check, 2,000 random logs: TS view = `fwcore console.replay` view | equal; after Day 9 the TS reducer is deleted |

## 7. The math view: each theorem as an equation (in sync with Lean)

Notation: a log is `L = (e₁, …, eₙ)`. `S₀` is the empty state. `δ` is the reducer `apply`. The projection is
`π(L) = δ(…δ(δ(S₀, e₁), e₂)…, eₙ)` (Lean `project`, a left fold). `seen(s)` is the set of keys already applied.
`key(e)`, `actor(e)` and `body(e)` are an event's fields. For a card `c`: `head(c)` is its current build commit;
`scr(c)`, `rev(c)` and `dev(c)` are the commits its screen, review and device evidence belong to; `last(c)` is the
time of its latest event. `⊥` means "none".

The table describes the **fixed** reducer, `ConsoleV2.lean` (all MEASURED: proved there, Lean 4.35.0). `ok(s,e)`
means `check(s, e)` accepts `e`. `viol(c)` is the card's violation flag; `rb(c)` is the agent recorded as its
reviewer; `builders(c)` are the agents that built commits on it; `owner(c)` is its owner agent.

| # | Lean name | Equation | In words |
|---|---|---|---|
| T1 | `apply_seen` | key(e) ∈ seen(s) ⟹ δ(s, e) = s | an event already accepted changes nothing |
| T2 | `apply_idem` | δ(δ(s, e), e) = δ(s, e) | applying an event twice equals applying it once |
| T3 | `reject_keeps` | ¬ok(s, e) ⟹ δ(s, e) = s | a refused event changes nothing at all, not even `seen`, so the same fact can be applied later |
| T4 | `project_append` | π(L₁ ⧺ L₂) = foldl δ (π(L₁)) L₂ | a snapshot of a prefix plus the tail equals the full replay |
| T5 | `unauthorized_rejected` | (actor(e), body(e)) ∉ May ⟹ ¬ok(s, e) | an actor can only cause what the table allows |
| T6 | `only_user_answers` | body(e) = answer(·) ∧ actor(e) ≠ user ⟹ δ(s, e) = s | only you can answer a step |
| T7 | `landed_fact_accepted` | body(e) = landed(c, ·) ∧ actor(e) = git ∧ c ∈ cards(s) ⟹ ok(s, e) | a git landing of a known card is never refused |
| T8 | `land_requires` (via `project_inv`) | ∀L, ∀c ∈ cards(π(L)): landed(c) ∧ ¬viol(c) ⟹ approved(c) ∧ head(c) ≠ ⊥ ∧ scr(c) = head(c) ∧ rev(c) = head(c) ∧ (¬needsDevice(c) ∨ dev(c) = head(c)) | in *every* state any log can produce, a landing without a violation had approval, a passing screen, an accepted review and (if needed) a device verdict, all for the commit that landed |
| T9 | `landReq_ready` | ∀L, ∀c ∈ cards(π(L)): landReq(c) ≠ ⊥ ∧ ¬landed(c) ⟹ ready(c) | an accepted land request is only ever held by a ready card |
| T10 | `review_independent` | ∀L, ∀c ∈ cards(π(L)), ∀r: rb(c) = r ⟹ r ≠ owner(c) ∧ r ∉ builders(c) | the recorded reviewer neither owns the card nor built on it |
| T11 | `stale_mono` | t ≤ t′ ∧ stale(λ, t, w, c) ⟹ stale(λ, t′, w, c) | for a fixed (frozen) limit λ and live-wait count w, once stale a row stays stale until an event touches it |
| T12 | `stale_live` | w > 0 ⟹ ¬stale(λ, t, w, c) | a row with a live wait is never stale |
| T13 | `built_resets` | ¬landed(c) ∧ approved(c) ⟹ stage(step_t(built(c, sha, a), c)) = screen | a new build sends the card back to screen |

Still in the first sketch only (`Console.lean`, not yet ported): `lastAt_mono` (a card's last-event time never moves
backwards) and `answer_once` (a closed step is never answered again). To prove next: `reorder_converges`,
`usage_last_wins`, `stage_own_evidence` (the stage advances only on its own evidence), `agent_events_only` (note 03).

**What T8 does and does not say.** It says the console's flag `landed ∧ ¬violation` is never set without the
evidence. It does **not** say that a landing without evidence cannot happen; that is what the bare repo, the
sandbox and SPK-t (e) are for, and if it happens anyway the console shows it as a violation instead of hiding it.

Definitions, also as math:
- `stage(c)` = land if landed(c); else question if ¬approved(c); else build if head(c) = ⊥; else screen if
  scr(c) ≠ head(c); else review if rev(c) ≠ head(c); else device if needsDevice(c) ∧ dev(c) ≠ head(c); else
  landReady.
- `ready(c)` ⟺ approved(c) ∧ head(c) ≠ ⊥ ∧ scr(c) = head(c) ∧ rev(c) = head(c) ∧ (¬needsDevice(c) ∨ dev(c) = head(c)).
- On `landed(c, sha)` for an unlanded card: landed(c′) = true and viol(c′) ⟺ ¬(landReq(c) = sha ∧ ready(c)).
- `needsYou(s, c)` ⟺ ∃ st ∈ steps(s): card(st) = c ∧ status(st) = waiting (plus a violation or an open permission
  prompt on the card, §4.4).
- `stale(λ, t, w, c)` ⟺ w = 0 ∧ t − last(c) ≥ λ, where λ = λ_c is frozen at stage entry and w = |liveWaits(c)|
  (natural-number subtraction: if last(c) > t the age is 0).

**Keeping math and Lean in sync.** Superseded by note 04's pipeline (see `README.md` §3): the math lives in each
declaration's docstring, `lake exe mathview` exports it with a **deep** statement hash (the statement plus the bodies
of every `Fw` definition it reaches, over all imported `Fw` modules), and CI fails when that hash differs from the
one recorded in the reviewer-owned sign-off file. The first proposal here (a `math:` line plus a regenerated
`MATH.md`) would only have forced a regenerated table, not a re-read of the math.

## 8. What is proved today, and what remains (MEASURED / INFERRED)

**Fixed sketch:** `research/kickoff/10-automation-and-proof/lean-scratch/02-events/ConsoleV2.lean`: 362 lines,
18 theorems, 7 `#guard` examples, Lean core only. Builds with `~/.elan/bin/lean ConsoleV2.lean` in about 3.5 s wall
time (MEASURED, one run). `grep -c -E "sorry|native_decide|implemented_by|unsafe"` gives 0. `#print axioms`:
`apply_idem` uses only `propext`; `land_requires`, `review_independent` and `cardStep_inv` use `propext`,
`Classical.choice` and `Quot.sound` (MEASURED; `Classical.choice` comes from `grind` and `simp_all` in the case split).

**First sketch (kept for the record):** `Console.lean`: 368 lines, 22 theorems, 5 `#guard` examples; builds in about
1.0-1.1 s; axioms `propext` and `Quot.sound` only. It has the three faults listed at the top of this note; the
out-of-order and self-review faults reproduce on it.

What the proofs cover, and what they do not:
- They cover the **decision logic** of the console: dedupe, authority, rejection, the step lifecycle, the landing
  rule over all logs, and the monotonicity of time-derived views.
- They do **not** cover IO: that a hook fired, that git reported truthfully, that console-api stamped `actor` and
  `signedBy` from the right channel and capability, that every spawn, commit and hook was observed. Those are L3
  premises with adapter tests and reconcilers (note 03 x.15, x.16; rev 3 §5.1 "Not proved").
- Next theorems (T1 tier, small): `reorder_converges`; `usage_last_wins`; `stage_own_evidence`;
  `agent_events_only` (the agent-allowed events are exactly the `may` table's agent rows);
  `needsYou` turns false exactly when the last open step for the card closes;
  `priority.set` gives a permutation; the stage owner table is total; `approve` requires a registered prediction
  (add `card.text` to `Body`); the lease × step product machine from [05 §4.4]; **convergence**: for logs `L` and `L′`
  with the same set of facts, `reconcile` makes `π(L) = π(L′)` (this needs facts to be keyed by subject and
  commutative per subject. It is the hardest one and stays INFERRED until tried).

## 9. (e) The MVP: Day 1-5 producers and the no-write rule

Aligned with rev 3 §10.2 (the console step queue on Day 4-5; the team starts on Day 3). **Superseded in part by
`docs/plan/rev5-delta.md` §21:** under Lean-first the console core runs in `fwcore serve` from Day 4-5, and the
temporary TS reducer below is only the fallback if `fwcore serve` is not ready by the end of Day 5.

| Day | Producers and parts | Notes |
|---|---|---|
| Day 1 | `~/.fw-console/<repo-id>/` created by a bootstrap script, including **console-api's bare repo holding `main`**; the `Event` envelope zod schema | no git-hook emitter (git hooks run inside the agent's sandbox, §3.2). Facts from the first commits are not lost: the git reconciler backfills them from refs and reflogs when console-api starts on Day 4 |
| Day 2 | the spool format and `emit.mjs` (synchronous, under 100 ms, silent stdout) with unit tests (no socket, full disk, bad payload, timing) | — |
| Day 3 (team start) | Claude Code observer hooks via `emit.mjs` (sync, spool only): `SessionStart`, `SubagentStart`, `SubagentStop`, `TeammateIdle`, `PreCompact`, `PostCompact`, `StopFailure`, `Notification(permission_prompt\|agent_needs_input)`, `PostToolUseFailure(Bash)`; `spawn-guard` (`PreToolUse(Agent)`, `onFailure: block`); the **capability hook** (`PreToolUse(Bash)` on `pnpm fw *`); settings with the **sandbox block and deny rules** from §6.4; **SPK-t** | the three rev 3 hooks become one emitter plus spawn-guard. Each observer names its v1 problem (§3.3 table), as rev 3 §2.2 requires |
| Day 4-5 | console-api: the single writer, spool drain, `events.jsonl` plus snapshots, CLI socket with capability check, TS reducer for **steps and cards** (temporary, ported from `ConsoleV2.lean`'s semantics), the git reconciler (primary git producer, with backfill), SSE; console-web: the step queue and the card table with derived columns (stage, owner, next action, age, needs-you); `fw card open\|approve`, `fw step` (script-posted), `fw land` (request) | the device watcher for the **Simulator lane** only; the usbmux phone lane arrives with M3. No agent ever runs `status`-like commands |
| Day 6 | the transcript tailer (`usage`), replacing agent-run `fw usage` | rev 3 Day 6 meter check reads from it |
| Day 9 | `fwcore console.apply` / `console.replay` from `Fw/Spec/Console.lean`; the G5 oracle runs once and the TS reducer is deleted | lean-prover, from this sketch |
| Day 10 | G1 v1 replay and G2 precision; artifact and card watchers (with the M1 artifact store) | input to the M1 review |

**The rule, stated for `CLAUDE.md`** (one line, with its enforcers): *"You never write console state; `pnpm fw`
sends requests, and the console derives everything else. Enforced by: the sandbox `denyWrite` and the Edit/Write deny
rules on `~/.fw-console`, the CLI socket's actor table (`may`), and the reducer's checks (Lean)."*

## 10. Changes this note proposes to the plan (for the rev 4 merge; PLAN.md not edited)

(Superseded by `docs/plan/rev5-delta.md`, which merges this list with notes 01, 03 and 04; kept for the record.)

- §3.4 Lean MVP: add `Fw/Spec/Console` (reducer, authority, views, landing rule) to the MVP tier. It takes over the
  later-tier `Stage` and `Step`.
- §3.2 "console-api → status" contract: every column is derived (§4.4). Drop `waiting-for` from hand-backs.
- §3.4 hooks: replace "3 hooks" with one synchronous, silent, spool-only observer emitter (9 events, §3.3), the
  PreToolUse capability hook, and `spawn-guard`.
- §8.3 settings: add the sandbox block, the deny rules on the state directory and the CLI socket allowance (§6.4).
  Put the state directory outside the repo and outside `.git`.
- §9.2: stage changes are derived from evidence keyed by commit. The lead's only stage inputs are `approve` and
  `land.request`; `landed` is a git fact that is never refused and raises `violation` without a request;
  `land_requires` is enforced by the reducer from Day 9, not "checked in TS in MVP". Main lives in console-api's bare
  repo.
- §8.5 "Owner state from events": `fw` stage commands become `fw` requests; console-api runs the jobs and emits the
  facts.
- Appendix B: add SPK-t (sandbox plus socket).
- §5.3: add the `math:` docstring convention and the generated `lean/MATH.md`.

## Sources

- Claude Code hooks reference: https://code.claude.com/docs/en/hooks (event list, common input fields, per-event
  inputs, exit-code table, `async`, `onFailure`, `http` hook failure handling, "runs once" dedupe, `WorktreeCreate`
  replacing git), read 2026-10-17.
- Claude Code permissions: https://code.claude.com/docs/en/permissions (scope of Read/Edit deny rules over Bash
  subprocesses; `//` and `~/` anchors), read 2026-10-17.
- Claude Code sandboxing: https://code.claude.com/docs/en/sandboxing (default write scope, child processes, the
  shared `.git` exception for worktrees, protected paths, `allowUnsandboxedCommands`, `excludedCommands`, hooks
  outside the sandbox, `allowUnixSockets`), read 2026-10-17.
- git hooks: https://git-scm.com/docs/githooks (`reference-transaction` states and stdin, `post-commit`,
  `post-merge`, `core.hooksPath`), read 2026-10-17.
- v1 @ eae1bb9: `tools/status.mjs` l.1-69; `CLAUDE.md` l.378-455; `console/status.json`; `console/steps/C-*.json`;
  `tools/usblink.mjs` l.1-25; `tools/lib/usbmux.mjs` l.1-12.
- This repo: `docs/plan/PLAN.md` rev 3 (§2.2, §3.2-3.4, §5, §8.3-8.5, §9.2, §10.2);
  `research/kickoff/05-lean-proofs-and-backend.md` §4.4, §5.1; `research/kickoff/07-claude-code-agent-teams.md` §2.5,
  §6.1, §8; `research/kickoff/08-chat-forensics/README.md`; `research/kickoff/05-lean-sketch/Fw/Spec/{Stage,Lease}.lean`.
