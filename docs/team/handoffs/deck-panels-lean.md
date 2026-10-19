# deck-panels-lean handoff (fix round 1)

State: branch worktree-wf_f0e4209d-fe6-3, fix-round commit on top of c9b3a6cc.

Done
- filled_five docstring states the three point evaluations; dropped the unproved "all is first" and "comes first" prose.
- Services meta at <=1030/touch: 12px/16px added. Logo: monogram only when logo is undefined; named-missing file gives an empty logo box; img draggable=false.
- mq.w-le-480 in MEDIA_IDS, Scope.lean people.deck rewrite list (+docstring), scope.gen.json regenerated; media.test.ts reads deck and panels CSS.
- initials test compares Lean ASCII spec with the unicode rule over every about name.
- Port-audit items in people.deck: article cards (cover, avatar+name byline, clock + "N min read", title, excerpt), photo price badge, video play badge, audio mute icon, rail rating star; Post data carries price/video/title/excerpt/readMinutes (restated from the original). Mobile (<=1030/touch) variants restated.
- footprint.gen.json and FootprintData.lean regenerated (new icons.tsx).

Verified: apps/site tests 80 files / 5282, typecheck, lake build of PeopleDeckPanels, Gate.Scope, FootprintData, scope --check, ci-paths 32/32.
Known: apps/runner land-inputs 2 failures also on main.

TS stand-ins: icons.tsx draws star, clock, play, mute geometry itself (original elements, sizes, viewBoxes); replace with svg-extract's svg.gen.json when it lands. Pixel equality is for the gate run.
