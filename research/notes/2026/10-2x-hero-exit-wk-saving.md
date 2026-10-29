# hero.exit:threaded: the WebKit style saving per element

Tags: CONFIRMED (Lean theorem or source cited), INFERRED (reasoned, not seen). No CI or phone runs. Pin:
WebKit 862f17d (`W` = `Source/WebCore`).

## Answer

* On WebKit the variant's scrolled frame runs the original's single style pass but restyles 6 elements (phone band)
  or 12 (above), with 13 or 25 animation units. The original's inherited `--exit-opacity` write resolves the whole
  hero subtree: 123 or 215 elements. `HeroExitWork.wk_style_saving`, CONFIRMED (Lean, under the premise below).
* With the fan-out counted, the WebKit trade has strictly fewer style units and restyled elements, still one added
  compositor pass: `wk_trade_r2`, and under `frameWorkE` `wk_trade_r2E`. `wk_trade`, `wk_tradeE` and `wkOrigChanges` are unchanged.
* `ResourceFlags` `hero.exit:threaded` WebKit style is per element: (style passes, restyled elements) over the
  golden frames is (1, 123) for the original and (1, 6) for the variant, so the prediction is `down`. The phone check
  (627-631 against 646-651 records per run) moves from disagree to agree. Checks: agree 52, unresolved 9,
  confounded 24, disagree 7, unpredicted 7.
* Ledger row n 6 stays `proved` by `why`; the new theorems are in its `leanFor`. `Gen.run` keeps
  `hero.exit:threaded` at `enter`, no blockers.

## The premise: WebKit's inherited propagation

`WkInheritRule r`: after an inherited custom-property write on a root, one style pass resolves the root and, unless
the root has no box, each child under the same rule. Source, CONFIRMED:

| Step | Source @862f17d |
|---|---|
| inherited custom properties live in the inherited rare data | `W/style/computed/StyleComputedStyleBase+GettersInlines.h:288-290` |
| a changed custom-property value fails `nonFastPathInheritedEqual` (`DataRef` compares by value, `Source/WTF/wtf/DataRef.h:87-90`@862f17d) | `W/style/computed/StyleComputedStyle.cpp:296-297` |
| which adds `Change::Inherited` | `W/style/StyleChange.cpp:42-43` |
| an inherited change resolves every child (`DescendantsToResolve::Children`) | `W/style/StyleTreeResolver.cpp:307-308` |
| children resolve in full, no fast path under `Change::Inherited` | `W/style/StyleTreeResolver.cpp:1190-1204` |
| `display: none` stops the descent | `W/style/StyleTreeResolver.cpp:1387-1388` |

The rule fixes the count: any `r` that follows it equals `Restyle.wkFull` on every tree (`eq_wkFull_of_rule`), and
`wkFull` follows it (`wkInheritRule_wkFull`). Unlike Chromium (`crFull`, 99 and 172) WebKit has no independent-
inheritance clone path for subtrees without custom properties, so it counts 123 and 215.

The variant side: its animated properties are non-inherited, so a changed consumer resolves only children with an
explicit `inherit` of a non-inherited property (`W/style/StyleTreeResolver.cpp:310-311,1207-1209`; the flag is set
only for `inherit` of a non-inherited property, `W/style/StyleBuilder.cpp:439-440,576-577`). In the threaded build
`data-exit-scope` is unset (`apps/site/src/parts/hero.exit/index.tsx:81`), so the scoped `inherit` rules do not apply;
the remaining `inherit` declarations in the hero subtree are of inherited properties (`color`, `font`). CONFIRMED.

## Lean

`lean/Fw/Parts/HeroExitWork.lean`, section `WkFan`:

* `styleElems E f`: distinct elements of the frame's changes that dirty `style`.
* `wkOrigR2 r ℓ lo`: the lifted `wk_trade` original frame plus the hero's inherited write and `wkFanOut r ℓ`
  restyles (116 phone, 202 wide under `wkFull`); `wk_orig_r2`: same passes, `wkFanOut r ℓ + 1` more style units.
* `wk_orig_r2_elems`, `wk_var_elems`, `wk_style_saving`, `wk_trade_r2`, `wk_trade_r2E`.

`lean/Fw/Engine/ResourceFlags.lean`: `wkStyleElemPair` with `#guard`s on `((1, 123), (1, 6))` and its sign `down`;
the old `mechanisms` entry for the disagreement is removed.

## Limits

* The inherited-propagation rule is a cited premise, not modelled engine code.
* Query containers (`.card` has `container-type`) defer their descendants (`W/style/StyleTreeResolver.cpp:1390-1392`);
  INFERRED that they are resumed in the same update, so they are counted.
* The phone records count style recalcs, not elements, so the check agrees in direction only. The variant run also
  renders fewer frames (588 against 693-696). INFERRED.
* RG11 stays a hypothesis of `consumer_eq_s`.

## Open

* The fan rows use synthetic element ids `100 + i`, not ids from the page tree.
* Query-container deferral: that the deferred descendants resume in the same update is INFERRED, not read from source.
