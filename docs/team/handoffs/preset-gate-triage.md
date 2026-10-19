# preset-gate-triage handoff

Branch worktree-wf_b6a284ed-7ed-1, CI branch ci/preset-gate-triage. Read first: research/notes/2026/10-19-preset-gate-triage.md.

## State
- 3 gate dispatches on ci/preset-gate-triage (Chromium, sha 0f0e95a7): 39197237678 = preset v2-proved, 39197247960 = morph.mount:shift,
  39197258964 = hero.countdown:strip. 4th dispatch unused.
- Result (MEASURED): hero.countdown face count <- strip; nav actions/bar counts <- shift (hosted morph panel matched by the structural
  selectors); platform --morph-fade fixed by morph-tween-inherit (passes in the re-gate). Preset now fails only those 3 count items (392 bad readings).
- No code, preset or Gen.lean edited; only the note and this handoff.

## Open (lead decides)
- Row 1: keep strip in Λ only if the gate gets a Lean variant role map + theorem (visual half proved: HeroCountdownOpt.strip_visSame); else unlink.
- Row 2: fix anchors.json bar/actions selectors to exclude [data-fw="morph-panel"], then one re-gate of the shift arm / preset.
- WebKit arm of the preset not run (accepted limit).
- Local checks (package tests, ci-paths) not run: no code touched.
