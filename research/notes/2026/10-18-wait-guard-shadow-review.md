---
id: wait-guard-shadow-review
kind: note
title: Wait guard shadow review (rounds 1 to 5)
status: done
created: 2026-10-18
topics: [wait-guard, hooks]
---

# Wait guard shadow review

Moved verbatim from `docs/team/tools/wait-guard.md` (section "Shadow review", task wait-guard-enforce) by task
context-slop, so the tool doc holds only usage. The rules it reviewed: `docs/team/tools/wait-guard.md`.

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
