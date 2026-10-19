---
id: 2026-10-19-port-completeness
kind: note
title: "Port completeness audit: 26 gaps vs the snapshot, 12 not covered by a task; a stale dist build showed a placeholder page"
status: review
created: 2026-10-19
topics: [port, faithfulness, svg, assets]
---

# Port completeness audit (read-only, main e4927758)

Static comparison of snapshot/site/index.html and its compiled assets with apps/site/src on main. Evidence cites snapshot byte offsets and rewrite file:line. INFERRED until a gate or visual-diff run confirms the rendered result.

| section | part | missing | covered by |
|---|---|---|---|
| build | apps/site/dist/aot (the prerendered build on disk) | The build on disk is from before the port. It shows an MUI placeholder nav ('Placeholder site', Menu/Drawer/Sign up buttons) and none of the ported sections. If the user looked at this build, it shows almost nothing of t | none |
| document head | <title>, meta description, og:*, twitter:*, canonical, hreflang alternates, favicons/apple-touch-icon/manifest | Title is the placeholder 'fw site (placeholder)'. None of the original's SEO/social meta tags or icon links are present. | none |
| document body end | nav.site-locale-links (English / ไทย / Indonesia links in the initial HTML) | Not rendered. The rewrite has these links only inside the lang menu, which is mounted when opened. | none |
| nav | Fastwork wordmark logo (svg viewBox 0 0 181 46, 9 paths) | Drawn as a placeholder (two rounded rects) instead of the real wordmark. | svg-extract |
| nav | Language switch globe icon | Approximated: the rewrite uses an ellipse plus a full-width line, while the original uses a circle plus two meridian arcs (path <path data omitted>M12 3.5c2.3 …'). Small difference in shape. | none |
| hero | Hand-drawn accent word 'you' (3 boil frames of accent-svg, plus the cycled-word artwork) | Strokes are a generic stand-in wave from standInPath(), not the original's lettering paths. The view boxes and insets are correct. | svg-extract |
| hero | 'RSVP Demo day' calendar icon | The six date-dot paths <path data omitted><path data omitted> are missing, so the icon shows only the frame and header line. | snapshot-paths-cleanup |
| people | The 'o' of 'pe-o-ple' wordmark glyph (img /selling/people-wordmark/o.svg) | Replaced by a CSS ring span. The o.svg file is not served (it is not in assets.manifest.json). | people-o-glyph |
| people / profile showcase | Claim badge icon (img /selling/icons/claim.svg) and location pin icons (img /selling/icons/pin.svg, twice per  | CSS shapes are used instead of the original icons, and neither SVG is in the asset manifest. | people-o-glyph |
| people / profile showcase | Feed tabs Services / Reviews / About content | Only the Portfolio tab has content. The other three tabs render an empty div. The original has services grid cards, a reviews summary with filters/toggles, and about/certificates. | deck-panels-lean |
| people / profile showcase | Article post cards (cover, byline with author avatar and name, clock icon with read-minutes, title, excerpt) | Article posts (cine-cafe, local-llm, slow-website) render only as a cover-image tile. The byline, clock SVG, title and excerpt text are dropped, and Post data has no title/excerpt/readMinutes fields. | deck-panels-lean |
| people / profile showcase | Photo post price badge (span.price) and video play badge (span.video with svg) | Neither is rendered. The original shows prices on graphic-designer star-coffee/hunq and ai-automation marketing, and a play icon on all 5 video-editor posts. Post data does not carry price or video. | deck-panels-lean |
| people / profile showcase | Audio card mute icon (svg <path data omitted>) | Drawn as a CSS span instead of the original SVG. | none |
| people / profile showcase | Service rail rating star (svg.star 14x14, color #2b313b) | Replaced with the text glyph '★'. | none |
| people / pain / commission | content-visibility deferral ([data-start-selling-render=deferred] with contain-intrinsic-block-size) for peopl | Not ported for people. Pain and commission have it partly (pain.notes/scene.ts, commission/driver.ts:149-156). This changes paint behaviour, not visible content. | people-pain-deferral |
| pain | Notes avoiding the commission card / nav on-dark exclusion | Selectors match no element, so pain notes do not avoid the commission card and nav.hitTest's exclude/include classes never match. This is a behaviour gap, not missing content. | dead-selectors |
| commission | Heading underline artwork (svg.underline-frame frame-0..2, viewBox 199.201 x 19.8599) | Uses its own approximated 'hand-drawn style' paths instead of the original's paths. The shape is close but not identical. | none |
| commission | Hand-drawn '0%' mark (svg.zero-frame frame-0..2, 4 paths each: zero, two percent circles, slash) | Replaced by its own 2-path stand-in (a loop and a slash), so it reads as 'Ø' rather than the original '0%' lettering. | none |
| morph panel (end-of-page panel hosted in nav) | Title, CTA label, RSVP link, footer (operated-by line, copyright, privacy link) | All text is placeholder: 'Placeholder panel title', 'Action', 'Link', 'Placeholder line' x2, 'Placeholder link'. The links point to #morph-panel instead of f.fastwork.co/demoday and fastwork.com/privacy. The original sho | none |
| morph panel | CTA calendar icon date dots | Same as the hero: the 6 dot paths are missing from the calendar icon. | snapshot-paths-cleanup |
| platform | Fastwork logo mark inside the secure-payment shield (svg 67.2px, viewBox 0 0 46 46) | A circle stand-in instead of the logo mark. | svg-extract |
| platform | Star icon in the profile stats 'Reviews' and in the search result ratings | Approximated star path (<path data omitted>) instead of the original's (<path data omitted>). Small shape difference. | none |
| platform | Search result 'Legal consult' thumbnail fallback image | The <img> fallback src /samples/docs/lawyer/lawyer-consult-cover.png is not in assets.manifest.json, so it is not copied into the build. Only browsers that load the AVIF <source> show the picture. | none |
| overlays: why-bring drawer | Benefit item icons (reputation.svg, payment.svg, folder.svg) and divider image (divider.svg) | All four are replaced by a transparent 1x1 GIF, so the items show no icons and the dividers are blank. None of the files are in assets.manifest.json. | none |
| overlays: why-bring drawer | Brand mark in the drawer header (svg.why-bring-mark viewBox 0 0 46 46) | A placeholder ring glyph instead of the mark. | svg-extract |
| overlays: waitlist signup dialog | Brand mark above 'Join our waitlist' (svg 32px, viewBox 0 0 74 66) | A placeholder ring glyph in a 46x46 box instead of the original 74x66 mark. | svg-extract |

## Evidence

- apps/site/dist/aot (the prerendered build on disk): apps/site/dist/aot/index.html and build-info.json are dated 2026-10-18 21:26, older than HEAD e4927758 (2026-10-19 11:13). Its <header data-fw=nav> contains 'Placeholder site' and id=open-menu/open-drawer/open-dialog. Not rebuilt here because this audit is read-only, so every finding below comes fro
- <title>, meta description, og:*, twitter:*, canonical, hreflang alternates, favi: snapshot/site/index.html <head> (bytes 0-5909): icon-192/favicon.ico/favicon.svg/apple-touch-icon/site.webmanifest links, og:title 'Fastwork · Show the world…', canonical, 4 hreflang alternates. Rewrite: apps/site/index.html:6 has only charset, viewport and the placeholder title.
- nav.site-locale-links (English / ไทย / Indonesia links in the initial HTML): snapshot/site/index.html byte ~99371 <nav class="site-locale-links" aria-label="Language">. Nothing matches site-locale-links in apps/site/src; the links exist only at apps/site/src/parts/nav.langMenu/index.tsx:9-11.
- Fastwork wordmark logo (svg viewBox 0 0 181 46, 9 paths): snapshot: header.start-selling-top-nav a.start-selling-top-nav-logo svg (byte 6617). Rewrite: apps/site/src/parts/nav/index.tsx:142-145 uses <rect> shapes, and the comment at :57 says 'placeholder shape … until svg-extract'.
- Language switch globe icon: snapshot byte 17114 .start-selling-language-switch__icon svg. Rewrite: apps/site/src/parts/nav.langMenu/index.tsx:86-90.
- Hand-drawn accent word 'you' (3 boil frames of accent-svg, plus the cycled-word : snapshot: h1#start-selling-heading em.script-accent svg.accent-svg.is-idle-frame-0..2 (bytes 37281-39181). Rewrite: apps/site/src/parts/hero.accent/index.tsx:121 d={standInPath(...)}, and data.ts:4 and :55 describe it as a stand-in.
- 'RSVP Demo day' calendar icon: snapshot: a.hero-cta-rsvp svg.solar-calendar-linear (byte 42344) has 10 paths. Rewrite: apps/site/src/parts/hero/index.tsx:28-37 has 2 paths.
- The 'o' of 'pe-o-ple' wordmark glyph (img /selling/people-wordmark/o.svg): snapshot: img.start-selling-future-people-o-vector (byte 44647). Rewrite: apps/site/src/parts/people.o/index.tsx:118-120 <span className={css.ring} />.
- Claim badge icon (img /selling/icons/claim.svg) and location pin icons (img /sel: snapshot: .start-selling-profile-claim img (byte 50507) and .start-selling-profile-location img (bytes 50952, 51807). Rewrite: apps/site/src/parts/people.deck/panel.tsx:32, :38, :65.
- Feed tabs Services / Reviews / About content: Original templates are in nodes/2.DyWL8TcE.js (feed.summaryTitle and the reviewFilter/reviewToggle selenium ids near byte 288548, feed.certificates). Rewrite: apps/site/src/parts/people.deck/panel.tsx:169-171 renders <div className={css.feedPanel} /> for any tab other than 'posts'.
- Article post cards (cover, byline with author avatar and name, clock icon with r: Original template fj in nodes/2.DyWL8TcE.js near byte 277000 (span.cover, span.byline, svg.clock, span.title, span.excerpt). Rewrite: apps/site/src/parts/people.deck/panel.tsx:93-101 uses the same plain tile for every non-audio kind, and people/data.ts:14-19 Post has only kind/id/ratio.
- Photo post price badge (span.price) and video play badge (span.video with svg): Original templates pj/mj in nodes/2.DyWL8TcE.js just before byte 278375 ('r.post.price&&', 'r.post.video&&'). Rewrite: apps/site/src/parts/people.deck/panel.tsx:93-101 and people/data.ts:14-19.
- Audio card mute icon (svg <path data omitted>): snapshot: button.card.is-audio span.mute svg (byte 55036). Rewrite: apps/site/src/parts/people.deck/panel.tsx:118-120 <span className={css.muteIcon} />.
- Service rail rating star (svg.star 14x14, color #2b313b): snapshot: aside.rail li .rating svg.star (bytes 56389, 57761, 59127). Rewrite: apps/site/src/parts/people.deck/panel.tsx:156.
- content-visibility deferral ([data-start-selling-render=deferred] with contain-i: Handoff docs/team/handoffs/content-people-pain-commission.md 'Open' section. No data-render handling in apps/site/src/parts/people*/.
- Notes avoiding the commission card / nav on-dark exclusion: apps/site/src/parts/pain.notes/index.tsx:40 cardSelector '[data-fw="commission-card"], .commission-card' (the commission card at commission/index.tsx has neither). apps/site/src/parts/nav.hitTest/logic.ts:19-21 uses original class names (.commission-card, .start-selling-future-card, .pain, …).
- Heading underline artwork (svg.underline-frame frame-0..2, viewBox 199.201 x 19.: snapshot: h2#commission-heading svg.underline-frame (bytes 62283-62860). Rewrite: apps/site/src/parts/commission/data.ts:32-37 ('Own hand-drawn style underline paths').
- Hand-drawn '0%' mark (svg.zero-frame frame-0..2, 4 paths each: zero, two percent: snapshot: svg.zero-frame.frame-0 (byte 63884) has 4 paths with stroke-width 8/4.8/4.8/4.8. Rewrite: apps/site/src/parts/commission/data.ts:39-44 (ZERO_PATHS has 2 paths) and commission/index.tsx (zeroMark).
- Title, CTA label, RSVP link, footer (operated-by line, copyright, privacy link): Original template lN at nodes/2.DyWL8TcE.js ~byte 336700, which sets header.future, waitlist.join, header.operated, header.copyright and header.privacy. Rewrite: apps/site/src/parts/morph.panel/index.tsx:66, :70, :80, :85, :88-90, :95-99.
- CTA calendar icon date dots: Original lN template calendar svg has 10 paths. Rewrite: apps/site/src/parts/morph.panel/index.tsx:119-128.
- Fastwork logo mark inside the secure-payment shield (svg 67.2px, viewBox 0 0 46 : snapshot: .start-selling-platform-secure-network-shield-logo-mark svg (byte 85029). Rewrite: apps/site/src/parts/platform/Visuals.tsx:378-381.
- Star icon in the profile stats 'Reviews' and in the search result ratings: snapshot bytes 71085, 79325, 80142. Rewrite: apps/site/src/parts/platform/Visuals.tsx:27-33.
- Search result 'Legal consult' thumbnail fallback image: snapshot byte 79807 img src=/samples/docs/lawyer/lawyer-consult-cover.png. Rewrite: apps/site/src/parts/platform/content.ts:48 and Visuals.tsx:180-183. The manifest lists only /selling/optimized/external/lawyer-consult-cover-240.avif.
- Benefit item icons (reputation.svg, payment.svg, folder.svg) and divider image (: Original template EE in nodes/2.DyWL8TcE.js ~byte 82600 uses icons /selling/commission/why-bring/{reputation,payment,folder}.svg and li.why-bring-divider img divider.svg. The files exist in snapshot/site/selling/commission/why-bring/. Rewrite: apps/site/src/parts/overlays.drawer/index.tsx:17 (PIXEL)
- Brand mark in the drawer header (svg.why-bring-mark viewBox 0 0 46 46): Original TE template in nodes/2.DyWL8TcE.js ~byte 82300. Rewrite: apps/site/src/parts/overlays.drawer/index.tsx:108-111.
- Brand mark above 'Join our waitlist' (svg 32px, viewBox 0 0 74 66): snapshot: dialog[data-modal-name=waitlist-signup] .heading svg (byte 94649). Rewrite: apps/site/src/parts/overlays.signup/index.tsx:136-139.
