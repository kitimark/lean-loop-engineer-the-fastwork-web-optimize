import Lean.Data.Json
/-!
# Part variants (feature flags) of the rewritten page

A configuration is a *total function* `Part → Variant`: "every part resolves to exactly one
variant" holds by construction, so there is nothing to test for it. What remains decidable and
checked: every chosen variant exists, and the registry's requires/conflicts rules hold.
-/
namespace Fw.Flags

/-- The six parts of the page that can be switched between variants. -/
inductive Part where
  | nav | hero | categories | carousel | countdown | footer
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The parts as a list, in a fixed order. -/
def Part.all : List Part := [.nav, .hero, .categories, .carousel, .countdown, .footer]

/-- The list of parts is complete: every part is in it. -/
theorem Part.mem_all (p : Part) : p ∈ Part.all := by cases p <;> simp [Part.all]

/-- A variant is named by a string. -/
abbrev Variant := String

/-- A configuration picks exactly one variant for every part (by its type: a total function). -/
abbrev Config := Part → Variant

/-- A registry rule between two parts: a requirement or a conflict. -/
inductive Rule where
  | requires  (p : Part) (v : Variant) (q : Part) (w : Variant)  -- p = v → q = w
  | conflicts (p : Part) (v : Variant) (q : Part) (w : Variant)  -- ¬ (p = v ∧ q = w)
deriving Repr, Lean.ToJson, Lean.FromJson

/-- A rule holds in a configuration: "if part `p` uses `v` then part `q` uses `w`", or
"`p = v` and `q = w` never together".
-/
def Rule.holds (c : Config) : Rule → Bool
  | .requires p v q w  => c p != v || c q == w
  | .conflicts p v q w => !(c p == v && c q == w)

#guard (Rule.requires .hero "v2" .nav "v2").holds (fun _ => "orig")
#guard !(Rule.requires .hero "v2" .nav "v2").holds (fun p => if p = .hero then "v2" else "orig")
#guard !(Rule.conflicts .hero "v2" .nav "v2").holds (fun _ => "v2")
#guard (Rule.conflicts .hero "v2" .nav "v2").holds (fun p => if p = .hero then "v2" else "orig")

/-- A registry lists the allowed variants per part (the head is the default) and the rules. -/
structure Registry where
  variants : Part → List Variant      -- allowed variants, head = default
  rules    : List Rule

/-- A configuration is valid when every chosen variant is registered for its part and every rule
holds.

Edge: the check runs over the list `Part.all`, which equals `Part` by
`Part.mem_all`; if `r.variants(p) = []` for some `p`, no configuration is ok.
-/
def Config.ok (r : Registry) (c : Config) : Bool :=
  Part.all.all (fun p => (r.variants p).contains (c p)) && r.rules.all (·.holds c)

#guard Config.ok { variants := fun _ => ["orig"], rules := [] } (fun _ => "orig")
#guard !Config.ok { variants := fun _ => ["orig"], rules := [] } (fun _ => "v2")
#guard !Config.ok { variants := fun _ => [], rules := [] } (fun _ => "orig")

/-- The default configuration takes the first registered variant of each part, or `"orig"` when
none is registered.
-/
def defaults (r : Registry) : Config := fun p => (r.variants p).headD "orig"

/-- Override one part of a configuration (function update). -/
def override (c : Config) (p : Part) (v : Variant) : Config := fun q => if q = p then v else c q

/-- Resolve a request: start from the defaults, apply the overrides left to right, and accept the
result only if it is valid.

Edge: for a part requested twice the last request wins; an empty request gives the defaults.
-/
def resolve (r : Registry) (req : List (Part × Variant)) : Except String Config :=
  check r (req.foldl (fun c (p, v) => override c p v) (defaults r))
where
  /-- Accept a configuration only if it is valid. -/
  check (r : Registry) (c : Config) : Except String Config :=
    if c.ok r then .ok c else .error "invalid configuration"

#guard
  let r : Registry := { variants := fun p => if p = .hero then ["v2", "orig"] else ["orig"], rules := [] }
  (match resolve r [(.hero, "orig"), (.hero, "v2")] with | .ok c => c .hero == "v2" | .error _ => false)
  && (match resolve r [(.hero, "v3")] with | .ok _ => false | .error _ => true)
  && (match resolve r [(.hero, "v3"), (.hero, "v2")] with | .ok c => c .hero == "v2" | .error _ => false)
  && (match resolve r [] with | .ok c => c .hero == "v2" | .error _ => false)

/-- Whatever `resolve` returns is a valid configuration. -/
theorem resolve_sound {r : Registry} {req : List (Part × Variant)} {c : Config}
    (h : resolve r req = .ok c) : c.ok r = true := by
  unfold resolve resolve.check at h
  split at h
  · cases h; assumption
  · cases h

/-- The parts on which two configurations differ, in the order of `Part.all`. -/
def diff (a b : Config) : List Part := Part.all.filter (fun p => a p != b p)

/-- A/B isolation: overriding one part to a different value yields a pair that differs in exactly
that part (the v1 "mechanism check: the arm removed exactly the named thing", by construction).
-/
theorem override_diff (c : Config) (p : Part) (v : Variant) (h : c p ≠ v) :
    diff c (override c p v) = [p] := by
  cases p <;> simp [diff, override, Part.all, h]

end Fw.Flags
