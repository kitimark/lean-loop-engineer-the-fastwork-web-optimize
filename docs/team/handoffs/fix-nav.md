# Handoff: fix-nav
Branch worktree-agent-a7058ba8f6c56fcfb (CI ref ci/fix-nav), reset to ci/integrate-ports head 30734ae (a merge conflicted with newer main files, so not merged). Commit b8c380c.
Gate run 39071220949 (parts nav, nav.hitTest, nav.langMenu): merged summary 0 failures in chromium and WebKit.

Fix (apps/site/src/parts/nav/nav.module.css, `.nav`): two declarations, `color` and `font-family`. Cause: the original sets them on `body`; our site has no body rule, so they did not reach the nav.

| cell | property | original value | snapshot source | port's old value | cause class | formula |
|---|---|---|---|---|---|---|
| nav, nav.hitTest, role nav | border-{top,right,bottom,left}-color (border width 0, colour = currentColor) | rgb(23, 23, 23) = #171717 | snapshot/site-pretty/_app/immutable/assets/0.ChGpbVhU.css `body { color: var(--color-text-primary) }` (l.512-524); `--color-text-primary: #171717` light scheme (l.54) | black (UA default colour) | port wrong: inherited property missing (global body rule not ported) | constant, no viewport dependence |
| nav, role earn (button, `font: inherit`) | font-family | "Google Sans", -apple-system, BlinkMacSystemFont, "Avenir Next", Avenir, "Segoe UI", "Helvetica Neue", "Adwaita Sans", Cantarell, Ubuntu, Roboto, Noto, Helvetica, Arial, sans-serif | 0.ChGpbVhU.css `--font-family-body` (l.174-176), applied by `body { font-family: var(--font-family-body) }` (l.517) | UA button font (Chromium "Times New Roman" on the button, WebKit -webkit-standard) | port wrong: same inherited-property gap | constant |
| nav.langMenu, role switch (button, `font: inherit`) | font-family | same stack as above | same | same | same | constant |
| nav and nav.hitTest, WebKit phone-rotation#3@932x430 | width 884 vs 879.97 (also transform, background-color mid-transition) | 884px = min(984px, 100vw - 48px) at 932 | nav.module.css `--hero-pill-w` | 879.97 | not reproduced in run 39071220949 (0 failures): a WebKit settle-timing sample (width transition 0.68s sampled at 99%), not a CSS difference | width = min(984, vw - 48) |

Notes
- The shared root cause is a missing global body rule (color #171717, font-family stack, plus font-size/line-height/-webkit-font-smoothing in the same rule). Other parts restate it locally (commission, pain). A single body rule in reset.css would serve all; not done (not my file).
- No @font-face for Google Sans exists in our site (snapshot has google-sans-latin*.woff2 under assets/): computed font-family matches, glyphs fall through to the next stack entry. The gate reads computed strings, so it does not see this.
- Local node_modules were absent in this worktree (wt-prep skipped), so no vitest run; the change is CSS only.
