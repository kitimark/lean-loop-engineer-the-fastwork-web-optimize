# site-assets handoff

State: branch worktree-wf_664fab74-06b-1, one commit (see git log). Task: one source for every snapshot file the site serves.

- `apps/site/assets.manifest.json`: `files` [{url, src}] (84: 5 fonts, hero/*, platform network/*, the 45 /selling/ URLs
  that main and the three content branches write) and `bundled` (globs a Vite import.meta.glob bundles, reads only).
- `apps/site/scripts/build.mjs`: copies each `files` entry byte for byte to dist/<engine>/<url>; a missing source fails the
  build with the url and src. Replaces the hard-coded font copies.
- `apps/runner/src/land.ts`: `siteAssetReads()` derives apps/site's extra reads from the manifest.
- Tests: `node --test apps/site/scripts/assets.test.mjs` (every listed file exists; every /selling/ and /fonts/ URL in
  apps/site/src is listed); land-inputs.test.ts checks listed <=> declared read.

Verified locally: assets.test.mjs 2/2, apps/site tsc, aot build (dist copies equal snapshot bytes). Build is
Vite-neutral: CSS url(/selling/...) still warns "didn't resolve at build time" (pre-existing, served from dist).

Open: gate evidence is CI run on ci/site-assets (ids in the report). assets.test.mjs is not in the vitest include
(apps/site/vitest.config.ts is outside this task's files); add `scripts/**/*.test.mjs` or a package script later.
Hero template URLs (`${id}-cover.jpg`) are covered by listing all of hero/*; a new template URL needs a manifest entry
by hand (test cannot see computed URLs). Limit: hand-written allowlist, Lean Fw.Site.Assets later. After merge, the
content lanes rebase on this and keep their `/selling/...` URLs.
