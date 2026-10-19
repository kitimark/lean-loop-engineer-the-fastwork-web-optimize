# people-o-glyph handoff

State: people.o glyph and the claim/pin icons now render as `<img>` of the snapshot SVGs, served by URL
(`/selling/people-wordmark/o.svg`, `/selling/icons/claim.svg`, `/selling/icons/pin.svg`), as the original does.
svg-extract had not landed; no path data is committed or inlined: the three files are listed in
apps/site/assets.manifest.json and build.mjs copies them byte for byte.

Changed: people.o/index.tsx + o.module.css (ring removed), people.deck/panel.tsx + deck.module.css (img sizes
7.5x7.5, 8x10.5, compact 10x13 as the original CSS), manifest, regenerated footprint golden (footprint.gen.json,
FootprintData.lean via part-footprint.mjs --write; the Lean file was not rebuilt, run lake build on it).

Verified: `pnpm test` in apps/site, 5147 pass. No browser run, no check.sh.
Open: Lean build of FootprintData; CI breakpoint pixel check of the glyph (original width .533em x .542em, kept).
