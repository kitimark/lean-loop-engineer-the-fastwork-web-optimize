import Fw.Console
/-!
# What the reducer guarantees about feedback threads

The reducer (`Fw.Console.check`, `Fw.Console.accept`) keeps a feedback thread in `State.fb` and uses the functions of
`Fw.Console.ReviewFeedback`. These theorems are the contract the console UI and the watch rely on: who may write each event,
which `to` a reply may name, that a reply closes exactly the comment it names, and that the text is capped.
-/
namespace Fw.Console.ReviewFeedbackLaws
open Fw.Console Fw.Console.ReviewFeedback

/-- **Feedback is never accepted from the lead.** Indeed from no actor but the user: a `review.feedback` event from any other
actor changes nothing. -/
theorem feedback_only_user {s : State} {e : Event} {f i t : String}
    (hb : e.body = .reviewFeedback f i t) (ha : e.actor ≠ .user) : apply s e = s := by
  have : may e.actor e.body.type = false := by
    rw [hb]; cases h : e.actor <;> simp_all [may, mayList, Body.type]
  exact reject_keeps (unauthorized_rejected this)

/-- The lead's feedback is refused with the authority table's reason. -/
theorem feedback_from_lead_refused (s : State) (e : Event) (f i t : String)
    (hb : e.body = .reviewFeedback f i t) (ha : e.actor = .lead) :
    check s e = some "actor lead may not cause review.feedback" := by
  simp [check, hb, ha, may, mayList, Body.type, EvType.name, Actor.name]
  rfl

/-- **A reply is never accepted from the user.** Indeed from no actor but the lead: a `review.feedback.reply` event from any
other actor changes nothing. -/
theorem reply_only_lead {s : State} {e : Event} {f to t : String}
    (hb : e.body = .reviewFeedbackReply f to t) (ha : e.actor ≠ .lead) : apply s e = s := by
  have : may e.actor e.body.type = false := by
    rw [hb]; cases h : e.actor <;> simp_all [may, mayList, Body.type]
  exact reject_keeps (unauthorized_rejected this)

/-- The user's reply is refused with the authority table's reason. -/
theorem reply_from_user_refused (s : State) (e : Event) (f to t : String)
    (hb : e.body = .reviewFeedbackReply f to t) (ha : e.actor = .user) :
    check s e = some "actor user may not cause review.feedback.reply" := by
  simp [check, hb, ha, may, mayList, Body.type, EvType.name, Actor.name]
  rfl

/-- **An unknown `to` is refused.** -/
theorem reply_unknown_refused (s : State) (e : Event) (f to t : String)
    (hb : e.body = .reviewFeedbackReply f to t) (ha : e.actor = .lead) (hu : ∀ x ∈ s.fb, x.id ≠ to) :
    check s e = some "no such feedback" := by
  simp [check, hb, ha, may, mayList, Body.type, reply_refuses_unknown s.fb f to t hu]

/-- **An already-answered `to` is refused.** -/
theorem reply_answered_refused (s : State) (e : Event) (f to t : String)
    (hb : e.body = .reviewFeedbackReply f to t) (ha : e.actor = .lead) (x : Fb)
    (hx : s.fb.find? (·.id == to) = some x) (hfl : x.flag = f) (hc : x.isOpen = false) :
    check s e = some "feedback already answered" := by
  simp [check, hb, ha, may, mayList, Body.type, reply_refuses_answered s.fb f to t x hx hfl hc]

/-- **A repeated feedback id is refused.** -/
theorem feedback_repeat_refused (s : State) (e : Event) (f i t : String)
    (hb : e.body = .reviewFeedback f i t) (ha : e.actor = .user) (x : Fb) (hx : x ∈ s.fb) (hid : x.id = i)
    (hf : f.contains ':' = true) (hne : i.isEmpty = false) : check s e = some "feedback id exists" := by
  simp [check, hb, ha, may, mayList, Body.type, post_refuses_repeat s.fb f i t x hx hid hf hne]

/-- **The text of a feedback is capped.** A feedback the reducer accepts has a text of at most `textCap` characters. -/
theorem feedback_text_capped {s : State} {e : Event} {f i t : String} (hb : e.body = .reviewFeedback f i t)
    (h : check s e = none) : t.length ≤ textCap := by
  simp only [check, hb] at h
  split at h
  · cases h
  · exact post_text_capped h

/-- **The text of a reply is capped.** -/
theorem reply_text_capped' {s : State} {e : Event} {f to t : String} (hb : e.body = .reviewFeedbackReply f to t)
    (h : check s e = none) : t.length ≤ textCap := by
  simp only [check, hb] at h
  split at h
  · cases h
  · exact reply_text_capped h

/-- **A long text is refused.** -/
theorem feedback_long_refused (s : State) (e : Event) (f i t : String) (hb : e.body = .reviewFeedback f i t)
    (h : textCap < t.length) : (check s e).isSome = true := by
  by_cases hc : check s e = none
  · have := feedback_text_capped hb hc; omega
  · exact Option.isSome_iff_ne_none.mpr hc

/-! ## What an accepted event does to the thread -/

/-- An accepted feedback appends one open comment (stamped with the event time). -/
theorem accept_feedback (s : State) (e : Event) (f i t : String) (hb : e.body = .reviewFeedback f i t) :
    (accept s e).fb = post s.fb f i t e.ts := by
  simp [accept, hb]

/-- An accepted reply sets the reply of the comment it names. -/
theorem accept_reply (s : State) (e : Event) (f to t : String) (hb : e.body = .reviewFeedbackReply f to t) :
    (accept s e).fb = answer s.fb f to t e.ts := by
  simp [accept, hb]

/-- Any other event leaves the thread alone. -/
theorem accept_fb_other (s : State) (e : Event) (h1 : ∀ f i t, e.body ≠ .reviewFeedback f i t)
    (h2 : ∀ f to t, e.body ≠ .reviewFeedbackReply f to t) : (accept s e).fb = s.fb := by
  unfold accept
  cases hb : e.body with
  | reviewFeedback f i t => exact absurd hb (h1 f i t)
  | reviewFeedbackReply f to t => exact absurd hb (h2 f to t)
  | runFinish r ok => simp only; split <;> simp
  | _ => simp [cardOf]

/-- The thread keeps distinct ids through the reducer. -/
theorem apply_idsNodup {s : State} (h : IdsNodup s.fb) (e : Event) : IdsNodup (apply s e).fb := by
  unfold apply step
  split
  · exact h
  · split
    · exact h
    · rename_i hc
      show IdsNodup (accept s e).fb
      cases hb : e.body with
      | reviewFeedback f i t =>
        rw [accept_feedback s e f i t hb]
        have : ReviewFeedback.postRefusal s.fb f i t = none := by
          simp only [check, hb] at hc
          split at hc
          · cases hc
          · exact hc
        exact idsNodup_post h this e.ts
      | reviewFeedbackReply f to t =>
        rw [accept_reply s e f to t hb]
        exact idsNodup_answer h f to t e.ts
      | _ => rw [accept_fb_other s e (by simp [hb]) (by simp [hb])]; exact h

/-- **Every projected log has distinct feedback ids.** -/
theorem project_idsNodup (l : List Event) : IdsNodup (project l).fb := by
  unfold project
  suffices ∀ s, IdsNodup s.fb → IdsNodup (l.foldl apply s).fb from this {} idsNodup_nil
  induction l with
  | nil => intro s h; exact h
  | cons e es ih => intro s h; exact ih _ (apply_idsNodup h e)

/-- **A reply closes exactly the comment it names.** When the reducer accepts a reply over a thread with distinct ids, the thread
has the same comments, the named comment is answered with the reply text and time, and every other comment is as it was;
so one open comment fewer. -/
theorem accepted_reply_closes_one {s : State} {e : Event} {f to t : String} (hb : e.body = .reviewFeedbackReply f to t)
    (hc : check s e = none) (h : IdsNodup s.fb) :
    openCount (accept s e).fb + 1 = openCount s.fb := by
  rw [accept_reply s e f to t hb]
  have : replyRefusal s.fb f to t = none := by
    simp only [check, hb] at hc
    split at hc
    · cases hc
    · exact hc
  exact answer_closes_one h this e.ts

end Fw.Console.ReviewFeedbackLaws
