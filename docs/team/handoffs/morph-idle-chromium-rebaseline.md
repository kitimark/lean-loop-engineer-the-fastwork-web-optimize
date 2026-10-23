Branch: worktree-wf_1a1544e3-bc5-1 (CI branch ci/morph-idle-chromium-rebaseline). Worktree: .claude/worktrees/wf_1a1544e3-bc5-1
CI runs (chromium-counts, swipe-v1, runs=3, rewrite), all complete/success:
 - primary, strict same image (image_run=39914488176, image 47b1dcbe in all six shards): base 39940682332, flag 39940686591 (fw=morph.columns:idle-none)
 - supporting, separate images (sha f3248e9): base 39936881473, flag 39937184249
Verdict (MEASURED, census.layers summed over zones rest..y05000 = 545 frames, per VM shard): primary base 74368/74365/74366, flag
71036/71034/71037, delta -3332/-3331/-3329 (-4.48 %); sign kept 3 of 3; supporting delta -3331/-3330/-3325. Font-less was 28107 -> 24667 (-12.2 %).
Correction made: earlier text said 503 frames for this range; it is 545 (sums were right).
Numbers: results/morph-idle-none/chromium-font-rebaseline.json (primary + supporting). Note: research/notes/2026/10-20-morph-idle-none.md (last section).
Accepted limits: Chromium only (WebKit unresolved); cause of the larger font-image base stays INFERRED.
Open: nothing for the pinned unit. Phone and WebKit not done.
Read first: the note's last section.
