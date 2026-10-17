# snapshot-extract handoff

State: branch `worktree-agent-a9218b9a1500c50f7`, commit b5442a0 (CI branch `ci/snapshot-extract`, workflow `snapshot-extract`).
Run 1 (id 39073827202): extract jobs passed (3 per engine); the `report` job failed only because `cli.mjs` imported the
engine drivers statically (no puppeteer in that job). Fixed in b5442a0 (dynamic import). Run 2 (id 39076794756) is green:
its merged datasets are byte-identical to run 1's (the committed ones), so 6 extraction jobs per engine agree.

Read first: `docs/team/tools/snapshot-extract.md`, then `lean/Fw/Site/Reference.lean`, `packages/snapshot-extract/src/`.

Numbers (run 1 data): 1290 Chromium and 1243 WebKit stable cells over 116 environments and 47 (part, role) pairs;
Chromium quarantined 1 row (`nav.hitTest/nav/background-color`), WebKit 85 (mostly `animation-play-state`, `will-change`).
Port vs original (Chromium): 193 of 1290 cells differ (inherited-never-set 27, declared-in-ref-unset-in-port 133,
port-sets-differently 33); top properties font-family 45, line-height 28, text-align 17. WebKit: 166 of 1243.
Fonts: the original loads Google Sans and Playpen Sans Start Selling, the snapshot ships both; the port loads none (body
falls to Times New Roman). 231 keys differ between the engines on the original; `platform.stageBg` differs in value
(aspect-ratio, height, width, font-family) and in source (border radii, box-sizing, margins, max-width).

Conventions: dataset schema `fw.snapshot-extract.reference/1`; the committed form has numbers and keywords only (no selectors;
`reference-full-*` with selectors stays a CI artifact). A cell is kept only when 3 runs agree (premise id
`snapshot-extract.determinism`; it is not yet registered in the premise-tests list, so register it there).

Open items:
- Regenerating the datasets needs a CI run (artifact `snapshot-reference`), then copy `reference-{chromium,webkit}.jsonl` to
  `packages/contracts/golden/site/`; Lean `#guard`s (counts, 231 disagreements, 54 body-inherited cells) will flag changes.
  lake does not track `include_str`: touch `Reference.lean` to force a rebuild after replacing a dataset.
- TS stand-ins: the report categories (`src/report.mjs`) and the in-page cascade winner (`src/page.mjs`, `@layer` ignored,
  specificity approximate) have no Lean golden vectors yet.
- WebKit-quarantined animation cells read as `onlyChromium` in the split.
- `pnpm-lock.yaml` got one importer line for `packages/snapshot-extract`.
- fix-proofs and lean-coverage: use `Dataset.find?` on `referenceChromium`/`referenceWebkit` as the `generated` source.
