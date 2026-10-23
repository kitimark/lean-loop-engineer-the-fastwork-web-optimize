branch: worktree-wf_67f38c32-29a-1
worktree: .claude/worktrees/wf_67f38c32-29a-1
last commit: see git log
CI runs: none pushed (local-only lean + node tests via fw slot)

State: the footprint extractor records class names only from class-value positions.
- Rule in Lean: lean/Fw/Parts/ClassPos.lean (`classes`, one theorem per position, `cases`); golden
  packages/contracts/golden/parts/footprint.classpos.jsonl (generator lean/scripts/ClassPosGolden.lean).
- Extractor: apps/site/scripts/part-footprint.mjs `collectClassTokens` / `classChildren`; test
  apps/site/scripts/part-footprint.classpos.test.mjs replays the golden (wired into apps/site test:run).
- Helpers recognised: cx, cls, clsx, classNames (cx and cls are the ones in apps/site) and `[..].filter(Boolean).join(' ')`.
- Regenerated chain: FootprintData.lean, footprint.gen.json; FootprintRows and footprint-diff unchanged; --check green.

Removed rows (all false, comparison literals): platform/Visuals.tsx:279 setClass left (side === 'left'),
Visuals.tsx:378 setClass us (f.id === 'us'), platform/index.tsx:48 setClass secureMesh (kind === 'secureMesh').
No real class row disappeared (people.deck/people.o setModuleClass rows through the `cls` helper and the join chain are class positions).

Outside the task writes: lean/Fw.lean (import), lean/Fw/Parts/ClassPos.lean, lean/scripts/ClassPosGolden.lean,
packages/contracts/golden/parts/footprint.classpos.jsonl, apps/site/package.json (test:run).
Accepted limits: other helper names, object-form clsx({a: b}), non-literal class computation stays '?'.
