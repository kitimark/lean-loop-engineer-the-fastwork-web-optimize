# gate-engine slow on land legs: apt variance, plus a cache save nothing reads

Task `ci-gate-engine-webkit-slow`. Sources: job logs of existing land runs (`gh run view <run> --log --job <job>`), `gh cache list`, Lean `Fw.Ops.GateEngineTiming`, golden `packages/contracts/golden/ops/gate-engine-timing.jsonl`. No run was dispatched.

## Answer
- The 66 / 87 / 70 s webkit steps (MEASURED) are the apt sub-step (`playwright-core install-deps webkit`, 60 / 82 / 65 s), not the Playwright download (WebKit + FFmpeg download in 5 s, every run). Chromium 42 s is the same (apt 37 s of 42). Class `aptVariance` (Lean `stepClass`): the part outside apt is 5-6 s on every row.
- The Post step of 910dacd (43 s, run 40026269429) is the cache save of the apt debs (39 s upload) and the browsers (4 s). Class `fixableSave` (Lean `postClass`).
- Both caches miss on every sampled leg (7 of 7) with one stable key per engine (webkit 969c76e, chromium 1a85621), so it is not key churn and not a missing restore. They miss because a land leg runs on a fresh `ci/land-<task>-<sha>` branch, GitHub lets a branch restore only its own and the default branch's caches (CONFIRMED, docs.github.com "Dependency caching reference", cache access restrictions), and `gh cache list` shows 24 gate-* entries, all on `ci/land-*` refs (2144 MB of the 10.8 GB used), none on `main`. Every land uploads ~356 MB nobody reads (webkit leg 204 MB, chromium leg 152 MB) and adds to the quota that evicts the Lake entry.

## Per sub-step (seconds, MEASURED from logs)
| run | engine | step | apt sub-step | apt fetch | Post | class |
|---|---|---|---|---|---|---|
| 40024272661 (32c4fd4) | webkit | 66 | 60 | 11 | 6 | aptVariance |
| 40031018930 (9bdab20) | webkit | 87 | 82 | 34 | 9 | aptVariance |
| 40026269429 (910dacd) | webkit | 70 | 65 | 43 | 43 | aptVariance + fixableSave |
| 40028997665 baseline | webkit | 33 | 28 | 8 | 8 | ok |
| 40037942688 | webkit | 53 | 48 | 27 | 7 | aptVariance |
| 40024272661 | chromium | 42 | 37 | 6 | 5 | aptVariance |
| 40028997665 baseline | chromium | 23 | 19 | 4 | 4 | ok |

apt fetch is the sum of the "Fetched ... in Ns" lines. Run 1 shows apt time beyond the fetch (index processing 20 s, dpkg 25 s), also variance.

## Fix (action, `.github/actions/gate-engine/action.yml`)
- Save rule (Lean `shouldSave`, theorem `land_prefix_no_save`): no save on `ci/land-*`; every other ref saves. The saves are separate `actions/cache/save` steps (same pinned SHA) that run after the install, only on a miss. The action implements the rule as a shell `case`; its six golden `ref` rows were replayed against it, 0 mismatches.
- Effect: the land-leg Post step drops to about 0 s (4-43 s removed) and 356 MB per land (204 MB webkit leg, 152 MB chromium leg) is no longer uploaded.
- Not fixable in the action: the apt time itself. It becomes cheaper only when the debs cache hits (fetch 8-43 s gone). It hits when `main` holds the entry: `premise-tests.yml` job `engine` seeds it on a `main` push, and that job runs when `.github/actions/gate-engine/**` changes, so landing this change seeds `main`.

## How the next land legs show it (INFERRED until they run)
1. First land after this one: the gate-engine log has `Cache restored from key: gate-apt-debs-969c76e...` (not "Cache not found") and no "Cache saved"; Post gate-engine <= 1 s; apt fetch lines shrink.
2. Verify on main: `premise-tests` push run of the landing commit has job `engine` (not skipped) and "Cache saved with key: gate-apt-debs-969c76e..." on ref main; `gh cache list` shows gate-* entries on refs/heads/main.
3. If the restore does not hit, the key changed or the entry was evicted (quota): read `gh cache list`.
Follow-up (outside this task's writes): `lean/scripts/check.sh` has no job for the new golden: `job "gate-engine-timing golden check" sh -c 'printf "import Fw.Ops.GateEngineTiming\n#eval Fw.Ops.GateEngineTiming.gen [\"--check\"]\n" | lake env lean --stdin'`.

## Follow-ups (task `gate-engine-cache-followups`, 2026-10-24)

### (1) Seeding observed, restore not yet
- `main` was pushed at ecedf75e9. Its premise-tests push run 40045796969 ran guard, job engine (chromium, job 120727183333) and engine (playwright-webkit, job 120727183423): success (MEASURED, `gh run view`). `gh cache list` then shows on `refs/heads/main`: gate-apt-debs-969c76e 108 MB, gate-pw-browsers-969c7.. 96 MB, gate-hs-zip-a0c54c.. 125 MB, gate-apt-debs-1a85621 27 MB (356 MB), created 00:37:19-00:37:51Z. CONFIRMED seeded.
- The first land run created after that, 40045936776 (00:38:03Z, ci/land-accent-nolayout-measure-852ffd7), had no engine leg (jobs check-sh, suites-a, suites-b: the engine legs run only when the selection holds e2e-preview, land.yml `steps.suites.outputs.engine`). So no "Cache restored" / Post line exists yet. Follow-up: read the first land run after 00:37Z whose jobs include `land (chromium)` or `land (playwright-webkit)`: expect `Cache restored from key: gate-apt-debs-969c76e...`, no `Cache saved`, Post <= 1 s. Until then the restore is INFERRED from the docs rule.

### (2) Lean class `RestoreClass` and the seeding rule (`Fw.Ops.GateEngineTiming`)
- `restoreClass ref hit holds`: restored (hit), firstSave (miss on a saving ref), missingRestore (miss on `ci/land-*` while `main` holds none; the land legs read before 00:37Z get this class under the fixed rule `shouldSave` of ecedf75e9, though at their commits the action still saved on `ci/land-*`, e.g. run 40037942688 webkit: Cache saved 23:13:35Z), keyMiss (miss although `main` holds the entry: the key differs). One theorem per branch (`restoreClass_hit/_first/_missing/_keyMiss`).
- Seeding: `seedsMain engineRan holds`: a skipped engine job seeds nothing (`skipped_keeps`, `unseeded_stays`); a run of it seeds (`ran_seeds`). Eviction: 7 idle days (docs.github.com "Usage limits and eviction policy", CONFIRMED); `evicted_reseed`, `fresh_no_reseed`, `unseeded_reseed`, `weekly_restore_keeps` (a restore every gap < 7 days keeps the entry).
- Reseed rule (no scheduled workflow, accepted limit): when `needsReseed`, the next `main` push that changes `.github/actions/gate-engine/**` or the gate inputs reseeds; otherwise the land legs miss with class missingRestore and the lead reads `gh cache list`.
- Golden rows `leg`, `restoreCase`, `seed`, `evict` in `packages/contracts/golden/ops/gate-engine-timing.jsonl`.

### (3) Checks
`lean/scripts/check.sh` job "gate-engine-timing golden check"; `scripts/gate-engine-ref.test.mjs` cuts the `case "${GITHUB_REF_NAME:-}"` line out of the action and runs it in bash on every golden `ref` row, checks the three save steps ask for `save == 'true'`, the restore classes against the ref rule, and the branch-only list against the trigger golden rows.

### (4) Trigger.lean: writers keyed on the ref
`savesOn ref w`: a gate cache saves iff `shouldSave ref`; `land_saves_no_gate`: land.yml's three gate writers save nothing on `ci/land-*`; `branch_entry_unread`: an entry saved on a branch other than `main` is read by no other branch. `branchOnlyWriters` (gate writers not land, not a seeder; golden field `branchOnly`) are in breakpoint-gate (gate), preview-e2e (engine), smoothness (cadence), snapshot-extract (extract), trajectory-probe (frames, probe) and visual-diff (shoot, port-fonts, navscroll, people-layout). A run on `ci/<task>` uploads its own copy only on a restore miss (the action saves only when `cache-hit` is not `true`: `main` lacks the key because it is unseeded or evicted, or the branch changed the key inputs); with `main` seeded it hits and saves nothing. Sizes on a miss: webkit leg 204 MB (apt 108 + browsers 96), chromium leg 152 MB (apt 27 + zip 125), both engines 356 MB; smoothness chromium only (152 MB). The 24 entries on `ci/land-*` (2144 MB) in `gh cache list` are all pre-fix saves; no other branch holds a gate entry now. Follow-up: apply the same rule (no save off `main` or non-seeder) if quota pressure returns.

## Restore observed (task `gate-engine-restore-observe`, 2026-10-24)

- Runs after seed run 40045796969: 40045936776 (no engine leg), 40047376675 (00:55:41Z, ci/land-gc-live-agent-cwd-b081d56, first with engine legs), 40048885356 and 40049992630 (both legs, not read). Read: 40047376675 jobs 120732159815 (playwright-webkit) and 120732159810 (chromium), logs and step times from `gh run view` (MEASURED).
- Restored (CONFIRMED in the log): webkit `Cache restored from key: gate-apt-debs-969c76eb...` 00:57:42Z and `gate-pw-browsers-969c76eb...`; chromium `gate-apt-debs-1a856213...` and `gate-hs-zip-a0c54c69...`. All three "Save ..." steps outcome=skipped; no `Cache saved` line; no `Post Run ./.github/actions/gate-engine` step exists (Post <= 1 s).
- gate-engine step: webkit 39 s (before 53-87 s), apt sub-step 33 s, fetch 5 s; chromium 19 s (before 23-42 s), apt 13 s, fetch 1 s. The apt sub-step still runs (dpkg unpack and trigger work), so the restore saves the fetch and the Post, not the install.
- Golden: samples rows for both legs (hit true, postS 0, step ok, post ok) and leg rows class `restored` with run 40047376675. Lean theorems `miss_before_restore`, `restored_legs_fast`, `legs_classes`.
- Test changes (`scripts/gate-engine-ref.test.mjs`): reads the literal `.github/actions/gate-engine/action.yml`; the restore-class JS test is dropped, because it compared the golden with itself and the action emits no restore class (Lean `legs_classes` and `restoreCases_classes` prove the classes).
