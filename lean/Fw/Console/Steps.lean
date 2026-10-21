import Fw.Console.ReviewFeedback
import Fw.Obs.FeedbackAlert
/-! Topics group open steps under the lead's summary; steps and topics carry comment threads. -/
namespace Fw.Console.Steps
open Fw.Console.ReviewFeedback

/-- The longest topic title, in characters. -/
def titleCap : Nat := 120

/-- Why a `step.topic` event is refused (`none` = accepted): empty id, blank or long title, or an invalid summary. -/
def topicRefusal (id title summary : String) : Option String :=
  if id.isEmpty then some "topic id is empty"
  else if title.toList.all Char.isWhitespace then some "title is empty"
  else if titleCap < title.length then some s!"title is longer than {titleCap} characters"
  else textRefusal summary

def stepSubject (id : String) : String := "step:" ++ id

/-- The thread subject of a topic. -/
def topicSubject (id : String) : String := "topic:" ++ id

/-- Whether a thread subject names a step or a topic (any other subject is a review flag). -/
def isStepSubject (s : String) : Bool := s.startsWith "step:" || s.startsWith "topic:"

theorem isStepSubject_step (id : String) : isStepSubject (stepSubject id) = true := by
  simp [isStepSubject, stepSubject]

theorem isStepSubject_topic (id : String) : isStepSubject (topicSubject id) = true := by
  simp [isStepSubject, topicSubject]

/-- A `step.topic` event of the log: id, title, summary and stamp time. -/
structure TopicEv where
  id      : String
  title   : String
  summary : String
  ts      : Nat
deriving Repr, DecidableEq

/-- A topic as the latest valid event defines it. -/
structure Topic where
  id        : String
  title     : String
  summary   : String
  updatedAt : Nat
deriving Repr, DecidableEq

/-- One event: an invalid one changes nothing. -/
def define (ts : List Topic) (e : TopicEv) : List Topic :=
  if (topicRefusal e.id e.title e.summary).isSome then ts
  else if ts.any (·.id == e.id) then
    ts.map fun t => if t.id == e.id then { t with title := e.title, summary := e.summary, updatedAt := e.ts } else t
  else ts ++ [⟨e.id, e.title, e.summary, e.ts⟩]

/-- The topics of a log, in the order of their first definition. -/
def topics (evs : List TopicEv) : List Topic := evs.foldl define []

theorem define_nodup {ts : List Topic} (h : (ts.map (·.id)).Nodup) (e : TopicEv) : ((define ts e).map (·.id)).Nodup := by
  unfold define
  split
  · exact h
  split
  · have : (ts.map fun t => if t.id == e.id then { t with title := e.title, summary := e.summary, updatedAt := e.ts } else t).map (·.id)
        = ts.map (·.id) := by
      simp only [List.map_map]
      apply List.map_congr_left
      intro t _
      by_cases hh : t.id == e.id
      · simp at hh; simp [hh]
      · have hn : ¬ t.id = e.id := by simpa using hh
        simp [hn]
    rw [this]; exact h
  · rename_i _ hn
    simp only [List.map_append, List.map_cons, List.map_nil]
    rw [List.nodup_append]
    refine ⟨h, by simp, ?_⟩
    intro a ha b hb hab
    simp only [List.mem_singleton] at hb
    subst hb
    obtain ⟨x, hx, rfl⟩ := List.mem_map.mp ha
    apply hn
    exact List.any_eq_true.mpr ⟨x, hx, by simp [hab]⟩

theorem topics_nodup (evs : List TopicEv) : ((topics evs).map (·.id)).Nodup := by
  unfold topics
  suffices ∀ (acc : List Topic), (acc.map (·.id)).Nodup → ((evs.foldl define acc).map (·.id)).Nodup from this [] List.nodup_nil
  induction evs with
  | nil => intro acc h; exact h
  | cons e es ih => intro acc h; exact ih _ (define_nodup h e)

theorem define_latest (ts : List Topic) (e : TopicEv) (h : topicRefusal e.id e.title e.summary = none) :
    ∃ t ∈ define ts e, t.id = e.id ∧ t.title = e.title ∧ t.summary = e.summary ∧ t.updatedAt = e.ts := by
  unfold define
  simp only [h, Option.isSome_none, Bool.false_eq_true, ↓reduceIte]
  split
  · rename_i hany
    obtain ⟨x, hx, hxe⟩ := List.any_eq_true.mp hany
    refine ⟨{ x with title := e.title, summary := e.summary, updatedAt := e.ts }, List.mem_map.mpr ⟨x, hx, ?_⟩, ?_⟩
    · simp at hxe; simp [hxe]
    · simp at hxe; simp [hxe]
  · exact ⟨⟨e.id, e.title, e.summary, e.ts⟩, by simp, rfl, rfl, rfl, rfl⟩

theorem define_invalid (ts : List Topic) (e : TopicEv) (h : (topicRefusal e.id e.title e.summary).isSome = true) :
    define ts e = ts := by
  simp [define, h]

/-! ## Grouping -/

/-- An open step for the user, as the grouping reads it: id, topic and last activity. -/
structure Item where
  id    : String
  topic : Option String
  last  : Nat
deriving Repr, DecidableEq

/-- A group: a topic (`none` is the group of steps without a known topic) with its open steps. -/
structure Group where
  topic         : Option String
  title         : String
  summary       : String
  updatedAt     : Option Nat
  items         : List Item
  openQuestions : Nat
  activity      : Nat
deriving Repr, DecidableEq

/-- The topic an item belongs to: its own when that topic is defined, otherwise none. -/
def itemKey (ts : List Topic) (i : Item) : Option String :=
  match i.topic with
  | some t => if ts.any (·.id == t) then some t else none
  | none => none

/-- The greatest activity time among items, from a start value. -/
def latest (start : Nat) (its : List Item) : Nat := its.foldl (fun m i => max m i.last) start

/-- The items whose topic is not a defined one. -/
def rest (ts : List Topic) (items : List Item) : List Item := items.filter fun i => itemKey ts i == none

/-- The group of the items without a defined topic. -/
def other (ts : List Topic) (items : List Item) : Group :=
  { topic := none, title := "Other", summary := "", updatedAt := none, items := rest ts items, openQuestions := 0,
    activity := latest 0 (rest ts items) }

def mkGroups (ts : List Topic) (items : List Item) (fs : List Fb) : List Group :=
  (ts.map fun t =>
    let its := items.filter (itemKey ts · == some t.id)
    { topic := some t.id, title := t.title, summary := t.summary, updatedAt := some t.updatedAt, items := its,
      openQuestions := (openOf fs (topicSubject t.id)).length, activity := latest t.updatedAt its }) ++
  (if (rest ts items).isEmpty then [] else [other ts items])

theorem mem_items {ts : List Topic} {items : List Item} {fs : List Fb} {g : Group} (hg : g ∈ mkGroups ts items fs) (i : Item) :
    i ∈ g.items ↔ i ∈ items ∧ itemKey ts i = g.topic := by
  simp only [mkGroups, List.mem_append, List.mem_map] at hg
  rcases hg with ⟨t, _, rfl⟩ | hg
  · simp [List.mem_filter]
  · split at hg
    · simp at hg
    · simp only [List.mem_singleton] at hg
      subst hg
      simp [other, rest, List.mem_filter]

theorem cover (ts : List Topic) (items : List Item) (fs : List Fb) (i : Item) (hi : i ∈ items) :
    ∃ g ∈ mkGroups ts items fs, i ∈ g.items := by
  cases hk : itemKey ts i with
  | none =>
    have hne : (rest ts items).isEmpty = false := by
      rw [Bool.eq_false_iff]
      intro h
      simp only [rest, List.isEmpty_iff, List.filter_eq_nil_iff] at h
      have := h i hi
      simp [hk] at this
    refine ⟨other ts items, ?_, ?_⟩
    · unfold mkGroups
      apply List.mem_append_right
      simp only [hne]
      simp
    · simp [other, rest, List.mem_filter, hi, hk]
  | some t =>
    have hdef : ts.any (·.id == t) = true := by
      unfold itemKey at hk
      split at hk
      · rename_i t' ht
        split at hk
        · rename_i hh; simp at hk; subst hk; exact hh
        · cases hk
      · cases hk
    obtain ⟨x, hx, hxt⟩ := List.any_eq_true.mp hdef
    simp at hxt
    refine ⟨_, List.mem_append_left _ (List.mem_map.mpr ⟨x, hx, rfl⟩), ?_⟩
    simp [List.mem_filter, hi, hk, hxt]

/-- The rank of a group: topics with open work first, then the group of the rest, then quiet topics. -/
def Group.rank (g : Group) : Nat :=
  match g.topic with
  | none => 1
  | some _ => if g.items.isEmpty && g.openQuestions == 0 then 2 else 0

/-- Whether `a` may stand before `b`: lower rank first, then the more recent activity. -/
def before (a b : Group) : Bool := a.rank < b.rank || (a.rank == b.rank && b.activity ≤ a.activity)

/-- The order of the groups (stable: equal groups keep their definition order). -/
def order (gs : List Group) : List Group := gs.mergeSort before

/-- The grouped view of the open steps. -/
def view (ts : List Topic) (items : List Item) (fs : List Fb) : List Group := order (mkGroups ts items fs)

theorem before_trans (a b c : Group) (h1 : before a b = true) (h2 : before b c = true) : before a c = true := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at *
  omega

theorem before_total (a b : Group) : (before a b || before b a) = true := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  omega

theorem order_perm (gs : List Group) : (order gs).Perm gs := List.mergeSort_perm gs before

theorem order_sorted (gs : List Group) : (order gs).Pairwise (fun a b => before a b = true) :=
  List.pairwise_mergeSort before_trans before_total gs

theorem before_rank {a b : Group} (h : before a b = true) : a.rank ≤ b.rank := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  omega

theorem before_activity {a b : Group} (h : before a b = true) (hr : a.rank = b.rank) : b.activity ≤ a.activity := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  omega

theorem order_rank_sorted (gs : List Group) : (order gs).Pairwise (fun a b => a.rank ≤ b.rank) :=
  (order_sorted gs).imp before_rank

theorem rank_cases (g : Group) : g.rank = 0 ∨ g.rank = 1 ∨ g.rank = 2 := by
  unfold Group.rank
  split <;> (try split) <;> simp

theorem view_mem_items {ts : List Topic} {items : List Item} {fs : List Fb} {g : Group} (hg : g ∈ view ts items fs) (i : Item) :
    i ∈ g.items ↔ i ∈ items ∧ itemKey ts i = g.topic :=
  mem_items ((order_perm _).mem_iff.mp hg) i

theorem view_cover (ts : List Topic) (items : List Item) (fs : List Fb) (i : Item) (hi : i ∈ items) :
    ∃ g ∈ view ts items fs, i ∈ g.items := by
  obtain ⟨g, hg, hi'⟩ := cover ts items fs i hi
  exact ⟨g, (order_perm _).mem_iff.mpr hg, hi'⟩

/-! ## The alerts for questions on steps and topics -/

/-- The `step.question` alerts: the open threads of step and topic subjects, from the same fold as the review alerts. -/
def questionAlerts (evs : List Ev) : List (String × String) :=
  (Fw.Obs.FeedbackAlert.alerts evs).filter fun p => isStepSubject p.1

/-- The `review.feedback` alerts: the open threads of the other subjects (review flags). -/
def reviewAlerts (evs : List Ev) : List (String × String) :=
  (Fw.Obs.FeedbackAlert.alerts evs).filter fun p => !isStepSubject p.1

def questionSubjects (evs : List Ev) : List String := (questionAlerts evs).map Prod.fst

def reviewFlags (evs : List Ev) : List String := (reviewAlerts evs).map Prod.fst

theorem mem_questionSubjects (evs : List Ev) (f : String) :
    f ∈ questionSubjects evs ↔ isStepSubject f = true ∧ openOf (thread evs) f ≠ [] := by
  have := Fw.Obs.FeedbackAlert.mem_flags evs f
  simp only [questionSubjects, questionAlerts, List.mem_map, List.mem_filter, Prod.exists, exists_and_right, exists_eq_right]
  constructor
  · rintro ⟨hd, hs⟩
    refine ⟨hs, this.mp ?_⟩
    simpa only [Fw.Obs.FeedbackAlert.flags, List.mem_map, Prod.exists, exists_and_right, exists_eq_right] using hd
  · rintro ⟨hs, ho⟩
    have hf := this.mpr ho
    simp only [Fw.Obs.FeedbackAlert.flags, List.mem_map, Prod.exists, exists_and_right, exists_eq_right] at hf
    exact ⟨hf, hs⟩

theorem mem_reviewFlags (evs : List Ev) (f : String) :
    f ∈ reviewFlags evs ↔ isStepSubject f = false ∧ openOf (thread evs) f ≠ [] := by
  have := Fw.Obs.FeedbackAlert.mem_flags evs f
  simp only [reviewFlags, reviewAlerts, List.mem_map, List.mem_filter, Prod.exists, exists_and_right, exists_eq_right,
    Bool.not_eq_true']
  constructor
  · rintro ⟨hd, hs⟩
    refine ⟨hs, this.mp ?_⟩
    simpa only [Fw.Obs.FeedbackAlert.flags, List.mem_map, Prod.exists, exists_and_right, exists_eq_right] using hd
  · rintro ⟨hs, ho⟩
    have hf := this.mpr ho
    simp only [Fw.Obs.FeedbackAlert.flags, List.mem_map, Prod.exists, exists_and_right, exists_eq_right] at hf
    exact ⟨hf, hs⟩

theorem kinds_disjoint (evs : List Ev) (f : String) : ¬ (f ∈ questionSubjects evs ∧ f ∈ reviewFlags evs) := by
  rintro ⟨h1, h2⟩
  have a := ((mem_questionSubjects evs f).mp h1).1
  have b := ((mem_reviewFlags evs f).mp h2).1
  simp [a] at b

theorem post_opens (evs : List Ev) (f i t : String) (ts : Nat) (hs : isStepSubject f = true)
    (h : postRefusal (thread evs) f i t = none) : f ∈ questionSubjects (evs ++ [Ev.post f i t ts]) := by
  rw [mem_questionSubjects]
  refine ⟨hs, ?_⟩
  exact (Fw.Obs.FeedbackAlert.mem_flags _ f).mp (Fw.Obs.FeedbackAlert.post_opens evs f i t ts h)

theorem reply_closes (evs : List Ev) (f to t : String) (ts : Nat)
    (h : replyRefusal (thread evs) f to t = none)
    (honly : ∀ y ∈ thread evs, y.flag = f → y.isOpen = true → y.id = to) :
    f ∉ questionSubjects (evs ++ [Ev.reply f to t ts]) := by
  rw [mem_questionSubjects]
  intro ⟨_, hne⟩
  exact Fw.Obs.FeedbackAlert.reply_closes evs f to t ts h honly ((Fw.Obs.FeedbackAlert.mem_flags _ f).mpr hne)

end Fw.Console.Steps
