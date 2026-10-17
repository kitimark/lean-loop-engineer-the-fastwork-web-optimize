import Lean.Data.Json
/-!
# Topic lifecycle R → I → D → F → V → L (v1 fixes/LEAD.md "Stages and gates")
-/
namespace Fw.Stage

inductive Stage where
  | R | I | D | F | V | L
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

def Stage.idx : Stage → Nat
  | .R => 0 | .I => 1 | .D => 2 | .F => 3 | .V => 4 | .L => 5

def Stage.next : Stage → Option Stage
  | .R => some .I | .I => some .D | .D => some .F | .F => some .V | .V => some .L | .L => none

inductive Attribution where
  | named | located | unexplained
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

inductive Role where
  | owner | lead | reviewer
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The card that closes a stage. -/
structure Card where
  closes   : Stage
  signedBy : Role
  attribution : Option Attribution := none   -- only on the D card
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Gate: who may sign which stage, and D must be NAMED to open F. -/
def gateOk (c : Card) : Bool :=
  match c.closes with
  | .D => c.signedBy == .lead && c.attribution == some .named
  | .V => c.signedBy == .reviewer
  | .L => c.signedBy == .lead
  | _  => c.signedBy == .owner

structure Topic where
  stage : Stage := .R
  cards : List Card := []
deriving Repr, Lean.ToJson, Lean.FromJson

def advance (t : Topic) (c : Card) : Except String Topic :=
  if c.closes ≠ t.stage then .error "card closes another stage"
  else if !gateOk c then .error "gate not met"
  else match t.stage.next with
    | some s => .ok { stage := s, cards := c :: t.cards }
    | none   => .error "already landed"

/-- No stage is skipped: every successful advance moves exactly one stage. -/
theorem advance_one {t t' : Topic} {c : Card} (h : advance t c = .ok t') :
    t'.stage.idx = t.stage.idx + 1 := by
  unfold advance at h
  split at h; · cases h
  split at h; · cases h
  cases hs : t.stage <;> simp [hs, Stage.next] at h <;> (try subst h) <;> rfl

/-- A topic can only reach F through a lead-signed NAMED attribution card. -/
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
