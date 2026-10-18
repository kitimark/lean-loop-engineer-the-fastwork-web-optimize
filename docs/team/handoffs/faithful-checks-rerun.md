# Handoff faithful-checks-rerun

State: branch worktree-wf_e6ffd6eb-9d3-4, pushed as ci/faithful-rerun. Base main 175b220c plus the 4 faithful-checks commits cherry-picked
(Wire.lean, check.sh, package.json conflicts resolved by keeping both sides).

Verdict (MEASURED, CI runs 39146329183 swipe-v1, 39146332555 swipe-touch-v1, commit b8c051ab, 3 shards per arm, Lean-decided):
R fails y04000, y04500, tail on BOTH profiles; control A'/A passes. Shape (frames, px) now equals A in every zone; the touch lane gave
data (last time none). Off-band: layout work (y04000 LayoutCount 0 vs 24), fewer rAF callbacks, compositor census. Not diagnosed.
Note: research/notes/2026/10-19-faithful-rerun.md. Files: results/faithful/{swipe-v1,swipe-touch-v1}.verdict.json, results/faithful/runs/*.

Anchor: lean/Fw/Gate/PageRoot.lean (theorems with LaTeX; lean/scripts/check.sh green) and role pageRoot of part engine.scroll in
packages/gate-breakpoints/src/anchors.json (the task named packages/gate-breakpoints/anchors.json, which does not exist).

Open items / follow-ups outside my writes:
- page.mjs does not collect scrollWidth; wire it (record next to innerWidth), parse it in Fw/Wire/Gate, and make the item
  Fw.Gate.PageRoot.pageRootItem part of the engine.scroll cell. Until then the anchor is the box width of the root.
- Files edited outside the task writes: lean/Fw.lean (import PageRoot), lean/Fw/Faithful/Measured.lean (regenerated),
  lean/Fw/Wire.lean, lean/scripts/check.sh, lean/scripts/FaithfulGolden.lean, packages/measure-chromium/{package.json,src/faithful.mjs,
  test/faithful.test.mjs}, packages/contracts/golden/faithful/ (from faithful-checks; land --allow).
- Diagnose the layout and rAF differences (wave 1 input), then re-run: pnpm fw ci <id> --branch ci/<b> --store <dir>;
  zone-baseline.mjs --store <dir> --target original|rewrite --profile p --run <id> --out results/faithful/runs; zone-baseline.mjs baseline ...;
  node packages/measure-chromium/src/faithful.mjs verdict; ... lean.
- Local: pnpm install --offline --frozen-lockfile first; after a bare lake build run lake build fwcore (the binary can vanish, fw ci wait then fails).

Read first: the note, then results/faithful/swipe-v1.verdict.json (verdict.zones[].offBand), then lean/Fw/Gate/PageRoot.lean.
