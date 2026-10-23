branch: worktree-wf_c886ec11-19e-1 (CI branch ci/counts-lane-fonts)
worktree: .claude/worktrees/wf_c886ec11-19e-1
last commit: 907b3195b (pushed as ci/counts-lane-fonts); pushes+dispatches used: 1 of 6
CI runs: 39900399252 chromium-counts push of 907b3195b (swipe-v1 both x3, new image): running
verified: Lean Profile.lean builds, golden regenerated and --check ok, profile.test.mjs 11 pass, ci-paths 54 pass (all local, not results)
open: image build must pass (fonts-liberation=1:1.07.4-11 line in docker/apt-manifest.txt was added by hand-sorted insertion, the Dockerfile's dpkg diff is its check); then dispatch desktop-1280 both x3, people-o-hover base and --fw people.o:preview-translate x3 on ci/counts-lane-fonts; compare swipe-v1 classes with classes.frozen.json; write research/notes/2026/10-2x-counts-lane-fonts.md; full check.sh, package tests, merge main, fw land --dry

Design (why): the lane's system fonts = one pinned Debian package fonts-liberation (the Chrome .deb's own font dependency, per the old Dockerfile comment) in one dir (docker/fonts.conf, generated text from Lean Fw.Measure.Profile.fontsConf); run.mjs refuses a container whose fc-list lacks the Lean fontsOk families and records meta.systemFonts. Rejected: page's web font ready before first layout (cannot be forced on the original page without editing it).
Dispatch form: pnpm -s fw run --target both --engines chromium --profile desktop-1280 --runs 3 --ref ci/counts-lane-fonts (people-o-hover: --target rewrite, flag --fw people.o:preview-translate)
Read first: research/notes/2026/10-2x-chrome-balance-repro.md (Platforms), packages/measure-chromium/Dockerfile.
