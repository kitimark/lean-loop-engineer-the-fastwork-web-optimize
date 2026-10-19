# nav-anchor-hosted handoff

State: branch worktree-wf_86652ab9-962-3, ci/nav-anchor-hosted. Only file changed: packages/gate-breakpoints/src/anchors.json (nav part, roles `bar`, `actions`).
- `bar` rewrite is now `[data-fw="nav"] > div:not([data-fw="morph-panel"])`; `actions` is `[data-fw="nav"] > div:not([data-fw="morph-panel"]) > div`.
- Why: morph.mount:shift mounts the hosted morph panel (root `<div data-fw="morph-panel">`, children backdrop/veil/center) as the last child of the nav,
  so the structural selectors counted bar 2 and actions 4 (research/notes/2026/10-19-preset-gate-triage.md row 2).
- Faithful arm: the nav's DOM (apps/site/src/parts/nav/index.tsx:128-148) has exactly one `div` child of the header (the bar) and one `div` child of the bar (actions),
  none carries data-fw="morph-panel", so the new selectors select the same elements as before (CONFIRMED by source read, not a DOM run).
- Lean: nothing reads the selector strings (Items.lean declares the shape only); no generated file embeds them. No Lean change.
- Open: CI gate result (run id in the report); PhaseFree/HiddenBefore instances for morph.panel stay a follow-up.
Read first: the triage note row 2, then anchors.json nav part.
