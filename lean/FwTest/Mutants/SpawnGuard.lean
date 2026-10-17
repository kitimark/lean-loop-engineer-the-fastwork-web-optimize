import Fw.Ops.SpawnGuard

/-! # Mutant killers for `Fw.Ops.SpawnGuard` (task m0-mutants)

Golden cases for the counting helpers and the case-insensitive infix test at its edges (a match
that only starts at the last character, and the empty pattern). -/

namespace FwTest.Mutants.SpawnGuard
open Fw.Ops.SpawnGuard

/-- Agent `n` of role `r` and kind `k`, spawned by the lead. -/
def ag (n r : String) (k : Kind) : Agent := ⟨n, r, k, "lead"⟩

-- countSub: every non-teammate, and no teammate
#guard countSub [ag "t" "x" .teammate] == 0
#guard countSub [ag "t" "x" .teammate, ag "s" "x" .subagent, ag "w" "x" .worktree] == 2
#guard countKind .worktree [ag "t" "x" .teammate, ag "w" "x" .worktree, ag "v" "x" .worktree] == 2
#guard countRole "x" [ag "t" "x" .teammate, ag "s" "y" .subagent, ag "w" "x" .worktree] == 2

-- hasInfix: every start position, including the last character and the empty suffix
#guard hasInfix "x" "abx" && hasInfix "BX" "abx" && hasInfix "" "" && hasInfix "" "ab"
#guard hasInfix "ab" "ab" && !hasInfix "abc" "ab" && !hasInfix "y" "abx" && !hasInfix "x" ""

/-- Why the mutant `List.range (|s| + 2)` of `hasInfix` is equivalent: the extra start position
`|s| + 1` tests the same window as the existing position `|s|` (both suffixes are empty).

$$\forall l, p \in \mathrm{Char}^{*},\ n \in \mathbb{N}:\quad \mathrm{take}_n(\mathrm{drop}_{|l|+1}(l)) = p \iff \mathrm{take}_n(\mathrm{drop}_{|l|}(l)) = p$$

Starting one character past the end reads the same empty window as starting at the end. -/
theorem infix_past_end (l p : List Char) (n : Nat) :
    ((l.drop (l.length + 1)).take n == p) = ((l.drop l.length).take n == p) := by
  simp [List.drop_of_length_le (Nat.le_succ l.length)]

-- isAsk: one matching pattern is enough; the empty pattern never matches
#guard isAsk { askModels := ["opus", "haiku"] } ⟨"", "x", false, "claude-Haiku-4", "lead", 0⟩
#guard !isAsk { askModels := ["opus", "haiku"] } ⟨"", "x", false, "sonnet", "lead", 0⟩
#guard !isAsk { askModels := [""] } ⟨"", "x", false, "sonnet", "lead", 0⟩

/-- An input with roles `exRoles`, the given caps and an unnamed request for role `r`. -/
def unnamed (c : Caps) (r : String) : Input := ⟨[], exRoles, c, [], 1000, ⟨"", r, false, "", "lead", 0⟩⟩

-- excused: only with the cap flag, only for a read-only subagent role, never for an unknown role
#guard excused (unnamed { unnamedReadOnly := true } "reviewer")
#guard !excused (unnamed { unnamedReadOnly := false } "reviewer")
#guard !excused (unnamed { unnamedReadOnly := true } "lean-prover")
#guard !excused (unnamed { unnamedReadOnly := true } "researcher")
#guard !excused (unnamed { unnamedReadOnly := true } "nobody")
#guard !excused ⟨[], [⟨"ro", .teammate, false⟩, ⟨"sw", .subagent, true⟩], { unnamedReadOnly := true }, [], 1000,
  ⟨"", "ro", false, "", "lead", 0⟩⟩
#guard !excused ⟨[], [⟨"ro", .teammate, false⟩, ⟨"sw", .subagent, true⟩], { unnamedReadOnly := true }, [], 1000,
  ⟨"", "sw", false, "", "lead", 0⟩⟩

-- the example input is the documented one: no caps given, time 1000 s
#guard (exInput [] [] ⟨"", "x", false, "", "lead", 0⟩).now == 1000
-- the example roster is the documented table P₀
#guard exRoles == [⟨"lean-prover", .worktree, true⟩, ⟨"researcher", .teammate, true⟩, ⟨"reviewer", .subagent, false⟩]

end FwTest.Mutants.SpawnGuard
