# land-legs-followups handoff

State: branch worktree-wf_b6f1e1ef-717-1 (probe branch ci/land-legs-followups-1). `sh lean/scripts/check.sh` green; apps/runner `pnpm test` green (46 files);
`node --test scripts/ci-paths.test.mjs` and `.github/scripts/gate-jobs.test.mjs` green.

Done
- (1) Lean `Fw.Console.LandLegs.legsVeto : Option (List Bool) -> Bool` (`none` and `some []` say nothing, else `!legsOk`), theorems `legsVeto_none/_empty/_fail/_all_pass/_iff`,
  guards, golden cases `console.landLegsVeto` in `land-legs.jsonl`, fwcore op `console.landLegsVeto`. `legsPass` (land-remote.ts) builds the input and replays the answer;
  the dead `j.name !== "lane"` filter is gone; land.md says what the code does.
- (2) preview-e2e.md (artifact names `land-preview-e2e-<leg>`, `LANE leg=.. engine=..`) and the checks.ts comment.
- (3) Finding: main already seeds the webkit caches (premise-tests `engine`), but the keys named the runner image version and the fleet runs two image versions at once,
  so a land on the other image missed (MEASURED: run 39351337087 miss, key f9bed..., main held 4cf25...). Fix: `ImageVersion` is no longer a declared input of the
  `browsers` and `apt-debs` caches; `os` (`$ImageOS`, ubuntu24) is, because playwright-core downloads a different WebKit build per Ubuntu release
  (coreBundle.js:34333-34334 in 1.64.1). GateSpeedGolden.lean, action.yml, goldens, gate-jobs test (run 4 hit, new run 6: other Ubuntu release, miss) follow.
- Round 2: land.md and gate-speed.md say what the code does (no image in keys, OS kept, main seeds on each main push, hand re-seed only after a Playwright bump);
  `land-remote-lines.test.ts` (each `remote:` line once across stderr and result lines); legsPass/legsVeto comments no longer mention a running job.
- (4) `fw land` prints each `remote:` line once: `log: logLine` (stderr + log file), no longer pushed to the result lines.

Measured, cross-image (webkit leg, branch ci/land-legs-followups-1, key gate-*-969c76...). Save: run 39355359869 on image 20261012.149.1 (miss, saved both caches).
Same-image hits: 39355755543, 39356078900 (image 20261012.149.1; gate-engine step 28 s in 39355755543). **Cross-image hit: run 39356404406, webkit leg on image
20261018.154.1 restored the key saved on 20261012.149.1** (apt-debs and browsers both "restored"); gate-engine step 23 s; apt "Need to get 0 B/107 MB of archives": 0 .deb
files downloaded (only the package index, 6.3 MB), 177 packages installed from the cache. Before the fix: miss 64 s (39351337087), 42 s (39352751826); hit 25 s (39350750068).
So the cross-image hit is MEASURED (one run, one pair of images): about 19 to 41 s less than a miss, the same as a same-image hit within noise (23 vs 28 s). The earlier probes
(39352751826, 39353183174) never crossed images and showed nothing about this. The effect for other branches needs main's seed under the new keys (written by the next main push).
Probes used: 4 of 4.

Open
- (5) Reading the lane's end from the poller's cached facts: not done (the poller was stopped, `tooBig`, during this task; `fw ci wait` refused). Needs the poller first.
- setup-lean (about 40 s) untouched: separate task, touches the Lake one-writer rules.
- TS stand-ins: none beyond replays of Lean goldens.
Read first: `docs/team/tools/land.md` (legs section), `docs/team/tools/gate-speed.md` (Caches).
