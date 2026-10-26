# Breakpoint gate: replaced parts (task gate-replaced-parts)

Status: proved in Lean, harness wired and tested. No CI gate run here (the morph.stage rerun belongs to morph-stage).

## Problem
`fw=morph.stage:on` unmounts morph.mount and morph.tween. Gate run 40339272935 fails 28 Chromium and 24 WebKit cells,
all in those two parts: their anchor counts are 0 on the rewrite and 1 on the original (research/notes/2026/10-2x-morph-stage.md
in the morph-stage worktree). `Fw.Gate.FlagDelta` only excuses style tuples, so no flag that unmounts a part could pass the gate.

## Design (closed)
- Entry `Fw.Gate.FlagDelta.ReplacedPart` (id, flag, part, reason, premise : Lean.Name). The canonical list
  `Fw.Gate.FlagDelta.replacedParts` is empty today. The gate reads its entries only from `flag-delta.jsonl`, lines of kind `replaced`.
- An item is an absent anchor (`Fw.Gate.Replaced.absent`) when all of these hold: it is a count item (key `count`), not
  decided by rect, its status is `differ`, and its rewrite count is `some 0`. Because `countStatus a 0 = differ ↔ 0 < a`
  (`countStatus_absent`), the original has the anchor.
- An entry excuses an item only when its flag is on, its part is the reading's part and the item is an absent anchor.
  A style delta is tried first (`excuse`). A reading passes only when every failing item is excused. This is the
  FlagDelta rule with one more excuse kind.

## Theorems (lean/Fw/Gate/Replaced.lean)
| claim | theorem |
|---|---|
| an entry never excuses another part's item | `entry_same_part`, `other_part_none`, `other_part_fails` |
| an entry never excuses a present anchor | `present_none`, `present_anchor_fails` |
| an entry never excuses a style, box or info item | `not_count_none`, `excuse_style` (a style item's excuse is FlagDelta's), `delta_not_count` |
| an excuse needs the flag on | `entry_flag_on` |
| no entries means today's verdict and excused list | `readingVerdict_nil`, `allExcused_nil`, `excusedItems_nil` |
| a verdict changes only from fail to pass | `readingVerdict_changes` |
| one unexcused failing item keeps the fail | `unexcused_fails` |
| a pass means each item is a style delta or an absent anchor of an entry for this part | `pass_items` |
| exactness: flag on, entry for the part, all failing items absent anchors means pass | `absent_pass` |

## Golden and harness
- `packages/contracts/golden/gate/replaced.jsonl` (scripts/GateReplacedGolden.lean, check.sh job "replaced golden
  check") holds 2 fixture entries (flag `fixture.stage:on`, parts morph.mount and morph.tween, premise
  `Fw.Gate.Replaced.fixture_unmounted_iff`) and 26 reading cases. Each case is decided with the fixture entries or
  with none.
- `packages/gate-breakpoints/src/replaced.mjs` replays the decision. Its test checks every Lean case.
  `summary.mjs applyFlagDeltas` uses it with the canonical entries. `flag-delta.mjs wireItem` now also carries
  `rewriteCount`, the rewrite count of a count item.
- `flag-delta.jsonl` is byte-identical: no canonical entry exists yet.

## The entry morph-stage adds (in its own writes)
In `lean/Fw/Gate/FlagDelta.lean`, add `import Fw.Parts.MorphStage` and:
```lean
def replacedParts : List ReplacedPart :=
  [ { id := "stage-mount", flag := "morph.stage:on", part := "morph.mount",
      reason := "the sticky stage replaces the scroll-jack; the mount target is not mounted under the flag",
      premise := ``Fw.Parts.MorphStage.jack_off_iff },
    { id := "stage-tween", flag := "morph.stage:on", part := "morph.tween",
      reason := "the sticky stage replaces the scroll-jack; the tween scroller is not mounted under the flag",
      premise := ``Fw.Parts.MorphStage.jack_off_iff } ]
```
Then regenerate `packages/contracts/golden/gate/flag-delta.jsonl` with
`cd lean && lake env lean --run scripts/GateFlagDeltaGolden.lean > ../packages/contracts/golden/gate/flag-delta.jsonl`.
In `packages/gate-breakpoints/test/flag-delta.test.mjs`, the pinned list in "the replaced-part list is the reviewed
one" becomes `[['morph.stage:on', 'morph.mount', 'Fw.Parts.MorphStage.jack_off_iff'], ['morph.stage:on', 'morph.tween', 'Fw.Parts.MorphStage.jack_off_iff']]`.
Then rerun the gate with `fw=morph.stage:on`.

## Accepted limits
- The premise is checked to name an existing declaration (double-backtick name, resolved at compile time). Lean does
  not check what that theorem states. The reviewer checks that it says the part is unmounted under the flag.
- The TS side is a port of the decision, replayed against every Lean case, like FlagDelta. It is not run through fwcore.
