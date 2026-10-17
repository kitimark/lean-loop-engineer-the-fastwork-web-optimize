# math-r9-fix handoff

State: branch `worktree-agent-a69505e61f59f5fab` (commit: see `git log -1 --grep "Task: math-r9-fix"`), base ffeff73.
`sh lean/scripts/check.sh` green; mathview lint: 1951 entries, 0 failing, 0 bound-and-applied, 100 quantifier
warnings (unchanged).

Done
- 6 round-9 disagree rows (research/notes/2026/10-17-math-review-r9-a82e4a4.md) fixed as the notes say:
  Freeze.levelOf_mono (c \preceq c'), Freeze.tableOf (\operatorname{tb}), classifyAllU and classifyAllU_row (bind \tau),
  SelfCheck.check_sound (row field d, function \delta), Snapshot.layers_additive (where-clause inside the $$, with Z/N).
- 2 more rows the new lint found with the same flaw: Measure.classifyAll (bind \tau) and Measure.obs_le
  (bounds K, T instead of k, t next to k(R), t(R)). These need a math-review pass.
- New lint `ShadowLint` in lean/MathViewMain.lean, an error (joins `bad`): in one $$ block, a name that is bound
  (\forall/\exists list, tuple or comma list before \in/\notin/\subseteq, comprehension subscript), applied
  (`v(`, `\operatorname{v}(`, not inside a sub/superscript) and used as a value (operand of = < > \le \ge \ne outside
  an argument list, or an index as k in R_k). The value condition keeps function variables (f, g, B, R, p) legal.
- Measured: on the round-9 export (a82e4a4 state) 5 hits, all true (the 3 reviewer rows + classifyAll, obs_le); on an
  older export also the 3 round-8 Obs.Health rows (hungB, Stall, wait_not_hang). 0 false positives. Without the
  value condition: ~60 hits, nearly all legal function variables, so keep it.
- #guards: positives (round-8 `\exists f.\ f(a) = f`, check_sound, classifyAll), negatives (fix with \tau,
  `\forall f, x: f(x) = g(x)`, budget B, `\operatorname{classify}_p(R) = p`), tokenizer cases.

Open
- Fw.Obs.Health.sysAlerts (round 9, n reused) left to watch-slow; this lint does not catch plain reuse of a name.
- The lint is token-level: a function variable compared as a value (`f = g`) and applied would be flagged; none today.

Read first: lean/MathViewMain.lean (ShadowLint module note), lean/MathView.lean (warnEntry for the older lint).
