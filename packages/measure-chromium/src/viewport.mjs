// Container-side twin of Lean Fw.Measure.Viewport.viewportFaithful (no Lean in the container). Checked against the
// measure.viewport goldens in test/fwcore.test.mjs. Holds the rule only: the caller refuses the run.
export function viewportFaithful(profile, observed) {
  return observed.w === profile.w && observed.h === profile.h;
}
