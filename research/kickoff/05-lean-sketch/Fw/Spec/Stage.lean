import Lean.Data.Json
/-!
# Topic lifecycle R → I → D → F → V → L (v1 fixes/LEAD.md "Stages and gates")
-/
namespace Fw.Stage

/-- The six stages of a topic, in order.

$$\mathrm{Stage} = \{R, I, D, F, V, L\}$$
-/
inductive Stage where
  | R | I | D | F | V | L
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The position of a stage, from 0 to 5.

$$\operatorname{idx}(R, I, D, F, V, L) = (0, 1, 2, 3, 4, 5)$$
-/
def Stage.idx : Stage → Nat
  | .R => 0 | .I => 1 | .D => 2 | .F => 3 | .V => 4 | .L => 5

/-- The stage after a given one; $L$ has none.

$$\operatorname{next}: R \mapsto I,\ I \mapsto D,\ D \mapsto F,\ F \mapsto V,\ V \mapsto L,\ L \mapsto \bot$$
-/
def Stage.next : Stage → Option Stage
  | .R => some .I | .I => some .D | .D => some .F | .F => some .V | .V => some .L | .L => none

/-- How well the D stage explained the cause.

$$\mathrm{Attribution} = \{\mathrm{named}, \mathrm{located}, \mathrm{unexplained}\}$$
-/
inductive Attribution where
  | named | located | unexplained
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- Who signs a card.

$$\mathrm{Role} = \{\mathrm{owner}, \mathrm{lead}, \mathrm{reviewer}\}$$
-/
inductive Role where
  | owner | lead | reviewer
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The card that closes a stage: the stage, the signer, and (on the D card) the attribution.

$$\mathrm{Card} = \mathrm{Stage} \times \mathrm{Role} \times \mathrm{Attribution}_\bot, \qquad c = (c.\mathit{closes},\ c.\mathit{signedBy},\ c.\mathit{attribution}),\ c.\mathit{attribution} = \bot \text{ by default}$$
-/
structure Card where
  closes   : Stage
  signedBy : Role
  attribution : Option Attribution := none   -- only on the D card
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Gate: who may sign which stage, and D must be NAMED to open F.

$$\operatorname{gateOk}(c) = \mathrm{true} \iff \begin{cases} c.\mathit{signedBy} = \mathrm{lead} \ \land\ c.\mathit{attribution} = \mathrm{named} & \text{if } c.\mathit{closes} = D \\ c.\mathit{signedBy} = \mathrm{reviewer} & \text{if } c.\mathit{closes} = V \\ c.\mathit{signedBy} = \mathrm{lead} & \text{if } c.\mathit{closes} = L \\ c.\mathit{signedBy} = \mathrm{owner} & \text{if } c.\mathit{closes} \in \{R, I, F\} \end{cases}$$
-/
def gateOk (c : Card) : Bool :=
  match c.closes with
  | .D => c.signedBy == .lead && c.attribution == some .named
  | .V => c.signedBy == .reviewer
  | .L => c.signedBy == .lead
  | _  => c.signedBy == .owner

#guard gateOk { closes := .D, signedBy := .lead, attribution := some .named }
#guard !gateOk { closes := .D, signedBy := .lead, attribution := some .located }
#guard !gateOk { closes := .D, signedBy := .owner, attribution := some .named }
#guard gateOk { closes := .V, signedBy := .reviewer } && !gateOk { closes := .V, signedBy := .lead }
#guard gateOk { closes := .L, signedBy := .lead } && gateOk { closes := .F, signedBy := .owner }

/-- A topic: its current stage and the cards that closed earlier stages (newest first).

$$\mathrm{Topic} = \mathrm{Stage} \times \mathrm{Card}^{*}, \qquad t_0 = (R, [\,])$$
-/
structure Topic where
  stage : Stage := .R
  cards : List Card := []
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Advance a topic with a card: the card must close the current stage and pass its gate, and the
topic moves one stage on; $L$ is terminal.

$$\operatorname{advance}(t, c) = \begin{cases} \mathrm{error}(\texttt{"card closes another stage"}) & \text{if } c.\mathit{closes} \ne t.\mathit{stage} \\ \mathrm{error}(\texttt{"gate not met"}) & \text{else if } \neg\operatorname{gateOk}(c) \\ \mathrm{ok}\big((s',\ c :: t.\mathit{cards})\big) & \text{else if } \operatorname{next}(t.\mathit{stage}) = s' \\ \mathrm{error}(\texttt{"already landed"}) & \text{otherwise (} t.\mathit{stage} = L \text{)} \end{cases}$$
-/
def advance (t : Topic) (c : Card) : Except String Topic :=
  if c.closes ≠ t.stage then .error "card closes another stage"
  else if !gateOk c then .error "gate not met"
  else match t.stage.next with
    | some s => .ok { stage := s, cards := c :: t.cards }
    | none   => .error "already landed"

#guard (match advance {} { closes := .R, signedBy := .owner } with
  | .ok t => t.stage == .I && t.cards.length == 1 | .error _ => false)
#guard (match advance {} { closes := .I, signedBy := .owner } with
  | .ok _ => "ok" | .error e => e) == "card closes another stage"
#guard (match advance { stage := .D } { closes := .D, signedBy := .lead, attribution := some .located } with
  | .ok _ => "ok" | .error e => e) == "gate not met"
#guard (match advance { stage := .L } { closes := .L, signedBy := .lead } with
  | .ok _ => "ok" | .error e => e) == "already landed"

/-- No stage is skipped: every successful advance moves exactly one stage.

$$\forall t, t' \in \mathrm{Topic},\ \forall c \in \mathrm{Card}:\quad \operatorname{advance}(t, c) = \mathrm{ok}(t') \;\Rightarrow\; \operatorname{idx}(t'.\mathit{stage}) = \operatorname{idx}(t.\mathit{stage}) + 1$$
-/
theorem advance_one {t t' : Topic} {c : Card} (h : advance t c = .ok t') :
    t'.stage.idx = t.stage.idx + 1 := by
  unfold advance at h
  split at h; · cases h
  split at h; · cases h
  cases hs : t.stage <;> simp [hs, Stage.next] at h <;> (try subst h) <;> rfl

/-- A single successful step into F is made only by a lead-signed card that closes D with a NAMED
attribution (about that one step; "every topic at F has such a card in its history" is not proved
here, gap G6 of the Lean-to-math note).

$$\forall t, t', c:\quad \operatorname{advance}(t, c) = \mathrm{ok}(t') \ \land\ t'.\mathit{stage} = F \;\Rightarrow\; c.\mathit{closes} = D \ \land\ c.\mathit{signedBy} = \mathrm{lead} \ \land\ c.\mathit{attribution} = \mathrm{named}$$
-/
theorem enter_F {t t' : Topic} {c : Card} (h : advance t c = .ok t') (hF : t'.stage = .F) :
    c.closes = .D ∧ c.signedBy = .lead ∧ c.attribution = some .named := by
  unfold advance at h
  split at h; · cases h
  rename_i hc
  split at h; · cases h
  rename_i hg
  have hc' : c.closes = t.stage := by simpa using hc
  cases hs : t.stage <;> simp [hs, Stage.next] at h <;> (try subst h) <;> simp_all [gateOk]

end Fw.Stage
