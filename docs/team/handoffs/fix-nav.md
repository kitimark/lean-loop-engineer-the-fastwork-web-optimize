# Handoff: fix-nav
Base: branch reset to ci/integrate-ports head 30734ae (a merge conflicted with newer main files; not merged).
- Cause (port wrong): the original's body sets colour #171717 and font-family (--font-family-body, assets/0.ChGpbVhU.css:176,512-524); our site has no body rule, so nav border colours (currentColor) were black and `font: inherit` buttons (earn, lang switch) fell back to the UA font. Fix: color and font-family on `.nav` in apps/site/src/parts/nav/nav.module.css. No @font-face exists in our site, so computed font-family matches but glyphs fall through (shared, outside nav).
- Left: WebKit phone-rotation#3@932x430 nav width 879.97 vs 884 (also bg oklab, transform): our width transition (0.68s) is 99% done when sampled; likely settle timing, not CSS. Check on the gate result.
- A shared fix would be a body rule (color, font-family) in reset.css / Root; not done (not my file).
