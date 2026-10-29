# hero.exit:threaded: one animation per CSS name, and what a style unit is

Tags: CONFIRMED (Lean theorem or source cited), INFERRED (reasoned, not seen). No CI or phone runs in this task. Pins:
WebKit 862f17d (`W` = `Source/WebCore`), Chromium f842f52 (`B` = `third_party/blink/renderer/core`).

## Answer

* `HeroExitOpt` counted a consumer's opacity and transform as one animation (`N + 3` / `N + 4`). The CSS declares
  one animation name per property, so the count is `2N + 5` in both bands. The list is now read from `exitNames`,
  the names the site test checks against the CSS, with one property per name (`nameProp`): `animCount_eq`. CONFIRMED.
* A style unit is per element in both engines. The compositor tick and the keyframe apply are per animation. CONFIRMED
  (source below).
* WebKit: the variant's style units now equal the original's (`2N + 5` each, on the same `N + 2` elements:
  `wk_style_elems`). The strict style drop is gone. `wk_trade` stays strict through the script pass, with the new
  conjunct `V.units .style = O.units .style` (also in `wk_tradeE`). CONFIRMED (Lean).
* Chromium lane: style units `V = O + (N + 2)` (was `+ [¬ℓ]`), props `V = O + (N + 3)` (was `+ 1 + [¬ℓ]`), in both
  bands (`cr_lane_mixed`). Per element the ride-along covers `N + 2` elements, a strict subset of the original's `N + 3`
  (`cr_lane_style_elems`). Real Chrome: only the compositor units change (`cr_real_trade` keeps its statement).
* `cr_style_saving` and `cr_lane_style_saving` stay strict: `13 < 99` and `25 < 172`. The golden predictions in
  `golden/engine/hero-exit.jsonl` do not change.
* Ledger row n 6 stays `proved`; `why` gives `proved`; `Gen.run` keeps `hero.exit:threaded` at `enter`, no blockers.
* One measured check flips: the WebKit style footprint sign is now `same`, while the phone count went down (627-631
  against 646-651 records per run). INFERRED cause: the variant run renders fewer frames (588 against 693-696), so it
  records fewer style recalcs while each rendering update costs the same. `ResourceFlags` lists it as a disagreement
  with that mechanism.

## Style unit: WebKit (per element)

* `KeyframeEffect::animationDidTick` calls `invalidate()` (`W/animation/KeyframeEffect.cpp:2129-2132`), which reaches
  `Element::invalidateStyleForAnimation` → `Node::invalidateStyle(Validity::AnimationInvalid)`
  (`W/dom/Element.cpp:2763-2767`).
* `Node::invalidateStyle` marks ancestors only while the node is `Valid`, and `adjustStyleValidity` only raises the
  validity (`W/dom/Node.cpp:1018-1023`, `951-957`). A second animation on the same element adds no work there.
* `TreeResolver::determineResolutionType` picks the resolution per element (`W/style/StyleTreeResolver.cpp:1162`).
  The element is resolved once, and its animated update calls `applyKeyframeEffects` once.
* `KeyframeEffectStack::applyKeyframeEffects` loops over the sorted effects (`W/animation/KeyframeEffectStack.cpp:141`):
  the apply work is per animation inside one element's resolution.
* Each effect gets its own accelerated representation (`KeyframeEffect::acceleratedRepresentation`, `W/animation/KeyframeEffect.cpp:3292-3295`).
  `translate` shares `transform`'s style difference (`W/style/StyleDifference.cpp:246-247`), which `cssWk` follows.

## Style unit: Chromium (per element)

* `KeyframeEffect::ApplyEffects` calls `SetNeedsAnimationStyleRecalc` (`B/animation/keyframe_effect.cc:698`,
  `739-742`). That call returns early once the element has a style change (`B/dom/element.cc:7419-7428`).
* `StyleResolver::ResolveStyle` applies the animated style and calls `IncrementResolvedStyleCounters`, one
  `IncStyleForElementCount` per element (`B/css/resolver/style_resolver.cc:1362-1364`). `UpdateLayoutTree.elementCount`
  is the delta of that counter (`B/dom/document.cc:2855-2867`).
* `CSSAnimations::CalculateAnimationUpdate` creates one `CSSAnimation` per name (`B/animation/css/css_animations.cc:2499`),
  and each `Animation` gets its own compositor animation (`B/animation/animation.cc:3450`).

## What the model keeps (INFERRED limits)

* `Fw.Engine` units stay per change and per compositor animation. The per-element counts are the separate lemmas
  `wk_style_elems` and `cr_lane_style_elems`, not a new engine unit. Moving the engines to per-element style units
  is a follow-up.
* The site test `apps/site/src/parts/hero.exit/threaded.test.ts` checks the animation names against the golden; it
  does not check `nameProp`, the property each name animates. Follow-up.
* RG11 stays a hypothesis. Blur-kernel interior frames and data-exit-live handover frames stay unmodelled.

## Evidence names

`Gen.lean` now lists the theorems the proved branch of `threadedEvidence` cites (`threadedRowNames`, resolved names).
`#guard`s check that every theorem token in that text is one of them (or `threaded_proofs_iff`), and test the link
check `threadedLinkGaps` on inline ledgers. `Gen.run` (run by check.sh's preset job) checks that each name is in row
n 6's `leanFor` or `leanAgainst` of the ledger file. A compile-time read of the ledger would put `research/` in the
Lean build cone, which `scripts/ci-paths.test.mjs` refuses.
