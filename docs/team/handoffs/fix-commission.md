# Handoff: fix-commission

Branch `worktree-agent-afb706fb2b3e7298b` (CI ref `ci/fix-commission`), on integrate-ports 30734ae. Cell data: run 39067170911 (a = original, b = rewrite).
Method: static comparison of snapshot CSS/JS (`snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`, `nodes/2.DyWL8TcE.js`) with the port; the port CSS rules for commission and commission.typing match the snapshot byte for byte in value (checked blocks 1-348, 916-1166).

## Root finding
The rewrite loads NO webfont: no `@font-face` anywhere in apps/ (theme.ts: "system font stack placeholder"), while the original loads "Google Sans" (`assets/0.ChGpbVhU.css:1-35`, woff2 files `google-sans-latin-normal.BbZhqv4U.woff2` etc.).
Text metrics differ (pill 157 vs 153 px, message 244 vs 232), so lines wrap differently: this explains the height cells, `title-wrapped`, typing scale. Needs a SHARED change (global @font-face, built into dist from the snapshot files at build time); not done here.

## Table (cell | property | original value, source | port old | cause | formula)
| cell | property | original (source) | port old | cause | formula |
|---|---|---|---|---|---|
| commission section/track/card/sticky | height at 641-1100 | referral copy 198.4 px tall -> section 829.77 @720 (css 233-300 `.commission-copy`, 916-1166 compact; text laid out in Google Sans) | 777.44 | original depends on webfont (missing in rewrite) | height = sum of line boxes; line count = ceil(textWidth(font)/copyWidth); copyWidth(720)=328 |
| commission runway | height (display:none, compact) | `''` after the frame body ran: `d.style.height = A()||reduced ? '' : 0.06*innerHeight px` (js 3115) | 54px kept after resize | port wrong (one frame late: body ran in a second rAF after the engine frame; original runs it in the same rAF, js 2667-2672 `iE`) | h = 0.06*vh unless compact(w,dw,touch) or reduced; compact = w<=1000 or dw<=500 or (touch and w<=1200) |
| commission title/titleMuted/titleAccent | display | `.title-wrapped` set when compact and `Range.getClientRects().length > 1` (js 3076-3082; css 916-1166 `h2.title-wrapped{display:block}`) -> block/inline/inline-block | flex/block/inline-block (not wrapped) | original depends on webfont (width of "Other platforms keep taking fee." at 36/32 px) | wrapped = compact and textWidth(36px or 32px at w<=640) > w - 40 |
| commission inner / rows | margin-inline | used value of `margin-inline:auto` (css `.commission-inner` max-width 1136, card padding 56): 16px / 8px at 1280; read from a content-visibility-skipped subtree | 0px | gate misreads: rects are equal in both arms (x=119, w=1041); the computed used margin of auto in a skipped subtree depends on whether the subtree was laid out at that width before the skip | (min(1136, w-112) vs w-112)/2 : (w-112-1136)/2 = 16 at 1280 |
| commission underline | opacity, transform | fired earlier in the prepared page (IO ratio >=0.45 on the header once, js 3124-3131) -> `idle`: opacity 1, identity | hidden (opacity 0, rotateX(82deg)) | original depends on layout/position: the prepare scroll (1.5 vh above morph target) puts the header >=45% in view in the original; with the rewrite's different section height/position it does not (INFERRED, not shown) | fires iff top_header < vh and visible fraction >= 0.45 |
| commission.typing visual | --visual-scale, w/h/transform at <=720 | `min(0.8, parentClientWidth/432)` by ResizeObserver (js 2511-2518): 329 px -> 0.7616 | 0.8 (stale or wider column) | likely the same stale-layout/font cause (column width differs after the skipped-layout resize); not shown | scale = min(0.8, columnWidth/432) |
| commission.typing avatarLarge / message / referral | transition-*, opacity, transform | running (visible) state: `opacity,transform .28s ease-out`, `.48s` for referral (css 425-583) | `.resetting` state (`transition:none`, opacity 0) | original depends on the visual being in view (IO trigger on the fee visual, js 2496-2503) in the prepared page | resetting iff not intersecting (threshold 0/.05/.2) |
| commission.typing beat x/y | rect | -58.2/-3876 (stale rect of a not-rendered node) | 0/0 | gate misreads: a node with no layout box at 462/320 px reports the last/odd rect | none |

## Changed
- `apps/site/src/parts/commission/driver.ts`: engine callback runs the frame body directly (was: request an own frame). Tests: 452 pass.

## Open / next
- Shared: add the global Google Sans @font-face (4 files in snapshot assets) to the build; then re-run `commission,commission.typing`.
- Result of the narrowed gate run 39071577161: see the lead report.
