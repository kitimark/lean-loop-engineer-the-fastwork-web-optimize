---
id: 2026-10-19-port-plan
kind: note
title: "Port plan: corrected gap list, 9 port lanes with exact write sets, a Lean-first completeness gate, and the faithful arm's declared differences"
status: review
created: 2026-10-19
topics: [port, faithfulness, svg, assets, lanes, lean]
---

# Port plan (main 024e2d06)

Sources: the Fable plan and its three investigations (content and artwork, behaviour and states, gate blind spots) plus
one adversarial check of them, all in the scratchpad (not committed). Every cited line was re-read at 024e2d06. No
`apps/site/src` file changed since 2a7a8f13, where the investigations ran. The gap list extends
`research/notes/2026/10-19-port-completeness.md`.

## Answer

- The port is complete for fonts, static body text (167 of 168 strings), hero avatars and covers, roles, flags,
  shield layers and the platform background. CONFIRMED by the content and artwork investigation.
- Open: SVG stand-ins, 9 asset files the manifest lacks, empty deck panels, placeholder morph panel copy, the
  document head, and 5 small behaviour gaps (B1, B3 to B6).
- The breakpoint gate passes anyway because it reads no text, attributes, SVG children or asset sets. CONFIRMED:
  `page.mjs` reads no `textContent`, `src`, `href`, `viewBox` or `alt`.
- Plan: 8 port lanes plus one gate lane, L7 `port-completeness-gate`. "Fully ported" means checks 1 to 4 pass on
  a fresh prerender and in the listed states, with every exclusion named in Lean together with its reason.

## Faithful arm: declared differences (lead decision 1)

| difference | kind | status |
|---|---|---|
| B2: signup has no transport. The original POSTs `/api/waitlist`; the port shows "temporarily unavailable" on every valid submit (overlays.signup/index.tsx:105-109) | by design | CONFIRMED |
| B7: no GTM, no Cloudflare beacon, no SvelteKit preload-data | by design | CONFIRMED |
| Signup restores focus to its opener on close (overlays.signup/index.tsx:48-57); the original never reads `activeElement` | over-faithful, kept (a11y) | CONFIRMED |
| AVIF `<picture>` sources: the snapshot holds 9 avif files and the manifest serves 3; 6 files load jpg/png instead | deferred until after C3 (changes counts) | structure CONFIRMED, bytes INFERRED |
| morph.columns loads images `eager` (morph.columns/index.tsx:73); the original uses `lazy` | deferred until after C3 (changes counts) | CONFIRMED |

The two deferred items stay differences until their lane lands after C3; they are not dropped.
## Gap list (C visible content, B behaviour, M meta/a11y/bytes)

| part | gap | kind | lane |
|---|---|---|---|
| nav | wordmark drawn as 2 `<rect>` vs 9 paths (nav/index.tsx:142-145) | C | svg-extract r1 |
| nav.langMenu | globe stand-in = circle + path + ellipse, 3 children (nav.langMenu/index.tsx:86-90); the original is a circle plus two meridian arcs | C | svg-extract r1 |
| hero.accent | 'you' frames drawn by a stand-in path generator (hero.accent/index.tsx:114-121) | C | svg-extract r1 |
| hero | calendar has 2 paths vs 10 (hero/index.tsx:28-37); bell and calendar hold literal path strings (:16-37), INFERRED from the Solar icon set | C | svg-extract r1 / snapshot-paths-cleanup |
| hero.countdown | aria-label `countdown` vs "Time until launch" (hero.countdown/index.tsx:143) | M | doc-head-locale |
| hero.countdown | B1: the clock is not re-read on `visibilitychange`; the original re-reads it | B | behaviour-small |
| commission | own underline and '0%' paths, 2 vs 4 (commission/data.ts:32-44) | C | svg-extract r1 |
| platform | shield mark is a `<circle>` (platform/Visuals.tsx:378-381); star is a stand-in `<path>` (:27-33); pin | C | svg-extract r1 |
| platform | claim.svg, pin.svg, lawyer fallback png missing from the manifest; `.is-drawn:after` feTurbulence grain at opacity .18 absent | C | asset-icons-gaps |
| overlays.drawer | 1x1 GIF divider (overlays.drawer/index.tsx:17); 4 why-bring icons missing from the manifest | C | asset-icons-gaps |
| overlays.drawer, overlays.signup | B5: `.sb-button` `:active:not(:disabled)` and `:disabled` have no port rule | B | behaviour-small |
| overlays.signup | 46x46 box mark (overlays.signup/index.tsx:136-139) | C | svg-extract r1 |
| overlays.signup | B3: weaker rules. The original rejects emoji-only names (grapheme split + Extended_Pictographic) and uses a stricter email regex; the port uses a non-blank name and a simple regex (overlays.signup/logic.ts:142-151) | B | behaviour-small |
| overlays.signup | Turnstile step and role picker in the original, not located in the static HTML | B | none until a runtime check in a user session (INFERRED) |
| morph.panel | 6 placeholder strings, links to `#morph-panel`, calendar 2 vs 10 paths (morph.panel/index.tsx:60-126) | C | morph-panel-content (after svg-extract) |
| people.o | o-glyph ring is `css.ring`, not o.svg (people.o/index.tsx:118-120) | C | people-o-glyph |
| people.deck | Services/Reviews/About panels and feedPanel empty (panel.tsx:169-171), Intl dates, review filters, tab `:hover` | C/B | deck-panels-lean |
| people.deck | mute icon (panel.tsx:118-120), rail star `★` glyph (:156) | C | deck-panels-lean next round (lead decision 2) |
| people, pain | 0 `deferred` / content-visibility hits under people | B (work) | people-pain-deferral |
| pain.notes, nav.hitTest | selectors that match nothing | B (work) | dead-selectors |
| nav, hero, overlays | B4: 14 of 27 `data-selenium` ids missing (header.*, hero.*, waitlist.*, why-bring.*) | M | selenium-ids |
| document | title, description, og/twitter, canonical, hreflang, icons; body-end locale links; B6 `<html dir="ltr" data-theme="light">` | M | doc-head-locale |

Rows CONFIRMED by re-reading the cited line at 024e2d06, except those marked INFERRED.
## Lanes and exact write sets (lead decisions 2, 3, 5, 6)

Prefix `parts/` = `apps/site/src/parts/`. Every lane also writes its own `docs/team/handoffs/<lane>.md`.

| lane | writes | Lean-first | after |
|---|---|---|---|
| svg-extract r1 (running) | parts/{nav,nav.langMenu,hero,hero.accent,overlays.drawer,overlays.signup,morph.panel}/index.tsx, parts/commission/data.ts, parts/platform/Visuals.tsx, apps/site/scripts/{svg-extract,build}.mjs, apps/site/assets.manifest.json, apps/site/src/svg.gen.d.ts | none | none |
| morph-panel-content | parts/morph.panel/** | none (content) | svg-extract |
| asset-icons-gaps | parts/overlays.drawer/**, parts/platform/**, apps/site/assets.manifest.json | none | svg-extract |
| doc-head-locale (+B6, +countdown aria-label) | apps/site/index.html, apps/site/src/entry-*.tsx, apps/site/scripts/build.mjs, apps/site/assets.manifest.json, parts/nav/**, parts/hero.countdown/index.tsx | meta and locale constants generated from Lean | svg-extract |
| people-o-glyph | parts/people.o/**, parts/people.deck/panel.tsx, parts/people.deck/deck.module.css, apps/site/assets.manifest.json | none (content) | svg-extract |
| deck-panels-lean (+mute icon, rail star) | parts/people.deck/**, lean/Fw/Parts/PeopleDeck*.lean, lean/Fw.lean, packages/contracts/golden/parts/people.deck.jsonl, apps/site/assets.manifest.json | tab/filter reducers, date format | people-o-glyph |
| behaviour-small (B1, B3, B5) | parts/hero.countdown/{driver,logic}.ts and their tests, parts/overlays.signup/{logic.ts,logic.test.ts,signup.module.css}, parts/overlays.drawer/drawer.module.css, lean/Fw/Parts/{OverlaySignup,HeroCountdown}.lean, packages/contracts/golden/parts/{overlays.signup,hero.countdown}.jsonl | `emailOk`, name rule, visibility = "refresh now" event | svg-extract, asset-icons-gaps |
| selenium-ids (B4) | parts/{nav,nav.langMenu,hero,hero.cue,overlays.signup,overlays.drawer}/index.tsx, plus the file that renders `header.link.privacy` (not in parts/nav; the lane locates it first) | id table as a Lean-generated constant | svg-extract, asset-icons-gaps, doc-head-locale |
| people-pain-deferral + dead-selectors (1 agent) | parts/{pain,pain.notes,nav.hitTest}/**/*.css, plus people CSS that deck-panels-lean does not touch | gate `Coverage`, liveness allowlist | none |
| port-completeness-gate (L7) | lean/Fw/Port/{Text,Attrs,Svg,Sections}.lean, lean/Fw/Site/Assets.lean (new), lean/Fw.lean, scripts/port/digest.mjs and its tests, packages/contracts/golden/port/** | all checks (below) | none; start once machine load allows |

Shared files and their order:
- `assets.manifest.json`: svg-extract, then asset-icons-gaps, doc-head-locale, people-o-glyph, deck-panels-lean. Each
  lane rebases on main and appends entries without reordering.
- `parts/platform/` and `parts/overlays.drawer/`: svg-extract, then asset-icons-gaps, then behaviour-small and
  selenium-ids.
- `people.deck/panel.tsx`: svg-extract, then people-o-glyph, then deck-panels-lean.
- `parts/nav/**`, `parts/hero.countdown/index.tsx`: doc-head-locale, then selenium-ids on nav (behaviour-small: countdown `driver.ts`, `logic.ts` only).
- `lean/Fw.lean`: deck-panels-lean and L7 each append one import line. Whichever lands second rebases.
- `packages/contracts/golden/`: flat files `parts/<part>.jsonl` (CONFIRMED ls). Each lane writes only the files named
  above; L7 owns `port/**`.
- svg-extract's work-graph node declares `apps/site/src/parts/**` and `apps/site/scripts/**` (CONFIRMED
  docs/team/work-graph.json), which covers every lane above. Until the graph narrows it to the r1 file list above,
  lanes that write under those globs start only after svg-extract lands. L7's script lives at the repo root for
  this reason.
- `apps/site/src/parts/people/` has no CSS file (CONFIRMED ls). The deferral lane's people-side file must be named
  before that part of the lane starts. Every people.deck CSS file belongs to deck-panels-lean.
- people-o-glyph's graph node lists `lean/Fw/Parts/**`; it needs no Lean, so the graph drops that glob.

## L7 port-completeness-gate (lead decision 4)

Each check decides per section or per svg, never by a pooled threshold. Exclusions form one Lean list per check, and
each entry carries a reason (countdown digits, pinned clock text, rewrite `data-fw`, hashed asset names).

| # | check | Lean | catches |
|---|---|---|---|
| 1 | text digest per section: non-empty text leaves, whitespace collapsed, trimmed, hashed | `Fw.Port.Text`: normaliser, `digest_eq ↔ leaves_eq` | placeholder text, empty panels |
| 2 | attribute multiset per section (`href src srcset alt lang hreflang rel property name content`) up to a rename map from `/_app/immutable/...` to manifest urls | `Fw.Port.Attrs` | links, head meta, icons, locale links |
| 3 | asset reference set: $S_{orig} \subseteq S_{rw} \lor \text{excluded}$ | `Fw.Site.Assets` (new module; `assets.manifest.json:2` names it only in prose) | missing files |
| 4 | svg shape digest: viewBox, child counts by tag, per-path `d` byte length and command-letter skeleton | `Fw.Port.Svg`: `digest_eq → same counts ∧ same command sequence` | stand-in artwork |
| 5 | checks 1, 2 and 4 in `prepare` states: deck `tab=services|reviews|about`, drawer open, signup open | state list in anchors.json | runtime-mounted content |

- Section roots: the snapshot has 0 `data-fw` attributes (CONFIRMED grep of snapshot/site/index.html). Check 1
  therefore needs `Fw.Port.Sections`, a table with one row per part id holding the orig selector and the rewrite
  selector, seeded from the anchors.json orig/rewrite selector pairs.
- Check 4 is not pure on the rewrite side. After svg-extract, path data comes at build time from gitignored
  `*.gen.json`. So check 4 runs on a fresh `dist/aot` prerender for SSR svgs, and in check-5 states for the svgs
  mounted only on interaction: morph panel calendar, drawer and signup marks, deck mute icon and star.
- Order: rebuild `dist/aot`, then checks 3 and 4, then 1 and 2 on the prerender, then 5. `scripts/port/digest.mjs`
  reads the snapshot at run time and stores only hashes and skeletons, never text runs or path data.

## Schedule

- svg-extract first, then asset-icons-gaps, doc-head-locale and morph-panel-content. L7 checks 3 and 4 start as
  soon as load allows; L7 writes nothing another lane writes.
- Before C3: people-o-glyph, deck-panels-lean, behaviour-small, the deferral + dead-selectors lane, and L7 checks 1
  and 2. After those land: selenium-ids.
- After C3: AVIF `<picture>` plus morph.columns lazy as one lane; check 5, unless deck-panels-lean lands early.
- No two Lean lanes (deck-panels-lean, behaviour-small, L7) compile while a vite build runs.

## Corrections to the Fable draft

- Wordmark, shield and star rows split as above; 'you' frames are in hero.accent; the globe has 3 children.
- `Fw.Site.Assets` does not exist (CONFIRMED ls lean/Fw/Site); L7 creates it. svg-extract has no Lean item.
- Golden files are flat, so the "golden/** only L4 and L7" claim is dropped. The "17 of 26 gaps caught by checks
  3 and 4" figure is dropped as unsupported.
- At least 5 gate role selectors target img or svg, not 3. The conclusion holds, because none reads content.
- B4 cannot fit in doc-head-locale: its ids live in hero, hero.cue, overlays.signup and overlays.drawer, so it
  became its own lane.

## What this changes in the plan

- §6.6 Parity gate: add the faithful arm's declared differences table, and add the completeness checks 1 to 5 as a
  second gate next to the box/style gate.
- §10.7 Lego lanes: add lanes behaviour-small, selenium-ids and port-completeness-gate. Narrow the svg-extract and
  people-o-glyph writes in work-graph.json. Record the shared-file order above.
- §12 Decisions: record lead decisions 1 to 6 (declared differences, mute icon and star to deck-panels-lean,
  selenium-ids lane, L7 as its own lane, behaviour-small scope, shared-file order).
