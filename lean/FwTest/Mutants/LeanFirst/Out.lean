import Fw.Ops.LeanFirstSearch

/-!
# Tier-K kills of the lean-first output properties (renderer mutants)

Task `lfg-spec`. Each mutant is a `Render` with one plausible bug in the printed lines or the exit code.
-/
namespace FwTest.Mutants.LeanFirst

open Fw.Search Fw.Ops.LeanFirst

/-- Pending exits 1 instead of 75 (no retry).
$$o(s, F) = \begin{cases} \operatorname{out}(s, F)[\mathit{exit} := 1] & \operatorname{out}(s, F).\mathit{kind} = \mathrm{pending} \\ \operatorname{out}(s, F) & \text{otherwise} \end{cases}$$ -/
def outPending1 : Render := fun s F =>
  let o := out s F
  if o.kind = .pending then { o with exit := 1 } else o

/-- An extra pass verdict line first (the design note's `gTwoVerdicts`).
$$o(s, F) = \operatorname{out}(s, F)[\mathit{lines} := \texttt{VERDICT pass lean-first} :: \operatorname{out}(s, F).\mathit{lines}]$$ -/
def outTwoVerdicts : Render := fun s F =>
  let o := out s F
  { o with lines := mkLine .verdict "pass lean-first" :: o.lines }

/-- A refusal that exits 0.
$$o(s, F) = \begin{cases} \operatorname{out}(s, F)[\mathit{exit} := 0] & \operatorname{out}(s, F).\mathit{kind} = \mathrm{refused} \\ \operatorname{out}(s, F) & \text{otherwise} \end{cases}$$ -/
def outRefuseExit0 : Render := fun s F =>
  let o := out s F
  if o.kind = .refused then { o with exit := 0 } else o

/-- A refusal printed with the raw (uncleaned) subject on its one line.
$$o(s, F) = \begin{cases} (\mathrm{refused}, 1, [\texttt{VERDICT refused lean-first:} \mathbin{+\!\!+} \operatorname{name}(\operatorname{rule}(\rho_0)) \mathbin{+\!\!+} \texttt{␣} \mathbin{+\!\!+} \operatorname{subj}(\rho_0)]) & g(s, F) = \mathrm{refuse}(\rho_0 :: \rho s) \\ \operatorname{out}(s, F) & \text{otherwise} \end{cases}$$ -/
def outRaw : Render := fun s F =>
  match gate s F with
  | .refuse (r :: _) => ⟨.refused, 1, ["VERDICT refused lean-first:" ++ r.rule.name ++ " " ++ r.subject]⟩
  | _ => out s F

#guard (searchUpTo 0 (qPendingExit outPending1)).isSome
#guard (searchUpTo 0 (qOneVerdict outTwoVerdicts)).isSome
#guard (searchUpTo 0 (qExitZeroIff outRefuseExit0)).isSome
#guard (searchUpTo 0 (qNoNewline outRaw)).isSome

/-- **Kill of `missing_fact_not_pass`, exit half**.
$$\lnot\operatorname{PendingExit}(o_{\mathrm{pending1}})$$
A pending result that exits 1 is caught. -/
theorem PendingExit_rejects_outPending1 : ¬ PendingExit outPending1 :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.missingKills])] (fun h => (qPendingExit_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `one_verdict`** (the design note's `gTwoVerdicts`).
$$\lnot\operatorname{OneVerdict}(o_{\mathrm{twoVerdicts}})$$
A second VERDICT line is caught. -/
theorem OneVerdict_rejects_outTwoVerdicts : ¬ OneVerdict outTwoVerdicts :=
  refutes_of_search _ _ _ [(.ratchet, base)] (fun h => (qOneVerdict_iff _).mp h) (by decide +kernel)

/-- **Kill of `exit_zero_iff`**.
$$\lnot\operatorname{ExitZeroIff}(o_{\mathrm{refuse0}})$$
A refusal that exits 0 is caught. -/
theorem ExitZeroIff_rejects_outRefuseExit0 : ¬ ExitZeroIff outRefuseExit0 :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.unproved])] (fun h => (qExitZeroIff_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `no_newline`**.
$$\lnot\operatorname{NoNewline}(o_{\mathrm{raw}})$$
A theorem name with a line break forges a second line when the subject is printed raw, and is caught. -/
theorem NoNewline_rejects_outRaw : ¬ NoNewline outRaw :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.newlineName])] (fun h => (qNoNewline_iff _).mp h)
    (by decide +kernel)

end FwTest.Mutants.LeanFirst
