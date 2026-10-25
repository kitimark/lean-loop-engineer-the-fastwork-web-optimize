# phone-thermal-pin handoff
branch: worktree-wf_781356ec-209-1 (CI branch ci/phone-thermal-pin)
worktree: .claude/worktrees/wf_781356ec-209-1 (under the main checkout)
last commit: decd3209c (merge of main; later commit only edits this handoff)
CI runs: 40204768832 lean pass (early commits); 40212266200 lean pass (merge commit). No measurement run needed.

## Verified
- Lean pinned-thermal rules (lean/Fw/Device/Thermal.lean) compile; golden device/thermal.jsonl 432 lines, --check ok; check.sh green.
- TS twins pass the golden; measure-webkit 833 pass, contracts 11 pass, apps/runner 3533 pass, ci-paths 56 pass.
- Phone check done (MEASURED): Serious held at all 5 readings of a 2-visit block; induced Serious matches real Serious within spread; no throttle shown.
- Premise "owner exit clears the condition" REFUTED (stuck Serious 34 min after a TERM without clear). Owner is now OWNER_PY: clears on its own connection, acks, then exits.

## Open
- Reported state falls to Nominal ~2 min after a clear on an unheated phone; after real load it stays Serious (heatRemains).
- Owner killed by KILL or dead alone ends `unconfirmed`; next run (or pin-stop --dir) runs one set-and-clear cycle.
- Findings-ledger entry skipped (not an optimization candidate).

## Conventions
- test/pin-world.mjs is a shared test helper (not *.test.mjs; outside the writes patterns).
- pymobiledevice3 via pipx ==11.44.0, always --userspace, never --native; stop with kill -TERM; raw data in .local/phone/<date>-pin/ (gitignored).
- Worktree needs `pnpm install --offline --frozen-lockfile` before git push.

## Read first
research/notes/2026/10-25-phone-thermal-pin.md, docs/team/tools/device-lag-recorder.md ("Pinned thermal state"), src/device-phone-pin.mjs, src/device-thermal-pin.mjs.
