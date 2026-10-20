# engine-release-notes (researcher) handoff

State: branch worktree-wf_4ec44a34-b4d-1. Round 1 at 116b8529; round 2 (this commit) applies the 7 r1 findings. No
code or Lean changes.

Verified (details and citations in the note)
- The hero.exit:scoped freeze is open WebKit bug 325900, with the reader half in 321094. Both are NEW. Neither bug id
  nor its radar (189482288, 184130578; 320984 is 184017733) appears in any Safari note from 26.0 through 27.2 beta.
- The only partial fix is 320984 at 318999@main, above the 27.0.x branch point 316606@main, so not in pin 862f17d.
- Chromium passes per the 325900 report (150, 154; Firefox 156). Pin 156 is untested, INFERRED to pass via
  matched_properties_cache.cc:200-216@f842f52.
- Chromium tracker searched through its JSON endpoint (note §4 table): no open issue matches Mechanism A or B.
- Mechanism B: 26 open WebKit titles reviewed; one candidate, 293727 (rdar 152630876, Safari 18.x, NEW), relevance
  OPEN. WAAPI's update path writes only computed style (KeyframeEffect.cpp:1644-1668,1842-1934@862f17d); the only
  attribute write is commitStyles (WebAnimation.cpp:1912), which the site never calls.

Open items
- 293727: check whether our reader writes match its trigger (the §5 trajectory probe would show it).
- No WebKit blog post on will-change or style invalidation; the will-change chromestatus id is missing.
- The 27.2 beta (20625.2.8) base revision is unknown; re-check 325900, 321094, 320984 at each Safari release.

How it was done
- Apple notes: https://developer.apple.com/tutorials/data/documentation/safari-release-notes/<slug>.json; grep ids
  and radars, positive control 158919736.
- Chrome Status: https://chromestatus.com/api/v0/features?q=... (strip `)]}'`).
- Bugzilla: /rest/bug?quicksearch=...&include_fields=id,summary,status.
- Chromium tracker: POST https://issues.chromium.org/action/issues/list, body
  [null,null,null,null,null,["157"],["<query>",null,<n>]]; strip `)]}'`; status at issue[2][2]. Use title: and
  status:open, plain words match comments. Never copy reporter/owner emails or names.
Read first: research/notes/2026/10-21-engine-release-notes.md sections Answer and 4.
