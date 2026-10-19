# indep-bridge handoff
**State:** branch `worktree-wf_11ac09ad-a60-3`, see `git log -1`. New `lean/Fw/Parts/Bridge.lean`, imported in
`lean/Fw.lean`. `lake build` is green; axioms are `propext`, `Classical.choice` and `Quot.sound` only.
**Verified (Lean, all in `Fw.Parts.Bridge`):**
- The literal `Independent p q → Indep p q` fails: 299 ordered chain pairs on `codeParts` (`chainPairs_code_iff`,
  `chainTargets_code`), e.g. commission → engine.scroll → hero.exit; seven self-`Independent` rows (`selfIndep_code`).
  Counterexamples: `chain_not_readsOnly`, `selfIndep_not_readsOnly`.
- The adopted `Indep` is `Flow ps i j := ¬ Reach ps i j`. `Reach` is the path closure of non-`quiet` edges, where
  `quiet` is `Independent` minus the reverse half of I3. The premise is `FlowSound ps obs`.
- Bridge: `Isolated ps p` gives `∀ q ≠ p, Flow ps p q` (`flow_of_isolated`). The 14 isolated rows (`isolated_code`):
  commission.typing, hero.cue/deck, morph.panel, nav.langMenu, overlays.drawer/signup, people, people.carousel,
  platform.entries/glint/marquee/stageBg/sweep. Only overlays.drawer and people are `Independent` of all rows.
- `lego_swap_{sound,units,visible,passes}_flow` hold under `FlowSound` plus `Isolated`.
- S3: a strict part saving on stage s never raises page s passes (`passes_append_le`, `passes_pageOf_le`). Under `≤`
  alone the page can rise by exactly 1 (`passes_append_le_succ`; `passes_append_le_fails` hits it on style, layout).
**PLAN §10.7 status changes:**
- S3 becomes CONFIRMED. Its only hypothesis is a strict per-stage saving; "≤ ⇒ never an increase" is refuted.
- S1, S2 (per-flag attribution) and S5 (sibling and visual cut) are CONFIRMED only relative to `FlowSound codeParts`
  for frame and arm, and only for the 14 isolated rows. S5 also needs equal band height and an equal visible scene.
  S5 only for isolated rows that are stacked bands. nav.langMenu, overlays.drawer, overlays.signup and morph.panel
  (CG2, in the nav) are excluded, as PLAN §4.8 limit 2 requires. Remaining S5 candidates: commission.typing, hero.cue,
  hero.deck, people, people.carousel, platform.entries/glint/marquee/stageBg/sweep. All stay INFERRED until
  `FlowSound` is proved; its open parts are row completeness, I5, and reads no wire carries (hit tests, computed
  style, `rect:?`). The units sum (`frameWork_append_units`) was already unconditional.
**Open items:** the hero.countdown ↔ morph.countdown group swap (they reach each other); a `FlowSound` instance for a
concrete frame/arm model; swaps of non-isolated rows. FlowSound(arm) and stackScene need a map from codeParts index to
page band. For a nested sub-part the parent's arm reads the child, so lego_swap_visible_flow does not apply to
sub-parts until arms are modelled per band.
**Conventions:** positions are `codeParts` indices (alphabetical id order), not stack order; `adj_code` checks
`codeAdj`; large literals use `decide +kernel`. **Read first:** Bridge.lean section headers, `flow_of_isolated`.
