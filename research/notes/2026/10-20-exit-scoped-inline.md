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
(Lean `readerWrites`: the stage value, and `calc(1 - <value>)`, or `0` under reduced motion). The readers are the
elements `READER_SELECTOR` (`[data-fw="hero"]`, `[data-fw="hero-cue"]`, `[data-orbit-id]`, `[data-fw="hero-deck"] >
article`) selects below the stage. `liveReaders` (scope.ts) queries them on mount and again at the next write after a
child-list change or a change of `data-fw` or `data-orbit-id` below the stage (a `MutationObserver`, read synchronously
with `takeRecords` in the writer), so a reader mounted later (remount, HMR) gets the inline writes too. scoped.test.ts
checks that the selector selects exactly the elements carrying the Lean `readers` classes (16);
readers.component.test.ts (jsdom) mounts the whole hero, checks that the 16 readers hold an inline `--exit-opacity`
after the parts' effects ran, and that `liveReaders` picks up an added deck card and drops a removed reader.

Side effect on the part graph (CONFIRMED, `Fw.Parts.Bridge`): the footprint now records hero.exit writing `--exit-*` on
hero, hero.cue and hero.orbit elements. Two edges join `adj codeParts` (hero to hero.exit, hero.cue to hero.exit),
hero.cue leaves the isolated rows (14 to 13, `isolated_code`) and the failing literal-bridge pairs go from 299 to 322
(`chainPairs_code_length`). docs/report/v2-report.md lines 124, 559 still state 14 isolated parts (outside this task's
writes; follow-up for the lead).

Footprint attribution of the deck cards (CONFIRMED, apps/site/scripts/part-footprint.mjs): an element's owner is the
part folder whose JSX renders it (research/notes/2026/10-19-contract-rows-from-code.md, "owner rule: the JSX folder"),
and a selector is resolved by its subject compound only (`resolveSelector` takes the last compound). The deck's cards are
the `<article>` of hero.orbit/card.tsx, so `[data-fw="hero-deck"] > article` resolves to hero.orbit and no hero.deck to
hero.exit edge exists under that rule; hero.deck stays isolated. The ancestor compound `[data-fw="hero-deck"]` is a
structural dependency the footprint does not see: a deck variant without that attribute would drop the deck cards from
the inline writes. hero.deck has one variant (`faithful`), and scoped.test.ts renders it and fails if the selector
stops selecting exactly the reader-class elements. A footprint that resolves ancestor compounds is a follow-up.

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

The `.inline` branch of `wkResolve` (fresh, no lookup, no add) is the model's premise taken from the lines above, not
derived; `wkRun_inline`, `shown_inline_eq` and `inline_visSame` hold under it. The trajectory runs below measure it.

Limits: the cache model has one entry per reader key and no eviction (MatchedDeclarationsCache sweeps and evicts); the
unit counts are model products, validated only as between-arm deltas. The pre-first-write state is covered by `defaults`
(the chain). The JS reduced-motion read and the CSS media are assumed to agree within a frame (INFERRED).


## CI (MEASURED)

Branch `ci/exit-scoped-inline`. At 071906af (round 1; macOS walks hero only, reps 3): 39448209903 and 39452631146
(`?fw=hero.exit:scoped`), A/A 39456741492 (`?fw=hero.exit:faithful`: both arms run the default config). At 45a40e7b
(merged main plus `liveReaders`; macOS walks hero and morph, reps 5): 39466179818 (scoped) and A/A 39472217441. Bug A
before the fix: 187 new hero units on macos-26 and 228 on Linux WebKit (runs 39419128841, 39407166794).

New units against the faithful arm on the hero path (the path of bug A; `rel = new` in `units-<engine>.json`):

| run | commit | macOS WebKit | Linux WebKit | Chromium |
|---|---|---|---|---|
| 39448209903 scoped | 071906af | 0 | 0 | 0 |
| 39452631146 scoped | 071906af | 0 | 0 | 0 |
| 39456741492 A/A | 071906af | 0 | 0 | 0 |
| 39466179818 scoped | 45a40e7b | 0 | 0 | 0 |
| 39472217441 A/A | 45a40e7b | 0 | 0 | 0 |

The macOS hero `both` units (41, 49, 83 scoped; 98, 58 A/A) fail in the faithful arm too: they are the faithful arm's
own red against the original (bug C, task faithful-hero-baseline), not new.

Lean `outcome` (`Fw.Gate.Trajectory.outcome` on `Fw.Preset.Gen.storedOf` of each artifact, computed in a scratch
script; nothing is written to `v2-proved.trajectory.jsonl`, which is outside this task):

    outcome: run 39448209903 chromium hero: pass
    outcome: run 39448209903 chromium morph: pass
    outcome: run 39448209903 linux-webkit hero: pass
    outcome: run 39448209903 linux-webkit morph: no verdict: coverage
    outcome: run 39448209903 mac-webkit hero: pass
    outcome: run 39452631146 chromium hero: pass
    outcome: run 39452631146 chromium morph: pass
    outcome: run 39452631146 linux-webkit hero: pass
    outcome: run 39452631146 linux-webkit morph: no verdict: coverage
    outcome: run 39452631146 mac-webkit hero: pass
    outcome: run 39456741492 chromium hero: pass
    outcome: run 39456741492 chromium morph: pass
    outcome: run 39456741492 linux-webkit hero: pass
    outcome: run 39456741492 linux-webkit morph: no verdict: coverage
    outcome: run 39456741492 mac-webkit hero: pass
    outcome: run 39466179818 chromium hero: pass
    outcome: run 39466179818 chromium morph: pass
    outcome: run 39466179818 linux-webkit hero: pass
    outcome: run 39466179818 mac-webkit hero: pass
    outcome: run 39466179818 mac-webkit morph: fail
    outcome: run 39472217441 chromium hero: pass
    outcome: run 39472217441 chromium morph: pass
    outcome: run 39472217441 linux-webkit hero: pass
    outcome: run 39472217441 mac-webkit hero: pass
    outcome: run 39472217441 mac-webkit morph: fail

At 45a40e7b Linux WebKit walked no morph units in either run, so that cell has no line. `mac-webkit morph: fail` holds
in the A/A run as well, so it is the A/A floor. The morph path is reported here and not counted: the footprint puts the
hero.exit writes on no morph-path node (owners hero, hero.cue, hero.orbit, hero.exit).

Content-new morph units (coverage-new units left out; they are 42 per empty width/step bucket (one bucket per run at 071906af; 4 in 39466179818 and 3 in A/A 39472217441 on macOS), the one-empty-bucket
noise of the tool doc):

| run | engine | units |
|---|---|---|
| 39448209903 | Chromium | nav.cls.is-on-dark 390 close@3; nav.rect, nav.transform.shift 1280 close@0 |
| 39448209903 | Linux WebKit | nav.rect, nav.background-color, actions.gap 641 close-hold@0 |
| 39452631146 | Chromium | nav.cls.is-on-dark 390 close@3; nav.background-color 1280 a2; earn.max-width 1280 close@0 |
| 39452631146 | Linux WebKit | nav.background-color 390, 640 close@0; logo.color 390 close@0; earn.opacity 390 open@10, 1280 close@0; earn.max-width 1280 close@0 |
| 39456741492 A/A | Chromium | nav.background-color 1280 a2; earn.opacity, earn.max-width 1280 close-hold@0 |
| 39456741492 A/A | Linux WebKit | nav.background-color 390 close-hold@0; earn.opacity 390 close@10, 640 close-hold@0; earn.max-width 390 close@7, close@10, 641 open@10 |
| 39466179818 | macOS WebKit | earn.opacity, earn.max-width 390 close@0, 640 close@0, 640 close-hold@0; earn.opacity 1280 close@0; nav.background-color 641 a3 |
| 39466179818 | Chromium | none |
| 39472217441 A/A | macOS WebKit | earn.opacity, earn.max-width 390 close@0; nav.background-color 641 close@0, 1280 a6 |
| 39472217441 A/A | Chromium | earn.opacity 1280 close@0 |

Each of these units is a sample taken inside a CSS transition (approach `aN`, `close@0` or `close-hold@0` of the nav
colour and rect, and of earn opacity and max-width). The A/A runs show this class in all three engines; task
trajectory-transition-window fixes the sampling. Matched by exact unit (path, node, prop, width, step) against the
macOS A/A 39472217441, 6 of the 8 macOS scoped units fail in one arm there: earn.opacity and earn.max-width 390 close@0
are new in it; earn.max-width 640 close@0 fails in both arms there, and earn.opacity 640 close@0 and close-hold@0 and
nav.background-color 641 a3 fail in the faithful arm only. Two units fail in neither arm of the macOS A/A: earn.max-width 640 close-hold@0 and
earn.opacity 1280 close@0. The second is new in the Chromium A/A of the same commit; the first is new in no A/A.
The 390 px `nav.cls.is-on-dark` close@3 unit fails in both arms of A/A 39456741492: it is the stale `is-on-dark` of
every rewrite arm (handoff preset-drop-waapi), at the A/A floor.

Chromium counts, swipe-v1 at 430 px (narrow), 3 runs per arm, per-frame counts identical across the 3 runs in the exit window; swipe totals within 67 (default) and 9 (scoped); r1 quoted: 39461009752
(`?fw=hero.exit:scoped`) and 39462188464 (default, faithful), `trace.UpdateLayoutTree.elementCount` per frame:

| scroll | default | scoped | delta | Lean |
|---|---|---|---|---|
| 20-140 px | 134-139 | 44-49 | 90 | `inline_narrow_delta` 90 (99 -> 9) |
| 150-940 px (one frame at 890: 56) | median 136 | median 45 | 91 | 90 |
| 1400-1800 px (about 40 frames) | | | -1 | not modelled |
| whole swipe | 43631 | 35269 | -8362 (-19.2 %) | |

The drop matches the predicted 90 at the start of the exit, and is one element more from 150 px on. That extra element,
and the one element more that scoped resolves at 1400-1800 px, are not identified (INFERRED: an element outside the Lean
tree).
