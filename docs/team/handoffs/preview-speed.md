# preview-speed handoff

State: branch worktree-wf_72edc914-a26-1. Lean `Fw.Console.PreviewCache` (kind, cacheControl, compressible; theorems
reuse_only_hashed, html_no_cache, unhashed_revalidates, changed_bytes_new_etag, hashed_url_pins_bytes), op `console.previewCache`,
golden `packages/contracts/golden/console/console.previewCache.jsonl`. `sh lean/scripts/check.sh` green.

Code (apps/console-api/src/preview): `cache-policy.ts` (TS STAND-IN of the Lean kind/cacheControl/compressible, checked
against the golden; ETag, Accept-Encoding, compression); `serve-child.ts` (ETag, 304, br/gzip precompressed once per file,
cache key mtime+ctime+size+ino, policy read from the file's path below its root, keep-alive 65 s); `proxy.ts` (node http
upstream, forwards Accept-Encoding and If-None-Match, passes cache headers through; html/css rewritten once per
(id, arm, path, query, upstream ETag), own strong ETag, compressed once; compare and 404 stay no-store from upstream).
Tests: `test/preview-speed.test.ts` (31: golden, 304, compression, rebuilt file never stale, proxy), `test/preview.test.ts`
line 203 now expects no-cache. console-api 393 tests green, ci-paths 32, runner land-inputs 40.

MEASURED (this Mac, loopback, snapshot/site as both arms, crawl of html + linked assets + css url(); 103 requests;
modeled time = bytes at 20 Mbit/s + ceil(requests/6) x 20 ms, not a real throttle; harness not committed):

| load | before: req / KB / modeled ms | after: req / KB / modeled ms |
|---|---|---|
| first, r and o | 103 / 9072 / 4076 | 103 / 8336 / 3775 |
| reload, r and o | 103 / 9072 / 4076 | 85 (82 x 304, 18 from cache) / 18.1 / 307 |

Reload bytes fall 99.8 percent, modeled time 93 percent. First load shrinks only 8 percent: the snapshot holds 1.45 MB of
text, the rest is fonts and images already compressed (follow-up: image formats, not cache policy).

Open items / accepted limits: no CDN or HTTP/2 (6 parallel connections remain); unhashed images and fonts still cost a 304 round
trip each on reload (82); a hash containing `-` or a name that looks like a word is treated unhashed (safe side); rewritten
immutable css would stay in the browser if rewrite.ts changed (ids are unique per preview). Real-phone numbers not taken.
Read first: cache-policy.ts, then serve-child.ts serveFile, proxy.ts rewriteLane branch.
