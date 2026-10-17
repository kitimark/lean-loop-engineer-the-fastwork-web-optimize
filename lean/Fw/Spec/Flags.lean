import Lean.Data.Json
/-!
# Part variants (feature flags) of the rewritten page

A configuration is a *total function* `Part → Variant`: "every part resolves to exactly one
variant" holds by construction, so there is nothing to test for it. What remains decidable and
checked: every chosen variant exists, and the registry's requires/conflicts rules hold.
-/
namespace Fw.Flags

/-- The six parts of the page that can be switched between variants.

$$\mathrm{Part} = \{\mathrm{nav}, \mathrm{hero}, \mathrm{categories}, \mathrm{carousel}, \mathrm{countdown}, \mathrm{footer}\}$$
-/
inductive Part where
  | nav | hero | categories | carousel | countdown | footer
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The parts as a list, in a fixed order.

$$\mathrm{Part.all} = [\mathrm{nav}, \mathrm{hero}, \mathrm{categories}, \mathrm{carousel}, \mathrm{countdown}, \mathrm{footer}]$$
-/
def Part.all : List Part := [.nav, .hero, .categories, .carousel, .countdown, .footer]

/-- The list of parts is complete: every part is in it.

$$\forall p \in \mathrm{Part}:\quad p \in \mathrm{Part.all}$$
-/
theorem Part.mem_all (p : Part) : p ∈ Part.all := by cases p <;> simp [Part.all]

/-- A variant is named by a string.

$$\mathrm{Variant} = \text{strings}$$
-/
abbrev Variant := String

/-- A configuration picks exactly one variant for every part (by its type: a total function).

$$\mathrm{Config} = \mathrm{Variant}^{\mathrm{Part}} = \{\, c \mid c : \mathrm{Part} \to \mathrm{Variant} \,\}$$
-/
abbrev Config := Part → Variant

/-- A registry rule between two parts: a requirement or a conflict.

$$\mathrm{Rule} = \mathrm{requires}(p, v, q, w) \mid \mathrm{conflicts}(p, v, q, w), \qquad p, q \in \mathrm{Part},\ v, w \in \mathrm{Variant}$$
-/
inductive Rule where
  | requires  (p : Part) (v : Variant) (q : Part) (w : Variant)  -- p = v → q = w
  | conflicts (p : Part) (v : Variant) (q : Part) (w : Variant)  -- ¬ (p = v ∧ q = w)
deriving Repr, Lean.ToJson, Lean.FromJson

/-- A rule holds in a configuration: "if part $p$ uses $v$ then part $q$ uses $w$", or
"$p = v$ and $q = w$ never together".

$$\operatorname{holds}_c\big(\mathrm{requires}(p, v, q, w)\big) = \mathrm{true} \iff \big(c(p) = v \Rightarrow c(q) = w\big)$$

$$\operatorname{holds}_c\big(\mathrm{conflicts}(p, v, q, w)\big) = \mathrm{true} \iff \neg\big(c(p) = v \land c(q) = w\big)$$
-/
def Rule.holds (c : Config) : Rule → Bool
  | .requires p v q w  => c p != v || c q == w
  | .conflicts p v q w => !(c p == v && c q == w)

#guard (Rule.requires .hero "v2" .nav "v2").holds (fun _ => "orig")
#guard !(Rule.requires .hero "v2" .nav "v2").holds (fun p => if p = .hero then "v2" else "orig")
#guard !(Rule.conflicts .hero "v2" .nav "v2").holds (fun _ => "v2")
#guard (Rule.conflicts .hero "v2" .nav "v2").holds (fun p => if p = .hero then "v2" else "orig")

/-- A registry lists the allowed variants per part (the head is the default) and the rules.

$$r = (\mathit{variants} : \mathrm{Part} \to \mathrm{Variant}^{*},\ \ \mathit{rules} : \mathrm{Rule}^{*})$$
-/
structure Registry where
  variants : Part → List Variant      -- allowed variants, head = default
  rules    : List Rule

/-- A configuration is valid when every chosen variant is registered for its part and every rule
holds.

$$\operatorname{ok}_r(c) = \mathrm{true} \iff \big(\forall p \in \mathrm{Part.all}:\ c(p) \in r.\mathit{variants}(p)\big) \ \land\ \big(\forall \rho \in r.\mathit{rules}:\ \operatorname{holds}_c(\rho)\big)$$

Edge: the check runs over the list $\mathrm{Part.all}$, which equals $\mathrm{Part}$ by
`Part.mem_all`; if $r.\mathit{variants}(p) = [\,]$ for some $p$, no configuration is ok.
-/
def Config.ok (r : Registry) (c : Config) : Bool :=
  Part.all.all (fun p => (r.variants p).contains (c p)) && r.rules.all (·.holds c)

#guard Config.ok { variants := fun _ => ["orig"], rules := [] } (fun _ => "orig")
#guard !Config.ok { variants := fun _ => ["orig"], rules := [] } (fun _ => "v2")
#guard !Config.ok { variants := fun _ => [], rules := [] } (fun _ => "orig")

/-- The default configuration takes the first registered variant of each part, or `"orig"` when
none is registered.

$$\operatorname{defaults}_r(p) = \begin{cases} v_1 & \text{if } r.\mathit{variants}(p) = [v_1, \dots] \\ \texttt{"orig"} & \text{if } r.\mathit{variants}(p) = [\,] \end{cases}$$
-/
def defaults (r : Registry) : Config := fun p => (r.variants p).headD "orig"

/-- Override one part of a configuration (function update).

$$\operatorname{override}(c, p, v) = c[p \mapsto v], \qquad c[p \mapsto v](q) = \begin{cases} v & q = p \\ c(q) & q \ne p \end{cases}$$
-/
def override (c : Config) (p : Part) (v : Variant) : Config := fun q => if q = p then v else c q

/-- Resolve a request: start from the defaults, apply the overrides left to right, and accept the
result only if it is valid.

$$c^{\star} = \operatorname{defaults}_r[p_1 \mapsto v_1]\cdots[p_n \mapsto v_n], \qquad \operatorname{resolve}(r, [(p_1, v_1), \dots, (p_n, v_n)]) = \begin{cases} \mathrm{ok}(c^{\star}) & \text{if } \operatorname{ok}_r(c^{\star}) \\ \mathrm{error}(\texttt{"invalid configuration"}) & \text{otherwise} \end{cases}$$

Edge: for a part requested twice the last request wins; an empty request gives the defaults.
-/
def resolve (r : Registry) (req : List (Part × Variant)) : Except String Config :=
  check r (req.foldl (fun c (p, v) => override c p v) (defaults r))
where
  /-- Accept a configuration only if it is valid.

  $$\operatorname{check}(r, c) = \begin{cases} \mathrm{ok}(c) & \text{if } \operatorname{ok}_r(c) \\ \mathrm{error}(\texttt{"invalid configuration"}) & \text{otherwise} \end{cases}$$
  -/
  check (r : Registry) (c : Config) : Except String Config :=
    if c.ok r then .ok c else .error "invalid configuration"

#guard
  let r : Registry := { variants := fun p => if p = .hero then ["v2", "orig"] else ["orig"], rules := [] }
  (match resolve r [(.hero, "orig"), (.hero, "v2")] with | .ok c => c .hero == "v2" | .error _ => false)
  && (match resolve r [(.hero, "v3")] with | .ok _ => false | .error _ => true)
  && (match resolve r [(.hero, "v3"), (.hero, "v2")] with | .ok c => c .hero == "v2" | .error _ => false)
  && (match resolve r [] with | .ok c => c .hero == "v2" | .error _ => false)

/-- Whatever `resolve` returns is a valid configuration.

$$\operatorname{resolve}(r, \mathit{req}) = \mathrm{ok}(c) \;\Rightarrow\; \operatorname{ok}_r(c) = \mathrm{true}$$
-/
theorem resolve_sound {r : Registry} {req : List (Part × Variant)} {c : Config}
    (h : resolve r req = .ok c) : c.ok r = true := by
  unfold resolve resolve.check at h
  split at h
  · cases h; assumption
  · cases h

/-- The parts on which two configurations differ, in the order of `Part.all`.

$$\operatorname{diff}(a, b) = [\, p \in \mathrm{Part.all} \mid a(p) \ne b(p) \,]$$
-/
def diff (a b : Config) : List Part := Part.all.filter (fun p => a p != b p)

/-- A/B isolation: overriding one part to a different value yields a pair that differs in exactly
that part (the v1 "mechanism check: the arm removed exactly the named thing", by construction).

$$\forall c \in \mathrm{Config},\ p \in \mathrm{Part},\ v \in \mathrm{Variant}:\quad c(p) \ne v \;\Rightarrow\; \operatorname{diff}\big(c,\ c[p \mapsto v]\big) = [p]$$
-/
theorem override_diff (c : Config) (p : Part) (v : Variant) (h : c p ≠ v) :
    diff c (override c p v) = [p] := by
  cases p <;> simp [diff, override, Part.all, h]

end Fw.Flags
