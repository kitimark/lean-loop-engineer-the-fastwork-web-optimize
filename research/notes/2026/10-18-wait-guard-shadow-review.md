---
id: wait-guard-shadow-review
kind: note
title: Wait guard shadow review (rounds 1 and 2)
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
