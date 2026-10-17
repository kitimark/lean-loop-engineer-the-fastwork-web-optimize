import Auto
open Auto.DeviceQueue Auto.Console Auto.ArtifactKey
theorem h1 (s : State) (e : Event) (k : Nat) (h : s.steps[k]? = some .answered) :
    (apply s e).1.steps[k]? = some .answered := by
  grind [apply, applyBody, stepNext, Std.HashMap.getElem?_insert]
theorem h2 (v : Input → Val) (i : Input) (w : Val) (hw : w ≠ v i) (a : Artifact) :
    key v a ≠ key (update v i w) a ↔ i ∈ a.deps := by
  grind [key, update, List.map_inj_left]
theorem h3 (t : Nat) (best : Job) (ks : List Job) : ∀ k ∈ ks, before t (pickFrom t best ks) k = true := by
  induction ks generalizing best <;> grind [pickFrom, before]
theorem h4 (k : Nat) (es : List Event) : ∀ s : State, answersAccepted k s es ≤ 1 := by
  induction es <;> grind [answersAccepted, answers_after_answered, apply_answer_sets]
