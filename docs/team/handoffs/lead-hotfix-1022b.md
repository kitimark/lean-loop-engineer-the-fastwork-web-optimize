# lead-hotfix-1022b

- State: restores the resume-runner text `--dry (no --allow)` that scripts/build-review.test.mjs:59 asserts (lead-hotfix-1022 changed
  it; lean run 39770576911 failed), keeps the branch from git rev-parse, and asserts that in the test (9/9 pass).
- Open: the land does not run the script tests (task land-script-tests, incident inc-land-misses-script-tests).
- Read first: .claude/workflows/build-review.js resumed(), scripts/build-review.test.mjs.
