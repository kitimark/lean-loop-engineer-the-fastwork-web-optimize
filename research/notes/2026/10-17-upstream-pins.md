---
id: 2026-10-17-upstream-pins
kind: note
title: "Upstream pins after the verifier fixes: 8 entries, one tag per published package"
status: review
created: 2026-10-17
topics: [upstream, chromium, webkit, lean, mui, emotion, react, serena, tooling]
---

Lock: `refs/upstream/sources.lock.yaml`; per-pin evidence: `refs/upstream/PINS.md`. Every HEAD in `.cache/upstream/` equals its lock sha (`git rev-parse HEAD`, 2026-10-17, MEASURED).

| id | tag | sha7 | verified by | status |
|---|---|---|---|---|
| chromium | `156.0.8078.4` | f842f52 | `chrome/VERSION` l.1-4 = Dockerfile `HS_VERSION` | CONFIRMED |
| webkit | `WebKit-7625.1.29.10.29` | 862f17d | `Version.xcconfig` l.24-28, l.54, l.57 vs Simulator framework 8625.1.29.10.29 | CONFIRMED |
| lean4 | `v4.35.0` | eb6cafb | `src/CMakeLists.txt` l.10-13 | CONFIRMED |
| mui | `v9.5.0` | 1c3f8b4 | 5 `package.json` l.3 = 9.5.0 (now incl. private-theming) | CONFIRMED |
| emotion | `@emotion/styled@11.14.1` | 4922955 | per-package diff vs own tags: react, cache, sheet, use-insertion-effect-with-fallbacks `src/` identical | CONFIRMED |
| emotion-server | `@emotion/server@11.11.0` | 1135f8e | own tag; 23 files differ from 4922955 | CONFIRMED |
| emotion-serialize | `@emotion/serialize@1.3.3` (= `@emotion/utils@1.4.2`) | c161e6f | own tags; `src/index.ts` of both differs from 4922955 | CONFIRMED |
| react | `v19.3.1` | 61aa00d | `package.json`, `ReactVersion.js` = 19.3.1 | CONFIRMED |

Not pinned: the phone (iOS 27.0.1). It is probably a `WebKit-7625.1.29.1[1-8].y` tag (INFERRED); the 11.x series stops at 11.27, so the macOS host build 11.28 is unpublished (`git ls-remote --tags`, MEASURED).

**Emotion lesson.** Changesets publishes each package separately, so the one tag `@emotion/styled@11.14.1` matching every lockfile *version* did not prove the *source*: `server`, `serialize` and `utils` changed `src/` after their last release with no bump. The old "same version implies same source" (INFERRED) was false.

**Adding a pin.** (1) Version from `pnpm-lock.yaml`, a Dockerfile or the runtime. (2) `git ls-remote <url> 'refs/tags/<tag>^{}'`; in a monorepo use each package's own `<pkg>@<v>` tag, and `git diff --name-status <a> <b> -- packages/<p>` against any other pin of that repo. (3) Lock entry: id, tag, version, 40-hex sha, paths (shared repo: dir `<id>@<sha7>`). (4) `node scripts/refs-fetch.mjs <id>`; check HEAD = sha and a version file in the tree. (5) PINS.md row; `node scripts/serena-upstream.mjs`.

## What this changes in the plan
- **§7.1 `refs/upstream/`:** sources.lock.yaml holds one entry per published package source, not one per repo.
- **§7.2 example `builds`:** `webkit:7624/ios` and `chromium:155.0.8059.80` are stale. Use `webkit:8625.1.29.10.29/ios` and `chromium:156.0.8078.4` (lead to edit).
- **docs/team/serena.md / `scripts/serena-upstream.mjs`:** `languageOf` has no entry for `emotion-server` or `emotion-serialize`, so neither gets a project. Also, `serena project health-check` adds every clone it checks to `~/.serena/serena_config.yml` `projects:`.
