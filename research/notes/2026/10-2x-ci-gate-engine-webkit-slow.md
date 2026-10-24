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
