import Fw.Parts.MorphMount

/-!
# Mounting the original's morph panel once per sweep page

On the original site the morph panel is mounted lazily: a one-way flag is set the first time `#platform` comes within
200 % of the viewport (IntersectionObserver, `2.DyWL8TcE.js:13080-13089`; modelled as `Fw.Parts.MorphMount.mountNext`).
The gate's `mountPanel` (`packages/gate-breakpoints/src/page.mjs:184-205`@6626359) scrolls `#platform` to the middle
of the viewport and back, then waits 3 frames and 300 ms. `evalCollect` (`packages/gate-breakpoints/src/run.mjs:87-99`@7ceb81c)
reads the early parts, runs `mountPanel`, then reads the late parts, at every stop of a sweep.

Here the page's mount flag is a `Bool`, `mountPanel` is `mount near` with `near` = "scrolling there makes `#platform`
intersect" (true when the page has `#platform`, the same at every stop of one page), and a resize between stops is any
map of the flag that never unmounts. Then mounting at the first stop only gives the same states, and so the same
reads, at every stop as mounting at every stop (`mountOnce_eq_mountEvery`).
-/

namespace Fw.Gate

/-- One `mountPanel` call: the flag is set if it was set or the scroll made `#platform` intersect.

The flag after `mountPanel`. -/
def mount (near m : Bool) : Bool := m || near

/-- `mount` is the panel's own transition with an intersecting entry and no push.

The gate's helper drives the site's own mount rule. -/
theorem mount_eq_mountNext (near m : Bool) : mount near m = Fw.Parts.MorphMount.mountNext m near false := by
  cases near <;> cases m <;> rfl

/-- **Mounting twice is mounting once.**

A second `mountPanel` on the same page changes nothing. -/
theorem mount_idem (near m : Bool) : mount near (mount near m) = mount near m := by
  cases near <;> cases m <;> rfl

/-- What a stop sees: the flag when the early parts are read (after the resize) and when the late parts are read.

The two reads of `evalCollect`. -/
abbrev StopObs := Bool × Bool

/-- **Today: mount at every stop.** From flag `m`, stop `i` resizes (`m ↦ r_i(m)`), reads the early parts,
mounts, and reads the late parts; the next stop starts from the mounted flag.

`evalCollect` at every stop of one sweep page. -/
def mountEvery (near : Bool) : Bool → List (Bool → Bool) → List StopObs
  | _, [] => []
  | m, r :: rs => (r m, mount near (r m)) :: mountEvery near (mount near (r m)) rs

/-- Stops without a mount: resize, then both reads see the same flag.

The stops after the first in the proposed run. -/
def mountNone : Bool → List (Bool → Bool) → List StopObs
  | _, [] => []
  | m, r :: rs => (r m, r m) :: mountNone (r m) rs

/-- **Proposed: mount at the first stop only.**

`mountPanel` once per sweep page. -/
def mountOnce (near : Bool) : Bool → List (Bool → Bool) → List StopObs
  | _, [] => []
  | m, r :: rs => (r m, mount near (r m)) :: mountNone (mount near (r m)) rs

#guard mountEvery true false [id, id, id] = [(false, true), (true, true), (true, true)]
#guard mountOnce true false [id, id, id] = [(false, true), (true, true), (true, true)]
#guard mountOnce true false [] = []
-- a resize that unmounts breaks the equality (why the premise is needed)
#guard mountOnce true false [id, fun _ => false] ≠ mountEvery true false [id, fun _ => false]

/-- When `#platform` does not intersect, a mount does nothing, so mounting at every stop is mounting at none.

Helper for `mountOnce_eq_mountEvery`. -/
theorem mountEvery_false (m : Bool) (rs : List (Bool → Bool)) : mountEvery false m rs = mountNone m rs := by
  induction rs generalizing m with
  | nil => rfl
  | cons r rs ih =>
    have h : mount false (r m) = r m := by cases r m <;> rfl
    simp only [mountEvery, mountNone, h, ih]

/-- Once mounted, with resizes that never unmount, every later read sees a mounted panel, with or without mounts.

Helper for `mountOnce_eq_mountEvery`. -/
theorem mounted_stays (near : Bool) (rs : List (Bool → Bool)) (hmono : ∀ r ∈ rs, r true = true) :
    mountEvery near true rs = mountNone true rs ∧ mountNone true rs = rs.map fun _ => (true, true) := by
  induction rs with
  | nil => exact ⟨rfl, rfl⟩
  | cons r rs ih =>
    have hr : r true = true := hmono r (by simp)
    have ih' := ih fun r' hr' => hmono r' (by simp [hr'])
    have hm : mount near true = true := by cases near <;> rfl
    simp only [mountEvery, mountNone, hr, hm, ih'.1, ih'.2, List.map_cons]
    trivial

/-- **Mounting once per sweep page equals mounting at every stop.** Premise: nothing unmounts the panel, i.e. every
resize between stops keeps a set flag set (the IntersectionObserver flag is one-way, `2.DyWL8TcE.js:13080-13089`);
`near` is the same at every stop of the page. Then from any start flag the two runs see the same flags at every early
and every late read.

So `ORIG_PREPARE` can run once per sweep page instead of at each of its stops. -/
theorem mountOnce_eq_mountEvery (near m : Bool) (rs : List (Bool → Bool))
    (hmono : ∀ r ∈ rs, r true = true) : mountOnce near m rs = mountEvery near m rs := by
  cases rs with
  | nil => rfl
  | cons r rs =>
    have hmono' : ∀ r' ∈ rs, r' true = true := fun r' hr' => hmono r' (by simp [hr'])
    simp only [mountOnce, mountEvery]
    cases near with
    | false => rw [mountEvery_false]
    | true =>
      have hm : mount true (r m) = true := by cases r m <;> rfl
      rw [hm, (mounted_stays true rs hmono').1]

end Fw.Gate
