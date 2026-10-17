# snapshot/

`site/` is a mirror of the compiled public site at https://fastwork.com/ (SvelteKit build `1789284481295`, built
2026-09-13; last crawl 2026-09-30). It is kept byte-for-byte unmodified: it is the frozen baseline that the
measurements and the breakpoint gate compare the rewrite against.

Fastwork has approved publishing a copy of its compiled homepage, including fonts, in this repository.
The files remain under Fastwork's terms; the repository's MIT license does not cover this directory.

## Integrity

`../snapshot.lock.json` pins the snapshot. Its method: the git tree id of `snapshot/site` (a tree id hashes every byte
below it), with these files excluded as volatile scratch (they are in `.gitignore`): `.mirror/missing-local.txt`,
`.mirror/chrome-profile/`, `.DS_Store`. Check it with:

```sh
git write-tree --prefix=snapshot/site/    # after git add snapshot/site; expect c15a27be5676fe08bee1fed9ed99e1b9d903c80c
```

The snapshot id is `b<build>-<first 8 hex of sha256("site <tree>\nsite-pretty <tree>\n")>`. A prettier-formatted copy
(`site-pretty/`) was used for reading only; it is derived, not tracked, and no harness reads it.
