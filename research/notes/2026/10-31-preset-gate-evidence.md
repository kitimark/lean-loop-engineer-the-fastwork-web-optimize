# Preset members need breakpoint-gate evidence

`hero.exit:threaded` entered v2-proved at d6174ba8c on trajectory evidence alone. The breakpoint gate then failed it on
Playwright WebKit (run 41087718575, 147 readings; `10-31-park-attrib.md:23`). Membership in `Fw.Preset.V2Proved` and
`Fw.Preset.Shipped` reads ledger rows and stored trajectory runs only; no gate verdict was recorded anywhere (CONFIRMED,
`lean/Fw/Preset/V2Proved.lean:210` `ok`, `lean/Fw/Preset/Shipped.lean:47` `gateMet` reads trajectory cells).

## The rule

`lean/Fw/Preset/GateEvidence.lean` holds three tables and one rule. The preset check (`Fw.Preset.Gen.run`, check.sh job
`preset v2-proved check`) applies it to every member of v2-proved and shipped.

- `runs`: one row per engine verdict of a breakpoint-gate run: run id, head sha, engine, the exact `?fw=` set, verdict.
- `admissions`: per preset and member, the commit that first wrote the member into the preset golden and the preset's
  full flag set at that commit.
- `waivers`: the members admitted before this rule that lack evidence, each with a reason.

`status` (line 66): a member is **proved** when, on Chromium and on Playwright WebKit, the newest run whose flag set equals
its admission set passes. Without that pair a waived member is **pending** with the waiver's reason. Any other member is
**unproved**, and so is a member with no admission row or whose admission set lacks it. An unproved member, a waiver or
admission of a non-member, or a waiver of a proved member makes `problems` non-empty and the check throws.

`setProblems` (line 101) ties the admission sets of each preset to its current flag set: every admission set is a subset
of it, one equals it, and every two are nested. A hand-typed row `<"v2-proved", X, sha, [X.key]>` for a new member is
not nested with `[engine.scroll:unthrottle]`, so `Gen.run` throws before any run is read.

### Which flag set counts

The single flag is not enough. The gate
compares readings of the whole page, and one flag can move the layout or
timing another part's readings depend on. A pass of each flag alone then says nothing about the
pair (INFERRED; no recorded run shows such an interaction yet). A pass of a superset does not cover the set either. The
admission set is the set that shipped at that commit, so its pass is the claim the preset makes. The newest run decides,
so a later failing run of the same set withdraws the proof.

### Theorems (`lean/Fw/Preset/GateEvidence.lean`)

| theorem | line | statement |
|---|---|---|
| `proved_evidence` | 237 | proved implies an admission row whose set holds the member, and on each engine a passing run of exactly that set that is the newest of that set |
| `not_proved_of_no_admission` | 262 | no admission row, not proved |
| `not_proved_of_no_run` | 277 | an admission set with no recorded run, not proved |
| `problems_of_no_admission` | 295 | a member without an admission row fails the check, whatever the waivers |
| `problems_of_no_pass` | 300 | an unwaived member without a passing pair fails the check |
| `waivers_pinned` | 367 | the waivers are exactly the five pre-rule members below |
| `status_of_*` | 210-235 | one theorem per branch of `status` |
| `setProblems_of_outside`, `_of_no_full`, `_of_unnested` | 323, 330, 343 | one theorem per objection of `setProblems` |
| `forged_single_fails` | 360 | an extra v2-proved row whose set is only a new member `X` fails `setProblems` |

`Fw.Preset.Gen.gate_fails_of_new_v2` and `gate_fails_of_new_shipped` (`lean/Fw/Preset/Gen.lean:1004`, `:1010`) apply this
to the generated presets: a new member without an admission row makes the list `run` throws on non-empty.
`tie_fails_of_forged_v2` (`:998`) does the same for a forged single-flag row against the generated flag sets.

## Evidence per member

Admission sets come from `git log` of `packages/contracts/golden/preset/v2-proved.json` and `shipped.json` (CONFIRMED,
`git show <commit>:<file>`).

| preset | member | admission commit | admission set | status | evidence |
|---|---|---|---|---|---|
| v2-proved | engine.scroll:unthrottle | 8dae67ead | unthrottle | proved | run 40101370753 passes both engines |
| v2-proved | hero.exit:threaded | d6174ba8c | unthrottle, threaded | pending | Playwright WebKit fails: 41078004214 on this set, 41087718575 on threaded alone |
| v2-proved | platform:faded-pause | 6f307554e | all three | pending | no run of this set; 40287895072 passes faded-pause alone |
| shipped | engine.scroll:unthrottle | fb2934b2e | unthrottle, threaded | pending | 41078004214 fails Playwright WebKit on this set |
| shipped | hero.exit:threaded | fb2934b2e | unthrottle, threaded | pending | as v2-proved |
| shipped | platform:faded-pause | 9446c6407 | all three | pending | as v2-proved |

Runs in the table (CONFIRMED: `gh run view` for head sha, branch and conclusion; engine verdicts from each run's
merge-job log):

| run | head | `?fw=` | Chromium | Playwright WebKit | source |
|---|---|---|---|---|---|
| 39774976109 | ff8c8cd1b | threaded | pass | fail | `10-31-park-attrib.md:21` |
| 40101370753 | 0bd2a50c6 | unthrottle (preset v2-proved at that head) | pass | pass | `10-2x-webkit-morph-cell.md:86,101` |
| 40287895072 | 5a82a5463 | faded-pause | pass | pass | `10-2x-platform-faded-pause.md:35` |
| 41078004214 | 72d0bfd91 | unthrottle, threaded | pass | fail | `10-31-park-attrib.md:20` |
| 41086902481 | 31fdd85b6 | none | pass | pass | `10-31-park-attrib.md:22` |
| 41087718575 | 31fdd85b6 | threaded | pass | fail | `10-31-park-attrib.md:23` |

- The v2-proved preset at 0bd2a50c6 holds `engine.scroll:unthrottle` only (CONFIRMED, `git show
  0bd2a50c6:apps/site/src/registry/presets/v2-proved.json`).
- The shipped preset was created with threaded already in it, so its unthrottle admission set holds threaded. That is why
  unthrottle is proved in v2-proved and pending in shipped.
- The verdicts of all six runs were re-read from their merge-job logs (`gate verdict <engine>:` lines).

## Output

- `packages/contracts/golden/preset/gate-evidence.jsonl`: one line per (preset, member) with status, admission, the
  proving run ids or the reason, and every recorded run whose flag set holds the member.
- `Fw.Preset.Gen.run` prints one `gate evidence:` line per member.

## Limits

- The tables are Lean data written from the runs above; the gate merge job does not feed them yet.
- Admission rows are written by hand from git history; the check cannot replay git (CI clones are shallow).
  `setProblems` ties them to the generated flag sets, but two members added in one commit could still claim a nested
  set between the earlier sets and the current one; that set holds every earlier member and needs its own passing run.
- A waiver needs a Lean edit and a change to `waivers_pinned`, so it shows in review; the rule does not stop a reviewer
  from accepting one.
- No preset changed. Whether threaded stays is the user's decision (console step threaded-look).
