/-!
# Feedback threads on the review cards

The user leaves a comment on a review card (a flag under review) so the lead does more research and answers. A comment is
`review.feedback {flag, id, text}`; the lead's answer is `review.feedback.reply {flag, to, text}`. The comments of one flag form a
thread, kept in the order they were posted. A comment is **open** until a reply names it, then **answered**.

This module holds the pure thread: what a post or a reply is refused for, what it does, and the alert detail the watch shows
for open comments. The reducer (`Fw.Console.check`, `Fw.Console.accept`) calls these functions on its `fb` list, so the
authority table and the thread rules live in Lean and console-api only stamps, appends and forwards.

Accepted limits: a comment is never edited or deleted (a correction is a new comment); there are no attachments; the text is data
and is shown as plain text.
-/
namespace Fw.Console.ReviewFeedback

/-- The longest comment or reply, in characters (Unicode code points). -/
def textCap : Nat := 2000

/-- How many characters of the newest open comment the watch alert shows. -/
def detailChars : Nat := 120

/-- One comment of a thread: its flag, id, text, post time (ms) and, once answered, the reply text and time. -/
structure Fb where
  flag     : String
  id       : String
  text     : String
  postedAt : Nat
  reply    : Option (String × Nat) := none
deriving Repr, DecidableEq

/-- A comment is open until a reply names it. -/
def Fb.isOpen (f : Fb) : Bool := f.reply.isNone

/-- The status word of a comment (the wire value). -/
def Fb.status (f : Fb) : String := if f.isOpen then "open" else "answered"

/-- Whether a reply `(flag, to)` names this comment: same id and same flag. -/
def Fb.named (flag to : String) (f : Fb) : Bool := f.id == to && f.flag == flag

/-- Why a text is refused (`none` = acceptable): only white space, or longer than `textCap` characters. -/
def textRefusal (t : String) : Option String :=
  if t.toList.all Char.isWhitespace then some "text is empty"
  else if textCap < t.length then some s!"text is longer than {textCap} characters"
  else none

/-- Why a post is refused (`none` = accepted): the flag must be a key `part:variant`, the id non-empty and new, the text valid.
Edge: the check order is the reason order, so a bad flag is reported before a repeated id.
-/
def postRefusal (fs : List Fb) (flag id text : String) : Option String :=
  if !flag.contains ':' then some "flag must be a key part:variant"
  else if id.isEmpty then some "id is empty"
  else if fs.any (·.id == id) then some "feedback id exists"
  else textRefusal text

/-- Why a reply is refused (`none` = accepted): `to` must name a comment of this flag (an unknown id, or an id of another flag, is
unknown), it must still be open, and the text valid.
-/
def replyRefusal (fs : List Fb) (flag to text : String) : Option String :=
  match fs.find? (·.id == to) with
  | none => some "no such feedback"
  | some f =>
    if f.flag != flag then some "no such feedback"
    else if !f.isOpen then some "feedback already answered"
    else textRefusal text

/-- A post appends an open comment at the end of the list. -/
def post (fs : List Fb) (flag id text : String) (t : Nat) : List Fb :=
  fs ++ [{ flag, id, text, postedAt := t }]

/-- A reply sets the reply of the comment it names; every other comment is untouched. -/
def answer (fs : List Fb) (flag to text : String) (t : Nat) : List Fb :=
  fs.map fun f => if f.named flag to then { f with reply := some (text, t) } else f

/-- The open comments of a flag, in posting order. -/
def openOf (fs : List Fb) (flag : String) : List Fb := fs.filter fun f => f.flag == flag && f.isOpen

/-- The flag of every open comment, in posting order (a flag with several open comments is listed several times). -/
def openFlagList (fs : List Fb) : List String := (fs.filter (·.isOpen)).map (·.flag)

/-- The alert detail of a flag: how many comments are open and the first `detailChars` characters of the newest one. -/
def detail (fs : List Fb) (flag : String) : String :=
  let o := openOf fs flag
  s!"{o.length} open; newest: {match o.getLast? with | some f => String.ofList (f.text.toList.take detailChars) | none => ""}"

/-! ## The thread of a flag -/

/-- The ids of a thread are all different (kept by `post`, which refuses a repeated id). -/
def IdsNodup (fs : List Fb) : Prop := (fs.map (·.id)).Nodup

/-- The empty thread has distinct ids. -/
theorem idsNodup_nil : IdsNodup [] := List.nodup_nil

/-- An accepted post keeps the ids distinct. -/
theorem idsNodup_post {fs : List Fb} (h : IdsNodup fs) {flag id text : String} (hr : postRefusal fs flag id text = none)
    (t : Nat) : IdsNodup (post fs flag id text t) := by
  have h3 : (fs.any (·.id == id)) = false := by
    unfold postRefusal at hr
    split at hr
    · cases hr
    split at hr
    · cases hr
    split at hr
    · cases hr
    rename_i hn
    simpa using hn
  simp only [post, IdsNodup, List.map_append, List.map_cons, List.map_nil]
  rw [List.nodup_append]
  refine ⟨h, by simp, ?_⟩
  intro a ha b hb hab
  simp only [List.mem_singleton] at hb
  subst hb
  obtain ⟨x, hx, rfl⟩ := List.mem_map.mp ha
  have := List.any_eq_false.mp h3 x hx
  simp at this
  exact this hab

/-- A reply keeps the ids unchanged. -/
theorem answer_ids (fs : List Fb) (flag to text : String) (t : Nat) :
    (answer fs flag to text t).map (·.id) = fs.map (·.id) := by
  simp only [answer, List.map_map]
  apply List.map_congr_left
  intro f _
  by_cases h : f.named flag to <;> simp [h]

/-- A reply keeps the ids distinct. -/
theorem idsNodup_answer {fs : List Fb} (h : IdsNodup fs) (flag to text : String) (t : Nat) :
    IdsNodup (answer fs flag to text t) := by
  unfold IdsNodup; rw [answer_ids]; exact h

/-! ## Text is capped -/

/-- **A text is accepted only within the cap.** A post or reply that passes its refusal check has a text of at most
`textCap` characters. -/
theorem textRefusal_none {t : String} (h : textRefusal t = none) :
    t.toList.all Char.isWhitespace = false ∧ t.length ≤ textCap := by
  unfold textRefusal at h
  split at h
  · cases h
  split at h
  · cases h
  rename_i h1 h2
  exact ⟨by simpa using h1, by omega⟩

/-- A text over the cap is refused. -/
theorem textRefusal_long {t : String} (h : textCap < t.length) : (textRefusal t).isSome = true := by
  unfold textRefusal; split <;> simp_all

/-- A blank text is refused. -/
theorem textRefusal_blank {t : String} (h : t.toList.all Char.isWhitespace = true) : (textRefusal t).isSome = true := by
  unfold textRefusal; simp [h]

/-- An accepted post has a capped text. -/
theorem post_text_capped {fs : List Fb} {flag id text : String} (h : postRefusal fs flag id text = none) :
    text.length ≤ textCap := by
  unfold postRefusal at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  exact (textRefusal_none h).2

/-- An accepted reply has a capped text. -/
theorem reply_text_capped {fs : List Fb} {flag to text : String} (h : replyRefusal fs flag to text = none) :
    text.length ≤ textCap := by
  unfold replyRefusal at h
  split at h
  · cases h
  · split at h
    · cases h
    split at h
    · cases h
    exact (textRefusal_none h).2

/-! ## A post -/

/-- **A post adds exactly one open comment, last.** -/
theorem post_open (fs : List Fb) (flag id text : String) (t : Nat) :
    post fs flag id text t = fs ++ [{ flag, id, text, postedAt := t, reply := none }] := rfl

/-- A post keeps every earlier comment as it was. -/
theorem post_keeps (fs : List Fb) (flag id text : String) (t : Nat) (f : Fb) (h : f ∈ fs) :
    f ∈ post fs flag id text t := by
  simp [post, h]

/-- **A repeated id is refused.** -/
theorem post_refuses_repeat (fs : List Fb) (flag id text : String) (f : Fb) (hf : f ∈ fs) (hid : f.id = id)
    (hflag : flag.contains ':' = true) (hne : id.isEmpty = false) :
    postRefusal fs flag id text = some "feedback id exists" := by
  have : (fs.any (·.id == id)) = true := List.any_eq_true.mpr ⟨f, hf, by simp [hid]⟩
  simp [postRefusal, hflag, hne, this]

/-- A post to a flag that is not a key is refused. -/
theorem post_refuses_flag (fs : List Fb) (flag id text : String) (h : flag.contains ':' = false) :
    postRefusal fs flag id text = some "flag must be a key part:variant" := by
  simp [postRefusal, h]

/-! ## A reply -/

/-- **An unknown `to` is refused.** -/
theorem reply_refuses_unknown (fs : List Fb) (flag to text : String) (h : ∀ f ∈ fs, f.id ≠ to) :
    replyRefusal fs flag to text = some "no such feedback" := by
  have : fs.find? (·.id == to) = none := by
    rw [List.find?_eq_none]; intro f hf; simpa using h f hf
  simp [replyRefusal, this]

/-- **An already-answered `to` is refused.** -/
theorem reply_refuses_answered (fs : List Fb) (flag to text : String) (f : Fb)
    (hf : fs.find? (·.id == to) = some f) (hfl : f.flag = flag) (hr : f.isOpen = false) :
    replyRefusal fs flag to text = some "feedback already answered" := by
  simp [replyRefusal, hf, hfl, hr]

/-- A `to` that names a comment of another flag is refused as unknown. -/
theorem reply_refuses_other_flag (fs : List Fb) (flag to text : String) (f : Fb)
    (hf : fs.find? (·.id == to) = some f) (hfl : f.flag ≠ flag) :
    replyRefusal fs flag to text = some "no such feedback" := by
  simp [replyRefusal, hf, hfl]

/-- A reply keeps the length of the thread. -/
theorem answer_length (fs : List Fb) (flag to text : String) (t : Nat) :
    (answer fs flag to text t).length = fs.length := by simp [answer]

/-- **A reply changes nothing but the comment it names**: every other comment is as it was. -/
theorem answer_keeps_other (fs : List Fb) (flag to text : String) (t : Nat) (f : Fb) (hf : f ∈ fs)
    (h : f.named flag to = false) : f ∈ answer fs flag to text t := by
  simp only [answer, List.mem_map]
  exact ⟨f, hf, by simp [h]⟩

/-- Whether a comment is open after a reply: open before, and not the one named. -/
theorem answer_isOpen (f : Fb) (flag to text : String) (t : Nat) :
    (if f.named flag to then { f with reply := some (text, t) } else f).isOpen = (f.isOpen && !f.named flag to) := by
  by_cases h : f.named flag to <;> simp [h, Fb.isOpen]

/-- The number of open comments. -/
def openCount (fs : List Fb) : Nat := (fs.filter (·.isOpen)).length

/-- The ids are distinct, so a comment found by id is the only one with that id and flag. -/
theorem filter_named_of_find {fs : List Fb} (h : IdsNodup fs) {flag to : String} {f : Fb}
    (hf : fs.find? (·.id == to) = some f) (hfl : f.flag = flag) :
    fs.filter (Fb.named flag to) = [f] := by
  induction fs with
  | nil => simp at hf
  | cons x xs ih =>
    have hnd : IdsNodup xs := (List.nodup_cons.mp (by simpa [IdsNodup] using h)).2
    have hx : x.id ∉ xs.map (·.id) := (List.nodup_cons.mp (by simpa [IdsNodup] using h)).1
    by_cases hxt : x.id = to
    · have hfx : f = x := by
        simp [hxt] at hf; exact hf.symm
      subst hfx
      have hnone : xs.filter (Fb.named flag to) = [] := by
        rw [List.filter_eq_nil_iff]
        intro y hy
        have : y.id ≠ f.id := fun e => hx (List.mem_map.mpr ⟨y, hy, e⟩)
        simp only [Fb.named, hxt] at this ⊢
        simp [this]
      simp [Fb.named, hxt, hfl, hnone]
    · have hxf : (x.id == to) = false := by simpa using hxt
      simp only [List.find?_cons, hxf] at hf
      have := ih hnd hf
      simp [Fb.named, hxt, this]

/-- The count step: with exactly one named comment in the list, and it open, the reply closes it. -/
theorem openCount_answer_aux (flag to text : String) (t : Nat) :
    ∀ (fs : List Fb) (f : Fb), fs.filter (Fb.named flag to) = [f] → f.isOpen = true →
      openCount (answer fs flag to text t) + 1 = openCount fs := by
  intro fs
  induction fs with
  | nil => intro f key; simp at key
  | cons x xs ih =>
    intro f key hop
    by_cases hn : x.named flag to = true
    · have hk : x :: xs.filter (Fb.named flag to) = [f] := by simpa [List.filter_cons, hn] using key
      have hxf : x = f := (List.cons.inj hk).1
      have hnone : xs.filter (Fb.named flag to) = [] := (List.cons.inj hk).2
      have hid : xs.map (fun f => if f.named flag to then { f with reply := some (text, t) } else f) = xs := by
        conv => rhs; rw [← List.map_id xs]
        apply List.map_congr_left
        intro y hy
        have := List.filter_eq_nil_iff.mp hnone y hy
        simp only [Bool.not_eq_true] at this
        simp [this]
      subst hxf
      have e1 : answer (x :: xs) flag to text t = { x with reply := some (text, t) } :: xs := by
        unfold answer; rw [List.map_cons, hid]; simp [hn]
      rw [e1]
      have hr : x.reply = none := by simpa [Fb.isOpen] using hop
      simp [openCount, Fb.isOpen, hr]
    · have hn' : x.named flag to = false := by simpa using hn
      have hk : xs.filter (Fb.named flag to) = [f] := by simpa [List.filter_cons, hn'] using key
      have := ih f hk hop
      have e1 : answer (x :: xs) flag to text t = x :: answer xs flag to text t := by
        simp [answer, hn']
      rw [e1]
      simp only [openCount, List.filter_cons] at this ⊢
      split <;> simp [this]

/-- **A reply closes exactly one open comment.** After an accepted reply the thread has one open comment fewer. -/
theorem answer_closes_one {fs : List Fb} (h : IdsNodup fs) {flag to text : String}
    (hr : replyRefusal fs flag to text = none) (t : Nat) :
    openCount (answer fs flag to text t) + 1 = openCount fs := by
  unfold replyRefusal at hr
  cases hf : fs.find? (·.id == to) with
  | none => simp [hf] at hr
  | some f =>
    simp only [hf] at hr
    by_cases h1 : (f.flag != flag) = true
    · simp [h1] at hr
    by_cases h2 : (!f.isOpen) = true
    · simp [h1, h2] at hr
    have hfl : f.flag = flag := by simpa using h1
    have hop : f.isOpen = true := by simpa using h2
    exact openCount_answer_aux flag to text t fs f (filter_named_of_find h hf hfl) hop

/-! ## The flags with an open comment -/

/-- **A flag is listed exactly when it has an open comment.** -/
theorem mem_openFlagList (fs : List Fb) (flag : String) : flag ∈ openFlagList fs ↔ openOf fs flag ≠ [] := by
  simp only [openFlagList, List.mem_map, List.mem_filter, openOf, ne_eq, List.filter_eq_nil_iff]
  constructor
  · rintro ⟨f, ⟨hf, ho⟩, rfl⟩ h
    have := h f hf
    simp [ho] at this
  · intro h
    refine Classical.byContradiction fun hc => h ?_
    intro f hf
    simp only [Bool.and_eq_true, beq_iff_eq, not_and]
    intro hfl ho
    exact hc ⟨f, ⟨hf, ho⟩, hfl⟩

/-! ## The thread of a log -/

/-- An accepted event of the log, as the thread reads it: a post (flag, id, text, time) or a reply (flag, `to`, text, time). -/
inductive Ev where
  | post  (flag id text : String) (ts : Nat)
  | reply (flag to text : String) (ts : Nat)
deriving Repr, DecidableEq

/-- The thread after one event: a refused event changes nothing (the reducer's rule). -/
def stepEv (fs : List Fb) : Ev → List Fb
  | .post flag id text ts => if (postRefusal fs flag id text).isNone then post fs flag id text ts else fs
  | .reply flag to text ts => if (replyRefusal fs flag to text).isNone then answer fs flag to text ts else fs

/-- The thread of a list of events: the left fold of `stepEv` from the empty thread. -/
def thread (evs : List Ev) : List Fb := evs.foldl stepEv []

/-- One event keeps the ids distinct. -/
theorem idsNodup_stepEv {fs : List Fb} (h : IdsNodup fs) (e : Ev) : IdsNodup (stepEv fs e) := by
  cases e with
  | post flag id text ts =>
    by_cases hn : (postRefusal fs flag id text).isNone = true
    · simp only [stepEv, hn, ite_true]
      exact idsNodup_post h (Option.isNone_iff_eq_none.mp hn) ts
    · simpa [stepEv, hn] using h
  | reply flag to text ts =>
    by_cases hn : (replyRefusal fs flag to text).isNone = true
    · simp only [stepEv, hn, ite_true]
      exact idsNodup_answer h flag to text ts
    · simpa [stepEv, hn] using h

/-- **Every thread has distinct ids.** -/
theorem idsNodup_thread (evs : List Ev) : IdsNodup (thread evs) := by
  unfold thread
  suffices ∀ (fs : List Fb), IdsNodup fs → IdsNodup (evs.foldl stepEv fs) from this [] idsNodup_nil
  induction evs with
  | nil => intro fs h; exact h
  | cons e es ih => intro fs h; exact ih _ (idsNodup_stepEv h e)


end Fw.Console.ReviewFeedback
