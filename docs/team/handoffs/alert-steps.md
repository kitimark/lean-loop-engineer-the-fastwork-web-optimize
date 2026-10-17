# alert-steps handoff

State: branch worktree-agent-a832a5f0931ddfc35. Lean `console.alert` op proved and wired; drain.ts calls it; check.sh and the console-api, runner and contracts tests are green.

Read first: `lean/Fw/Console/Alert.lean` (rule + theorems), `lean/Fw/Wire/Console.lean` (`opAlert`), `apps/console-api/src/spool/drain.ts` (`alertPlan`, flights, openAlerts).

Rule (Lean, `Fw.Console.Alert.act`):
- Opens: `StopFailure`; `Notification` with type `permission_prompt` (names the tool), `agent_needs_input` or no type (needs input). Other types (idle_prompt) open nothing.
- Step id `alert-<slug(agent_id)|main>-<hook ts>`; keys `alert:<id>` and `alert-close:<id>`; one open alert per agent.
- Closes: the same agent's later `PostToolUse`, `PostToolUseFailure`, `SubagentStop` or `Stop` -> `step.cancel` by actor script (a refused cancel is ignored).
- Notification with no agent_id: attributed only to the single agent with a tool in flight, and only if the lead has no tool in flight other than `Agent`; else no alert.
- Proved: attrib_sound, attrib_lead_only, parse_stepId (id round trip), post_event, lead_notification_silent, post_names_agent, no_second_alert, close_sound, close_complete, closer_no_post.

Conventions: golden `packages/contracts/golden/console/console.alert.jsonl` is generated (`cd lean && lake env lean --run scripts/OpsGolden.lean`; cases are in `lean/Fw/Ops/Golden.lean`, a one-block edit outside the write list). `emit.mjs` now records `notification_type`, `message_len` and the tool token from "permission to use <Tool>" in a Notification (never the message text); `ObsRecord` has the two optional fields.

Open items:
- Attribution of an agent-less Notification needs `PreToolUse` records; `.claude/settings.json` only runs emit.mjs on PostToolUse(Failure), so today the in-flight list is empty and such Notifications are not attributed (no alert; the user sees the prompt in the terminal). Lead: add `PreToolUse` `*` (async) -> emit.mjs to turn it on. The flight bookkeeping in drain.ts is TS glue (memory only, empty after a restart = fewer attributions).
- Old alert steps with `alert-<hash12>` ids never auto-close (the id does not parse); cancel by hand.
- math-reviewer and the math lock have not seen the new Alert.lean entries.
