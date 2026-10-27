# phone-morph-push handoff (state: partial, blocked on one user step)

branch: worktree-phone-morph-push; worktree: .claude/worktrees/phone-morph-push; last commit: `git log -1` (main merged at d14b940c3).
CI runs: none pushed (no CI push needed for this task). Phone sessions: none run; no processes of mine left running.

## Verified (MEASURED, 2026-10-27, one try)
- Phone is paired, wired, Developer Mode on, unlocked, Nominal, charging; ports 9460/9461 and 9221/9222 free, no foreign proxy.
- `node src/device-cli.mjs thermal` reads the phone. `pnpm install --offline --frozen-lockfile` and `pnpm build` in apps/site done here
  (dist/aot has morph.geom and morph.tween:geom-timed).
- No WebDriverAgent and no safaridriver Remote Automation exist; the replay path the task names (WDA) is not built. Instead the existing
  XCUITest push driver (`src/throttle/driver/UITests/PushServer.swift`, served by `touch-push.mjs startServer`) builds and signs for the
  real phone: `src/device-xcui.mjs` (`buildDeviceDriver`, test `test/device-xcui.test.mjs`, 3 pass). Build took 17 s with the keychain's
  Apple Development certificate and `-allowProvisioningUpdates`.
- The first run on the phone failed at launch: "Developer App certificate is not trusted" (xcodebuild code 65 after 146 s).

## Blocked on the user (open[0])
Phone: Settings > General > VPN & Device Management > Developer App > Trust the certificate (and Settings > Developer > Enable UI
Automation, if that switch is shown). Then restart this task.

## Next (in order, after the trust)
1. `buildDeviceDriver` into a scratch dir, then `startServer(driver,{udid,...})`; expect `ready` (Safari in front). If it fails after the
   trust, read `<dir>/try.log` for the new reason before asking again.
2. Plan: arms base, morph.geom:on, morph.geom:on+morph.tween:geom-timed, morph.stage:on, base repeated, interleaved, 3+ visits per arm.
   Reuse `PhoneArms.armLabel` / `table` (cells over visits) for the verdict; add a Lean push-visit plan + metric list + golden first
   (`visitMin` in PhoneArms.lean is minutes per visit, not a visit count; the task text's "visits >= visitMin" is a misreading).
3. Visit = `withPhone` (device.mjs) tab with the arm's page, `--pin Serious` via device-thermal-pin.mjs, near-end scroll by script
   (throttle/finish-page.mjs `nearEndJs`), frame recorder (device-runs.mjs `phoneFrames` style), Timeline counts, then `go-<n>` files
   to the push server (forward push, hold, back, hold; see `push-cycle-pass.mjs askCycle`). The page is the real Safari tab, so the
   touches are real; the XCUITest path is a fixed swipe, not a replay of a recorded finger path (say so in the note).
4. Raw files in `.local/phone/2026-10-27/`; results/phone/2026-10-27-morph-push/{summary.json,tables.md}; note
   research/notes/2026/10-2x-phone-morph-push.md; ledger notes; check.sh via fw slot; dry land `VERDICT dry phone-morph-push`.

## Conventions
Team id comes from the keychain certificate at run time (never committed). Kill only PIDs this task started (xcodebuild runs in its own
process group via `runGroup`). Clear the induced thermal condition with our own owner at the end.
