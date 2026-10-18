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
| `unboundedLoop` | an `until`/`while` loop (foreground or not) with no `timeout`/`gtimeout` first word, no bound word (`-lt -le -gt -ge date SECONDS $(( (( deadline=`), and not a bounded read loop (below) | add a deadline, or `pnpm fw ci wait` |

**Bounded read loop** (Lean `readHead`, `inRedir`, `producerOut`; `readLoop_bounded`). The condition is exactly
`while [VAR=..] read [opts] [names]` ended by `;` or a newline, and the next segment starts with `do`: no `||`, `&&`, `|`,
second command, redirect or `-u fd` in the condition (`while read l || true` never fails). Its stdin is the last stdin
redirect of the `done` segment, else the pipe into it; it must be one of:
- a file: `done < f`, `<f`, `0<f` (not `/dev/*` except `/dev/null`, not `<&3`), a here-doc or here-string;
- `done < <(cmd)` or `cmd | while read` with `cmd` on the producer allowlist: `git` with a read-only subcommand
  (`ls-files ls-tree diff log show status branch tag for-each-ref rev-list rev-parse grep shortlog describe cat-file
  blame merge-base name-rev`, no `--stdin`), `gh run list|view`, `cat FILE...` (an operand, no `-`, no `-u`), `find`
  (no `-exec -execdir -ok -okdir`), `seq` (no `inf`/`nan`), `ls`, `printf`, `echo`; and, when their own input is finite,
  `grep`, `rg` (no `--pre`), `jq` (no `repeat recurse until while range def infinite`), `sort` (no `--compress...`),
  `head`, `wc`. No producer word may be `-`, `/dev/*` (but `/dev/null`), `(...`, or hold `<(`, `$(`, a backquote or
  `<&`. Anything else (`ping`, `tail`, `yes`, `log stream`, `sleep infinity`, `gh run watch`) is never finite
  (`producer_outside_list`); a filter after an endless producer is not either (`filter_needs_finite_input`).

That the loop really ends is not proved: `readLoop_bounded` is a fact about this classification. Premises: `read` fails
at the end of a finite input; the allowlisted producers end; a pipeline head reads the Bash tool's stdin, `/dev/null`
(MEASURED 2026-10-18: fd 0 is the character device `/dev/null`, `timeout 5 cat` exits 0 at once).

**Server smoke tests.** `node server.mjs & pid=$!; curl ...; kill $pid` is `bgLong`/`server` and is denied under enforce.
Use three calls instead: start the server with the Bash tool's `run_in_background: true` (no `&`), run the checks in the
next call, then stop the background task (TaskStop). The deny message says the same.

A "unit" is what a trailing `&` backgrounds: an and-or list (`a && b | c &`) or a whole `until/while/for/if/case ... done/fi/esac`
block. Segments split at `; newline | || && &` (`|` is a pipe, `&&`/`||` a join); leading `do then else elif { ! time` are
skipped when finding a segment's command, so `do while true` is a loop. `2>&1`, `>&2`, `&>` are redirects; `&` inside quotes or
a `#` comment is text. Here-document bodies (`<<EOF`, `<<'EOF'`, `<<-EOF` with tab-indented end) are data and skipped; a
body opens only at a `<<` typed unquoted (`echo "<<EOF"`, `echo '<<EOF'`, `echo \<<EOF` open none: `flushWord_quoted`).

## Known blind spots (shadow log shows how often they matter)
Code inside `$( )`, `( )` and `{ }` groups, function bodies (`f() { while true; ...; }; f`), `sh -c '...'` strings,
aliases; a here-doc operator glued to a word or in arithmetic (`cat<<EOF`, `$((1 << 2))`) or a delimiter glued to a
redirect (`<<EOF>f`); an empty quoted delimiter (`<< ''`); variables that name a device or FIFO (`done < "$f"`,
`cat "$f"`); a `for`/`if` block or `{ }` group whose stdin is redirected from an endless source around a filter;
`timeout N` as a later word; a `sleep $n` with a variable; `pnpm --filter x dev`; one bound word bounds every loop of its
unit. Goldens: `packages/contracts/golden/ops/ops.wait.jsonl` (generated from Lean).

Shadow review (false denies 0/1188, misses 0, MEASURED): `research/notes/2026/10-18-wait-guard-shadow-review.md`.

## Turning enforce on (lead hands this to the user)
After this lands on `main`: in the main checkout run `cd lean && lake build fwcore`; probe once, the reply must be
`allow`: `echo '{"op":"ops.wait","cmd":"while read l; do echo $l; done < f"}' | lean/.lake/build/bin/fwcore`; then write
`{"mode":"enforce"}` to `.fw-console/wait-guard.json` (or `FW_WAIT_GUARD=enforce` in the session env). Back out with
`{"mode":"shadow"}`.
