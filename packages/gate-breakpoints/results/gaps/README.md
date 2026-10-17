# Gaps lane results (CI artifacts only)

Copied unmodified from the `gaps-judged` artifact of the `gate-gaps` workflow (`.github/workflows/gate-gaps.yml`), branch
`ci/gap-harness`. Nothing here comes from a local run. Every verdict is Lean's (`fwcore`).

| dir | source run | repeats |
|---|---|---|
| `linux/` (Chromium 156.0.8078.4, Playwright WebKit GLib) | 39044573514, job `collect-linux (r1)` | `gaps.json` byte-identical across `r1` and `r2` of run 39044573514 and `r1` of run 39040510729 (compared with `cmp`) |
| `macos/` (Playwright WebKit Apple, WKWebView, iPhone and iPad Simulator iOS 27.0) | 39044573514, job `collect-macos (m1)` | run 39042512691 gave the same iPhone rows (iPad variants were cut by the arm time budget there); run 39041179813 had both Simulator arms timed out (before the CI timing fix) |
