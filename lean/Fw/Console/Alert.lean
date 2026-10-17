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
* **What it says.** The title names the agent (its type), the kind and, for a permission
  prompt, the tool.
* **When it closes.** The agent's next `PostToolUse`, `PostToolUseFailure`, `SubagentStop` or
  `Stop` that is later than the alert closes every open alert step of that agent.
* **Idempotent.** The step id is a function of agent and time, the command keys of the step
  and of its cancel are functions of the step id, and an agent with an open alert gets no
  second one.
-/

namespace Fw.Console.Alert

/-- The kind of an alert.

$$\mathrm{Kind} = \{\mathrm{permission}, \mathrm{needsInput}, \mathrm{stopFailure}\}$$
-/
inductive Kind where
  | permission | needsInput | stopFailure
deriving Repr, DecidableEq

/-- The wire name of a kind.

$$\operatorname{name}(k) = \texttt{"permission"}, \texttt{"needsInput"}, \texttt{"stopFailure"} \text{ for } k = \mathrm{permission}, \mathrm{needsInput}, \mathrm{stopFailure}$$
-/
def Kind.name : Kind → String
  | .permission => "permission" | .needsInput => "needsInput" | .stopFailure => "stopFailure"

/-- The hook facts the rule reads (`agentId = none` is the lead).

$$e = (\mathit{event}, \mathit{agent}_\bot, \mathit{type}_\bot, \mathit{tool}_\bot, \mathit{ntype}_\bot, \mathit{ts}) \in \mathrm{String} \times \mathrm{String}_\bot \times \mathrm{String}_\bot \times \mathrm{String}_\bot \times \mathrm{String}_\bot \times \mathbb{N}$$
-/
structure Ev where
  event : String
  agentId : Option String := none
  agentType : Option String := none
  tool : Option String := none
  ntype : Option String := none
  ts : Nat := 0
deriving Repr, DecidableEq

/-- A tool call in flight (`agentId = none` is the lead).

$$f = (\mathit{agent}_\bot, \mathit{type}_\bot, \mathit{tool}_\bot)$$
-/
structure Flight where
  agentId : Option String := none
  agentType : Option String := none
  tool : Option String := none
deriving Repr, DecidableEq

/-- The kind of alert an event opens, if any.

$$\operatorname{kindOf}(e) = \begin{cases} \mathrm{stopFailure} & e.\mathit{event} = \texttt{StopFailure} \\ \mathrm{permission} & e.\mathit{event} = \texttt{Notification} \land e.\mathit{ntype} = \texttt{permission\_prompt} \\ \mathrm{needsInput} & e.\mathit{event} = \texttt{Notification} \land (e.\mathit{ntype} = \bot \lor e.\mathit{ntype} = \texttt{agent\_needs\_input}) \\ \bot & \text{otherwise} \end{cases}$$
-/
def kindOf (e : Ev) : Option Kind :=
  if e.event == "StopFailure" then some .stopFailure
  else if e.event == "Notification" then
    match e.ntype with
    | some "permission_prompt" => some .permission
    | some "agent_needs_input" => some .needsInput
    | none => some .needsInput
    | some _ => none
  else none

/-- Events that end an agent's wait: its next tool result or answer.

$$\operatorname{closer}(\mathit{ev}) \iff \mathit{ev} \in \{\texttt{PostToolUse}, \texttt{PostToolUseFailure}, \texttt{SubagentStop}, \texttt{Stop}\}$$
-/
def closer (ev : String) : Bool :=
  ev == "PostToolUse" || ev == "PostToolUseFailure" || ev == "SubagentStop" || ev == "Stop"

/-- Who a `Notification` without `agent_id` belongs to: the single agent with a tool in flight,
and only when the lead has no tool in flight other than the `Agent` call waiting for it.

$$\operatorname{attrib}(\mathit{fs}) = \begin{cases} \bot & \exists f \in \mathit{fs}:\ f.\mathit{agent} = \bot \land f.\mathit{tool} \ne \texttt{Agent} \\ f_1 & \text{else if } F_a = f_1 :: R \text{ and } \forall g \in R:\ g.\mathit{agent} = f_1.\mathit{agent} \\ \bot & \text{otherwise} \end{cases},\quad \text{where } F_a = [\, f \in \mathit{fs} \mid f.\mathit{agent} \ne \bot \,] \text{ is the list of agent flights in the order of } \mathit{fs} \text{ (cases are tried first match first)}$$
-/
def attrib (fs : List Flight) : Option Flight :=
  if fs.any (fun f => f.agentId.isNone && f.tool != some "Agent") then none
  else match fs.filter (fun f => f.agentId.isSome) with
    | [] => none
    | f :: rest => if rest.all (fun g => g.agentId == f.agentId) then some f else none

/-- An attributed Notification names an agent and no other candidate exists.

$$\forall \mathit{fs}, f:\ \operatorname{attrib}(\mathit{fs}) = f \Rightarrow f \in \mathit{fs} \land f.\mathit{agent} \ne \bot \land (\forall g \in \mathit{fs}:\ g.\mathit{agent} \ne \bot \Rightarrow g.\mathit{agent} = f.\mathit{agent}) \land (\forall g \in \mathit{fs}:\ g.\mathit{agent} = \bot \Rightarrow g.\mathit{tool} = \texttt{Agent})$$
-/
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

$$\forall \mathit{fs}:\ \left(\forall g \in \mathit{fs}:\ g.\mathit{agent} = \bot\right) \Rightarrow \operatorname{attrib}(\mathit{fs}) = \bot$$
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

$$\operatorname{slugChar}(c) = \begin{cases} c & c \in \{\texttt{A}..\texttt{Z}, \texttt{a}..\texttt{z}, \texttt{0}..\texttt{9}, \texttt{\_}\} \\ \texttt{\_} & \text{otherwise} \end{cases}$$
-/
def slugChar (c : Char) : Char := if c.isAlphanum || c == '_' then c else '_'

/-- The slug of an agent id: `main` for the lead, else the first 40 characters made safe.

$$\operatorname{slug}(\bot) = \texttt{main};\quad \operatorname{slug}(a) = \operatorname{map}(\operatorname{slugChar}, \operatorname{take}(40, a)) \text{ (and } \texttt{\_} \text{ if } a \text{ is empty)}$$
-/
def slug : Option String → String
  | none => "main"
  | some a => if a.isEmpty then "_" else String.ofList ((a.toList.take 40).map slugChar)

/-- The step id of an alert of `agent` raised at hook time `t`.

$$\operatorname{stepId}(a, t) = \texttt{alert-} \cdot \operatorname{slug}(a) \cdot \texttt{-} \cdot t$$
-/
def stepId (a : Option String) (t : Nat) : String := "alert-" ++ slug a ++ "-" ++ toString t

/-- The characters up to the first `-` and those after it; a list without `-` is all left part.

$$\operatorname{cut}(\ell \cdot \texttt{-} \cdot r) = (\ell, r) \text{ for } \ell \text{ without } \texttt{-};\quad \operatorname{cut}(\ell) = (\ell, [\,]) \text{ for } \ell \text{ without } \texttt{-}$$
-/
def cut : List Char → List Char × List Char
  | [] => ([], [])
  | c :: cs => if c == '-' then ([], cs) else let r := cut cs; (c :: r.1, r.2)

/-- The number a list of decimal digit characters spells (most significant first).

$$\operatorname{decode}([d_1,\dots,d_k]) = \sum_i d_i \cdot 10^{k-i}$$
-/
def decode (l : List Char) : Nat := l.foldl (fun a c => a * 10 + (c.toNat - 48)) 0

/-- The slug and time inside an alert step id (`none` for any other id).

$$\operatorname{parse}(\texttt{alert-} \cdot s \cdot \texttt{-} \cdot t) = (s, t) \text{ for } s \text{ without } \texttt{-} \text{ and } t \text{ decimal; } \operatorname{parse}(\mathit{id}) = \bot \text{ otherwise}$$
-/
def parse (id : String) : Option (String × Nat) :=
  match id.toList with
  | 'a' :: 'l' :: 'e' :: 'r' :: 't' :: '-' :: rest =>
    let r := cut rest
    if r.2 != [] && r.2.all Char.isDigit then some (String.ofList r.1, decode r.2) else none
  | _ => none

/-- A decimal digit character reads back as its value.

$$\forall k < 10:\quad \operatorname{ord}(\operatorname{digit}(k)) - 48 = k$$
-/
theorem digit_val : ∀ k, k < 10 → (Nat.digitChar k).toNat - 48 = k := by decide

/-- Decoding the decimal digits of $n$ gives $n$.

$$\forall n:\quad \operatorname{decode}(\operatorname{toDigits}_{10}(n)) = n$$
-/
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

/-- Cutting after a dash-free prefix returns the prefix and the rest.

$$\forall \ell, r:\ (\forall c \in \ell:\ c \ne \texttt{-}) \Rightarrow \operatorname{cut}(\ell \cdot \texttt{-} \cdot r) = (\ell, r)$$
-/
theorem cut_append {l : List Char} (h : ∀ c ∈ l, c ≠ '-') (r : List Char) :
    cut (l ++ '-' :: r) = (l, r) := by
  induction l with
  | nil => simp [cut]
  | cons c cs ih =>
    have hc : c ≠ '-' := h c (by simp)
    have := ih (fun x hx => h x (by simp [hx]))
    simp [cut, hc, this]

/-- A slug never contains the separator `-`.

$$\forall a, \forall c \in \operatorname{slug}(a):\quad c \ne \texttt{-}$$
-/
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

/-- The id of an alert reads back as its agent slug and time.

$$\forall a, t:\quad \operatorname{parse}(\operatorname{stepId}(a, t)) = (\operatorname{slug}(a), t)$$
-/
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

/-- An alert step to post.

$$\mathrm{Alert} = (\mathit{step}, \mathit{key}, \mathit{title}, \mathit{kind}, \mathit{agent})$$
-/
structure Alert where
  step : String
  key : String
  title : String
  kind : Kind
  agent : String
deriving Repr, DecidableEq

/-- What the drain does for one event: post at most one alert step, cancel some open ones.

$$\mathrm{Out} = (\mathit{post}_\bot : \mathrm{Alert}_\bot,\ \mathit{close} : [\mathrm{String}])$$
-/
structure Out where
  post : Option Alert := none
  close : List String := []
deriving Repr, DecidableEq

private def clip (n : Nat) (s : String) : String := String.ofList (s.toList.take n)

/-- The title of an alert: names the agent (its type), the kind and the tool.

$$\operatorname{title}(k, \mathit{who}, \mathit{tool}) = \begin{cases} \text{“Agent } w \text{ asks permission to use } u \text{: answer its prompt in the Claude Code terminal, then press Done”} & k = \mathrm{permission} \\ \text{“Agent } w \text{ needs your input: answer it in the Claude Code terminal, then press Done”} & k = \mathrm{needsInput} \\ \text{“Agent } w \text{ stopped on an API failure; the lead restarts it from its handoff”} & k = \mathrm{stopFailure} \end{cases},\quad \text{where } w = \operatorname{clip}_{60}(\mathit{who}),\ u = \begin{cases} \operatorname{clip}_{40}(\mathit{tool}) & \mathit{tool} \ne \bot \\ \operatorname{clip}_{40}(\text{“a tool”}) & \mathit{tool} = \bot \end{cases},\ \operatorname{clip}_n(s) = \text{the first } n \text{ characters of } s \text{ (all of } s \text{ if it is shorter)}$$
-/
def title (k : Kind) (who : String) (tool : Option String) : String :=
  let w := clip 60 who
  match k with
  | .permission => s!"Agent {w} asks permission to use {clip 40 (tool.getD "a tool")}: answer its prompt in the Claude Code terminal, then press Done"
  | .needsInput => s!"Agent {w} needs your input: answer it in the Claude Code terminal, then press Done"
  | .stopFailure => s!"Agent {w} stopped on an API failure; the lead restarts it from its handoff"

/-- The agent an event opens an alert for: its own `agent_id` (`StopFailure` of the lead is the
lead's); a `Notification` without one only when attributable. Returns (agent id, agent type, tool).

$$\operatorname{subject}(e, \mathit{fs}) = \begin{cases} (e.\mathit{agent}, e.\mathit{type}, e.\mathit{tool}) & e.\mathit{agent} \ne \bot \lor e.\mathit{event} = \texttt{StopFailure} \\ (f.\mathit{agent}, f.\mathit{type}, e.\mathit{tool}) & e.\mathit{agent} = \bot \land e.\mathit{event} \ne \texttt{StopFailure} \land \operatorname{attrib}(\mathit{fs}) = f \\ \bot & \text{otherwise} \end{cases}$$
-/
def subject (e : Ev) (fs : List Flight) : Option (Option String × Option String × Option String) :=
  if e.agentId.isSome || e.event == "StopFailure" then some (e.agentId, e.agentType, e.tool)
  else match attrib fs with
    | some f => some (f.agentId, f.agentType, e.tool)
    | none => none

/-- The agent slug an open alert step belongs to (`none` for a step that is no alert).

$$\operatorname{owner}(\mathit{id}) = s \text{ if } \operatorname{parse}(\mathit{id}) = (s, \cdot);\ \bot \text{ otherwise}$$
-/
def owner (id : String) : Option String := (parse id).map (·.1)

/-- Does event `e` close the open alert step `id`: same agent, a closing event, strictly later
than the alert.

$$\operatorname{closes}(e, \mathit{id}) \iff \operatorname{closer}(e.\mathit{event}) \land \exists t:\ \operatorname{parse}(\mathit{id}) = (\operatorname{slug}(e.\mathit{agent}), t) \land t < e.\mathit{ts}$$
-/
def closes (e : Ev) (id : String) : Bool :=
  closer e.event && match parse id with
    | some (s, t) => s == slug e.agentId && decide (t < e.ts)
    | none => false

/-- The decision for one event, given the tool calls in flight and the ids of the alert steps
still open on the board.

$$\operatorname{act}(e, \mathit{fs}, \mathit{opn}) = (\mathit{post}, \mathit{close}),\quad \mathit{close} = [\, \mathit{id} \in \mathit{opn} \mid \operatorname{closes}(e, \mathit{id}) \,]$$
$$\mathit{post} = \begin{cases} (s, \texttt{alert:} \cdot s, \operatorname{title}(k, \tau, \mathit{tool}), k, \operatorname{slug}(a)) & \operatorname{kindOf}(e) = k \land \operatorname{subject}(e, \mathit{fs}) = (a, \mathit{ty}, \mathit{tool}) \land \neg \exists \mathit{id} \in \mathit{opn}:\ \operatorname{owner}(\mathit{id}) = \operatorname{slug}(a) \\ \bot & \text{otherwise} \end{cases},\quad \text{where } s = \operatorname{stepId}(a, e.\mathit{ts}),\ \tau = \begin{cases} \mathit{ty} & \mathit{ty} \ne \bot \\ \texttt{main} & \mathit{ty} = \bot \end{cases}$$
-/
def act (e : Ev) (fs : List Flight) (opn : List String) : Out :=
  let close := opn.filter (closes e)
  match kindOf e, subject e fs with
  | some k, some (a, ty, tool) =>
    if opn.any (fun id => owner id == some (slug a)) then { close }
    else
      let id := stepId a e.ts
      { post := some { step := id, key := "alert:" ++ id, title := title k (ty.getD "main") tool, kind := k, agent := slug a },
        close }
  | _, _ => { close }

/-- The key of the command that cancels alert step `id` (one per step, so a repeat is a duplicate).

$$\operatorname{closeKey}(\mathit{id}) = \texttt{alert-close:} \cdot \mathit{id}$$
-/
def closeKey (id : String) : String := "alert-close:" ++ id

/-- Only a `StopFailure` or a `Notification` ever opens an alert.

$$\forall e, \mathit{fs}, \mathit{opn}:\ \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{post} \ne \bot \Rightarrow e.\mathit{event} \in \{\texttt{StopFailure}, \texttt{Notification}\}$$
-/
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

/-- The lead's own Notification (no `agent_id`, nothing but the lead in flight) opens no alert.

$$\forall e, \mathit{fs}, \mathit{opn}:\ e.\mathit{event} = \texttt{Notification} \land e.\mathit{agent} = \bot \land (\forall g \in \mathit{fs}:\ g.\mathit{agent} = \bot) \Rightarrow \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{post} = \bot$$
-/
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

$$\forall e, \mathit{fs}, \mathit{opn}, a:\ \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{post} = a \Rightarrow \exists x:\ \operatorname{subject}(e, \mathit{fs}) = x \land a.\mathit{step} = \operatorname{stepId}(x.\mathit{agent}, e.\mathit{ts}) \land a.\mathit{agent} = \operatorname{slug}(x.\mathit{agent}) \land a.\mathit{key} = \texttt{alert:} \cdot a.\mathit{step} \land \operatorname{kindOf}(e) = a.\mathit{kind}$$
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

/-- No second alert is posted for an agent that already has one open.

$$\forall e, \mathit{fs}, \mathit{opn}, x:\ \left(\exists \mathit{id} \in \mathit{opn}:\ \operatorname{owner}(\mathit{id}) = \operatorname{slug}(x.\mathit{agent})\right) \land \operatorname{subject}(e, \mathit{fs}) = x \Rightarrow \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{post} = \bot$$
-/
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

/-- Everything closed is an open alert of the agent of the event, closed by a closing event.

$$\forall e, \mathit{fs}, \mathit{opn}, s:\ s \in \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{close} \Rightarrow s \in \mathit{opn} \land \operatorname{owner}(s) = \operatorname{slug}(e.\mathit{agent}) \land \operatorname{closer}(e.\mathit{event})$$
-/
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

$$\forall e, \mathit{fs}, \mathit{opn}, t:\ \operatorname{closer}(e.\mathit{event}) \land t < e.\mathit{ts} \land \operatorname{stepId}(e.\mathit{agent}, t) \in \mathit{opn} \Rightarrow \operatorname{stepId}(e.\mathit{agent}, t) \in \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{close}$$
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

/-- A closing event never opens an alert (a step never closes the alert it just opened).

$$\forall e, \mathit{fs}, \mathit{opn}:\ \operatorname{closer}(e.\mathit{event}) \Rightarrow \operatorname{act}(e, \mathit{fs}, \mathit{opn}).\mathit{post} = \bot$$
-/
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
#guard (act n1 [] []).post.map (·.title) ==
  some "Agent builder asks permission to use Bash: answer its prompt in the Claude Code terminal, then press Done"
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
  == some "Agent builder stopped on an API failure; the lead restarts it from its handoff"
#guard (act { event := "StopFailure", ts := 4 } [] []).post.map (·.step) == some "alert-main-4"
-- closing: same agent, later, closing event; other agents and older/equal ts stay open
#guard (act { event := "PostToolUse", agentId := some "a1", ts := 11 } [] ["alert-a1-10", "alert-a2-10", "alert-a1-11", "old-id"]).close
  == ["alert-a1-10"]
#guard (act { event := "PostToolUse", agentId := some "a1", ts := 10 } [] ["alert-a1-10"]).close == []
#guard (act { event := "PostToolUse", ts := 11 } [] ["alert-main-10"]).close == ["alert-main-10"]
#guard (act { event := "PreToolUse", agentId := some "a1", ts := 11 } [] ["alert-a1-10"]).close == []
#guard (act { event := "SubagentStop", agentId := some "a1", ts := 12 } [] ["alert-a1-10"]).close == ["alert-a1-10"]

end Fw.Console.Alert
