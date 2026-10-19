# preview-speed handoff (round 1)

State: branch worktree-wf_72edc914-a26-1. Lean `Fw.Console.PreviewCache`: `kind names path` decided by identity. hashed iff under
`/_app/immutable/`, OR listed in the rewrite build's `.vite/manifest.json` (`file`/`css`/`assets`, each `/<name>`; op input
`manifest`), OR `/mui.<sha8>.css` (apps/site/scripts/build.mjs:106). `.html` is always html; everything else no-cache + strong ETag.
The hashed-name heuristic (hashedStem/randomLooking) is gone from Lean and the TS stand-in.
Theorems: one per arm (`immutable_dir_hashed`, `manifest_name_hashed`, `mui_name_hashed`), `hashed_is_identified` (nothing else is
hashed), `hashed_serves_same_bytes` (non-vacuous: kind over manifest M, both builds ManifestFaithful + NameAddressed, hash/name
injective => same bytes), `unclassified_no_cache`, `reuse_only_hashed`, `html_no_cache`, `unhashed_revalidates`, `contains_names`.
Modelling assumption, INFERRED: sha256 hash and the name function are collision-free (`hinj`, `ninj`, `changed_bytes_new_etag`).
Golden rows incl. Roboto-SemiBold.woff2, og-1200x630.png, icon-darkMode.svg -> other.

TS stand-ins (checked against the golden by test/preview-speed.test.ts): `cache-policy.ts` kind/cachePolicy/manifestNames;
serve-child.ts reads `<rewrite root>/.vite/manifest.json` (re-read on mtime/ctime/size/ino change). Large files (> 4 MB) hash the
bytes actually sent (no cached ETag). console-api 400 tests green, ci-paths 32, runner land-inputs 40 (needs no apps/site/dist
in the tree). Harness: `apps/console-api/scripts/preview-bench.mjs`.

MEASURED (this Mac, headless Chrome, CDP Network.emulateNetworkConditions 20 Mbit/s, 20 ms RTT, fresh profile, 1280x800, loopback
through mountPreviewProxy over serve-child spawned by defaultHooks(...).serve; r = apps/site/dist/aot built from this tree,
o = snapshot/site; load event, bytes = CDP encodedDataLength; before = main's src/preview, after = this branch):

| arm, load | before: ms / req / KB | after: ms / req / KB |
|---|---|---|
| r first | 2424 / 52 / 5735 | 2134 / 52 / 4843 |
| r reload | 2404 / 52 / 5735 | 146 / 52 / 5.8 (24 x 304, 26 from cache, 2 x 200) |
| o first | 2166 / 59 / 5141 | 1950 / 59 / 4425 |
| o reload | 2278 / 59 / 5141 | 230 / 59 / 8.8 (37 x 304, 19 from cache, 3 x 200) |

Non-304 reload responses after: r: `/preview/bench/r/` (258 B, headers only: INFERRED Chrome reports the revalidated document as 200),
`/preview/bench/r/favicon.svg` (269 B, same); o: the same two plus `/preview/bench/o/analytics.js` (193 B, the no-store analytics stub,
a true 200 with an empty body). Single run per cell, no repeats; not a CI result.

Open items / accepted limits: no CDN or HTTP/2; images and fonts stay as the original ships them (format change is avif-picture after
C3); no real-phone run; bench skips the gate and the manager's build step (manager-shaped stub, as test/preview-speed.test.ts);
first load shrinks ~12 % only (images, fonts already compressed); only manifest or _app/immutable or mui names are immutable, so
unlisted content-hashed names revalidate (a 304 each) rather than risk stale bytes.
Read first: cache-policy.ts, then serve-child.ts serveFile/manifestReader, then PreviewCache.lean.
