Branch: worktree-wf_1a1544e3-bc5-1 (CI branch ci/morph-idle-chromium-rebaseline). Worktree: .claude/worktrees/wf_1a1544e3-bc5-1
Last commit: see git log (started from f3248e954).
CI runs (chromium-counts, `pnpm -s fw run`, swipe-v1, runs=3, rewrite, sha f3248e9): 39936881473 base success; 39937184249 flag
(fw=morph.columns:idle-none) success. Two of at most four runs used.
Verdict (MEASURED, unit = census.layers over the 503 frames rest..y05000, per VM shard): base 74368/74365/74365, flag 71037/71035/71040,
delta -3331/-3330/-3325 (-4.5 %); sign kept in 3 of 3; font-less was 28107 -> 24667 (-3440, -12.2 %). Numbers: results/morph-idle-none/chromium-font-rebaseline.json.
Verified: base counts equal the frozen font baseline run 39916914389 (74370/74367/74365) although the image ids differ (rebuilds).
Open: strict same-image-id pair (needs image_run, `fw run` does not send it): gh workflow run chromium-counts.yml --ref ci/morph-idle-chromium-rebaseline
  -f profile=swipe-v1 -f runs=3 -f target=rewrite -f image_run=39914488176 [-f fw=morph.columns:idle-none] (one without fw, one with).
Not done: WebKit (accepted limit), phone.
Read first: research/notes/2026/10-20-morph-idle-none.md (last section).
