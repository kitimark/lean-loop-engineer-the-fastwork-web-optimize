---
id: 2026-10-17-upstream-pins
kind: ref
title: "Upstream pins: engine and library version to tag to commit"
status: draft
created: 2026-10-17
topics: [upstream, chromium, webkit, lean, mui, tooling]
builds: ["chromium:156.0.8078.4", "webkit:8625.1.29.10.29/ios", "lean:v4.35.0", "npm:@mui/material@9.5.0", "npm:@emotion/react@11.14.0", "npm:@emotion/server@11.11.0", "npm:@emotion/serialize@1.3.3", "npm:react@19.3.1"]
---

# Upstream pins

Source of truth: `refs/upstream/sources.lock.yaml`. Fetch with `node scripts/refs-fetch.mjs [<id>] [--paths a,b]`;
checkouts land in `.cache/upstream/<name>@<sha7>/` (gitignored by `.gitignore` l.11 `.cache/`, CONFIRMED with
`git check-ignore -v`). Tags were resolved with `git ls-remote` (annotated tags peeled with `^{}`); every pin was
then checked inside the fetched tree.

| Engine / library | Browser or package version we run | Upstream tag | Commit (sha) | How verified | Status |
|---|---|---|---|---|---|
| Chromium (Blink, cc, viz) | Chrome Headless Shell 156.0.8078.4 (playwright-core 1.64.1, build v1248), counts lane | `chromium/chromium` `156.0.8078.4` (lightweight) | `f842f52ef39fd97b449eb27cff414bf05a98ddce` | Version from `packages/measure-chromium/Dockerfile` (`ARG HS_VERSION=156.0.8078.4`); `chrome/VERSION` at the sha reads MAJOR=156 MINOR=0 BUILD=8078 PATCH=4 (l.1-4) | CONFIRMED |
| WebKit (iOS) | iOS 27.0 (24A434) Simulator runtime: `WebKit.framework` CFBundleVersion `8625.1.29.10.29`, MobileSafari `8625.1.29.10.29`; page UA `Version/27.0` | `WebKit/WebKit` `WebKit-7625.1.29.10.29` (annotated; tag object `0b63a302a4ad`) | `862f17dcae0aace47ea0ec16e209d960abfd553c` | `Configurations/Version.xcconfig` at the sha: l.24-28 give 625.1.29.10.29, l.54 `SYSTEM_VERSION_PREFIX[sdk=iphone*] = 8`, l.57 bundle version = prefix + full version, so 8625.1.29.10.29 is exactly this source version; framework version read with `defaults read <RuntimeRoot>/System/Library/Frameworks/WebKit.framework/Info.plist CFBundleVersion` (MEASURED) | CONFIRMED |
| WebKit (phone) | iOS 27.0.1 on the phone (Safari 27) | not pinned | n/a | Not read from the device. Its build is probably a `7625.1.29.1[1-8].y` tag of the same branch (INFERRED; the macOS 27.0.1 host ships 22625.1.29.11.28). `git ls-remote --tags` (2026-10-17): the newest tag in the 7625.1.29.11.x series is 11.27; 11.28 is not published (the branch's newest is 18.27; series present: 10, 11, 12, 13, 14, 18) | INFERRED |
| WebKit (macOS host) | Safari 27.0.1, `WebKit.framework` 22625.1.29.11.28 (prefix 22 = macOS 27, Version.xcconfig l.49) | none (11.28 absent from `git ls-remote --tags`) | n/a | MEASURED (`defaults read`); not pinned, not used by any lane | MEASURED |
| Lean 4 | `leanprover/lean4:v4.35.0` (`lean/lean-toolchain`) | `leanprover/lean4` `v4.35.0` (lightweight) | `eb6cafb7290e8bd5f2937522d8d804f58f02bafc` | `src/CMakeLists.txt` l.10-13 at the sha: 4.35.0, `LEAN_VERSION_IS_RELEASE 1` | CONFIRMED |
| MUI | `@mui/material`, `@mui/system`, `@mui/styled-engine`, `@mui/utils`, `@mui/private-theming` 9.5.0 (`pnpm-lock.yaml`, `apps/site/package.json`) | `mui/material-ui` `v9.5.0` (annotated; tag object `d4366b2c20b6`) | `1c3f8b4903f21cfad12c102edb3db4ceba2e8c8c` | `packages/mui-{material,system,styled-engine,utils,private-theming}/package.json` at the sha all read `"version": "9.5.0"` (l.3) | CONFIRMED |
| Emotion (main) | react 11.14.0, cache 11.14.0, styled 11.14.1, sheet 1.4.0, use-insertion-effect-with-fallbacks 1.2.0 (`pnpm-lock.yaml`) | `emotion-js/emotion` `@emotion/styled@11.14.1` (annotated; tag object `eddd85ca7b9f`) | `49229553967b6050c92d9602eb577bdc48167e91` | Per-package tag check: each `@emotion/<p>@<v>` tag peeled with `git ls-remote`, then `git diff --name-status <tag commit> 4922955 -- packages/<p>`. styled: same commit. cache, use-insertion-effect-with-fallbacks (tag `3c19ce5997f7`): 0 files differ. react (`3c19ce5997f7`): only `package.json` (devDependency `@emotion/styled` 11.14.0 to 11.14.1). sheet (`70ad1d33892`): only `__tests__/index.js` and `types/index.d.ts`. So `src/` is identical to the published tag for all five | CONFIRMED |
| Emotion server | `@emotion/server` 11.11.0 | `@emotion/server@11.11.0` (annotated; tag object `829dce1ee068`) | `1135f8e9d97ea711eb483368313afdfe7b176845` | Same check against 4922955: 23 files in `packages/server` differ (all of `src/create-instance/*`, new `src/conditions/`), so it needs its own pin; `package.json` l.3 at the sha reads 11.11.0 | CONFIRMED |
| Emotion serialize, utils | `@emotion/serialize` 1.3.3, `@emotion/utils` 1.4.2 | `@emotion/serialize@1.3.3` and `@emotion/utils@1.4.2` (tag objects `2aab30e40c7c`, `b848b4be4cc7`) both peel to one commit | `c161e6f2f85977c27cc4a258d4efb0504a3b77b1` | Against 4922955: `serialize/src/index.ts`, `serialize/types/index.d.ts` and `utils/src/index.ts` differ; `package.json` l.3 reads 1.3.3 and 1.4.2 | CONFIRMED |
| React | `react`, `react-dom` 19.3.1 (`pnpm-lock.yaml`) | `facebook/react` `v19.3.1` (lightweight) | `61aa00df822d0eb76d0362eb8b6fdd3527693efe` | `packages/react/package.json` l.7 and `packages/react-dom/package.json` l.3 read 19.3.1; `packages/shared/ReactVersion.js` exports `'19.3.1'` | CONFIRMED |

Monorepo rule (from the Emotion check): one tag per repo is not enough when the repo publishes packages
independently. For every package we run, peel its own `<pkg>@<version>` tag and diff `packages/<p>` against the
pin; a package whose `src/` differs gets its own lock entry (`emotion-server`, `emotion-serialize`).

## Sparse checkout sizes (MEASURED, 2026-10-17, `git fetch --depth 1 --filter=blob:none`)

| Entry | Dir | Size on disk (.git) | Wall time, first fetch |
|---|---|---|---|
| chromium | `chromium@f842f52` | 144 MB (107 MB) | 56 s |
| webkit | `WebKit@862f17d` | 126 MB (99 MB) | 103 s |
| lean4 | `lean4@eb6cafb` | 5.6 MB | 34 s |
| mui | `material-ui@1c3f8b4` | 18 MB | 20 s |
| emotion | `emotion@4922955` | 1.6 MB (sparse set pruned to its 5 packages) | 16 s |
| emotion-server | `emotion-server@1135f8e` | 1.2 MB | not timed |
| emotion-serialize | `emotion-serialize@c161e6f` | 0.4 MB | not timed |
| react | `react@61aa00d` | 15 MB | 19 s |
| total | `.cache/upstream` | 292 MB | |

Most of the Chromium and WebKit `.git` is the one-commit tree set (all trees, no blobs). A re-run at the pinned sha
only updates the sparse set (about 0.1 s when nothing changes).

## What this changes in the plan

- **§7.1 Tree, `refs/upstream/`:** add `scripts/refs-fetch.mjs` next to `sources.lock.yaml` and `PINS.md`;
  `.cache/upstream/<name>@<sha7>/` is the only place upstream source is read from.
- **§7.2 `builds`:** the example `webkit:7624/ios` and `chromium:155.0.8059.80` are stale; the lanes run
  `webkit:8625.1.29.10.29/ios` (Simulator iOS 27.0) and `chromium:156.0.8078.4`. The phone build (iOS 27.0.1) still
  needs reading off the device before V-b compares Simulator and phone.
