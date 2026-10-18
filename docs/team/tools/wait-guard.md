# Wait guard (PreToolUse on `Bash`)

Hook: `apps/runner/hooks/wait-guard.mjs`. Decision: Lean `Fw.Ops.Wait.decideCmd` through `fwcore ops.wait` (the hook
only sends the command text and prints the answer). Every Bash call is logged to the spool as a `WaitGuard` record
(`verb` = `decision[:reason[:shape]]`; the command text is never logged), in every mode except `off`.

## Mode switch
| Mode | Effect | How |
|---|---|---|
| `shadow` (default, how it ships) | log only, no stdout | nothing to set |
| `enforce` | a refused command gets `permissionDecision: "deny"` with the fix | `FW_WAIT_GUARD=enforce` or `{"mode":"enforce"}` in `.fw-console/wait-guard.json` |
| `off` | nothing at all | `FW_WAIT_GUARD=off` or the file |

The env var wins over the file; an unknown value means `shadow`. fwcore missing, slow or erroring fails open.

## What is refused
| Reason / shape | Case | Fix |
|---|---|---|
| `bgLong` / `fwWatch` | `fw watch` (also `pnpm fw watch`, `node .../fw.mjs watch`) in a unit ended by `&` | Bash `run_in_background: true`, no `&` |
| `bgLong` / `loop` | a backgrounded `until`/`while` loop (a whole `... done &` compound) | same |
| `bgLong` / `server` | `pnpm\|npm\|yarn\|bun\|npx [run] dev\|serve\|start\|preview`, `vite`, `http-server`, `nodemon`, `live-server`, `browser-sync`, `http.server`, `fswatch`, `--watch`, `node\|tsx\|bun\|python <path containing "server">` | same |
| `bgLong` / `tail` | `tail -f`, `-F`, `--follow` | same |
| `bgLong` / `longSleep` | `sleep N` with N over `caps.maxSleepSec` (30 s; suffix s/m/h/d) | same |
| `unboundedLoop` | an `until`/`while` loop (foreground or not) with no `timeout`/`gtimeout` first word, no bound word (`-lt -le -gt -ge date seq SECONDS $(( (( deadline=`), and not a `while [VAR=..] read` loop over a finite input: a `done` redirect from a file (`< f`, `<f`, not `/dev/*` except `/dev/null`, not `<(...)`), a here-doc or here-string (`<<EOF`, `<<<`), or a pipe from a finite producer (a plain command with no long shape, not `yes`, bare `cat`, `-f`/`-F`/`--follow`/`watch`); proved `readLoop_bounded` | add a deadline, or `pnpm fw ci wait` |

A "unit" is what a trailing `&` backgrounds: an and-or list (`a && b | c &`) or a whole `until/while/for/if/case ... done/fi/esac`
block. Segments split at `; newline | || && &` (`|` is a pipe, `&&`/`||` a join); leading `do then else elif { ! time` are
skipped when finding a segment's command, so `do while true` is a loop. `2>&1`, `>&2`, `&>` are redirects; `&` inside quotes or
a `#` comment is text. Here-document bodies (`<<EOF`, `<<'EOF'`, `<<-EOF` with tab-indented end) are data and skipped.

## Known blind spots (shadow log shows how often they matter)
Code inside `$( )`, `( )`, `sh -c '...'` strings, aliases; a here-doc delimiter glued to a redirect (`<<EOF>f`);
`timeout N` as a later word; a `sleep $n` with a variable; `pnpm --filter x dev`; one bound word bounds every loop of its unit. Goldens: `packages/contracts/golden/ops/ops.wait.jsonl` (generated from Lean).

## Shadow review (task wait-guard-enforce, 2026-10-18)
MEASURED on the main spool (643 `WaitGuard` records, commands recovered by `tool_use_id`): old rules 638 allow, 5
`deny:unboundedLoop`; 4 were false positives (3 `while read ...; done < file`, 1 here-doc whose body had a `while` line),
1 true positive (`until [ "$(gh run view ...)" = completed ]; do sleep 150; done`, no counter). New rules: 642 allow,
1 deny (the true positive); false positives 0/642 on the real log and 0/31 on the synthetic allow set (50 rows).
Enforce switch for the lead to hand the user: `{"mode":"enforce"}` in `.fw-console/wait-guard.json` of the main checkout
(or `FW_WAIT_GUARD=enforce` in the session env); back out with `{"mode":"shadow"}`.

