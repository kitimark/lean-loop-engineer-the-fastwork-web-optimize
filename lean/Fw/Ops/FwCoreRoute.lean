/-!
# Which part of `fwcore` a command line runs (task `lean-bin-slim`)

One executable replaces `fwcore`, `fwtest`, `sweepsgen` and `partsgolden` (each ~100 MB, each stored again in the Lake
artifact cache on every relink). A first argument that names a former executable runs its old entry point with the
remaining arguments; every other command line keeps the old `fwcore` behaviour (`--ops` alone lists the ops, anything
else serves JSON lines). `Main.lean` matches on `route`; `route_old` and `route_sub` are the two guarantees.
-/
namespace Fw.Ops.FwCoreRoute

/-- What `fwcore` runs: the JSON-lines server, the op list, or one former executable.
$$\mathrm{Sub} = \{\mathrm{serve},\ \mathrm{ops},\ \mathrm{fwtest},\ \mathrm{sweepsgen},\ \mathrm{partsgolden}\}$$ -/
inductive Sub
  | serve
  | ops
  | fwtest
  | sweepsgen
  | partsgolden
deriving DecidableEq, Repr

/-- The subcommand names, each with the former executable it runs.
$$S = [(\texttt{fwtest}, \mathrm{fwtest}),\ (\texttt{sweepsgen}, \mathrm{sweepsgen}),\ (\texttt{partsgolden}, \mathrm{partsgolden})]$$ -/
def subs : List (String × Sub) :=
  [("fwtest", .fwtest), ("sweepsgen", .sweepsgen), ("partsgolden", .partsgolden)]

/-- The old `fwcore` (Main.lean before this task): exactly the argument list `[--ops]` lists the ops, every other list
serves.
$$\operatorname{old}(a) = \begin{cases} \mathrm{ops} & a = [\texttt{--ops}] \\ \mathrm{serve} & \text{otherwise} \end{cases}$$ -/
def oldMode (args : List String) : Sub :=
  if args == ["--ops"] then .ops else .serve

/-- The route of a command line: a first argument in `subs` selects that former executable and passes it the rest of
the list; any other list (including the empty one) goes to `oldMode` with its arguments unchanged.
$$\operatorname{route}(a) = \begin{cases} (s, r) & a = n :: r \text{ with } (n, s) \in S \\ (\operatorname{old}(a), a) & \text{otherwise} \end{cases}$$ -/
def route : List String → Sub × List String
  | "fwtest" :: rest => (.fwtest, rest)
  | "sweepsgen" :: rest => (.sweepsgen, rest)
  | "partsgolden" :: rest => (.partsgolden, rest)
  | args => (oldMode args, args)

#guard route [] == (.serve, [])
#guard route ["serve"] == (.serve, ["serve"])
#guard route ["--ops"] == (.ops, ["--ops"])
#guard route ["--ops", "x"] == (.serve, ["--ops", "x"])
#guard route ["fwtest"] == (.fwtest, [])
#guard route ["sweepsgen", "--scope", "--check", "f"] == (.sweepsgen, ["--scope", "--check", "f"])
#guard route ["partsgolden", "out"] == (.partsgolden, ["out"])
#guard route ["--scope", "sweepsgen"] == (.serve, ["--scope", "sweepsgen"])
#guard route ["mathview", "--lint"] == (.serve, ["mathview", "--lint"])
#guard route ["breakgen"] == (.serve, ["breakgen"])

/-- **Old command lines keep their meaning.** When the first argument is not a subcommand name (or there is none),
`fwcore` does what it did before, with the same arguments.
$$\forall a:\ \bigl(\forall (n, s) \in S:\ a = [\,] \lor a_0 \ne n\bigr) \Rightarrow \operatorname{route}(a) = (\operatorname{old}(a), a)$$ -/
theorem route_old (args : List String) (h : ∀ p ∈ subs, args.head? ≠ some p.1) :
    route args = (oldMode args, args) := by
  match args, h with
  | [], _ => rfl
  | x :: rest, h =>
    have h2 := h ("fwtest", .fwtest) (by simp [subs])
    have h3 := h ("sweepsgen", .sweepsgen) (by simp [subs])
    have h4 := h ("partsgolden", .partsgolden) (by simp [subs])
    simp only [List.head?_cons, ne_eq, Option.some.injEq] at h2 h3 h4
    unfold route
    split <;> simp_all

/-- **A subcommand runs its former executable on the rest of the line.** Each name in `subs` selects its executable,
which receives exactly the arguments after the name, as the old executable received them.
$$\forall (n, s) \in S,\ \forall r:\ \operatorname{route}(n :: r) = (s, r)$$ -/
theorem route_sub (n : String) (s : Sub) (rest : List String) (h : (n, s) ∈ subs) :
    route (n :: rest) = (s, rest) := by
  simp only [subs, List.mem_cons, Prod.mk.injEq, List.not_mem_nil, or_false] at h
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> rfl

end Fw.Ops.FwCoreRoute
