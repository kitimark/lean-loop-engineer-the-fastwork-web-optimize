import Lean
/-!
# Reach over the environment: the closure the props lint and the math view share

Task `lfg-mathview-facts` moved these helpers out of `lean/scripts/PropsLint.lean` (task `lfg-props-shape`) so that
the props lint and the math-view facts (`Fw.Spec.MathFacts`) follow constants by one rule. They are glue: they read the
environment and decide nothing beyond "is this module ours" (`isProject`, with `#guard`s) and "what does this constant
lead to" (`nextOf`).
-/
open Lean Meta

namespace Fw.Spec.Reach

/-- What a scan covers: the root names $R$ of the package's `lean_lib`s and the extra module $m_{\mathrm{main}}$
(`.anonymous` when there is none).
$$\mathrm{Scope} = \mathrm{List}(\mathrm{Name}) \times \mathrm{Name},\quad (R, m_{\mathrm{main}})$$ -/
structure Scope where
  /-- The `lean_lib` root names. -/
  libs : List Name
  /-- The extra module (a reviewer's probe), or `.anonymous`. -/
  extra : Name

/-- **Is a module ours?** Its root is the name of a `lean_lib` of the package, or it is the extra module being linted.
$$\forall R, m_{\mathrm{main}}, m,\ \operatorname{project}_{R, m_{\mathrm{main}}}(m) \iff \operatorname{root}(m) \in R \lor m = m_{\mathrm{main}}$$ -/
def isProject (sc : Scope) (mod : Name) : Bool := sc.libs.contains mod.getRoot || mod == sc.extra

#guard isProject ⟨[`Fw], `Refute⟩ `Fw.Spec.Incidents
#guard isProject ⟨[`Fw], `Refute⟩ `Refute
#guard isProject ⟨[`Fw, `FwTest, `MathView], .anonymous⟩ `FwTest.Golden
#guard isProject ⟨[`Fw, `FwTest, `MathView], .anonymous⟩ `MathView
#guard !isProject ⟨[`Fw], `Refute⟩ `Lean.Data.Json
#guard !isProject ⟨[`Fw], `Refute⟩ `FwTest.Golden
#guard !isProject ⟨[], .anonymous⟩ `Fw.Wire

/-- The module of a declaration: the module whose index the environment records for $n$, or the main module for a
declaration of the file being elaborated.
$$\operatorname{modOf}(n) = \begin{cases} \mathrm{moduleNames}[i] & n \text{ was imported from module index } i \\ \mathrm{mainModule} & \text{otherwise} \end{cases}$$ -/
def modOf (env : Environment) (n : Name) : Name :=
  match env.getModuleIdxFor? n with
  | some i => env.header.moduleNames[i.toNat]!
  | none => env.mainModule

/-- The type of a declaration with every leading `∀` stripped.
$$\operatorname{resultType}(\forall x : A,\ B) = \operatorname{resultType}(B),\qquad \operatorname{resultType}(e) = e \text{ otherwise}$$ -/
partial def resultType : Expr → Expr
  | .forallE _ _ b _ => resultType b
  | e => e

/-- The constants of the binder types of a type's leading `∀`s (metadata skipped), and its result type.
$$\operatorname{typeParts}(\forall x : A,\ B) = (\operatorname{consts}(A) \mathbin{+\!\!+} C_B,\ r_B) \text{ where } (C_B, r_B) = \operatorname{typeParts}(B),\quad \operatorname{typeParts}(\mathrm{mdata}(e)) = \operatorname{typeParts}(e),\quad \operatorname{typeParts}(e) = ([\,], e) \text{ otherwise}$$ -/
partial def typeParts : Expr → List Name × Expr
  | .forallE _ t b _ => let (bs, r) := typeParts b; (t.getUsedConstants.toList ++ bs, r)
  | .mdata _ e => typeParts e
  | e => ([], e)

/-- The value of a definition, theorem or opaque; none for every other kind of constant.
$$\operatorname{valueOf}(c) = \begin{cases} \mathrm{value}(c) & c \text{ a definition, theorem or opaque} \\ \bot & \text{otherwise} \end{cases}$$ -/
def valueOf? : ConstantInfo → Option Expr
  | .defnInfo d => some d.value
  | .thmInfo t => some t.value
  | .opaqueInfo o => some o.value
  | _ => none

/-- What a project constant leads to in `closure`: a definition's value; an inductive's type and its constructors; the
type of a constructor, theorem, opaque or axiom (a theorem's proof is not followed: it does not change what the
statement says).
$$\operatorname{next}(c) = \begin{cases} \operatorname{consts}(\mathrm{value}(c)) & c \text{ a definition} \\ \operatorname{consts}(\tau_c) \mathbin{+\!\!+} \operatorname{ctors}(c) & c \text{ an inductive} \\ \operatorname{consts}(\tau_c) & c \text{ a constructor, theorem, opaque or axiom} \\ [\,] & \text{otherwise} \end{cases}$$ -/
def nextOf : ConstantInfo → List Name
  | .defnInfo d => d.value.getUsedConstants.toList
  | .inductInfo i => i.type.getUsedConstants.toList ++ i.ctors
  | .ctorInfo c => c.type.getUsedConstants.toList
  | .thmInfo t => t.type.getUsedConstants.toList
  | .opaqueInfo o => o.type.getUsedConstants.toList
  | .axiomInfo a => a.type.getUsedConstants.toList
  | _ => []

/-- Every project constant reachable from the roots through `nextOf` (roots included when they are project
constants), as a list without repeats in depth-first order of first visit. A name that is not in the environment,
or whose module is not a project module, is neither listed nor followed.
$$\forall X,\ \operatorname{set}(\operatorname{closure}(X)) =\{c \mid \exists x \in X,\ x \to^{*} c,\ c \in \mathrm{env},\ \operatorname{project}(\operatorname{modOf}(c))\},\quad a \to b \iff a \in \mathrm{env} \land \operatorname{project}(\operatorname{modOf}(a)) \land b \in \operatorname{next}(a)$$ -/
partial def closure (env : Environment) (sc : Scope) (roots : List Name) : List Name := Id.run do
  let mut seen : NameSet := {}
  let mut out : Array Name := #[]
  let mut todo := roots
  while true do
    match todo with
    | [] => break
    | c :: rest =>
      todo := rest
      if seen.contains c then continue
      seen := seen.insert c
      unless isProject sc (modOf env c) do continue
      if let some ci := env.find? c then
        out := out.push c
        todo := nextOf ci ++ todo
  return out.toList

/-- The elements of a list expression, after `whnf` at each cons (the elements themselves are not reduced); throws on
a list that does not reduce to `cons`/`nil`.
$$\operatorname{listElems}(e) = [h_1, \dots, h_n] \text{ when } \operatorname{whnf}^{*}(e) = h_1 :: \dots :: h_n :: [\,]$$ -/
partial def listElems (e : Expr) : MetaM (List Expr) := do
  let e ← whnf e
  match e.getAppFnArgs with
  | (``List.cons, #[_, h, t]) => return h :: (← listElems t)
  | (``List.nil, _) => return []
  | _ => throwError "reach: not a list literal: {e}"

/-- A string literal, after `whnf`; throws on any other expression.
$$\operatorname{strLit}(e) = s \text{ when } \operatorname{whnf}(e) = \texttt{"}s\texttt{"}$$ -/
def strLit (e : Expr) : MetaM String := do
  match ← whnf e with
  | .lit (.strVal s) => return s
  | e => throwError "reach: not a string literal: {e}"

/-- The constructors of `Fw.Spec.Incidents.Sig`, the registered implementation signatures (none when the module is not
loaded).
$$\operatorname{sigCtors} = \begin{cases} \operatorname{ctors}(\mathrm{Sig}) & \mathrm{Sig} \text{ loaded} \\ [\,] & \text{otherwise} \end{cases}$$ -/
def sigCtors (env : Environment) : List Name :=
  match env.find? `Fw.Spec.Incidents.Sig with
  | some (.inductInfo i) => i.ctors
  | _ => []

/-- The rows of every registry: for each signature constructor $s$ (in declaration order), the elements of
`(registryFor s).rows`, unreduced (a row written as a named definition stays that constant).
$$\operatorname{registryRows} = [(s, i) : s \in \operatorname{sigCtors},\ i \in \operatorname{listElems}(\operatorname{rows}(\operatorname{registryFor}(s)))]$$ -/
def registryRows : MetaM (List (Name × Expr)) := do
  let env ← getEnv
  let mut out : List (Name × Expr) := []
  for c in sigCtors env do
    let reg := mkApp (mkConst `Fw.Spec.Incidents.registryFor) (mkConst c)
    let rows ← listElems (← mkAppM `Fw.Spec.Props.Registry.rows #[reg])
    out := out ++ rows.map (c, ·)
  return out

end Fw.Spec.Reach
