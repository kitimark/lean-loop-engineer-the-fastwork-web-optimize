# land-legs-followups handoff

State: branch worktree-wf_b6f1e1ef-717-1 (probe branch ci/land-legs-followups-1). `sh lean/scripts/check.sh` green; apps/runner `pnpm test` green (46 files);
`node --test scripts/ci-paths.test.mjs` and `.github/scripts/gate-jobs.test.mjs` green.

Done
- (1) Lean `Fw.Console.LandLegs.legsVeto : Option (List Bool) -> Bool` (`none` and `some []` say nothing, else `!legsOk`), theorems `legsVeto_none/_empty/_fail/_all_pass/_iff`,
  guards, golden cases `console.landLegsVeto` in `land-legs.jsonl`, fwcore op `console.landLegsVeto`. `legsPass` (land-remote.ts) builds the input and replays the answer;
  the dead `j.name !== "lane"` filter is gone; land.md says what the code does.
- (2) preview-e2e.md (artifact names `land-preview-e2e-<leg>`, `LANE leg=.. engine=..`) and the checks.ts comment.
- (3) Finding: main already seeds the webkit caches (premise-tests `engine`), but the keys named the runner image version and the fleet runs two image
  versions at once, so a land on the other image missed (MEASURED: run 39351337087 miss, key f9bed..., main held 4cf25...). A dispatch re-seed (39352076255) landed on the
  old image and re-hit the old key, so re-seeding cannot fix it. Fix: `image` is no longer a declared input of the `browsers` and `apt-debs` caches (GateSpeedGolden.lean,
  action.yml, goldens regenerated, gate-jobs test run-4 now a hit). Premises written in the Lean comment: browsers dir independent of the image; apt checks stale debs against its index.
- (4) `fw land` prints each `remote:` line once: `log: logLine` (stderr + log file), no longer pushed to the result lines.

Measured (webkit leg, gate-engine step, seconds): before miss 64 (39351337087), before hit 25 (39350750068, 24 in 39348856921); after, own-branch probes: miss 42
(39352751826), hit 30 (39353183174). Gain per land is 12 to 39 s when main's seed matches. After landing, main's push runs the seeders (new keys); the effect on
other branches is then checkable with `gh run list --workflow land.yml`. The own-branch probe cannot show main seeding.

Open
- (5) Reading the lane's end from the poller's cached facts: not done (the poller was stopped, `tooBig`, during this task; `fw ci wait` refused). Needs the poller first.
- setup-lean (about 40 s) untouched: separate task, touches the Lake one-writer rules.
- A test that `fw land` prints each remote line once is missing (land.ts has no test with the remote tier and a captured stderr).
- TS stand-ins: none beyond replays of Lean goldens.
Read first: `docs/team/tools/land.md` (legs section), `docs/team/tools/gate-speed.md` (Caches).
