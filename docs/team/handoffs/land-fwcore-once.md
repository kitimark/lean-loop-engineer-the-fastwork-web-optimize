# land-fwcore-once handoff

State: closed as a negative finding (branch worktree-wf_cb00fee1-49e-1, see tip commit). Shipped behaviour reverted to main (land.yml, LandLegs, land-remote.ts,
LakeJobsGen, Wire/Console, land-legs golden, land-legs test). Kept: `lean/Fw/Ops/WallTime.lean` (+ import in Fw.lean), the note, one line each in land.md and gate-speed.md.
Verified: `sh lean/scripts/check.sh` and the apps/runner tests, see the report.
Open: none. Probe branches stay on origin as evidence; the earlier prep-job design is in git history (commits cdb74d22, 05940801).
Read first: research/notes/2026/10-20-land-fwcore-once.md.
