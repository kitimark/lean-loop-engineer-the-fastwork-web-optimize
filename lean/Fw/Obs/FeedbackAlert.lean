import Fw.Console.ReviewFeedback
/-!
# The watch alert for open feedback

`fw watch` raises one alert `review.feedback <flag>` for every flag that has an open feedback comment. It opens when the user posts a
comment and closes when the lead replies. The decision is `alerts`: from the feedback events of the log it gives, per flag, the
alert detail. `Fw.Obs.Health` turns each pair into an `Alert` (code `review.feedback`, subject the flag); the theorems here are about
the pairs, so they hold for the alerts.
-/
namespace Fw.Obs.FeedbackAlert
open Fw.Console.ReviewFeedback

/-- The strings of a list, each once, in the order of their first occurrence. -/
def uniq (l : List String) : List String :=
  l.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) []

/-- The fold of `uniq` from any accumulator: no repeats when the accumulator has none, and exactly the strings of the accumulator and the list. -/
theorem uniq_aux (l acc : List String) (h : acc.Nodup) :
    (l.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) acc).Nodup ∧
    ∀ y, y ∈ l.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) acc ↔ y ∈ acc ∨ y ∈ l := by
  induction l generalizing acc with
  | nil => simp [h]
  | cons x xs ih =>
    simp only [List.foldl_cons]
    by_cases hx : acc.contains x = true
    · simp only [hx, ite_true]
      refine ⟨(ih acc h).1, fun y => ?_⟩
      have hm : x ∈ acc := List.contains_iff_mem.mp hx
      rw [(ih acc h).2 y]
      constructor
      · rintro (a | a)
        · exact Or.inl a
        · exact Or.inr (List.mem_cons_of_mem _ a)
      · rintro (a | a)
        · exact Or.inl a
        · rcases List.mem_cons.mp a with rfl | a
          · exact Or.inl hm
          · exact Or.inr a
    · have hx' : x ∉ acc := fun hm => hx (List.contains_iff_mem.mpr hm)
      have hc : acc.contains x = false := by simpa using hx
      simp only [hc, Bool.false_eq_true, ↓reduceIte]
      have hn : (acc ++ [x]).Nodup := by
        rw [List.nodup_append]
        refine ⟨h, List.nodup_cons.2 ⟨by simp, List.nodup_nil⟩, ?_⟩
        intro a ha b hb
        simp at hb
        rw [hb]; exact fun e => hx' (e ▸ ha)
      refine ⟨(ih _ hn).1, fun y => ?_⟩
      rw [(ih _ hn).2 y]
      simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false]
      constructor
      · rintro ((a | a) | a)
        · exact Or.inl a
        · exact Or.inr (Or.inl a)
        · exact Or.inr (Or.inr a)
      · rintro (a | a | a)
        · exact Or.inl (Or.inl a)
        · exact Or.inl (Or.inr a)
        · exact Or.inr a

/-- `uniq` has no repeated string. -/
theorem uniq_nodup (l : List String) : (uniq l).Nodup := (uniq_aux l [] List.nodup_nil).1

/-- `uniq` keeps exactly the strings of the list. -/
theorem mem_uniq (l : List String) (y : String) : y ∈ uniq l ↔ y ∈ l := by
  have := (uniq_aux l [] List.nodup_nil).2 y
  simpa [uniq] using this

/-- **The alerts**: for every flag with an open comment in the thread of the log, the flag and its detail text (how many are open
and the first 120 characters of the newest), in the order of the flag's first open comment. -/
def alerts (evs : List Ev) : List (String × String) :=
  let fs := thread evs
  (uniq (openFlagList fs)).map fun f => (f, detail fs f)

/-- The flags that have an alert. -/
def flags (evs : List Ev) : List String := (alerts evs).map Prod.fst

/-- The flags with an alert are the distinct flags of the open comments. -/
theorem flags_eq (evs : List Ev) : flags evs = uniq (openFlagList (thread evs)) := by
  simp [flags, alerts, List.map_map, Function.comp_def]

/-- **A flag has an alert exactly when it has an open comment.** -/
theorem mem_flags (evs : List Ev) (f : String) : f ∈ flags evs ↔ openOf (thread evs) f ≠ [] := by
  rw [flags_eq, mem_uniq, mem_openFlagList]

/-- **One alert per flag**: no flag is alerted twice. -/
theorem flags_nodup (evs : List Ev) : (flags evs).Nodup := by
  rw [flags_eq]; exact uniq_nodup _

/-- **The detail is the thread's**: the alert of a flag carries `detail`. -/
theorem mem_alerts (evs : List Ev) (f d : String) :
    (f, d) ∈ alerts evs ↔ openOf (thread evs) f ≠ [] ∧ d = detail (thread evs) f := by
  simp only [alerts, List.mem_map, Prod.mk.injEq]
  constructor
  · rintro ⟨x, hx, rfl, rfl⟩
    exact ⟨(mem_openFlagList _ _).mp ((mem_uniq _ _).mp hx), rfl⟩
  · rintro ⟨h, rfl⟩
    exact ⟨f, (mem_uniq _ _).mpr ((mem_openFlagList _ _).mpr h), rfl, rfl⟩

/-- In a list without repeats, a string occurs once if it is in the list and not at all otherwise. -/
theorem filter_len (l : List String) (h : l.Nodup) (f : String) :
    (l.filter (· == f)).length = if f ∈ l then 1 else 0 := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    rw [List.nodup_cons] at h
    by_cases hx : x = f
    · subst hx
      have : (xs.filter (· == x)).length = 0 := by
        rw [ih h.2]; simp [h.1]
      simp [List.filter_cons, this]
    · have hx' : (x == f) = false := by simpa using hx
      have := ih h.2
      simp [List.filter_cons, hx, this, List.mem_cons, Ne.symm hx]

/-- **The count**: a flag has exactly one alert when it has an open comment, none otherwise. -/
theorem alert_count (evs : List Ev) (f : String) :
    ((alerts evs).filter (·.1 == f)).length = if openOf (thread evs) f ≠ [] then 1 else 0 := by
  have : ((alerts evs).filter (·.1 == f)).length = ((flags evs).filter (· == f)).length := by
    simp [flags, List.filter_map, Function.comp_def]
  rw [this, filter_len _ (flags_nodup evs)]
  have hm := mem_flags evs f
  by_cases h : f ∈ flags evs
  · simp [h, hm.mp h]
  · have : ¬ openOf (thread evs) f ≠ [] := fun h' => h (hm.mpr h')
    simp [h, this]

/-- One more event is one more step of the fold. -/
theorem thread_snoc (evs : List Ev) (e : Ev) : thread (evs ++ [e]) = stepEv (thread evs) e := by
  simp [thread]

/-- **A post opens the alert**: after the user's comment is accepted, its flag has an alert. -/
theorem post_opens (evs : List Ev) (f i t : String) (ts : Nat)
    (h : postRefusal (thread evs) f i t = none) : f ∈ flags (evs ++ [Ev.post f i t ts]) := by
  rw [mem_flags]
  have : thread (evs ++ [Ev.post f i t ts]) = post (thread evs) f i t ts := by
    rw [thread_snoc]
    simp only [stepEv, h, Option.isNone_none, ite_true]
  rw [this]
  intro hnil
  have hm : ({ flag := f, id := i, text := t, postedAt := ts, reply := none } : Fb) ∈ openOf (post (thread evs) f i t ts) f := by
    simp [openOf, post, Fb.isOpen]
  rw [hnil] at hm
  cases hm

/-- **A reply closes the alert** when the comment it names was the flag's only open one: after the reply is accepted, the flag has no alert. -/
theorem reply_closes (evs : List Ev) (f to t : String) (ts : Nat)
    (h : replyRefusal (thread evs) f to t = none)
    (honly : ∀ y ∈ thread evs, y.flag = f → y.isOpen = true → y.id = to) :
    f ∉ flags (evs ++ [Ev.reply f to t ts]) := by
  rw [mem_flags]
  have : thread (evs ++ [Ev.reply f to t ts]) = answer (thread evs) f to t ts := by
    rw [thread_snoc]
    simp only [stepEv, h, Option.isNone_none, ite_true]
  rw [this]
  intro hne
  apply hne
  simp only [openOf, List.filter_eq_nil_iff, answer, List.mem_map]
  rintro y ⟨x, hx, rfl⟩
  by_cases hn : x.named f to = true
  · simp [hn, Fb.isOpen]
  · have hn' : x.named f to = false := by simpa using hn
    simp only [hn', Bool.false_eq_true, ite_false]
    intro hy
    simp only [Bool.and_eq_true, beq_iff_eq] at hy
    have := honly x hx hy.1 hy.2
    simp [Fb.named, this, hy.1] at hn'

/-- **The detail names the open count and the newest open text's first 120 characters.** -/
theorem detail_eq (fs : List Fb) (f : String) (x : Fb) (h : (openOf fs f).getLast? = some x) :
    detail fs f = s!"{(openOf fs f).length} open; newest: {String.ofList (x.text.toList.take detailChars)}" := by
  simp [detail, h]

/-- The quoted part of the detail is at most 120 characters. -/
theorem detail_quote_short (x : Fb) : (String.ofList (x.text.toList.take detailChars)).length ≤ detailChars := by
  simp only [String.length_ofList, List.length_take]
  omega

end Fw.Obs.FeedbackAlert
