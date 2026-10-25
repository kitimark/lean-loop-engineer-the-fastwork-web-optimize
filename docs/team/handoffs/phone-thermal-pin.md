# phone-thermal-pin handoff
branch: worktree-wf_781356ec-209-1 (CI branch ci/phone-thermal-pin)
worktree: .claude/worktrees/wf_781356ec-209-1 (under the main checkout)
last commit: 1d11d53c3 (update below after later commits)
CI runs: 40204768832 in_progress (first push; no measurement needed, only the lean/premise checks)

## Verified
- Lean pinned-thermal rules in lean/Fw/Device/Thermal.lean compile; golden device/thermal.jsonl regenerated (404 lines, --check ok).
- TS twins (src/device-thermal-pin.mjs) pass the golden; owner/session/block tests pass (pnpm --filter measure-webkit test: 830 pass).
- pin-probe on the phone: ThermalSerious reads back Serious within ~11 s of the spawn; owner stopped with SIGTERM only.

## Open
- Does clear (TERM of the owner) end the induced state? After the probe the phone stayed Serious for 12+ min (cool.log in .local/phone/2026-10-25-pin, not committed); real heat vs a sticky condition is being separated.
- The phone check (arms-run --only morph.countdown:strip --max-visits 2 --pin Serious) and the induced-vs-real comparison against .local/phone/2026-10-25-thermal/raw in the main checkout.
- Note research/notes/2026/10-25-phone-thermal-pin.md, findings ledger entry, fw land --dry, fw review ready.

## Conventions
- test/pin-world.mjs is a shared test helper (not a *.test.mjs file; listed in the report as outside the writes patterns).
- pymobiledevice3 via pipx ==11.44.0, always --userspace, stop with kill -TERM; raw data in .local/phone/<date>-pin/ (gitignored).
- Worktree needed `pnpm install --offline --frozen-lockfile` before git push (the pre-push hook runs apps/runner).

## Read first
docs/team/tools/device-lag-recorder.md ("Pinned thermal state"), lean/Fw/Device/Thermal.lean (section Pinned thermal state), src/device-phone-pin.mjs, src/device-thermal-pin.mjs.
