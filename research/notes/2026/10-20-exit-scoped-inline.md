# exit-scoped-inline: bug A of hero.exit:scoped (stale WebKit readers) and the inline fix

Task `exit-scoped-inline`. Inputs: bug A (MEASURED by trajectory-probe: macos-26 187 and Linux WebKit 228 new hero units in
copy, cta, countdown, deck.card, cue; Chromium 0; runs 39419128841 and 39407166794), ledger row `hero.exit.scoped.falsified`.

## Mechanism (CONFIRMED, WebKit source @862f17d)

The readers (`.card`, `.copy`, `.cue`) compute `opacity`, `filter`, `transform` and `translate` from `var(--exit-opacity)` and
`var(--exit-scatter)`. Under `hero.exit:scoped` both properties are registered with `inherits: false`; the readers get them
through `[data-exit-scope] .X { --exit-*: inherit }` rules.

1. WebKit resolves an element through the matched-declarations cache. The key is the element's matched declarations plus
   the parent's **inherited** custom properties: `computeHash(matchResult, parentStyle.inheritedCustomProperties())` and
   `find` compares `&entry.parentRenderStyle->inheritedCustomProperties()` by identity
   (Source/WebCore/style/MatchedDeclarationsCache.cpp:123-137,139-163; StyleResolver.cpp:693-695).
2. The parent's non-inherited custom properties (`m_nonInheritedData->rareData->customProperties`,
   Source/WebCore/style/computed/StyleComputedStyleBase+GettersInlines.h:293-295) are not part of the key. A stage write of a
   registered non-inherited property does not change the key, so each reader hits the entry it built earlier.
3. On a hit WebKit copies every non-inherited property from the entry (`copyNonInheritedFrom`, StyleResolver.cpp:703;
   StyleComputedStyle.cpp:225-233). If the parent's non-inherited data differs it re-applies the `ExplicitlyInherited`
   type only (StyleResolver.cpp:706-707,723-724), and that type selects declarations whose value is the `inherit` keyword
   (Source/WebCore/style/PropertyCascade.cpp:332-333). So `--exit-opacity: inherit` is re-applied (the reader's own variable
   is fresh, as the local repro showed) and `opacity: calc(var(--copy-in) * var(--exit-opacity))` keeps the cached value.
   The cta, countdown units and the rest of the copy move with the copy's stale transform and opacity.
4. Faithful has no such hit: the unregistered property is inherited data, so each write gives the parent new inherited
   custom properties and the identity test fails (MatchedDeclarationsCache.cpp:153).

## Fix: write the exit values inline on each reader

The scoped driver writes the stage as before and, in the same writer, `--exit-opacity` and `--exit-scatter` on each reader
(Lean `readerWrites`: the stage value, and `calc(1 - <value>)`, or `0` under reduced motion). The readers are queried once
on mount by `READER_SELECTOR` (`[data-fw="hero"]`, `[data-fw="hero-cue"]`, `[data-orbit-id]`, `[data-fw="hero-deck"] >
article`); scoped.test.ts checks that it selects exactly the elements carrying the Lean `readers` classes (16).

Side effect on the part graph (CONFIRMED, `Fw.Parts.Bridge`): the footprint now records hero.exit writing `--exit-*` on
hero, hero.cue and hero.orbit elements. Two edges join `adj codeParts` (hero to hero.exit, hero.cue to hero.exit),
hero.cue leaves the isolated rows (14 to 13, `isolated_code`) and the failing literal-bridge pairs go from 299 to 322
(`chainPairs_code_length`). docs/report/v2-report.md lines 124, 559 still state 14 isolated parts.

Why it is invalidation-safe (CONFIRMED, source): `element.style` makes the inline style a `MutableStyleProperties`
(Source/WebCore/dom/StyledElement.cpp:81-83,93-105). Mutable inline style is `IsCacheable::No`
(ElementRuleCollector.cpp:968-971), which makes the match result `isCompletelyNonCacheable` (:994-996), so the hash is 0
(MatchedDeclarationsCache.cpp:125-126): no lookup (:141-142), no add (StyleResolver.cpp:747). The inline change itself
re-resolves the reader; on the inline fast path a changed custom property forces a full apply
(Source/WebCore/style/MatchResultCache.cpp:126-127).

## Proved (Lean `Fw.Parts.HeroExitOpt`, section Scoped)

| theorem | statement |
|---|---|
| `wkRun_inherited`, `wkRun_inline` | in the cache model, faithful and inline show the current value at every frame |
| `wkRun_chain_frozen` | the chain shows the first value at every later frame (bug A); own value stays fresh |
| `chain_stale_webkit` | concrete copy-path counterexample: chain `[1, 1]` vs faithful `[1, 0.5]` |
| `chain_eq_chromium` | without the cache (Chromium model) the chain equals faithful |
| `shown_inline_eq`, `inline_visSame` | VisSame E: every scene drawn from the readers' inputs is equal for inline and faithful, both engines, every frame of every write sequence |
| `inline_touched` | 17 elements written per frame (stage + 16 readers), both widths |
| `inline_units` | resolutions per frame equal scoped: Chromium 9 / 17, WebKit 9 / 17 (narrow / wide); hidden readers are not marked (third_party/blink/renderer/core/dom/node.cc:1474-1479,1659-1660@f842f52; StyleTreeResolver.cpp:1386-1387@862f17d) |
| `inline_lt_faithful`, `inline_narrow_delta` | strictly below faithful; 90 fewer per frame at narrow |

Golden `hero.exit.scoped.json` gains `inline`, `readerWrites` and the reader rows of `frameWrites`; `scoped.test.ts` checks
`readerWrites`, the reader classes, the SSR reader count (16) and the writer order against it.

Limits: the cache model has one entry per reader key and no eviction (MatchedDeclarationsCache sweeps and evicts); the
unit counts are model products, validated only as between-arm deltas. The pre-first-write state is covered by `defaults`
(the chain). The JS reduced-motion read and the CSS media are assumed to agree within a frame (INFERRED).

## CI (OPEN at this commit)

Branch `ci/exit-scoped-inline` at the task commit. Dispatches needed (lead): trajectory `--fw hero.exit:scoped` twice
(Apple job runs), A/A `--fw hero.exit:faithful` once, Chromium counts swipe-v1 for scoped and faithful. Until run ids
exist, the 187 -> 0 claim is not measured.
