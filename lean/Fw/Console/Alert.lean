import Fw.Console
/-!
# Alert steps

The spool drain turns a few hook events into an *alert step*: a step the user sees on the board
because an agent is stuck or waiting. This module is the whole rule (it replaces the TypeScript
stand-in `alertFor`):

* **Which events open an alert.** `StopFailure` (the agent stopped on an API failure) and a
  `Notification` of type `permission_prompt` (permission prompt, names the tool) or
  `agent_needs_input` (needs input). Nothing else opens one.
* **Whom it names.** A hook event carries the agent that fired it. A `Notification` of the lead
  has no `agent_id`; its prompt is already in front of the user in the terminal, so it is no
  alert. A `Notification` without `agent_id` is attributed only on evidence: the list of tool
  calls in flight (a `PreToolUse` seen, no `PostToolUse` yet) must hold exactly one agent and no
  tool call of the lead other than the `Agent` call that waits for it. Otherwise it is not
  attributable and there is no alert.
* **What it says.** A short plain title, and a body with what happened (the agent type and, for a
  permission prompt, the tool), the impact and the action for the audience (`Plain`).
* **Whom it is for.** `user` only when the action needs the owner: a permission prompt or a question
  in the terminal, and a stop of the lead's own session. An API stop of a helper is `lead`'s to
  restart, so it is not shown under YOU.
* **When it closes.** The agent's next `PostToolUse`, `PostToolUseFailure`, `SubagentStop` or
  `Stop` that is later than the alert closes every open alert step of that agent.
* **Idempotent.** The step id is a function of agent and time, the command keys of the step
  and of its cancel are functions of the step id, and an agent with an open alert gets no
  second one.
-/

namespace Fw.Console.Alert

/-- The kind of an alert. -/
inductive Kind where
  | permission | needsInput | stopFailure
deriving Repr, DecidableEq

/-- The wire name of a kind. -/
def Kind.name : Kind → String
  | .permission => "permission" | .needsInput => "needsInput" | .stopFailure => "stopFailure"

/-- The hook facts the rule reads (`agentId = none` is the lead). -/
structure Ev where
  event : String
  agentId : Option String := none
  agentType : Option String := none
  tool : Option String := none
  ntype : Option String := none
  ts : Nat := 0
deriving Repr, DecidableEq

/-- A tool call in flight (`agentId = none` is the lead). -/
structure Flight where
  agentId : Option String := none
  agentType : Option String := none
  tool : Option String := none
deriving Repr, DecidableEq

/-- The kind of alert an event opens, if any. -/
def kindOf (e : Ev) : Option Kind :=
  if e.event == "StopFailure" then some .stopFailure
  else if e.event == "Notification" then
    match e.ntype with
    | some "permission_prompt" => some .permission
    | some "agent_needs_input" => some .needsInput
    | none => some .needsInput
    | some _ => none
  else none

/-- Events that end an agent's wait: its next tool result or answer. -/
def closer (ev : String) : Bool :=
  ev == "PostToolUse" || ev == "PostToolUseFailure" || ev == "SubagentStop" || ev == "Stop"

/-- Who a `Notification` without `agent_id` belongs to: the single agent with a tool in flight,
and only when the lead has no tool in flight other than the `Agent` call waiting for it.
-/
def attrib (fs : List Flight) : Option Flight :=
  if fs.any (fun f => f.agentId.isNone && f.tool != some "Agent") then none
  else match fs.filter (fun f => f.agentId.isSome) with
    | [] => none
    | f :: rest => if rest.all (fun g => g.agentId == f.agentId) then some f else none

/-- An attributed Notification names an agent and no other candidate exists. -/
theorem attrib_sound {fs : List Flight} {f : Flight} (h : attrib fs = some f) :
    f ∈ fs ∧ f.agentId.isSome = true ∧ (∀ g ∈ fs, g.agentId.isSome = true → g.agentId = f.agentId)
      ∧ (∀ g ∈ fs, g.agentId = none → g.tool = some "Agent") := by
  unfold attrib at h
  by_cases h1 : fs.any (fun f => f.agentId.isNone && f.tool != some "Agent") = true
  · simp [h1] at h
  · have h1' : fs.any (fun f => f.agentId.isNone && f.tool != some "Agent") = false := by simpa using h1
    simp only [h1', Bool.false_eq_true, ite_false] at h
    have h2 : ∀ g ∈ fs, g.agentId = none → g.tool = some "Agent" := by
      intro g hg hn
      have := List.any_eq_false.mp h1' g hg
      simpa [hn] using this
    split at h
    · simp at h
    · rename_i f0 rest hl
      split at h
      · rename_i hr
        have hf : f0 = f := by simpa using h
        subst hf
        have hmem : f0 ∈ fs.filter (fun f => f.agentId.isSome) := by rw [hl]; simp
        have hmem' := List.mem_filter.mp hmem
        refine ⟨hmem'.1, by simpa using hmem'.2, ?_, h2⟩
        intro g hg hs
        have : g ∈ fs.filter (fun f => f.agentId.isSome) := List.mem_filter.mpr ⟨hg, hs⟩
        rw [hl] at this
        rcases List.mem_cons.mp this with rfl | hr2
        · rfl
        · have := List.all_eq_true.mp hr g hr2
          simpa using this
      · simp at h

/-- With no agent in flight a Notification without `agent_id` is never attributed (the lead's
own prompt is no alert).
-/
theorem attrib_lead_only {fs : List Flight} (h : ∀ g ∈ fs, g.agentId = none) :
    attrib fs = none := by
  have : fs.filter (fun f => f.agentId.isSome) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro g hg; simp [h g hg]
  unfold attrib
  split <;> simp [this]

/-! ## Step ids -/

/-- A character allowed in an agent slug: ASCII letters, ASCII digits, `_` (never `-`, the id separator); any other
character, including a non-ASCII letter such as `é`, becomes `_`.
-/
def slugChar (c : Char) : Char := if c.isAlphanum || c == '_' then c else '_'

/-- The slug of an agent id: `main` for the lead, else the first 40 characters made safe. -/
def slug : Option String → String
  | none => "main"
  | some a => if a.isEmpty then "_" else String.ofList ((a.toList.take 40).map slugChar)

/-- The step id of an alert of `agent` raised at hook time `t`. -/
def stepId (a : Option String) (t : Nat) : String := "alert-" ++ slug a ++ "-" ++ toString t

/-- The characters up to the first `-` and those after it; a list without `-` is all left part. -/
def cut : List Char → List Char × List Char
  | [] => ([], [])
  | c :: cs => if c == '-' then ([], cs) else let r := cut cs; (c :: r.1, r.2)

/-- The number a list of decimal digit characters spells (most significant first). -/
def decode (l : List Char) : Nat := l.foldl (fun a c => a * 10 + (c.toNat - 48)) 0

/-- The slug and time inside an alert step id (`none` for any other id). -/
def parse (id : String) : Option (String × Nat) :=
  match id.toList with
  | 'a' :: 'l' :: 'e' :: 'r' :: 't' :: '-' :: rest =>
    let r := cut rest
    if r.2 != [] && r.2.all Char.isDigit then some (String.ofList r.1, decode r.2) else none
  | _ => none

/-- A decimal digit character reads back as its value. -/
theorem digit_val : ∀ k, k < 10 → (Nat.digitChar k).toNat - 48 = k := by decide

/-- Decoding the decimal digits of `n` gives `n`. -/
theorem decode_toDigits (n : Nat) : decode (Nat.toDigits 10 n) = n := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    by_cases h : n < 10
    · rw [Nat.toDigits_of_lt_base h]
      simp [decode, digit_val n h]
    · rw [Nat.toDigits_eq_ite (by omega)]
      simp only [h, ↓reduceIte]
      have h1 := ih (n / 10) (by omega)
      have hd := digit_val (n % 10) (Nat.mod_lt _ (by omega))
      simp only [decode, List.foldl_append, List.foldl_cons, List.foldl_nil] at h1 ⊢
      rw [h1, hd]
      omega

/-- Cutting after a dash-free prefix returns the prefix and the rest. -/
theorem cut_append {l : List Char} (h : ∀ c ∈ l, c ≠ '-') (r : List Char) :
    cut (l ++ '-' :: r) = (l, r) := by
  induction l with
  | nil => simp [cut]
  | cons c cs ih =>
    have hc : c ≠ '-' := h c (by simp)
    have := ih (fun x hx => h x (by simp [hx]))
    simp [cut, hc, this]

/-- A slug never contains the separator `-`. -/
theorem slug_no_dash (a : Option String) : ∀ c ∈ (slug a).toList, c ≠ '-' := by
  intro c hc
  cases a with
  | none => simp [slug] at hc; rcases hc with rfl | rfl | rfl | rfl <;> decide
  | some a =>
    simp only [slug] at hc
    by_cases he : a.isEmpty = true
    · simp [he] at hc; subst hc; decide
    · simp only [he, Bool.false_eq_true, ite_false, String.toList_ofList, List.mem_map] at hc
      obtain ⟨x, _, rfl⟩ := hc
      unfold slugChar
      split <;> rename_i h
      · intro hd
        subst hd
        simp at h
      · decide

/-- The id of an alert reads back as its agent slug and time. -/
theorem parse_stepId (a : Option String) (t : Nat) : parse (stepId a t) = some (slug a, t) := by
  have h1 := cut_append (slug_no_dash a) (Nat.toDigits 10 t)
  have hd : (Nat.toDigits 10 t).all Char.isDigit = true := by
    apply List.all_eq_true.mpr
    intro c hc
    exact Nat.isDigit_of_mem_toDigits (by omega) (by omega) hc
  have : (stepId a t).toList = 'a' :: 'l' :: 'e' :: 'r' :: 't' :: '-' :: ((slug a).toList ++ '-' :: Nat.toDigits 10 t) := by
    simp [stepId, Nat.toList_repr]
  rw [parse, this]
  simp only [h1, String.ofList_toList, hd, decode_toDigits]
  simp

/-! ## The decision -/

/-- A plain-language alert: a short title with no internal identifiers, the audience that must act, and a body
of lines `What happened`, `Impact`, the action (`What you do` for the user, `Action (lead)` for the lead) and
`Details` (identifiers belong in the details only).
-/
structure Plain where
  title : String
  audience : Audience
  body : String
deriving Repr, DecidableEq

/-- An alert step to post. -/
structure Alert where
  step : String
  key : String
  title : String
  kind : Kind
  agent : String
  audience : Audience
  body : String
deriving Repr, DecidableEq

/-- What the drain does for one event: post at most one alert step, cancel some open ones. -/
structure Out where
  post : Option Alert := none
  close : List String := []
deriving Repr, DecidableEq

private def clip (n : Nat) (s : String) : String := String.ofList (s.toList.take n)

/-- The body lines of a plain alert: what happened, impact, the action for the audience, details. -/
def bodyLines (aud : Audience) (what impact action details : String) : String :=
  "\n".intercalate
    ["What happened: " ++ what, "Impact: " ++ impact,
     (match aud with | .user => "What you do: " | .lead => "Action (lead): ") ++ action, "Details: " ++ details]

/-- Whom an alert of kind `k` of agent slug `agent` is for: the owner for a permission prompt, a question and a
stop of the lead's own session (`main`); the lead for a stop of any helper.
-/
def audienceOf (k : Kind) (agent : String) : Audience :=
  match k with
  | .permission | .needsInput => .user
  | .stopFailure => if agent == "main" then .user else .lead

/-- The plain text of an alert: the agent (its type) and the tool appear in the body only. -/
def plain (k : Kind) (agent : String) (who : String) (tool : Option String) : Plain :=
  let w := clip 60 who
  let t := clip 40 (tool.getD "a tool")
  let aud := audienceOf k agent
  match k with
  | .permission =>
    { title := "A helper needs your permission", audience := aud,
      body := bodyLines aud s!"The helper \"{w}\" asked to use {t} and is paused until it gets an answer."
        "Nothing is lost. It continues as soon as you answer."
        "Open the Claude Code terminal and answer its prompt (allow or deny). This step closes by itself when the helper continues."
        s!"agent {w}; tool {t}; hook Notification permission_prompt" }
  | .needsInput =>
    { title := "A helper is waiting for your answer", audience := aud,
      body := bodyLines aud s!"The helper \"{w}\" asked a question and is paused until it gets an answer."
        "Nothing is lost. It continues as soon as you answer."
        "Open the Claude Code terminal and answer its question. This step closes by itself when the helper continues."
        s!"agent {w}; hook Notification agent_needs_input" }
  | .stopFailure =>
    if agent == "main" then
      { title := "The lead session stopped on an API error", audience := aud,
        body := bodyLines aud "The main Claude Code session stopped because the model API failed."
          "Nothing is lost. The session does nothing until it is resumed."
          "In the Claude Code terminal, send any message (for example \"continue\"). This step closes by itself when the session runs again."
          "agent main; hook StopFailure" }
    else
      { title := "A helper stopped on an API error", audience := aud,
        body := bodyLines aud s!"The helper \"{w}\" stopped because the model API failed."
          "Its committed work and handoff note are kept. It does nothing until it is restarted."
          "Restart it from its handoff note. This step closes by itself when the helper runs again."
          s!"agent {w}; hook StopFailure" }

/-- **Audience is decided by the kind**: the plain text of an alert is for exactly the audience `audienceOf` names. -/
theorem plain_audience (k : Kind) (agent who : String) (tool : Option String) :
    (plain k agent who tool).audience = audienceOf k agent := by
  unfold plain
  cases k <;> simp only [] <;> (try split) <;> rfl

/-- **A helper's API stop is the lead's**: it is not shown to the owner. -/
theorem helper_stop_lead (agent : String) (h : (agent == "main") = false) :
    audienceOf .stopFailure agent = .lead := by
  simp [audienceOf, h]

/-- **A prompt or a question needs the owner**: it is for the user, whichever agent asked. -/
theorem prompt_user (agent : String) :
    audienceOf .permission agent = .user ∧ audienceOf .needsInput agent = .user := ⟨rfl, rfl⟩

/-- The audience of a step id posted before steps carried one: the spool alert (`alert-spool-<t>`, a problem of the
spool reader) is the lead's; any other id is the owner's.
-/
def legacyAudience (id : String) : Audience := if (parse id).map (·.1) == some "spool" then .lead else .user

/-- The agent an event opens an alert for: its own `agent_id` (`StopFailure` of the lead is the
lead's); a `Notification` without one only when attributable. Returns (agent id, agent type, tool).
-/
def subject (e : Ev) (fs : List Flight) : Option (Option String × Option String × Option String) :=
  if e.agentId.isSome || e.event == "StopFailure" then some (e.agentId, e.agentType, e.tool)
  else match attrib fs with
    | some f => some (f.agentId, f.agentType, e.tool)
    | none => none

/-- The agent slug an open alert step belongs to (`none` for a step that is no alert). -/
def owner (id : String) : Option String := (parse id).map (·.1)

/-- Does event `e` close the open alert step `id`: same agent, a closing event, strictly later
than the alert.
-/
def closes (e : Ev) (id : String) : Bool :=
  closer e.event && match parse id with
    | some (s, t) => s == slug e.agentId && decide (t < e.ts)
    | none => false

/-- The decision for one event, given the tool calls in flight and the ids of the alert steps
still open on the board.
-/
def act (e : Ev) (fs : List Flight) (opn : List String) : Out :=
  let close := opn.filter (closes e)
  match kindOf e, subject e fs with
  | some k, some (a, ty, tool) =>
    if opn.any (fun id => owner id == some (slug a)) then { close }
    else
      let id := stepId a e.ts
      let p := plain k (slug a) (ty.getD "main") tool
      { post := some { step := id, key := "alert:" ++ id, title := p.title, kind := k, agent := slug a,
                       audience := p.audience, body := p.body },
        close }
  | _, _ => { close }

/-- The key of the command that cancels alert step `id` (one per step, so a repeat is a duplicate). -/
def closeKey (id : String) : String := "alert-close:" ++ id

/-- Only a `StopFailure` or a `Notification` ever opens an alert. -/
theorem post_event {e : Ev} {fs : List Flight} {opn : List String}
    (h : (act e fs opn).post ≠ none) : e.event = "StopFailure" ∨ e.event = "Notification" := by
  unfold act at h
  by_cases hs : e.event = "StopFailure"
  · exact .inl hs
  · by_cases hn : e.event = "Notification"
    · exact .inr hn
    · exfalso
      have : kindOf e = none := by simp [kindOf, hs, hn]
      simp [this] at h

/-- The lead's own Notification (no `agent_id`, nothing but the lead in flight) opens no alert. -/
theorem lead_notification_silent {e : Ev} {fs : List Flight} {opn : List String}
    (he : e.event = "Notification") (ha : e.agentId = none) (hf : ∀ g ∈ fs, g.agentId = none) :
    (act e fs opn).post = none := by
  have hs : subject e fs = none := by
    simp [subject, ha, he, attrib_lead_only hf]
  unfold act
  rw [hs]
  cases kindOf e <;> simp

/-- A posted alert names the agent the event is about: its step id is the id of that agent at the
event time, and its key is derived from the step id.
-/
theorem post_names_agent {e : Ev} {fs : List Flight} {opn : List String} {a : Alert}
    (h : (act e fs opn).post = some a) :
    ∃ x, subject e fs = some x ∧ a.step = stepId x.1 e.ts ∧ a.agent = slug x.1
      ∧ a.key = "alert:" ++ a.step ∧ kindOf e = some a.kind := by
  unfold act at h
  cases hk : kindOf e with
  | none => simp [hk] at h
  | some k =>
    cases hx : subject e fs with
    | none => simp [hk, hx] at h
    | some x =>
      obtain ⟨a0, ty, tool⟩ := x
      simp only [hk, hx] at h
      split at h
      · simp at h
      · simp at h
        subst h
        exact ⟨(a0, ty, tool), rfl, rfl, rfl, rfl, rfl⟩

/-- No second alert is posted for an agent that already has one open. -/
theorem no_second_alert {e : Ev} {fs : List Flight} {opn : List String} {x}
    (hx : subject e fs = some x) (ho : ∃ id ∈ opn, owner id = some (slug x.1)) :
    (act e fs opn).post = none := by
  obtain ⟨id, hid, hown⟩ := ho
  unfold act
  rw [hx]
  cases kindOf e with
  | none => simp
  | some k =>
    obtain ⟨a0, ty, tool⟩ := x
    have : opn.any (fun id => owner id == some (slug a0)) = true := by
      simp only [List.any_eq_true]
      exact ⟨id, hid, by simpa using hown⟩
    simp [this]

/-- Everything closed is an open alert of the agent of the event, closed by a closing event. -/
theorem close_sound {e : Ev} {fs : List Flight} {opn : List String} {s : String}
    (h : s ∈ (act e fs opn).close) :
    s ∈ opn ∧ owner s = some (slug e.agentId) ∧ closer e.event = true := by
  have hc : s ∈ opn.filter (closes e) := by
    unfold act at h
    split at h
    · split at h <;> simpa using h
    · simpa using h
  obtain ⟨hm, hp⟩ := List.mem_filter.mp hc
  unfold closes at hp
  simp only [Bool.and_eq_true] at hp
  refine ⟨hm, ?_, hp.1⟩
  have hp2 := hp.2
  unfold owner
  split at hp2
  · rename_i s0 t hq
    simp only [Bool.and_eq_true, beq_iff_eq] at hp2
    simp [hq, hp2.1]
  · simp at hp2

/-- A closing event of an agent closes its earlier alert: the alert raised at `t < ts` for the
same agent is among those cancelled.
-/
theorem close_complete {e : Ev} {fs : List Flight} {opn : List String} {t : Nat}
    (hc : closer e.event = true) (ht : t < e.ts) (hm : stepId e.agentId t ∈ opn) :
    stepId e.agentId t ∈ (act e fs opn).close := by
  have hf : stepId e.agentId t ∈ opn.filter (closes e) := by
    apply List.mem_filter.mpr
    refine ⟨hm, ?_⟩
    simp [closes, hc, parse_stepId, ht]
  have hno : kindOf e = none := by
    have : e.event ≠ "StopFailure" ∧ e.event ≠ "Notification" := by
      unfold closer at hc
      simp only [Bool.or_eq_true, beq_iff_eq] at hc
      rcases hc with ((h | h) | h) | h <;> simp [h]
    simp [kindOf, this.1, this.2]
  unfold act
  simp [hno, hf]

/-- A closing event never opens an alert (a step never closes the alert it just opened). -/
theorem closer_no_post {e : Ev} {fs : List Flight} {opn : List String} (hc : closer e.event = true) :
    (act e fs opn).post = none := by
  cases hp : (act e fs opn).post with
  | none => rfl
  | some a =>
    exfalso
    rcases post_event (e := e) (fs := fs) (opn := opn) (by simp [hp]) with h | h <;> simp [closer, h] at hc

/-! ## Examples -/

private def n1 : Ev := { event := "Notification", agentId := some "a1", agentType := some "builder", tool := some "Bash",
                         ntype := some "permission_prompt", ts := 10 }

#guard kindOf n1 == some .permission
#guard kindOf { n1 with ntype := some "agent_needs_input" } == some .needsInput
#guard kindOf { n1 with ntype := none } == some .needsInput
#guard kindOf { n1 with ntype := some "idle_prompt" } == none
#guard kindOf { event := "StopFailure" } == some .stopFailure
#guard kindOf { event := "PostToolUse" } == none
#guard stepId (some "a1") 10 == "alert-a1-10"
#guard stepId none 7 == "alert-main-7"
#guard stepId (some "a-b.c") 7 == "alert-a_b_c-7"
#guard parse "alert-a1-10" == some ("a1", 10)
#guard parse "alert-hash0123456789" == none
#guard parse "step-1" == none
#guard (act n1 [] []).post.map (·.title) == some "A helper needs your permission"
#guard (act n1 [] []).post.map (·.audience) == some .user
#guard (act n1 [] []).post.map (·.body) == some
  ("What happened: The helper \"builder\" asked to use Bash and is paused until it gets an answer.\n" ++
   "Impact: Nothing is lost. It continues as soon as you answer.\n" ++
   "What you do: Open the Claude Code terminal and answer its prompt (allow or deny). This step closes by itself when the helper continues.\n" ++
   "Details: agent builder; tool Bash; hook Notification permission_prompt")
#guard (act { n1 with ntype := some "agent_needs_input" } [] []).post.map (·.audience) == some .user
-- a helper's API stop is the lead's; the lead session's own stop is the owner's
#guard (act { event := "StopFailure", agentId := some "a1", agentType := some "builder", ts := 4 } [] []).post.map (·.audience)
  == some .lead
#guard (act { event := "StopFailure", agentId := some "a1", agentType := some "builder", ts := 4 } [] []).post.map (·.body) == some
  ("What happened: The helper \"builder\" stopped because the model API failed.\n" ++
   "Impact: Its committed work and handoff note are kept. It does nothing until it is restarted.\n" ++
   "Action (lead): Restart it from its handoff note. This step closes by itself when the helper runs again.\n" ++
   "Details: agent builder; hook StopFailure")
#guard (act { event := "StopFailure", ts := 4 } [] []).post.map (·.audience) == some .user
#guard (act { event := "StopFailure", ts := 4 } [] []).post.map (·.title) == some "The lead session stopped on an API error"
-- a step posted before steps carried an audience: the spool alert is the lead's, anything else the owner's
#guard legacyAudience "alert-spool-1792389046068" == .lead
#guard legacyAudience "alert-a1-10" == .user
#guard legacyAudience "alert-main-7" == .user
#guard legacyAudience "web-1234abcd" == .user
#guard (act n1 [] []).post.map (·.step) == some "alert-a1-10"
#guard (act n1 [] ["alert-a1-3"]).post == none
#guard (act n1 [] ["alert-a2-3"]).post.isSome
-- the lead's own Notification: no agent_id, nothing in flight
#guard (act { n1 with agentId := none, agentType := none } [] []).post == none
-- no agent_id: attributed to the single agent with a tool in flight
#guard (act { n1 with agentId := none, agentType := none } [{ agentId := some "a1", agentType := some "builder", tool := some "Bash" }] []).post.map (·.step)
  == some "alert-a1-10"
-- ... but not when the lead has a tool of its own in flight, or two agents are in flight
#guard (act { n1 with agentId := none, agentType := none } [{ agentId := some "a1", tool := some "Bash" }, { tool := some "Read" }] []).post == none
#guard (act { n1 with agentId := none, agentType := none } [{ agentId := some "a1", tool := some "Bash" }, { agentId := some "a2", tool := some "Bash" }] []).post == none
-- the lead's waiting Agent call is no evidence against the single agent
#guard (act { n1 with agentId := none, agentType := none } [{ agentId := some "a1", tool := some "Bash" }, { tool := some "Agent" }] []).post.isSome
#guard (act { event := "StopFailure", agentId := some "a1", agentType := some "builder", ts := 4 } [] []).post.map (·.title)
  == some "A helper stopped on an API error"
#guard (act { event := "StopFailure", ts := 4 } [] []).post.map (·.step) == some "alert-main-4"
-- closing: same agent, later, closing event; other agents and older/equal ts stay open
#guard (act { event := "PostToolUse", agentId := some "a1", ts := 11 } [] ["alert-a1-10", "alert-a2-10", "alert-a1-11", "old-id"]).close
  == ["alert-a1-10"]
#guard (act { event := "PostToolUse", agentId := some "a1", ts := 10 } [] ["alert-a1-10"]).close == []
#guard (act { event := "PostToolUse", ts := 11 } [] ["alert-main-10"]).close == ["alert-main-10"]
#guard (act { event := "PreToolUse", agentId := some "a1", ts := 11 } [] ["alert-a1-10"]).close == []
#guard (act { event := "SubagentStop", agentId := some "a1", ts := 12 } [] ["alert-a1-10"]).close == ["alert-a1-10"]

end Fw.Console.Alert
