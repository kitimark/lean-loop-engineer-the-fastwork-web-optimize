#!/usr/bin/env python3
"""Generate breakpoints.json from the merged, verified sweep data (no Fastwork code; conditions + citations only)."""
import json, sys, collections

OUT = sys.argv[1]
F = {
    "2": "_app/immutable/assets/2.gBuqKVzi.css",
    "DH": "_app/immutable/assets/DialogHeader.Qcgwm6ST.css",
    "0": "_app/immutable/assets/0.ChGpbVhU.css",
    "html": "index.html",
    "N2": "_app/immutable/nodes/2.DyWL8TcE.js",
    "UI": "_app/immutable/chunks/D313Dngs.js",
    "RT": "_app/immutable/chunks/BSBv9QXB.js",
    "CZ": "_app/immutable/chunks/CzkAa0og.js",
}

def site(s):
    k, l = s.split(":", 1)
    return f"{F[k]}:{l}"

TOUCH = "(hover: none) and (pointer: coarse) and (width<=1200px)"
def combo(n, dw=True):
    return f"(width<={n}px), " + ("(device-width<=500px), " if dw else "") + TOUCH

# --- atomic media conditions (normalized to range syntax) -----------------------------------------
# id, condition, features, edges [(feature, N) meaning pair N|N+1], equivalent legacy forms, summary
MQ = [
 ("mq.rm-reduce", "(prefers-reduced-motion: reduce)", ["prefers-reduced-motion"], [], [],
  "Reduced motion: animations/transitions off or final states, and layout changes too (hero track height, sticky off via the no-preference twins, smooth scroll off)."),
 ("mq.rm-nopref", "(prefers-reduced-motion: no-preference)", ["prefers-reduced-motion"], [], [],
  "Motion allowed: entrance animations, pain sticky, drawer slide-in, title sweep, nav sheen."),
 ("mq.hover-hover", "(hover: hover)", ["hover"], [], [], "sb-button hover tint only on hover-capable input."),
 ("mq.hover-none", "(hover: none)", ["hover"], [], [], "UI-kit tooltip keeps itself open on pointer-leave on hover-less input; no tooltip is used on this page (INFERRED inert)."),
 ("mq.dark", "(prefers-color-scheme: dark)", ["prefers-color-scheme"], [], [],
  "Flips the light/dark toggles on the root; neutralised by html data-theme=light and the later light rule (0:258). Page must stay light (INFERRED no visible effect)."),
 ("mq.w-le-400", "(width<=400px)", ["width"], [("width", 400)], [], "Countdown smallest size."),
 ("mq.w-le-461", "(width<=461px)", ["width"], [("width", 461)], [], "Community pill stacks; proof text wraps."),
 ("mq.w-le-480", "(width<=480px)", ["width"], [("width", 480)], [], "Profile review summary restacks."),
 ("mq.w-le-600", "(width<=600px)", ["width"], [("width", 600)], ["(max-width: 600px)", "(max-width:600px)"],
  "Phone hero (mobile deck replaces orbit), CTA stack one column, accent box, signup padding; JS: ring splash skipped/finished and nav chrome ready at once (each OR reduced motion)."),
 ("mq.w-gt-600", "(width>600px)", ["width"], [("width", 600)], [], "Hero scroll-cue entrance and nav hero-pill fade-in only above 600."),
 ("mq.w-601-1279", "(width>=601px) and (width<=1279px)", ["width"], [("width", 600), ("width", 1279)], [], "Orbit edge push variable (continuous in vw inside the band)."),
 ("mq.w-601-1511", "(width>=601px) and (width<=1511px)", ["width"], [("width", 600), ("width", 1511)], [], "Orbit stage full width; side cards pushed in by the edge push."),
 ("mq.w-le-640", "(width<=640px)", ["width"], [("width", 640)], [], "Phone geometry: commission titles, why-bring full-width sheet, profile deck bleed, platform single column, morph pill/panel vars, nav geometry, compact language switch."),
 ("mq.w-gt-640", "(width>640px)", ["width"], [("width", 640)], [], "Nav translucent white background."),
 ("mq.w-641-1000", "(width>=641px) and (width<=1000px)", ["width"], [("width", 640), ("width", 1000)], [], "Commission tablet band: rows as a 2-column grid."),
 ("mq.w-le-720", "(width<=720px)", ["width"], [("width", 720)], [], "Platform section padding/radius/tools grid; morph footer stacks."),
 ("mq.w-le-860", "(width<=860px)", ["width"], [("width", 860)], ["(max-width: 860px)"],
  "Pure-width phone path: why-bring drawer, pain layout + notes hidden, people card/o/carousel, signup shell, platform checks hidden; JS: seller preview off, pain note layout set, pain-dark rule, (inert) sheet store."),
 ("mq.w-ge-861", "(width>=861px)", ["width"], [("width", 860)], ["(min-width: 861px)"],
  "Desktop profile showcase (inactive shells hidden) and desktop platform row titles; JS: one arm of the desktop deck gate."),
 ("mq.w-ge-861-nopref", "(width>=861px) and (prefers-reduced-motion: no-preference)", ["width", "prefers-reduced-motion"], [("width", 860)], [],
  "Nested block: profile sticky, chrome and tabs desktop geometry."),
 ("mq.w-861-1000", "(width>=861px) and (width<=1000px)", ["width"], [("width", 860), ("width", 1000)], [], "Platform card/mission spacing band."),
 ("mq.w-le-960", "(width<=960px)", ["width"], [("width", 960)], [], "Platform header/features/rows tablet layout."),
 ("mq.w-le-1000", "(width<=1000px)", ["width"], [("width", 1000)], [], "Platform row copy and row-title type; morph title size."),
 ("mq.w-ge-1001", "(width>=1001px)", ["width"], [("width", 1000)], [], "Platform mission title size."),
 ("mq.w-ge-1001-nopref", "(width>=1001px) and (prefers-reduced-motion: no-preference)", ["width", "prefers-reduced-motion"], [("width", 1000)], [], "Desktop sticky commission."),
 ("mq.w-le-1100", "(width<=1100px)", ["width"], [("width", 1100)], [], "Platform tools grid columns."),
 ("mq.w-le-1200", "(width<=1200px)", ["width"], [("width", 1200)], [], "Profile rail, posts grid and reviews gap (plain width, no touch clause: a separate desktop band 1031-1200)."),
 ("mq.c860", combo(860), ["width", "device-width", "hover", "pointer"], [("width", 860), ("device-width", 500), ("width(touch)", 1200)],
  ["(max-width: 860px), (max-device-width: 500px), (hover: none) and (pointer: coarse) and (max-width: 1200px)"],
  "Combo 860 (phone OR small device OR touch tablet to 1200): all shrink vars neutralised, profile deck becomes a snap rail, platform phone titles/sweep, nav+morph panel = viewport minus 40; JS: compact deck mode, note drag off."),
 ("mq.c1000", combo(1000), ["width", "device-width", "hover", "pointer"], [("width", 1000), ("device-width", 500), ("width(touch)", 1200)],
  ["three matchMedia calls OR-ed: (max-width: 1000px) | (max-device-width: 500px) | (hover: none) and (pointer: coarse) and (max-width: 1200px)"],
  "Combo 1000: commission phone/tablet layout; JS: compact class, compact arrow, runway spacer and title-wrap detection (polled per frame, no change listener)."),
 ("mq.c1030", combo(1030), ["width", "device-width", "hover", "pointer"], [("width", 1030), ("device-width", 500), ("width(touch)", 1200)], [],
  "Combo 1030: every profile widget compact (about, posts, reviews, gallery, feed)."),
 ("mq.c1000-nodw", combo(1000, dw=False), ["width", "hover", "pointer"], [("width", 1000), ("width(touch)", 1200)], [],
  "Countdown medium size. The only combo WITHOUT the device-width arm; differs from mq.c1000 only for fine pointer + device-width<=500 + width>1000 (INFERRED no real device)."),
]

# --- uses: (cond, kind, site, rules, parts, effect, props(sample)) ------------------------------
C, J = "css-media", "js-matchMedia"
U = [
 # reduced motion, CSS
 ("mq.rm-reduce", C, "DH:438", 1, ["ui.shared(sb-*)"], "sb ring/spinner animation shortened.", "animation-duration"),
 ("mq.rm-reduce", C, "DH:590", 1, ["ui.shared(sb-*)"], "sb-button delayed-loading animation delay dropped.", "animation-delay"),
 ("mq.rm-reduce", C, "DH:637", 1, ["ui.shared(sb-*)"], "sb-button transitions off.", "transition-duration"),
 ("mq.rm-reduce", C, "DH:711", 1, ["overlays.signup"], "sb-dialog open animation off.", "animation"),
 ("mq.rm-reduce", C, "2:1167", 9, ["pain.notes", "commission", "commission.typing", "overlays.drawer"], "Extra pain notes and every commission animation static (underline, fee avatars/messages, typing caret, why-bring).", "opacity transform animation will-change filter transition display"),
 ("mq.rm-reduce", C, "2:1376", 5, ["hero.accent"], "Script accent static.", "transition opacity transform animation stroke-dashoffset"),
 ("mq.rm-reduce", C, "2:2127", 6, ["hero", "hero.exit", "hero.orbit", "hero.cue"], "Hero track height changes (layout), no scatter/blur, cards/copy/CTA static.", "height --exit-scatter position --entered --profile-reveal filter transform translate scale animation --copy-in transition"),
 ("mq.rm-reduce", C, "2:3614", 6, ["people.card", "people.deck", "people.o", "people.carousel"], "People transitions off; people-o expanded state static.", "margin-top transition animation grid-template-columns height justify-content gap visibility opacity pointer-events flex-basis width +3"),
 ("mq.rm-reduce", C, "2:3900", 1, ["people.deck"], "Vinyl record spin off.", "animation"),
 ("mq.rm-reduce", C, "2:5150", 1, ["people.deck"], "Profile feed panel animation off.", "animation"),
 ("mq.rm-reduce", C, "2:6324", 1, ["platform.entries", "platform"], "Row point panel/desc transition off.", "transition"),
 ("mq.rm-reduce", C, "2:6500", 2, ["platform.marquee", "platform"], "Credential marquees stopped.", "animation filter opacity transform"),
 ("mq.rm-reduce", C, "2:6641", 1, ["platform.marquee", "platform"], "Secure currencies track off.", "animation"),
 ("mq.rm-reduce", C, "2:7174", 3, ["platform.glint", "platform"], "Secure network rings/shield/glint static.", "opacity transform animation"),
 ("mq.rm-reduce", C, "2:7547", 3, ["platform.entries", "platform", "platform.marquee"], "Profile phone and reviews track static.", "filter opacity transform animation"),
 ("mq.rm-reduce", C, "2:8169", 1, ["platform.entries", "platform"], "Service quote steps static.", "opacity transform animation"),
 ("mq.rm-reduce", C, "2:8615", 3, ["platform.entries", "platform"], "Invoice doc/card entrance static.", "filter opacity transform animation transition"),
 ("mq.rm-reduce", C, "2:8725", 1, ["platform.entries", "platform"], "Invoice/orders card static.", "opacity transform animation"),
 ("mq.rm-reduce", C, "2:8864", 1, ["platform.entries", "platform"], "Orders card static.", "opacity transform animation"),
 ("mq.rm-reduce", C, "2:9144", 2, ["platform.entries", "platform.stageBg", "platform"], "Agents search typing/caret static.", "opacity animation transform display"),
 ("mq.rm-reduce", C, "2:9229", 1, ["platform.entries", "platform.stageBg", "platform"], "Service card entrance static.", "filter transform animation"),
 ("mq.rm-reduce", C, "2:9361", 1, ["platform.entries", "platform"], "Service card transitions off.", "transition"),
 ("mq.rm-reduce", C, "2:10090", 3, ["platform.entries", "platform"], "Paid trace/packet/transfer/confetti static.", "animation display filter transform"),
 ("mq.rm-reduce", C, "2:10246", 2, ["platform.entries", "platform"], "Agents bubbles/replies static.", "filter opacity transform animation"),
 ("mq.rm-reduce", C, "2:10812", 2, ["morph.panel", "morph.tween", "nav", "morph.columns"], "Morph pill/panel/nav morph and column track: no transitions/blur.", "filter transition will-change animation"),
 ("mq.rm-reduce", C, "2:11288", 1, ["nav.langMenu"], "Language menu animation off.", "opacity animation transform"),
 ("mq.rm-reduce", C, "2:11599", 2, ["nav", "morph.tween"], "Nav transitions/blur off.", "transition filter"),
 ("mq.rm-reduce", C, "2:11766", 1, ["engine.scroll"], "Root scroll-behavior auto (smooth otherwise).", "scroll-behavior"),
 ("mq.rm-reduce", C, "html:58", 1, ["hero", "morph.panel"], "RSVP button border transition off (inline style block).", "transition"),
 # reduced motion, JS (17 sites)
 ("mq.rm-reduce", J, "N2:2495-2498", None, ["commission.typing"], "No typing loop; final text.", None),
 ("mq.rm-reduce", J, "N2:2917-2919", None, ["commission"], "Why-bring close delay 0 instead of 480 ms.", None),
 ("mq.rm-reduce", J, "N2:3101", None, ["commission"], "Runway spacer only when not reduced (and not C1000).", None),
 ("mq.rm-reduce", J, "N2:3681", None, ["hero.accent"], "Accent-word cycle never starts (read once).", None),
 ("mq.rm-reduce", J, "N2:3817", None, ["hero.countdown", "morph.countdown"], "Svelte MediaQuery store: digit spring skipped.", None),
 ("mq.rm-reduce", J, "N2:4156", None, ["hero.orbit"], "OR (width<=600): ring splash skipped/finished.", None),
 ("mq.rm-reduce", J, "N2:4596", None, ["pain.notes"], "Extra-note ticker off.", None),
 ("mq.rm-reduce", J, "N2:6225-6260", None, ["people.o"], "Reveal: expanded state and faces at once (else staged 1300 ms + 120 ms); reset when the heading leaves the 0.35 IntersectionObserver threshold.", None),
 ("mq.rm-reduce", J, "N2:10780", None, ["people.deck"], "Desktop scroll-driven deck off.", None),
 ("mq.rm-reduce", J, "N2:10917", None, ["people.deck"], "Deck mode recomputed on change.", None),
 ("mq.rm-reduce", J, "N2:11295", None, ["people.card", "pain"], "Future shrink becomes a step at 0.5.", None),
 ("mq.rm-reduce", J, "N2:11607", None, ["people.carousel"], "Avatar cycle off.", None),
 ("mq.rm-reduce", J, "N2:11861", None, ["platform.entries"], "Final state shown.", None),
 ("mq.rm-reduce", J, "N2:11995-12001", None, ["platform.entries", "platform.glint"], "Final state; glint SVG animate loop off.", None),
 ("mq.rm-reduce", J, "N2:12197-12215", None, ["platform.entries"], "Agents/credibility/orders final state.", None),
 ("mq.rm-reduce", J, "N2:12433-12449", None, ["platform"], "Platform shrink becomes a step at 0.5.", None),
 ("mq.rm-reduce", J, "N2:12979", None, ["nav"], "OR (width<=600): hero chrome ready at once.", None),
 # no-preference
 ("mq.rm-nopref", C, "DH:111", 1, ["ui.shared(sb-*)"], "Tooltip entrance animation (+1 @keyframes).", "animation"),
 ("mq.rm-nopref", C, "2:2299", 1, ["pain"], "Pain sticky (layout).", "position top"),
 ("mq.rm-nopref", C, "2:3986", 5, ["overlays.drawer"], "Drawer slide-in per side (+4 @keyframes).", "transition animation"),
 ("mq.rm-nopref", C, "2:11081", 1, ["platform.sweep", "platform"], "Title sweep gradient animation.", "color -webkit-text-fill-color background-image background-size background-clip animation"),
 ("mq.rm-nopref", C, "2:11530", 2, ["nav"], "Earn button sheen/unmask.", "mask-image animation mask-size mask-repeat"),
 ("mq.hover-hover", C, "DH:537", 1, ["ui.shared(sb-*)"], "sb-button hover background.", "background-image"),
 ("mq.hover-none", J, "UI:1172-1181", None, ["ui.shared(sb-*)"], "Tooltip: no hide on pointer-leave (INFERRED unused on this page).", None),
 ("mq.dark", C, "0:250", 1, ["theme.tokens"], "Light/dark toggles flipped; neutralised (0:258, html data-theme=light; portals copy data-theme UI:883).", "--lightningcss-light --lightningcss-dark"),
 ("mq.w-le-400", C, "2:1489", 4, ["hero.countdown", "morph.countdown"], "Countdown font 24 (cell 31 per v1).", "gap border-radius width min-width height padding font-size"),
 ("mq.w-le-461", C, "2:3594", 2, ["people.carousel"], "Community pill stacks.", "white-space background border flex-direction gap width max-width padding border-radius align-items display"),
 ("mq.w-le-480", C, "2:4635", 3, ["people.deck"], "Review summary restacks.", "grid-template-columns gap flex-flow align-items flex-basis"),
 ("mq.w-le-600", C, "2:2031", 13, ["hero", "hero.exit", "hero.orbit", "hero.cue", "hero.deck"], "Orbit hidden, mobile deck shown, copy repositioned, title sizes, cue placement.", "min-height display --copy-in width max-width opacity filter transform gap padding animation position +19"),
 ("mq.w-le-600", C, "2:5325", 1, ["hero.accent", "hero"], "Accent box size.", "flex width height"),
 ("mq.w-le-600", C, "2:11733", 1, ["overlays.signup"], "Signup content bottom padding (safe-area max()).", "padding-bottom"),
 ("mq.w-le-600", C, "html:58", 2, ["hero", "morph.panel"], "CTA stacks one column, RSVP first (legacy max-width syntax, inline style after the linked sheets).", "grid-template-columns order"),
 ("mq.w-le-600", J, "N2:4157", None, ["hero.orbit"], "OR reduced motion: skip ring splash at load/bfcache; change listener finishes it when it starts to match; widening never restarts it.", None),
 ("mq.w-le-600", J, "N2:12980", None, ["nav"], "OR reduced motion: is-hero-chrome-ready at once, else after 1140 ms or splash done; change listeners.", None),
 ("mq.w-gt-600", C, "2:1925", 2, ["hero.cue"], "Cue blur/copy-from-ring entrance; rest transform after splash.", "filter animation --copy-in opacity transform"),
 ("mq.w-gt-600", C, "2:11391", 2, ["nav"], "Hero pill hidden until chrome ready, then fades in.", "opacity pointer-events transition"),
 ("mq.w-601-1279", C, "2:2026", 1, ["hero.orbit"], "Edge push = max(0, (1280 - 100vw) x 0.35).", "--orbit-edge-push"),
 ("mq.w-601-1511", C, "2:2009", 3, ["hero.orbit"], "Stage full width; side cards pushed in.", "width left transform right"),
 ("mq.w-le-640", C, "2:1133", 6, ["commission", "overlays.drawer"], "Commission titles; why-bring full-width bottom sheet (safe-area padding at 2:1159).", "letter-spacing font-size top justify-content align-items padding border-radius width max-width max-height transform scrollbar-width +2"),
 ("mq.w-le-640", C, "2:3586", 2, ["people.card", "people.deck"], "Future shrink radius; deck bleed.", "--future-shrink-radius --profile-deck-bleed"),
 ("mq.w-le-640", C, "2:7803", 4, ["platform", "platform.stageBg"], "Rows single column; stage aspect.", "grid-template-columns align-items width grid-area aspect-ratio height padding"),
 ("mq.w-le-640", C, "2:10888", 21, ["platform", "morph.panel", "morph.columns"], "Platform features/rows; morph pill/panel geometry vars; columns 4+ hidden.", "padding white-space font-size grid-template-columns justify-content row-gap width max-width flex min-width gap line-height +14"),
 ("mq.w-le-640", C, "2:11274", 3, ["nav.langMenu"], "Language switch icon only.", "height padding width"),
 ("mq.w-le-640", C, "2:11564", 7, ["nav", "morph.tween"], "Nav phone geometry (pill/panel vars, top, inset, logo scale, button sizes).", "--hero-pill-w --pill-w --pill-h --panel-w --panel-h top --nav-bar-inset-x padding transform-origin scale gap height +5"),
 ("mq.w-gt-640", C, "2:11369", 2, ["nav"], "Translucent white nav background.", "background"),
 ("mq.w-641-1000", C, "2:1106", 4, ["commission"], "Rows 2-column grid, divider horizontal.", "flex-direction align-items gap flex justify-content width min-width max-width display grid-template-columns grid-column"),
 ("mq.w-le-720", C, "2:7825", 9, ["platform"], "Section padding, shrink radius, card, title, pain underlay vars, tools grid.", "padding --platform-shrink-radius gap font-size z-index margin-top --platform-enter-shrink --platform-shrink background grid-template-columns"),
 ("mq.w-le-720", C, "2:10793", 3, ["morph.panel"], "Morph footer stacks.", "justify-content display width"),
 ("mq.w-le-860", C, "2:899", 4, ["overlays.drawer"], "Why-bring drawer bottom-sheet style.", "justify-content padding transform text-wrap white-space top right"),
 ("mq.w-le-860", C, "2:2305", 10, ["pain", "pain.notes"], "Pain phone layout; notes hidden (JS twin N2:4415).", "background overflow justify-content align-items padding gap width max-width letter-spacing font-size font-weight line-height +3"),
 ("mq.w-le-860", C, "2:3519", 12, ["people.card", "people.o", "people.carousel"], "Future card layout, people-o face size, community pill.", "gap min-height padding overflow margin-bottom letter-spacing text-wrap flex-direction align-items font-size line-height display +10"),
 ("mq.w-le-860", C, "2:4093", 6, ["overlays.signup", "ui.shared(sb-*)"], "Dialog bar/action footer re-grid, sticky footer (safe-area padding at 2:4100).", "padding-inline grid-template-areas z-index padding background position bottom flex grid-area justify-self"),
 ("mq.w-le-860", C, "2:7798", 1, ["platform"], "Row checks hidden.", "display"),
 ("mq.w-le-860", J, "N2:4415", None, ["pain.notes"], "Base note layout: mobile set centred on an 860 design, desktop set on 1440x868; change listener + ResizeObserver.", None),
 ("mq.w-le-860", J, "N2:4592-4645", None, ["pain.notes"], "NOT matching and not reduced: 3 s extra-note ticker (max 12); see js.pain-container-1100.", None),
 ("mq.w-le-860", J, "N2:6203-6217", None, ["people.o"], "Seller preview (hover/focus/click) disabled; read per event.", None),
 ("mq.w-le-860", J, "N2:7179", None, ["overlays.signup"], "Reactive store for a sheet presentation; the only caller passes dialog (N2:13306), so inert but created.", None),
 ("mq.w-le-860", J, "N2:11295-11296", None, ["people.card", "pain"], "Above 860 pain always dark; at <=860 only once the showcase top <= 0.5 px; change listener.", None),
 ("mq.w-ge-861", C, "2:3248", 1, ["people.deck"], "Inactive profile shells display:none (2:3267). At touch 861-1200 / landscape device-width<=500 this overlaps mq.c860; 2:3267 (0,2,0) beats 2:3468 (0,1,0) display:flex regardless of order, so inactive shells stay hidden there (INFERRED visible outcome; measure 1024t, 932x430).", "display"),
 ("mq.w-ge-861", C, "2:5818", 26, ["platform", "platform.sweep"], "Desktop per-row title layout and sweep variant; later than 2:5672 so wins on shared props in the overlap.", "font-size font-weight line-height color -webkit-text-fill-color background-image background-size background-clip height animation display +3"),
 ("mq.w-ge-861", J, "N2:10780-10813", None, ["people.deck"], "Desktop deck = (min-width: 861px) AND NOT c860 AND NOT reduced: section height deck + 1.45vh + (n-1) x 0.34vh, --profile-scale eases from min(1.22, (innerWidth-112)/(deckWidth-248)) to 1; polled per frame.", None),
 ("mq.w-ge-861-nopref", C, "2:3249", 3, ["people.deck"], "Profile sticky, chrome, tabs desktop geometry (nested in 2:3248).", "--profile-scale z-index width position top justify-content gap flex-basis max-width"),
 ("mq.w-861-1000", C, "2:5624", 3, ["platform"], "Card/mission spacing, mission title size.", "padding-top gap font-size font-weight"),
 ("mq.w-le-960", C, "2:10836", 10, ["platform", "platform.stageBg"], "Header/features/rows tablet layout.", "padding gap grid-template-columns justify-content width max-width white-space flex-direction align-items flex order aspect-ratio +2"),
 ("mq.w-le-1000", C, "2:7753", 4, ["platform", "platform.sweep"], "Row copy padding, row-title type/overflow.", "padding font-size font-weight line-height overflow white-space height"),
 ("mq.w-le-1000", C, "2:10651", 1, ["morph.panel"], "Morph title 36px.", "font-size"),
 ("mq.w-ge-1001", C, "2:5810", 1, ["platform"], "Mission title size.", "letter-spacing white-space font-size font-weight"),
 ("mq.w-ge-1001-nopref", C, "2:226", 1, ["commission"], "Sticky commission (min-height 100vh+48, top -48). Overlaps mq.c1000 at touch 1001-1200 and landscape device-width<=500.", "min-height position top"),
 ("mq.w-le-1100", C, "2:7748", 1, ["platform"], "Tools grid columns.", "grid-template-columns"),
 ("mq.w-le-1200", C, "2:4484", 2, ["people.deck"], "Profile rail thumb/title smaller.", "flex-basis width font-size line-height"),
 ("mq.w-le-1200", C, "2:4508", 1, ["people.deck"], "Posts grid columns/gap.", "grid-template-columns gap"),
 ("mq.w-le-1200", C, "2:4935", 1, ["people.deck"], "Reviews gap.", "gap"),
 ("mq.c860", C, "2:3384", 15, ["people.card", "people.deck"], "Shrink vars reset, profile sticky off, tabs horizontal drag rail, deck x-mandatory snap; all shells shown only where (width>=861px) is false (see 2:3248).", "--future-shrink-scale --future-shrink-radius --profile-scale position top flex-direction justify-content align-items gap overflow touch-action visibility +37"),
 ("mq.c860", C, "2:3650", 1, ["people.card"], "Re-asserts future shrink scale 1 / radius 0.", "--future-shrink-scale --future-shrink-radius"),
 ("mq.c860", C, "2:5672", 13, ["platform", "platform.sweep"], "Mission/row titles stacked; 28px sweep variant (loses to 2:5818 in the overlap).", "font-size font-weight gap line-height color -webkit-text-fill-color background-image background-size background-clip height animation +3"),
 ("mq.c860", C, "2:10990", 14, ["commission", "people.card", "platform", "platform.stageBg", "platform.sweep", "morph.panel", "morph.tween", "nav"], "All shrink vars neutralised; platform card/stage/artboard resized; nav+morph panel = 100dvh-40 x 100vw-40.", "--future-shrink-scale --commission-shrink-scale --platform-shrink-scale border-radius transform padding aspect-ratio +15"),
 ("mq.c860", J, "N2:4647-4669", None, ["pain.notes"], "Note drag disabled (keys still move notes).", None),
 ("mq.c860", J, "N2:10913-10918", None, ["people.deck"], "Compact deck: horizontal tabs, drag rail (4 px slop), snap tracking (150 ms + scrollend), active +-1 shells rendered; change listener.", None),
 ("mq.c1000", C, "2:916", 33, ["commission"], "Phone/tablet commission: sticky off, single column, compact copy, fee visual scale, why-link.", "--commission-shrink-scale --commission-shrink-radius overflow min-height position top border-radius flex padding transform height display +24"),
 ("mq.c1000", J, "N2:3085-3099", None, ["commission"], "Compact class + arrow; runway 0.06 x innerHeight only when not compact and not reduced; title-wrap detection only when compact; polled per scroll/resize frame, no change listener.", None),
 ("mq.c1030", C, "2:3271", 20, ["people.deck"], "Widgets compact (crumb/claim hidden, cover, identity, avatar, stats).", "gap padding display flex-direction order aspect-ratio border-radius max-height z-index margin-top position color +13"),
 ("mq.c1030", C, "2:3684", 1, ["people.deck"], "Widget logo smaller.", "border-radius width height padding font-size"),
 ("mq.c1030", C, "2:3786", 12, ["people.deck"], "About widget compact.", "gap padding-top font-size line-height padding"),
 ("mq.c1030", C, "2:4290", 11, ["people.deck"], "Post card compact.", "border-radius gap padding font-size line-height width height -webkit-line-clamp bottom left top right"),
 ("mq.c1030", C, "2:4378", 1, ["people.deck"], "Post meta compact.", "gap font-size line-height"),
 ("mq.c1030", C, "2:4514", 4, ["people.deck"], "Posts masonry columns, rail layout.", "grid-template-columns column-count column-gap margin-bottom display"),
 ("mq.c1030", C, "2:4612", 6, ["people.deck"], "Review summary compact.", "gap white-space font-size line-height"),
 ("mq.c1030", C, "2:4770", 6, ["people.deck"], "Review item compact.", "border-radius gap padding font-size line-height width height"),
 ("mq.c1030", C, "2:4940", 12, ["people.deck"], "Reviews compact; filters horizontal scroll.", "grid-template-columns gap height padding font-size line-height border-radius width margin-left margin-inline padding-inline scrollbar-width +2"),
 ("mq.c1030", C, "2:5055", 3, ["people.deck"], "Gallery grid compact.", "grid-template-columns gap border-radius margin-bottom font-size line-height"),
 ("mq.c1030", C, "2:5133", 4, ["people.deck"], "Feed compact.", "--feed-inset margin-top gap padding font-size line-height padding-top"),
 ("mq.c1000-nodw", C, "2:1473", 3, ["hero.countdown", "morph.countdown"], "Countdown medium size (font 28, cell 36 per v1).", "border-radius gap width min-width height padding font-size"),
]

# --- non-media gates -------------------------------------------------------------------------------
G = [
 dict(id="css.floor-320", condition="root min-width 320px (below it the page stops shrinking and scrolls sideways)", kind="css-floor",
      features=["width"], edges=[("width", 319)], parts=["engine.scroll", "theme.tokens"], sites=["2:11745"],
      effect="Hard lower bound of every width band.", status="CONFIRMED"),
 dict(id="html.viewport-meta", condition="viewport meta width=device-width, initial-scale=1; no viewport-fit=cover", kind="html-attr",
      features=["width", "device-width"], edges=[], parts=["engine.scroll"], sites=["html:5"],
      effect="Every width query depends on it (without it iOS lays out at 980). Ship the identical meta. Without viewport-fit=cover iOS safe-area insets are 0 (INFERRED).", status="CONFIRMED (meta); safe-area consequence INFERRED"),
 dict(id="css.safe-area", condition="env(safe-area-inset-bottom) inside width blocks", kind="css-env",
      features=["width", "safe-area"], edges=[], parts=["overlays.drawer", "overlays.signup", "ui.shared(sb-*)"], sites=["2:1159", "2:4100", "2:11735"],
      effect="Sheet/footer/signup bottom padding; same fallbacks (0px twice, max(24px, inset) once).", status="CONFIRMED (CSS); value 0 INFERRED"),
 dict(id="css.hover-ungated", condition="16 plain :hover rules not gated by (hover: hover)", kind="css-hover-ungated",
      features=["hover", "pointer"], edges=[], parts=["hero", "overlays.drawer", "people.o", "platform", "nav"], sites=["2:894", "2:1873-1879", "2:2564"],
      effect="Sticky hover after a tap on touch; the rewrite must NOT add hover gates the original lacks.", status="CONFIRMED (grep count 16)"),
 dict(id="js.hero-splash-stage-1280", condition="hero stage clientWidth (fallback innerWidth) < 1280, splash expanding phase only", kind="js-width-check",
      features=["width"], edges=[("width", 1279)], parts=["hero.orbit"], sites=["N2:4033-4034", "N2:4100-4110", "N2:4192"],
      effect="Splash cards pulled in by (1280 - stage) x 0.35 px; design canvas 1512x779. Stage = viewport width at 601-1511 (INFERRED from 2:2009).", status="CONFIRMED"),
 dict(id="js.pain-container-1100", condition="pain-notes container width < 1100 (only when not (width<=860px) and not reduced)", kind="js-width-check",
      features=["container-width", "prefers-reduced-motion"], edges=[("container-width", 1099)], parts=["pain.notes"], sites=["N2:4592-4645", "N2:4692-4702"],
      effect="Extra-note placement: jittered slots below 1100, 120 scored random samples at or above; extras cleared when the commission card top < 0.995vh. Viewport width at which the container hits 1100 to be MEASURED.", status="CONFIRMED"),
 dict(id="js.commission-visual-scale", condition="ResizeObserver on parent: --visual-scale = min(0.8, parentWidth / 432)", kind="js-width-check",
      features=["container-width"], edges=[], parts=["commission.typing"], sites=["N2:2511-2518"],
      effect="Continuous scale below a 345.6 px parent; live.", status="CONFIRMED"),
 dict(id="js.countdown-cell", condition="digit spacer offsetHeight via ResizeObserver (follows CSS font at 400 / 1000-or-touch-1200)", kind="js-measure",
      features=["width", "prefers-reduced-motion"], edges=[], parts=["hero.countdown", "morph.countdown"], sites=["N2:3817", "N2:3829-3833", "N2:3858-3873", "RT:3110-3137"],
      effect="Face translateY = slot x measured cell height (v1: 31/36/52); faces hidden until height > 0; live on resize.", status="CONFIRMED"),
 dict(id="js.people-o-preview", condition="preview width min(320, innerWidth-24), 12 px from edges, flip above if past innerHeight-12; re-run on every scroll/resize frame", kind="js-width-check",
      features=["width", "height"], edges=[], parts=["people.o"], sites=["N2:6204-6215", "N2:6269", "N2:6304-6307"],
      effect="Knee at innerWidth 344; live recomputation via the scene engine subscription.", status="CONFIRMED"),
 dict(id="js.people-o-reveal-io", condition="IntersectionObserver threshold 0.35 on the future heading", kind="js-geometry",
      features=["height"], edges=[], parts=["people.o"], sites=["N2:6261-6268"],
      effect="Reveal staged when visible, reset when it leaves.", status="CONFIRMED"),
 dict(id="js.profile-sticky-computed", condition="computed position of the profile sticky == sticky (true only under mq.w-ge-861-nopref and not mq.c860)", kind="js-indirect",
      features=["width", "device-width", "hover", "pointer", "prefers-reduced-motion"], edges=[("width", 860)], parts=["nav", "people.deck"], sites=["N2:12966-12977", "N2:13001", "N2:13230-13231"],
      effect="Nav scroll-hidden / profile-sticky-hidden while pinned; per scroll frame.", status="CONFIRMED"),
 dict(id="js.nav-on-dark", condition="elementFromPoint at the nav centre against section selectors", kind="js-geometry",
      features=["width", "height"], edges=[], parts=["nav", "nav.hitTest"], sites=["N2:12950-12964"],
      effect="is-on-dark over pain/platform/shrinking commission; per scroll frame.", status="CONFIRMED"),
 dict(id="js.morph-arm", condition="platform rect height >= 0.45 x (visualViewport.height or innerHeight) and bottom <= that + 8; IO rootMargin 200%", kind="js-geometry",
      features=["height"], edges=[], parts=["morph.tween", "morph.mount"], sites=["N2:12691-12700", "N2:13040-13047", "N2:13082-13088"],
      effect="Arms wheel/touch scroll-jack for the 680 ms morph tween; reduced motion jumps. No width gate.", status="CONFIRMED"),
 dict(id="js.commission-bands", condition="card top in [0.06, 0.42] x innerHeight; bottom in [0.35, 0.85] x innerHeight; reduced = step at 0.5", kind="js-geometry",
      features=["height", "prefers-reduced-motion"], edges=[], parts=["commission"], sites=["N2:3075-3084", "N2:3112-3124"],
      effect="Enter-shrink / shrink vars; no width gate.", status="CONFIRMED"),
 dict(id="js.future-shrink-band", condition="viewport-height band 0.85-0.35 (reduced = step at 0.5)", kind="js-geometry",
      features=["height", "prefers-reduced-motion"], edges=[], parts=["people.card"], sites=["N2:11285-11290"],
      effect="--future-shrink; no width gate in JS (CSS mq.c860 neutralises it).", status="CONFIRMED"),
 dict(id="js.scene-activation", condition="scene active if rect within [-innerHeight, 2 x innerHeight]; IO rootMargin 100% (pain 150%)", kind="js-geometry",
      features=["height"], edges=[], parts=["engine.scene"], sites=["N2:2663-2680", "N2:2689-2731", "N2:2768"],
      effect="data scene active/paused; deferred rendering with measured intrinsic size; one rAF for scroll+resize.", status="CONFIRMED"),
 dict(id="js.dialog-direction", condition="unit vector from viewport centre to the focused trigger (16 px scale), at open", kind="js-geometry",
      features=["width", "height"], edges=[], parts=["overlays.signup", "ui.shared(sb-*)"], sites=["UI:1927-1934", "UI:2001-2012"],
      effect="--dialog-dir-x/y entrance direction; fallback 0/16 px.", status="CONFIRMED"),
 dict(id="js.waitlist-dialog-size", condition="width min(360px, 100vw - 48px); maxHeight 85vh (props, not media queries)", kind="js-width-check",
      features=["width", "height"], edges=[], parts=["overlays.signup"], sites=["N2:7313", "N2:13304"],
      effect="360 px at viewport >= 408, 100vw-48 below.", status="CONFIRMED"),
 dict(id="js.preload-hover", condition="link preload on mousemove (20 ms debounce) vs mousedown/touchstart", kind="js-touch-check",
      features=["hover", "pointer"], edges=[], parts=["engine.scroll"], sites=["html:64", "CZ:1180-1192"],
      effect="Network only, no visual effect; match or exclude on purpose.", status="CONFIRMED"),
 dict(id="js.firefox-ua", condition="user agent contains Firefox", kind="js-ua",
      features=["user-agent"], edges=[], parts=["engine.scroll"], sites=["RT:1417", "RT:2133"],
      effect="Svelte runtime template import path; no visual effect; not a breakpoint (listed for completeness).", status="CONFIRMED"),
]

CONT = [
 ("2:1764", "hero h1 font clamp 40px / 4.5vw / 64px", [889, 1422], "width", ["hero"]),
 ("2:1777", "hero title gap clamp 14 / 1.6vw / 24", [875, 1500], "width", ["hero"]),
 ("2:2261", "pain note padding clamp 12 / 2.6vw / 20", [462, 769], "width", ["pain.notes"]),
 ("2:2289", "pain note text clamp 14 / 2.2vw / 20", [636, 909], "width", ["pain.notes"]),
 ("2:2442, 2:5445, 2:5668", "future / platform / mission title clamp 36 / 4vw / 48", [900, 1200], "width", ["people.card", "platform"]),
 ("2:10894", "platform title clamp 32 / 8vw / 40 (inside width<=640)", [400, 500], "width", ["platform"]),
 ("2:3019-3020", "profile shell height clamp 743 / 100vh-80 / 820", [823, 900], "height", ["people.deck"]),
 ("2:2026", "orbit edge push max(0, (1280 - 100vw) x 0.35)", [1280], "width", ["hero.orbit"]),
 ("2:1569, 2:1600", "orbit unit 100cqw / 302 on an inline-size container", [], "container-width", ["hero.orbit"]),
 ("2:6394-6398", "platform artboard scale 100cqw / 640 (named inline-size container)", [], "container-width", ["platform.stageBg"]),
 ("2:6975-6993", "secure-network arm sizes from cqw/cqh (size container)", [], "container-size", ["platform.glint"]),
 ("N2:2511-2518", "commission fee visual min(0.8, parent / 432)", [345.6], "container-width", ["commission.typing"]),
 ("N2:6204-6215", "seller preview min(320, innerWidth - 24)", [344], "width", ["people.o"]),
 ("N2:13304", "waitlist dialog min(360, 100vw - 48)", [408], "width", ["overlays.signup"]),
 ("N2:10800", "desktop deck scale min(1.22, (innerWidth - 112) / (deckWidth - 248))", [], "width", ["people.deck"]),
 ("all sheets", "viewport units: vw 34, vh 15, svh 9, dvh 7 uses; 16 clamp() calls", [], "width+height", ["*"]),
]

OVERLAPS = [
 dict(a="mq.c860", b="mq.w-ge-861", region="touch (hover:none, pointer:coarse) at 861-1200, or device-width<=500 with width>=861 (phone landscape 932x430)",
      outcome="Both match. People: 2:3384 later wins on sticky/position, but 2:3267 (0,2,0) beats 2:3468 (0,1,0) so inactive shells stay display:none. Platform: 2:5818 is later than 2:5672 and wins; 2:10990 single-class selectors lose to 2:5818's multi-class ones (INFERRED).",
      status="CONFIRMED syntax; visible outcome INFERRED (measure at 1024t and 932x430)"),
 dict(a="mq.c1000", b="mq.w-ge-1001-nopref", region="touch at 1001-1200, or device-width<=500 with width>=1001 (not phone landscape 932x430: 932 < 1001)", outcome="Both match on commission; source order and specificity decide.", status="CONFIRMED syntax; outcome INFERRED"),
 dict(a="mq.c1000", b="mq.w-ge-1001", region="as above", outcome="Commission compact and platform desktop mission title both apply.", status="INFERRED"),
 dict(a="mq.c860 (JS)", b="mq.w-ge-861 (JS)", region="as the CSS overlap", outcome="JS resolves it: desktop deck requires NOT c860, so touch tablets get the compact JS deck while CSS still hides inactive shells.", status="CONFIRMED (N2:10783)"),
 dict(a="mq.w-le-860", b="mq.c860", region="touch or device-width<=500 with width>860", outcome="Pure-width users (people.o preview, pain layout, pain notes hidden, pain-dark, sheet store) take the DESKTOP path while combo users (deck, note drag, shrinks) take the compact path. Never substitute one for the other.", status="CONFIRMED"),
]

GAPS = [
 dict(lower="(width<=600px)", upper="(width>=601px)", open=[600, 601], probe=600.5, note="(width>600px) matches in the gap; 2:2009/2:2026 do not."),
 dict(lower="(width<=640px)", upper="(width>=641px)", open=[640, 641], probe=640.5, note="(width>640px) matches; 2:1106 does not."),
 dict(lower="(width<=860px)", upper="(width>=861px)", open=[860, 861], probe=860.5, note="CSS and JS ((max-width: 860px) vs (min-width: 861px)) both leave it unmatched."),
 dict(lower="(width<=1000px)", upper="(width>=1001px)", open=[1000, 1001], probe=1000.5, note="2:226 and 2:5810 vs the <=1000 rules."),
]

# ------------------------------------------------------------------------------------------------
uses_by = collections.defaultdict(list)
for cid, kind, s, rules, parts, eff, props in U:
    u = {"site": site(s), "kind": kind, "parts": parts, "effect": eff}
    if rules is not None:
        u["rules"] = rules
    if props:
        toks = props.split()
        more = [t for t in toks if t.startswith("+")]
        u["props"] = [t for t in toks if not t.startswith("+")]
        if more:
            u["propsTruncated"] = int(more[0][1:])
    uses_by[cid].append(u)

def uniq(xs):
    out = []
    for x in xs:
        if x not in out:
            out.append(x)
    return out

conditions = []
for cid, cond, feats, edges, legacy, summ in MQ:
    us = uses_by[cid]
    assert us, cid
    kinds = sorted({u["kind"] for u in us})
    kind = "+".join(kinds)
    rc = sum(u.get("rules", 0) for u in us if u["kind"] == C)
    entry = {
        "id": cid, "condition": cond, "kind": kind, "features": feats,
        "edges_px": sorted({n for _, n in edges}),
        "edges": [{"feature": f, "pair": [n, n + 1]} for f, n in edges],
        "parts": sorted(uniq(p for u in us for p in u["parts"])),
        "sites": [u["site"] for u in us],
        "effect": summ,
        "cssBlocks": sum(1 for u in us if u["kind"] == C),
        "jsSites": sum(1 for u in us if u["kind"] == J),
        "status": "CONFIRMED",
        "uses": us,
    }
    if rc:
        entry["ruleCount"] = rc
    if legacy:
        entry["equivalentForms"] = legacy
    conditions.append(entry)

for g in G:
    e = {
        "id": g["id"], "condition": g["condition"], "kind": g["kind"], "features": g["features"],
        "edges_px": sorted({n for _, n in g["edges"]}),
        "edges": [{"feature": f, "pair": [n, n + 1]} for f, n in g["edges"]],
        "parts": sorted(g["parts"]), "sites": [site(s) for s in g["sites"]],
        "effect": g["effect"], "status": g["status"],
    }
    conditions.append(e)

# edges index
idx = collections.OrderedDict()
for c in conditions:
    for e in c["edges"]:
        key = (e["feature"], e["pair"][0])
        d = idx.setdefault(key, {"feature": e["feature"], "px": e["pair"][0], "pair": e["pair"], "conditions": [], "parts": set(), "gatedBy": set()})
        d["conditions"].append(c["id"])
        d["parts"].update(c["parts"])
        k = c["kind"]
        if "css" in k:
            d["gatedBy"].add("css")
        if "js" in k:
            d["gatedBy"].add("js")
        if k == "css-floor":
            d["gatedBy"].add("css")
fo = {"width": 0, "width(touch)": 1, "device-width": 2, "container-width": 3}
edges = []
for (f, n), d in sorted(idx.items(), key=lambda kv: (kv[0][1], fo[kv[0][0]])):
    d["parts"] = sorted(d["parts"])
    d["gatedBy"] = "+".join(sorted(d["gatedBy"]))
    d["conditions"] = uniq(d["conditions"])
    edges.append(d)

width_pairs = sorted({tuple(d["pair"]) for d in edges if d["feature"] in ("width", "width(touch)")})
width_pairs = [list(p) for p in width_pairs]

profiles = [
 dict(id="desk", hover="hover", pointer="fine", deviceWidth="= viewport width", reducedMotion="no-preference", dpr=1, height=900, at="every edge pair"),
 dict(id="desk-rm", hover="hover", pointer="fine", deviceWidth="= viewport width", reducedMotion="reduce", dpr=1, height=900, at="every edge pair (reduced motion changes layout)"),
 dict(id="touch", hover="none", pointer="coarse", deviceWidth="= viewport width", reducedMotion="no-preference", dpr="3 if width<=500 else 2", height=900, at="every edge pair"),
 dict(id="touch-rm", hover="none", pointer="coarse", deviceWidth="= viewport width", reducedMotion="reduce", dpr=2, height=900,
      at=[[600, 601], [860, 861], [1000, 1001], [1030, 1031], [1200, 1201]]),
]
special = [
 dict(id="phone-landscape", viewport=[932, 430], screen=[430, 932], hover="none", pointer="coarse", dpr=3, reducedMotion=["no-preference", "reduce"],
      why="device-width<=500 arm with width 932: the mq.c860 + mq.w-ge-861 overlap only. 932 < 1001, so mq.c1000 matches and mq.w-ge-1001 does not: NOT in the mq.c1000 + mq.w-ge-1001 overlap (proved: lean Fw.Site.Breakpoints.matrix_landscape_overlaps). That overlap is run by touch at 1031/1200 and dw-arm-isolate at 1031/1201 with screen 500"),
 dict(id="dw-arm-isolate", viewport=[[1001, 900], [1031, 900], [1201, 900]], screen=[[500, 900], [501, 900]], hover="hover", pointer="fine", dpr=1, reducedMotion="no-preference",
      why="device-width 500/501 alone flips mq.c860/c1000/c1030 at viewports 1031 and 1201, and mq.c860/c1000 at 1001, where mq.c1030 already holds by width (1001 <= 1030) and does NOT flip; it never flips mq.c1000-nodw (the one combo without the arm) (proved: lean Fw.Site.Breakpoints.matrix_dw_arm)"),
 dict(id="hover-pointer-cross", viewport=[[1024, 768], [1200, 900]], combos=[["none", "fine"], ["hover", "coarse"]], dpr=2, reducedMotion="no-preference",
      why="the combos' touch arm needs hover:none AND pointer:coarse; each alone must not match it. At 1200 (screen 1200) no combo matches; at 1024 mq.c860, mq.c1000 and mq.c1000-nodw do not match, but mq.c1030 DOES, through its width arm (1024 <= 1030) (proved: lean Fw.Site.Breakpoints.matrix_cross_no_touch_arm). (hover: hover) and (hover: none) take both values in this block (matrix_neutral_hover_both_sides)"),
 dict(id="dark", viewport=[[1440, 900], [430, 932]], prefersColorScheme="dark", why="mq.dark must stay neutralised: pixels equal to light"),
 dict(id="fractional-gaps", viewport=[g["probe"] for g in GAPS], via="DPR 1.25 / browser zoom so innerWidth is fractional", why="the original leaves (N, N+1) unmatched by both sides; the rewrite must too"),
 dict(id="height-probes", viewport=[[1440, 822], [1440, 823], [1440, 900], [1440, 901], [430, 775], [430, 815]], why="profile shell clamp knees at viewport height 823/900; iOS toolbar heights; vh-band JS gates"),
]

n_pairs = len(width_pairs)
loads = (n_pairs * 2) * 3 + 5 * 2 + 2 + 3 * 2 + 2 * 2 + 2 + len(GAPS) + 6
breakdown = {"desk": n_pairs*2, "desk-rm": n_pairs*2, "touch": n_pairs*2, "touch-rm": 10, "phone-landscape": 2, "dw-arm-isolate": 6, "hover-pointer-cross": 4, "dark": 2, "fractional-gaps": len(GAPS), "height-probes": 6}
assert sum(breakdown.values()) == loads
matrix = {
 "edgePairs": width_pairs,
 "deviceWidthPairs": [[500, 501]],
 "containerPairs": [{"pair": [1099, 1100], "of": "pain-notes container (js.pain-container-1100)", "viewport": "find by measurement"}],
 "featureCombos": {"profiles": profiles, "special": special},
 "dpr": [
   {"dpr": 1, "for": "desk, desk-rm, dw-arm-isolate"},
   {"dpr": 2, "for": "touch above 500 px, touch-rm, hover-pointer-cross"},
   {"dpr": 3, "for": "touch at or below 500 px, phone-landscape"},
   {"dpr": 1.25, "for": "fractional-gaps probes (and v1's 1536 check)"},
   {"dpr": 2.625, "for": "fractional-gaps probes on a phone width (412)"},
 ],
 "dprNote": "No DPR-dependent code: no devicePixelRatio, no resolution queries, every srcset has one URL (CONFIRMED by grep). DPR changes raster only, plus fractional CSS widths.",
 "liveResize": {
   "edges": [p[0] for p in width_pairs],
   "jsEdges": [
     {"edge": 600, "why": "change listeners (splash finish is one-way; chrome ready)", "conditions": ["mq.w-le-600"]},
     {"edge": 860, "why": "w860 listeners (pain layout, pain-dark), c860 deck listener, ResizeObserver on notes", "conditions": ["mq.w-le-860", "mq.c860", "mq.w-ge-861"]},
     {"edge": 1000, "why": "commission compact polled per frame, no listener", "conditions": ["mq.c1000"]},
     {"edge": 400, "why": "countdown cell via ResizeObserver", "conditions": ["mq.w-le-400", "js.countdown-cell"]},
     {"edge": 1279, "why": "splash stage pull, only during the splash", "conditions": ["js.hero-splash-stage-1280"]},
   ],
   "sequences": [
     {"id": "desk-down-up", "widths": [1512, 1511, 1280, 1279, 1201, 1200, 1101, 1100, 1031, 1030, 1001, 1000, 961, 960, 861, 860, 721, 720, 641, 640, 601, 600, 481, 480, 462, 461, 401, 400, 320, "reverse"], "height": 900},
     {"id": "rotate", "viewports": [[430, 932], [932, 430], [430, 932]], "screen": [430, 932], "touch": True},
     {"id": "v1-pain", "widths": [1440, 600, 1440, 600, 1440], "note": "original non-deterministic (pain IO after reflow): accept either A/A class"},
     {"id": "touch-1024", "widths": [1024, 1201, 1024], "touch": True},
   ],
   "liveMediaFlips": [
     {"flip": "prefers-reduced-motion reduce <-> no-preference", "at": [430, 1024, 1440]},
     {"flip": "touch on <-> off (pointer-only change)", "at": [1024], "note": "commission c1000 is polled with no change listener: updates at the next scroll/resize frame (INFERRED); the rewrite must match"},
   ],
   "compare": "rewrite after sequence vs original after the SAME sequence (not vs a fresh load): some original state is path-dependent",
 },
 "estimate": {"loadsPerEngine": loads, "breakdown": breakdown, "engines": ["chromium", "playwright-webkit"], "plus": "one Simulator check (430x775 DPR 3) and the live-resize sequences", "status": "INFERRED arithmetic"},
}

doc = {
 "schema": "fw.breakpoints/1",
 "source": {"snapshot": "b1789284481295-a455e793", "root": "site-pretty", "baseline": "../fastwork-com-web-optimize/baseline.json",
            "sweeps": ["raw-css.md", "raw-js.md", "raw-v1.md", "verification pass (merged here)"],
            "note": "Conditions, citations and plain-language effects only; no Fastwork code. Lines are 1-based in the prettified snapshot."},
 "totals": {},
 "conditions": conditions,
 "edges": edges,
 "overlaps": OVERLAPS,
 "fractionalGaps": GAPS,
 "continuous": [{"sites": s, "expression": e, "knees_px": k, "axis": a, "parts": p} for s, e, k, a, p in CONT],
 "absent": ["@supports", "@container queries (containers exist only for cq units)", "orientation", "resolution", "any-hover", "any-pointer", "height/aspect-ratio queries", "print/screen/not/only",
            "devicePixelRatio", "screen.*", "maxTouchPoints", "ontouchstart/TouchEvent", "GestureEvent", "multi-URL srcset"],
 "unmappedPartIds": ["ui.shared(sb-*)", "theme.tokens", "hero (section shell)", "platform (section shell)"],
 "matrix": matrix,
}
mqs = [c for c in conditions if c["id"].startswith("mq.")]
doc["totals"] = {
 "mediaConditions": len(mqs),
 "cssMediaConditions": sum(1 for c in mqs if "css" in c["kind"]),
 "jsOnlyMediaConditions": sum(1 for c in mqs if c["kind"] == J),
 "sharedCssJs": sum(1 for c in mqs if c["kind"] == C + "+" + J),
 "nonMediaGates": len(conditions) - len(mqs),
 "cssBlocks": sum(c["cssBlocks"] for c in mqs),
 "cssRules": sum(c.get("ruleCount", 0) for c in mqs),
 "jsMatchMediaSites": sum(c["jsSites"] for c in mqs),
 "edges": len(edges),
 "widthEdgePairs": len(width_pairs),
}
json.dump(doc, open(OUT, "w"), indent=1, ensure_ascii=False)
open(OUT, "a").write("\n")
print(json.dumps(doc["totals"]), file=sys.stderr)
for d in edges:
    print(d["feature"], d["pair"], d["gatedBy"], len(d["conditions"]), ",".join(d["parts"]), file=sys.stderr)
