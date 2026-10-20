# Handoff: earn-transition-retarget (lean-prover)

State: branch `worktree-wf_e34eb985-8ed-1`, final commit in the report; CI ref `ci/earn-transition-retarget`.

Read first: `research/notes/2026/10-20-earn-transition-retarget.md` (model, engine citations, counts, intent, limits,
CI runs), then `lean/Fw/Parts/NavEarnOpt.lean`.

Verified:
- Lean `Fw.Parts.NavEarnOpt`: `transitionsOn` (3 branch theorems), `shown_off`, `faithful_lags`, `shown_settled`,
  `visSame_settled` (VisSame E on settled frames), `work_le` (any arm ≤ faithful), `trace_eq`; standard axioms only.
- Golden `packages/contracts/golden/parts/nav-earn.jsonl` (generator `lean/scripts/NavEarnGolden.lean`, job
  `nav-earn golden check` in `lean/scripts/check.sh`, listed in lean.yml inputs via `Fw.Ci.Trigger`).
- Flag `nav:earn-no-transition`: `apps/site/src/parts/nav/{part.json,logic.ts,index.tsx,nav.module.css}`; checked by
  `nav/earn.golden.test.ts` (transitionsOn rows, the CSS transition list, frame and work rows).

Conventions:
- The flag name deviates from the task's `nav.earn:no-transition`: the earn button belongs to the `nav` part.
- It is an L-class change (look change mid-transition); never a parity proof. The trajectory probe is expected to show
  `new` units on earn `max-width` and `opacity` (`faithful_lags`).

Open:
- Close push keeps faithful work (transitions return at m ≤ 0.001): hold `is-earn-still` to the tween's end.
- WebKit region B paint/composite counters for the earn button (webkit-lag-probe).
- User decision on the look change before any preset use.
