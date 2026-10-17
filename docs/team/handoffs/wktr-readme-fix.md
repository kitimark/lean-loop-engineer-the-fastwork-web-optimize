# wktr-readme-fix handoff

State: READMEs of `packages/measure-wktr` and `packages/measure-webkit` corrected (see the branch commit).

What changed
- measure-webkit "Feasibility" no longer says "There is no prebuilt". It says a prebuilt iOS-Simulator
  WebKitTestRunner exists (WebKit CI bucket `minified-archives.webkit.org`; `steps.py:58-59,485-491`,
  `config.json:425`, `download-built-product:54`, all @862f17d) and that the `wktr` lane gets it via
  `packages/measure-wktr/src/archive.json` + `scripts/fetch-archive.sh` + `.github/workflows/wktr.yml`. The old
  "run the spike on a cloud Mac / 120 GB" recommendation is marked superseded.
- `UIHelper.renderingUpdate()` is a rAF then `setTimeout(0)`, not one rendering update:
  `LayoutTests/resources/ui-helper.js:182-191` and `:554-557@862f17d` (CONFIRMED). Fixed in both READMEs.
- measure-wktr "Why the counts drift" said the gate is rendering updates and layer flushes "only"; the frozen file also
  tags `styleInvalidations` under `vt` (stable) as `role: gate`. Text now matches `classes.frozen.json`
  (3 gate types, 6 finding types; runs 39054209180, 39058900156, 39061993891). The lane stays a findings lane.

Checked, no change needed: the results table in the measure-wktr README equals `classes.frozen.json` (live 2 det + 7 quar;
vt 2 det + 1 stable + 6 quar; k/t values).

Open items
- `research/notes/2026/10-17-wktr-on-github-actions.md` quotes `steps.py:476-492` and `:57-59`; actual lines at
  862f17d are 485-491 and 58-59 (not edited here, outside the task).
- PLAN.md, work-graph and other docs may still carry the old "no prebuilt" wording; not searched outside the two READMEs.

Read first: the two READMEs' changed sections; pinned clone `.cache/upstream/WebKit@862f17d` (paths
`LayoutTests/resources`, `Tools/CISupport`).
