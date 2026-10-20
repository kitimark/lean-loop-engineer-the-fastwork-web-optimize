# Three flags falsified on real devices leave v2-proved

The user saw two bugs on real devices on 2026-10-20 (CONFIRMED by user report):

- The hero cards freeze during scroll, and the hero is gone after scrolling away and back. This happens on Safari
  WebKit only, desktop and mobile, with `hero.exit:scoped` in the search.
- The nav logo moves wrongly at the end-of-page morph, in Chromium and Safari WebKit.

## What changed

Three rows in `research/findings/ledger.json` carry `flag`, `fResult: "model-bug"` and `status: "refuted"`:

| row id | flag | engines with the bug |
|---|---|---|
| `morph.tween.waapi.falsified` | `morph.tween:waapi` | Chromium, WebKit |
| `morph.tween.waapiScoped.falsified` | `morph.tween:waapi-scoped` | Chromium, WebKit |
| `hero.exit.scoped.falsified` | `hero.exit:scoped` | WebKit |

`Fw.Preset.why` answers `falsifiedFlag` for a flag that a `model-bug` row names, and `Fw.Preset.falsified_not_mem`
proves that such a flag is never in the preset. `Fw.Preset.Gen.run []` regenerated the three generated files:

| file | change |
|---|---|
| `apps/site/src/registry/presets/v2-proved.json` | 9 flags, now 8: `morph.tween:waapi` left |
| `packages/contracts/golden/preset/v2-proved.json` | the same |
| `packages/contracts/golden/preset/v2-proved.decisions.jsonl` | the three flags now have the verdict `falsified-flag` |

`morph.tween` now falls back to `faithful` under `?preset=v2-proved`. The new site test "a part the preset leaves out
resolves to its faithful variant" checks this for every part the preset does not name. The other two flags had no
link and were never members. Their rows record the falsification, so a future link cannot bring them back in.

The ledger `about` now names the optional row fields `flag`, `fResult` and `evidence`.

## Mechanisms (details in each row's `mechanism`)

- **waapi and waapi-scoped.** The driver writes `data-fw-morph` only at push start and at finish
  (`waapi.driver.ts:110,140`). The nav derives `is-morphing` and `is-expanded` from that attribute
  (`nav/index.tsx:123-127`, `nav/logic.ts:63-64`), so the logo rule `.nav.is-morphing .logo` does not match during the
  morph. CONFIRMED (source). `MorphTweenOpt.waapi_vis` and `view_eq` assume that the scene is a function of the View.
  The shipped code is not, because it reads the stale attribute.
- **hero.exit:scoped.** WebKit reuses a cached style when an element's matched rules and its parent's inherited data are
  unchanged (`StyleResolver.cpp:693-728@862f17d`). Under `inherits: false` with `inherit` rules, the per-frame write no
  longer changes the inherited data, so the readers' `opacity`, `filter` and `transform` stay stale. CONFIRMED (source).
  `HeroExitOpt.consumer_eq_scoped` proves the variable's value only.

## Limits

- The evidence is the user's report plus a local debug repro (MEASURED locally, not a result). CI confirmation comes
  from task `trajectory-probe`, and each row says so in its `evidence` field.
- This task contains no site code fix. The fix directions are in each row's `next` field.
