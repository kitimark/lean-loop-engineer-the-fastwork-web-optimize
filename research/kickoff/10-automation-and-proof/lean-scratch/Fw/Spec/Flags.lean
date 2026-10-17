import Lean.Data.Json
/-!
# Part variants (feature flags) of the rewritten page

A configuration is a *total function* `Part → Variant`: "every part resolves to exactly one
variant" holds by construction, so there is nothing to test for it. What remains decidable and
checked: every chosen variant exists, and the registry's requires/conflicts rules hold.
-/
namespace Fw.Flags

inductive Part where
  | nav | hero | categories | carousel | countdown | footer
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

def Part.all : List Part := [.nav, .hero, .categories, .carousel, .countdown, .footer]
theorem Part.mem_all (p : Part) : p ∈ Part.all := by cases p <;> simp [Part.all]

abbrev Variant := String
abbrev Config := Part → Variant

inductive Rule where
  | requires  (p : Part) (v : Variant) (q : Part) (w : Variant)  -- p = v → q = w
  | conflicts (p : Part) (v : Variant) (q : Part) (w : Variant)  -- ¬ (p = v ∧ q = w)
deriving Repr, Lean.ToJson, Lean.FromJson

def Rule.holds (c : Config) : Rule → Bool
  | .requires p v q w  => c p != v || c q == w
  | .conflicts p v q w => !(c p == v && c q == w)

structure Registry where
  variants : Part → List Variant      -- allowed variants, head = default
  rules    : List Rule

def Config.ok (r : Registry) (c : Config) : Bool :=
  Part.all.all (fun p => (r.variants p).contains (c p)) && r.rules.all (·.holds c)

def defaults (r : Registry) : Config := fun p => (r.variants p).headD "orig"

def override (c : Config) (p : Part) (v : Variant) : Config := fun q => if q = p then v else c q

/-- Resolve a request (defaults, then overrides in order); `ok` only if the result is valid. -/
def resolve (r : Registry) (req : List (Part × Variant)) : Except String Config :=
  check r (req.foldl (fun c (p, v) => override c p v) (defaults r))
where
  check (r : Registry) (c : Config) : Except String Config :=
    if c.ok r then .ok c else .error "invalid configuration"

theorem resolve_sound {r : Registry} {req : List (Part × Variant)} {c : Config}
    (h : resolve r req = .ok c) : c.ok r = true := by
  unfold resolve resolve.check at h
  split at h
  · cases h; assumption
  · cases h

/-- The parts on which two configurations differ. -/
def diff (a b : Config) : List Part := Part.all.filter (fun p => a p != b p)

/-- A/B isolation: overriding one part yields a pair that differs in exactly that part
(the v1 "mechanism check: the arm removed exactly the named thing", by construction). -/
theorem override_diff (c : Config) (p : Part) (v : Variant) (h : c p ≠ v) :
    diff c (override c p v) = [p] := by
  cases p <;> simp [diff, override, Part.all, h]

end Fw.Flags
