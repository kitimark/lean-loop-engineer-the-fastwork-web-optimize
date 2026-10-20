# webkit-lag-source (researcher) handoff

State: branch worktree-wf_7a7ac477-cb3-1. One commit adds the note and this handoff. Note-only task: no package or Lean changes, so the package tests and lean/scripts/check.sh were not run.

What exists
- `research/notes/2026/10-20-webkit-lag-source.md`:
  - per-region cost tables (hero exit; end-of-page morph) and a Q1-Q5 mechanism table;
  - the predicted dominant cost per region;
  - candidates C1-C6;
  - 8 cost terms missing from `Fw.Engine.WebKit`.

Verified (CONFIRMED from WebKit source at 862f17d; citations are in the note)
- When a filter runs as a CA filter versus a painted filter. A blur-radius change is a Layout diff.
- backdrop-filter is always composited (CABackdropLayer).
- A size change re-creates and fully repaints the backing store. A scale change does not re-rasterize.
- A non-passive window `wheel` listener makes Mac wheel scrolling synchronous (50 ms wait at gesture start).
- iOS touchmove can prevent scrolling only until the pan starts.

Open
- All GPU and render-server costs are INFERRED (closed source). webkit-lag-probe should measure them (counters are listed under "What this changes in the plan").
- The `ENABLE(REMOTE_LAYER_TREE_ON_MAC_BY_DEFAULT)` value was not read.
- The panel and cue compositing reasons are inferred from CSS. A WKTR layer dump would confirm them.

Conventions
- Citations use `WC/`, `WK/`, `WTF/` at WebKit 862f17dcae0a. Fetch extra files with curl from raw.githubusercontent at that sha.

Read first
- Read the note's Answer and both region tables, then research/notes/2026/10-18-engine-webkit-pipeline.md §1-§4.
