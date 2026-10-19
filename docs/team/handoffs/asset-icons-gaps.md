# asset-icons-gaps handoff

State: committed d026f514 on branch worktree-wf_ded5198b-b6e-3 (round 1 fix on top).

Done
- assets.manifest.json: added why-bring divider/reputation/payment/folder .svg and samples/docs/lawyer/lawyer-consult-cover.png (src snapshot/site/<url>).
- overlays.drawer: icons and divider are <img> of the original URLs (no more 1x1 GIF).
- platform: profile pin is <img src=/selling/icons/pin.svg> (was GenSvg platform.pin; that art id is now unused by the part). The lawyer png was already the thumb src; it is now served.
- platform .ask::after: the original's is-drawn feTurbulence rule (opacity .18, z-index 1) restated, then the is-figma-bg override (grain.png, overlay .55), so the cascade equals the original. Only the search visual carries is-drawn in the original.

Verified: apps/site test and typecheck (the svg-extract file-scan test is timing-flaky at 5 s under load; passes alone).
Outside writes (generated, via part-footprint --write): packages/contracts/golden/parts/footprint.gen.json, lean/Fw/Parts/FootprintData.lean.
Open: pixel equality by the gate; AVIF picture deferred. ci-paths (32/32) and apps/runner test/land-inputs.test.ts (40/40) pass. Round 1 added render tests overlays.drawer/assets.test.ts and platform/assets.test.ts. Lead: add footprint.gen.json and FootprintData.lean to this task writes; svg-extract owner drops platform.pin.
