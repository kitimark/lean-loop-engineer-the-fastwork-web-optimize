# Handoff: morph-scroll-lock (C4), land-fix round (after round 3)

**State.** Branch `worktree-wf_22f9acfd-29a-1`: round 2 code b4b8b377, note 5ee20980, CI cbb7f262; round 3 merge of
main 2d2e2188 with the fixes in 24f3918a; handoff da34b5fd. CI ran at b4b8b37 only (round 3 dispatched none).
Land fix (land run 39511980842, suites-a, scope.test `mq.hover-none`): Lean scope 796d8e71 and the next commit, note and
handoff in the commit after those. Read first: `research/notes/2026/10-21-morph-scroll-lock.md` (verdict, design, Lean,
"Breakpoint gate: the new condition", CI, regen command, ledger row).

**Land fix (verified locally).** `Fw.Gate.Scope` `PartUse.added` (rewrite-only ids with reason), morph.tween lists
`mq.hover-none`; `pilot_added_exact`, `scope_hover_none_both`; `scope.gen.json` regenerated (`scopegen.mjs`, `--check` ok);
`scope.test.mjs` checks added = rewrite outside orig. gate-breakpoints `pnpm test` 425/425, `fw checks --affected --base
main --tier remote --leg suites-a` all 5 pass, `check.sh` green, site test+typecheck, ci-paths, runner land-inputs green.
The inventory `breakpoints.json` (the original) stays unchanged on purpose. No CI pushed this round.

**Verified (at 24f3918a).**
- `MorphTweenOpt.lean` keeps both sections: MT-L (scroll lock) and main's `WidthTail` (`hit_iff_mP` etc.), nothing dropped.
- Hover gate fails closed: Lean `hoverNoneOf` (`none` counts as matching), `engage_unread`, `engage_read_touch`; golden
  engage rows with `hoverNone: null`. `index.tsx` `scrollLockOf` uses `hoverNoneOf`; `scroll-lock.gate.test.ts` (jsdom)
  checks no lock when `(hover: none)` matches and when `matchMedia` throws, a lock when it reads false.
- `sh lean/scripts/check.sh` green (1:06); site `test` and `typecheck`, `scripts/ci-paths.test.mjs`, runner
  `land-inputs` green. Footprint regenerated (`part-footprint.mjs --write`); `Fw.Preset.Gen.run` left
  `look-change.candidates.jsonl` unchanged.
- The note's regen command for `lockJsonl` reproduces the golden byte for byte.

**Open.**
- Ledger row not applied; the JSON is in the note.
- The probe cannot show the scrollTo saving (`still_eq`); a trackpad-gesture probe step that records engagement is the follow-up.
- macOS runner scrollbar kind unknown; the net of 2 root style passes per morph against the saved scrollTo calls is INFERRED.

**Conventions.**
- Arm is `visClass: "L"`, kind `proposal`. Generated files: footprint (`apps/site/scripts/part-footprint.mjs --write`),
  `look-change.candidates.jsonl` (`#eval Fw.Preset.Gen.run []` in a scratch file, `lake env lean`).
- Golden regen: the `sh` block under "Lean (MT-L)" in the note (copies the module without `include_str` lines into a temp
  dir and runs `lockJsonl` with `lake env lean --run`); no source edit.
