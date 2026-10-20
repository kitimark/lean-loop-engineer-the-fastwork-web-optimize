# engine-release-notes (researcher) handoff

State: branch worktree-wf_4ec44a34-b4d-1, one commit on top of d5da2beb that adds the note and this handoff. No code
or Lean changes.

Verified (details and citations in the note)
- The hero.exit:scoped freeze is open WebKit bug 325900, with the reader half in 321094. Both are NEW. Neither
  appears in any Safari note from 26.0 through 27.2 beta, and neither is fixed on main.
- The only partial fix is 320984 at 318999@main. That is above the 27.0.x branch point 316606@main, so it is not in
  our pin 862f17d or in 27.0.1.
- The 13.1 post names no accelerated properties, does not mention custom properties, and says WAAPI is synced in a
  single shared engine. The concrete answers come from the WebKit 862f17d source.
- Chrome 156 has no relevant entry. Blink's matched properties cache guards explicit inheritance
  (matched_properties_cache.cc:200-216@f842f52).
- Mechanism B (animated custom property dependents) is fixed in the pin (bugs 210963, 250448). WAAPI never writes
  attributes, so the nav bug is in our code.

Open items
- issues.chromium.org was not searched because it is script-rendered; the queries are listed in note §4.
- No WebKit blog post was found on will-change or on style invalidation, and the will-change chromestatus id is
  missing.
- The base main revision of the 27.2 beta (20625.2.8) is unknown, so re-check 325900, 321094 and 320984 at each Safari
  release.

How it was done
- Apple notes: https://developer.apple.com/tutorials/data/documentation/safari-release-notes/<slug>.json
  (DocC JSON), using the slugs from the index JSON.
- Chrome Status: https://chromestatus.com/api/v0/features?q=... (strip the `)]}'` prefix).
- Bugzilla: the REST quicksearch at /rest/bug?quicksearch=. Never copy author names or emails.
Read first: research/notes/2026/10-21-engine-release-notes.md sections Answer and 5.
