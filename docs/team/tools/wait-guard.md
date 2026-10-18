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
| `unboundedLoop` | an `until`/`while` loop (foreground or not) whose **condition** has no bound (below); the body never counts (`body_irrelevant`): `date`, `deadline`, `$((n+1))`, `break` in the body bound nothing | bound the condition, `timeout N bash -c '...'`, or `pnpm fw ci wait` |

**Bound = the condition only, by an allowlist grammar B** (round 4, variable rule closed in round 6; Lean `atomParse`,
`varOk`, `relOk`, `boundAtom`, `condStep`, `comb`, `topAsg`; proved `boundAtom_iff`, `var_allow_iff`,
`upper_never_bound`, `seconds_capped`, `seconds_direction`, `addSeg_asg`, `grammar_only`, `subst_never_bound`). The condition is
the and-or list from `while`/`until` to `do`. An element is a bound only when it is exactly one of

    B ::= [ V OP N ] | [ N OP V ] | [[ V OP N ]] | [[ N OP V ]]     OP ∈ -lt -le -gt -ge
        | (( v OP N )) | (( N OP v ))                               OP ∈ <  <=  >  >=

V is `$v`, `${v}` or `"$v"` with v a plain name (letter or `_`, then letters, digits, `_`); in `(( ))` only the bare
name v. N is a decimal literal of 1 to 18 digits (`0` or no leading zero; 18 digits stay below 2^63, so the shell's
64-bit arithmetic never wraps). `$$ $# $? $!` and positionals are not names. **The variable rule is closed, no
denylist** (round 6, `var_allow_iff`): v counts only if

- (a) v = `SECONDS` and N ≤ 86400 (one day; a bigger N is most likely an epoch time, `seconds_capped`), moving toward
  the exit: `while` needs `SECONDS` `<`/`≤` N, `until` needs `>`/`≥` N (`seconds_direction`); or
- (b) v matches `^[a-z][a-z0-9_]*$`, the command assigned it a decimal literal earlier at its top level (`v=N` alone as
  a segment that starts an and-or list, not piped, not `&`, not inside a block; `i=0; while [ $i -lt 5 ]`,
  `addSeg_asg`), and v is not one of zsh's 14 lowercase special parameters (`zshLowerSpecials`: `histchars status
  prompt argv fignore cdpath fpath mailpath manpath psvar zsh_eval_context module_path path pipestatus`, the lowercase
  rows of `special_params[]` in zsh 5.9 `Src/params.c` l.295-442 @73d3173, pin `zsh` in
  `refs/upstream/sources.lock.yaml`).

Every other name is out of B with no list (`upper_never_bound`): any name with an uppercase letter except `SECONDS`
(`BASH_MONOSECONDS`, `PIPESTATUS`, `GROUPS`, `BASH_LINENO`, `BASH_ARGV`, `TTYIDLE`, `EPOCHSECONDS`, `RANDOM`, a user's
own `N`), a name starting with `_`, and a counter the command never set (`while [ $i -lt 5 ]` alone is denied: an unset
`i` makes `until [ $i -ge 5 ]` a test error forever). Bash sets only uppercase variables itself (bash manual, Shell
Variables; INFERRED, bash source not pinned), so (b) never meets a bash special.

**The tool shell may be zsh** (round 5). The agent Bash tool runs commands in the user's login shell, which on this Mac
is zsh 5.9, not bash. B is read so that each allowed element keeps its meaning in both shells: `[ ]`, `[[ ]]` and
`(( ))` with a plain variable and a decimal literal behave the same, and `SECONDS` counts up in both. What differs is
handled by denying it: `EPOCHSECONDS`/`EPOCHREALTIME` exist in zsh only after `zmodload zsh/datetime` and in bash only
from 5.0, so they are unset in macOS `/bin/bash` 3.2.57 too; `BASH_MONOSECONDS` exists only in bash ≥ 5.3. An unset
operand turns `[ $EPOCHSECONDS -ge N ]` into a test error (exit 2), so `until` on it never exits; all of them are
uppercase and so out of B (use `SECONDS`, which bash 3.2, bash 5 and zsh all count up). Bash-only specials
(`BASHPID`, `SRANDOM`, `BASH_ARGC`, ...) are unset in zsh and zsh-only ones (`TTYIDLE`, `status`) in bash; none is a
bound either way. The read-loop and `timeout` rules do not depend on the shell. Everything else bounds nothing (`grammar_only`): `$( )`, backquotes (`subst_never_bound`),
`$(( ))`, `${v:-..}`, a limit in a variable (`[ $SECONDS -lt $end ]`: write the literal, `[ $SECONDS -lt 600 ]`),
comma, ternary, hex, octal, `test`, a leading `!`, `<`/`>` in `[ ]` (a redirect) or `[[ ]]` (string order), string
compares, `true`, `:`, polls (`gh`, `ls`, `pgrep`) and function calls. Elements combine by bash's exit rule: for
`while`, `a && b` is bounded if either is, `a || b` only if both are; for `until` the other way round; after `;` the last
list decides. `timeout N` is not in B as a condition element (`while timeout 5 cmd` repeats forever); it bounds only as a
wrapper: a loop prefixed `timeout N` (N > 0) or inside `timeout N bash -c '...'` (a blind spot below, so allowed).

**Threat model.** The guard targets agent mistakes (a poll with no exit, a forgotten counter), not an adversary: an
agent that wants an endless loop can hide one in `bash -c`, `eval` or a function. Outside B it fails closed: an
unrecognised condition is unbounded, and the deny message names the forms that pass.

**Bounded read loop** (Lean `plainRead`, `inRedir`, `producerOut`; `readLoop_bounded`, `readLoop_input_free`). The
condition is `while [VAR=..] read [opts] [names]` (opts and names are words of letters, digits, `_`, `-`, or `$'\0'`-style: `-r -t 1 -d '' -d $'\0'`; no `-u fd`), ended
by `;` or a newline before `do`; a counter test may be `&&`-joined but never clears a free input (`read && [ $i -lt 9 ]`
over `tail -f` stays denied), and `read || x` never fails. Its stdin is the last stdin redirect of the `done` segment,
else the pipe into it; it must be one of:
- a file: `done < f`, `<f`, `0<f` (no device: no word containing `/dev/` or starting `dev/`, except `/dev/null`, so
  `//dev/zero` and `./../../dev/zero` are devices; not `<&3`), a here-doc, a here-string with no `$( )` or with one
  finite producer (`<<< "$(git diff --name-only)"`; `<<< "$(yes)"` is denied);
- `done < <(cmd)` or `cmd | ... | while read` with `cmd` on the producer allowlist: `git` (no `-c`, `--config-env`,
  `--exec-path`; no `--stdin`) with a read-only subcommand (`ls-files ls-tree diff log show status branch tag
  for-each-ref rev-list rev-parse grep shortlog describe cat-file blame merge-base name-rev reflog`, round 4:
  `worktree list`, `stash list`, `remote [-v|get-url]`, `config --list|-l|--get*` without `--edit`), `gh run|pr|issue
  list|view`, `cat FILE...` (an operand, no `-`, no `-u`), `find` (no `-exec -execdir -ok -okdir`), `seq` (no
  `inf`/`nan`), `ls`, `printf`, `echo`, `timeout N cmd`; and, when their own input is finite, the filters `grep`, `rg`
  (no `--pre`), `jq` (no `repeat recurse until while range def infinite`), `sort` (no `--compress...`), `head`, `wc`,
  `tr`, `cut`, `uniq`, `sed` (no `:label`/branch loop), `awk` (no `while for do getline`), `xargs CMD` (CMD itself on
  the list), `node scripts/*.mjs` (a repo script path, no `..`). No producer word may be `-`, a device (an output
  redirect such as `2>/dev/null` is not one), `(...`, or hold
  `<(`, `$(`, a backquote or `<&`. Anything else (`ping`, `tail`, `yes`, `log stream`, `sleep infinity`, `gh run watch`)
  is never finite (`producer_outside_list`); a filter after an endless producer is not either
  (`filter_needs_finite_input`).
- **node/pnpm decision (round 3):** `node scripts/*.mjs` is allowed as a producer (grep of `scripts/*.mjs` found no
  listen/watch/forever loop; they print and exit). `pnpm`, `npm`, `npx` are not: a script name can start a dev server or
  watcher. The deny message says to write their output to a file first: `pnpm ls > f.txt; while read l; do ...; done < f.txt`.

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
`cat "$f"`); a FIFO or `/proc` file named by a plain path (`cat fifo`, `cat /proc/kmsg`); `for ((;;))`; a command
substitution in an unquoted here-doc body; a `for`/`if` block or `{ }` group whose stdin is redirected from an endless
source around a filter; a `sleep $n` with a variable; `pnpm --filter x dev`. In B (round 4): a counter that never
moves, or is reset in the body (also `SECONDS=0` in the body), or made non-numeric after its literal assignment
(round 6 denies a counter the command never set); parameters added by zsh modules (`zsh/parameter`,
`zsh/datetime`, not in `Src/params.c`); quotes are removed before B is checked, so
`'$i'` and `\$i` read as the variable; word splitting of an unquoted `$i`; a counter set by `eval` or a backquote
assignment; `read -u fd` / `exec 0<` in the body; a body that appends to its own `done < f` file; `/proc/self/fd/0`;
sed's `e` command in a filter; the loop text inside `timeout 0|inf bash -c '...'` (`timeoutOk` refuses 0 and `inf` for a
loop it sees). Foreground
`tail -f` / `watch` without a loop are out of scope (the Bash tool timeout ends them). Goldens:
`packages/contracts/golden/ops/ops.wait.jsonl` (generated from Lean).

## Shadow review (task wait-guard-enforce, 2026-10-18)
Round 1, MEASURED on the main spool (643 `WaitGuard` records, commands recovered by `tool_use_id`): old rules 5
`deny:unboundedLoop`, 4 false positives (3 `while read ...; done < file`, 1 here-doc body with a `while` line), 1 true
positive (`until [ "$(gh run view ...)" = completed ]; do sleep 150; done`, no counter).
Round 2 (after the adversarial review), MEASURED on 1189 records (all recovered): 1188 allow, 1 deny (the true positive);
false denies 0/1188, misses 0 (the only real loops are that poll, one counter loop and 5 `while read` loops over files).
Synthetic corpus of 80 commands (every reviewer escape: `|| true`, `|| :`, `; [ 1 ];`, `ping`, `tail -fn`,
`tail --follow=name`, `cat /dev/urandom`, `cat -`, `cat -u`, `log stream`, `sleep infinity`, quoted `<<EOF`; 51 deny,
29 allow): 0 mismatches. `seq` is no longer a bound word (`seq inf | while read` passed on it).
Round 3 (bound from the condition only; filters, `xargs`, `gh pr`, `node scripts/*.mjs`, `read -d $'\0'`, devices,
here-string `$( )`), MEASURED on 2746 records: 2743 allow, 3 deny, all true positives (two polls with no bound, one
reviewer corpus whose here-doc ended early so its `until false` lines ran as code); false denies 0 (the one found,
`git reflog ... | while read`, fixed by adding `reflog`), misses 0 (33 allowed records with a loop keyword at a command
position: data in strings/here-docs or a counter loop). Synthetic corpus 278 rows (the 80 above plus 198 reviewer probes
of rounds 2-3), labeled with the ideal bash verdict: 24 mismatches, all by design or blind spots. False denies 17: 12 read
stdin (`cat -`, `cat |`, `grep x -`, `rg x -`, `< /dev/stdin`, `while read` with no input, `git credential fill`,
`git hash-object --stdin-paths`, `git check-ignore --stdin`, `git rev-list --stdin`), which end because stdin is
`/dev/null` but stay denied as the reviews asked; `while true; read l; do`; `read -u 3` on a closed fd;
`head -c 10 /dev/zero`; `< <(git log | cat)`; a counter checked by `break` in the body. Misses 7, all blind spots:
`cat /proc/kmsg`, `cat fifo`, `(sleep 300) &`, `{ sleep 300; } &`, `bash -c 'while true...'`, a function body, and
`while [ $x -lt 5 ]` with no increment.
Round 4 (allowlist grammar B; also `read -n 0|-N 0|-t 0` never counts as a read, backslash-newline is joined before
parsing, `2>/dev/null` in a producer is not a device, `git worktree|stash list` are producers), MEASURED on 4810 records
(all recovered): 4807 allow, 3 deny, the same 3 true positives (the `gh run view` poll, the reviewer here-doc corpus,
`until grep -qE ... ; do sleep 5; done`). Against round 3 on the same 4810 records: 0 newly denied, 2 newly allowed
(round-3 false denies on new records: `git worktree list --porcelain | awk | grep | while read`, `ls -t ... 2>/dev/null |
head -3 | while read`). False denies 0. Synthetic 80-row corpus: 1 mismatch, by design: `until [ $SECONDS -ge $end ]` is
now denied (a limit in a variable; no real record used it). Every round-3 reviewer probe with verdict deny (`$( )` polls
via `gh`/`ls`/`pgrep`, `$$`, `$#`, `$RANDOM`, `${x:-0}`, `$((0))`, SECONDS the wrong way, `!`, comma, ternary, hex,
octal in `(( ))`, `read -n 0`, `whi\⏎le`) is a `#guard` in `Fw/Ops/Wait.lean` and a golden row (`r4:`).
Round 5 (zsh tool shell: `EPOCHSECONDS` out of `clocks` into `noBoundVars`; N at most 18 digits; `_ OPTIND LINES
COLUMNS BASH_ARGC` added to `noBoundVars`), MEASURED on 6429 records (all recovered): 6425 allow, 4 deny. Against round
4 on the same records: 0 newly allowed, 1 newly denied, the round-4 reviewer's own probe of this hole
(`until (( EPOCHSECONDS >= 1760800000 )); do ...; [ $n -ge 5 ] && break; done`, which ends only by a `break` in the body,
the by-design `body_irrelevant` class). False denies on organic records 0. Synthetic 80-row corpus unchanged (1 mismatch,
`$SECONDS -ge $end`). Probes `until [ $EPOCHSECONDS -ge 1760800000 ]`, a 23-digit N, `while [ $_ -lt 10 ]` are
`#guard`s and golden rows (`r5:`).
Round 6 (closed variable rule: `SECONDS` with N ≤ 86400, or a lowercase name set to a literal at the top level before
the loop that zsh does not reserve; the `noBoundVars` denylist is gone), MEASURED on 7689 records (all recovered, main
spool read-only): 7685 allow, 4 deny (the same 4). Against round 5 (`main` fwcore) on the same records: 0 newly denied,
0 newly allowed; organic counter loops all set their counter first (`i=0; while ...`). Synthetic 80-row corpus
unchanged (1 mismatch, `$SECONDS -ge $end`). Round-5 reviewer probes (`BASH_MONOSECONDS` in `[ ]` and `(( ))`,
`PIPESTATUS`, `GROUPS`, `BASH_LINENO`, `BASH_ARGV`, zsh `status`/`TTYIDLE`, `SECONDS` against an epoch literal) are
`#guard`s and golden rows (`r6:`, 131 rows), as is the allowed `i=0; while [ $i -lt 5 ]; do ...; i=$((i+1)); done`.

## Turning enforce on (lead hands this to the user)
After this lands on `main`: in the main checkout run `cd lean && lake build fwcore`; probe once, the reply must be
`allow`: `echo '{"op":"ops.wait","cmd":"while read l; do echo $l; done < f"}' | lean/.lake/build/bin/fwcore`; then write
`{"mode":"enforce"}` to `.fw-console/wait-guard.json` (or `FW_WAIT_GUARD=enforce` in the session env). Back out with
`{"mode":"shadow"}`.
