import Fw.Parts.MorphEnd
/-! The pin-write rule under no bounce (flag `morph.end.nobounce`).

With `html { overscroll-behavior-y: none }` from first paint the page has no rubber band, so every scroll position
the page reads lies in `[0, maxY]` and never above `maxY`. The flag changes no code in the end reducer; it changes
which scroll positions the reducer can read. Statements in plain words: `research/notes/2026/10-2x-morph-end-nobounce.md`. -/
namespace Fw.Parts.MorphEndNobounce
open Fw.Parts.MorphEnd

def flagId : String := "morph.end.nobounce"
/-- The one rule, in `apps/site/src/styles/reset.css`; the page root carries `data-fw-nobounce` when the flag is on. -/
def css : String := "html:has([data-fw-nobounce]){overscroll-behavior-y:none}"
def attr : String := "data-fw-nobounce"

/-- No bounce: an event reads positions at most `m`, the real end of the page. -/
def Within (m : Rat) : Ev → Prop
  | .touchstart _ => True
  | .touchmove _ r => r.scrollY ≤ m
  | .wheel _ r => r.scrollY ≤ m
  | .scroll y m' => y ≤ m ∧ m' = m
  | .resize y m' => y ≤ m ∧ m' = m
  | .tick _ => True

/-- Under no bounce every brick combination has the pin as its write target while the pin is at most the end. -/
theorem nb_target (c : Cfg) (p m : Rat) (h : p ≤ m) : c.hooks.target p m = p := by
  rw [hooks_target]
  by_cases hc : c.clamp = true
  · have : min p m = p := by grind
    simp [hc, this]
  · simp [hc]

/-- A forward push at the end: the pin sits at the end and the page stays there, so the frame writes nothing. -/
theorem push_at_end_no_write (c : Cfg) (s : S) (m : Rat) (hp : s.pin = m) :
    (step c.hooks s (.scroll m m)).2.write = none ∧ (step c.hooks s (.resize m m)).2.write = none := by
  have ht := nb_target c s.pin m (by grind)
  rw [hp] at ht
  simp [step, frameOut, ht, hp]

/-- With the pin at the end, a frame writes only when the page is below the pin, and then writes the pin. -/
theorem pin_writes_below (c : Cfg) (s : S) (y m w : Rat) (hp : s.pin = m) (hy : y ≤ m)
    (hw : (step c.hooks s (.scroll y m)).2.write = some w) : y < s.pin ∧ w = s.pin := by
  have ht := nb_target c s.pin m (by grind)
  simp only [step, frameOut, ht] at hw
  split at hw
  · rename_i hc
    simp only [Option.some.injEq] at hw
    have hne : y ≠ s.pin := by simp at hc; exact hc.2
    exact ⟨by grind, hw.symm⟩
  · cases hw

/-- Contrast, with a bounce: the page read above the end is written back to the pin. -/
theorem bounce_writes_back (c : Cfg) (hc : c.clamp = false) (s : S) (m : Rat) (ha : s.tw.isActive = true)
    (hf : (c.release && s.rel) = false) (hp : m < s.pin) :
    (step c.hooks s (.scroll m m)).2.write = some s.pin := faithful_fight c hc s m ha hf hp

theorem moveStep_pin_le (h : Hooks) (s : S) (d : Rat) (r : Read) (m : Rat) (hp : s.pin ≤ m) (hr : r.scrollY ≤ m) :
    (moveStep h s d r).1.pin ≤ m := by
  rcases moveStep_cases h s d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, -, -, he⟩ <;> rw [he] <;>
    simp only [kept, applied, pinAfter] <;> (try split) <;> assumption

theorem step_pin_le (h : Hooks) (s : S) (e : Ev) (m : Rat) (hp : s.pin ≤ m) (he : Within m e) :
    (step h s e).1.pin ≤ m := by
  cases e with
  | touchstart y => simpa [step] using hp
  | touchmove y r => exact moveStep_pin_le h _ _ r m hp he
  | wheel d r => exact moveStep_pin_le h s d r m hp he
  | scroll y m' => simpa [step] using hp
  | resize y m' => simpa [step] using hp
  | tick now => simp only [step]; split <;> simpa using hp

/-- Over a whole recording read without bounce, no write ever asks for a position above the end. -/
theorem no_write_above_end (c : Cfg) (m : Rat) (s : S) (t : List Ev) (hp : s.pin ≤ m) (hw : ∀ e ∈ t, Within m e)
    (e : Ev) (o : Out) (w : Rat) (hm : (e, o) ∈ trace c.hooks s t) (hwo : o.write = some w) : w ≤ m := by
  induction t generalizing s with
  | nil => simp [trace] at hm
  | cons e' t ih =>
    simp only [trace, List.mem_cons, Prod.mk.injEq] at hm
    rcases hm with ⟨rfl, rfl⟩ | hm
    · obtain ⟨y, m', hy, ho⟩ := write_frame c.hooks s _ w hwo
      have hwin := hw _ (List.mem_cons_self ..)
      have ht := nb_target c s.pin m hp
      rcases hy with rfl | rfl <;> simp only [Within] at hwin <;> obtain ⟨-, rfl⟩ := hwin <;>
        simp only [step, frameOut, ht] at hwo <;> split at hwo <;> simp_all
    · exact ih _ (step_pin_le c.hooks s e' m hp (hw _ (List.mem_cons_self ..)))
        (fun e he => hw e (List.mem_cons_of_mem _ he)) hm

end Fw.Parts.MorphEndNobounce
