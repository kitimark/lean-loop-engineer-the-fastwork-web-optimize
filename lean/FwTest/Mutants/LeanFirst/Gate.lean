import Fw.Ops.LeanFirstSearch

/-!
# Tier-K kills of the lean-first gate properties (gate mutants)

Task `lfg-spec`. Each mutant is a `Gate` with one plausible bug; the guard shows the bound-0 search of
`Fw.Ops.LeanFirstSearch` finds a counterexample, and the kill theorem proves `¬ P mutant` in kernel from one grid
point (`Fw.Search.refutes_of_search`). No ledger incident exists for this gate, so these are mutant kills, not
registry rows.
-/
namespace FwTest.Mutants.LeanFirst

open Fw.Search Fw.Ops.LeanFirst

/-- The gate without one reason code: the reasons whose code is $c$ are dropped before judging.
$$g_c = \operatorname{judge}_{F \mapsto [\rho \in \operatorname{reasons}(F) : \operatorname{code}(\rho) \ne c]}$$ -/
def dropCode (c : String) : Gate := judge (fun F => (reasons F).filter (·.code != c))

/-- Forgets rule 1d (a property whose implementation is not reached from the wire passes). $$g = g_{\texttt{unreached}}$$ -/
def gIgnoreUnreached : Gate := dropCode "unreached"
/-- Binds reachability to any theorem, not the property's own implementation: an `unreached` reason is dropped when
some theorem of the land is reached from the wire.
$$g(s, F) = \operatorname{judge}_{F \mapsto [\rho \in \operatorname{reasons}(F) : \lnot(\operatorname{code}(\rho) = \texttt{unreached} \land \exists t \in F.\mathit{thms},\ t.\mathit{rw} = \mathrm{some}\ \mathrm{true})]}(s, F)$$ -/
def gAnyReached : Gate := judge fun F =>
  (reasons F).filter fun r => !(r.code == "unreached" && F.thms.any (·.reachFromWire == some true))
/-- Forgets rule 1c (an unproved property passes). $$g = g_{\texttt{unproved}}$$ -/
def gNoUnproved : Gate := dropCode "unproved"
/-- Reads only the math review. $$g = g_{\texttt{unsigned-adversary}}$$ -/
def gIgnoreAdversary : Gate := dropCode "unsigned-adversary"
/-- Passes decision code with an empty property list. $$g = g_{\texttt{no-props}}$$ -/
def gNoProps : Gate := dropCode "no-props"
/-- Forgets rule 2. $$g = g_{\texttt{no-kill}}$$ -/
def gNoKillCheck : Gate := dropCode "no-kill"
/-- Forgets hidden carriers. $$g = g_{\texttt{hidden}}$$ -/
def gNoHidden : Gate := dropCode "hidden"
/-- Forgets unregistered premise ids. $$g = g_{\texttt{unregistered}}$$ -/
def gNoUnregistered : Gate := dropCode "unregistered"
/-- Forgets refuted premises. $$g = g_{\texttt{refuted}}$$ -/
def gNoRefuted : Gate := dropCode "refuted"
/-- Passes unmarked branches. $$g = g_{\texttt{unmarked}}$$ -/
def gUnmarkedPass : Gate := dropCode "unmarked"
/-- Forgets rule 5. $$g = g_{\texttt{proof-before-search}}$$ -/
def gNoSearch : Gate := dropCode "proof-before-search"
/-- Forgets the ratchet. $$g = g_{\texttt{growth}}$$ -/
def gNoRatchet : Gate := dropCode "growth"

/-- Missing sources read as empty evidence (fail open): never pending.
$$g(s, F) = \begin{cases} \mathrm{pass} & [\rho \in \operatorname{reasons}(F) : \operatorname{en}(s, \mathit{lf}, \operatorname{rule}(\rho))] = [\,] \\ \mathrm{refuse}(\dots) & \text{otherwise} \end{cases}$$ -/
def gPendingPass : Gate := fun s F =>
  match (reasons F).filter (fun r => enforced s F.leanFirst r.rule) with
  | [] => .pass
  | rs => .refuse rs

/-- "One signoff per role": a role with two matching agreeing rows is refused as unsigned.
$$g(s, F) = \operatorname{judge}_{F \mapsto \operatorname{reasons}(F) \mathbin{+\!\!+} [\mathrm{unsigned}(P, r) \mid P \in \mathit{props},\ r \in [\mathrm{math}, \mathrm{adversary}],\ |[\sigma \in \Sigma : \operatorname{at}(\sigma, P, r)]| > 1]}(s, F)$$ -/
def gOneSignoff : Gate := judge fun F =>
  reasons F ++ F.props.flatMap fun P => [Role.math, Role.adversary].filterMap fun r =>
    if (F.signoffs.filter (·.matches P r)).length > 1 then some (.unsigned P.name r) else none

/-- Stage 1 enforces the ratchet too (the stage table out of order).
$$g(s, F) = \operatorname{gate}(s', F),\quad s' = \begin{cases} 3 & s = 1 \\ s & \text{otherwise} \end{cases}$$ -/
def gNewTasksRatchet : Gate := fun s F => gate (if s = .newTasks then .ratchet else s) F

/-- The shadow stage enforces everything.
$$g(s, F) = \operatorname{gate}(s', F),\quad s' = \begin{cases} 3 & s = 0 \\ s & \text{otherwise} \end{cases}$$ -/
def gShadowEnforces : Gate := fun s F => gate (if s = .shadow then .ratchet else s) F

#guard (searchUpTo 0 (qPassIff gIgnoreUnreached)).isSome
#guard (searchUpTo 0 (qRefusesUnreached gIgnoreUnreached)).isSome
#guard (searchUpTo 0 (qRefusesUnreached gAnyReached)).isSome
#guard (searchUpTo 0 (qRefusesUnproved gNoUnproved)).isSome
#guard (searchUpTo 0 (qStaleReviewRefuses gIgnoreAdversary)).isSome
#guard (searchUpTo 0 (qNoPropsRefuses gNoProps)).isSome
#guard (searchUpTo 0 (qMutantKillsOrRefuse gNoKillCheck)).isSome
#guard (searchUpTo 0 (qHiddenPremiseRefuses gNoHidden)).isSome
#guard (searchUpTo 0 (qUnregisteredPremiseRefuses gNoUnregistered)).isSome
#guard (searchUpTo 0 (qRefutedPremiseRefuses gNoRefuted)).isSome
#guard (searchUpTo 0 (qUntwinnedBranchRefuses gUnmarkedPass)).isSome
#guard (searchUpTo 0 (qProofBeforeSearchRefuses gNoSearch)).isSome
#guard (searchUpTo 0 (qRatchetRefusesGrowth gNoRatchet)).isSome
#guard (searchUpTo 0 (qMissingFactPending gPendingPass)).isSome
#guard (searchUpTo 0 (qGateMono gOneSignoff)).isSome
#guard (searchUpTo 0 (qStageMono gNewTasksRatchet)).isSome
#guard (searchUpTo 0 (qShadowPasses gShadowEnforces)).isSome

/-- **Kill of `pass_iff`**: the gate that forgets unreached implementations fails it.
$$\lnot\operatorname{PassIff}(g_{\texttt{unreached}})$$
Dropping the reachability check is caught (an unreached property passes). -/
theorem PassIff_rejects_gIgnoreUnreached : ¬ PassIff gIgnoreUnreached :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.stub])] (fun h => (qPassIff_iff _).mp h) (by decide +kernel)

/-- **Kill of `land_refuses_unreached`** (the stub case).
$$\lnot\operatorname{RefusesUnreached}(g_{\texttt{any-reached}})$$
A gate that counts a reached lemma for a property whose own implementation is a stub is caught. -/
theorem RefusesUnreached_rejects_gAnyReached : ¬ RefusesUnreached gAnyReached :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.stub])] (fun h => (qRefusesUnreached_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `land_refuses_unproved`**.
$$\lnot\operatorname{RefusesUnproved}(g_{\texttt{unproved}})$$
A gate that passes an unproved property is caught. -/
theorem RefusesUnproved_rejects_gNoUnproved : ¬ RefusesUnproved gNoUnproved :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.unproved])] (fun h => (qRefusesUnproved_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `stale_review_refuses`**.
$$\lnot\operatorname{StaleReviewRefuses}(g_{\texttt{unsigned-adversary}})$$
A gate that ignores the adversary's disagreement is caught. -/
theorem StaleReviewRefuses_rejects_gIgnoreAdversary : ¬ StaleReviewRefuses gIgnoreAdversary :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.disagreeAdv])] (fun h => (qStaleReviewRefuses_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `no_props_refuses`** (the design note's `gNoProps`).
$$\lnot\operatorname{NoPropsRefuses}(g_{\texttt{no-props}})$$
A gate that passes decision code with an empty property list is caught. -/
theorem NoPropsRefuses_rejects_gNoProps : ¬ NoPropsRefuses gNoProps :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.noProps])] (fun h => (qNoPropsRefuses_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `mutant_kills_or_refuse`**.
$$\lnot\operatorname{MutantKillsOrRefuse}(g_{\texttt{no-kill}})$$
A gate that passes a new theorem without a kill is caught. -/
theorem MutantKillsOrRefuse_rejects_gNoKillCheck : ¬ MutantKillsOrRefuse gNoKillCheck :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.noKill])] (fun h => (qMutantKillsOrRefuse_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `hidden_premise_refuses`**.
$$\lnot\operatorname{HiddenPremiseRefuses}(g_{\texttt{hidden}})$$
A gate that passes a hidden carrier premise is caught. -/
theorem HiddenPremiseRefuses_rejects_gNoHidden : ¬ HiddenPremiseRefuses gNoHidden :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.hidden])] (fun h => (qHiddenPremiseRefuses_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `unregistered_premise_refuses`**.
$$\lnot\operatorname{UnregisteredPremiseRefuses}(g_{\texttt{unregistered}})$$
A gate that passes an unregistered premise id is caught. -/
theorem UnregisteredPremiseRefuses_rejects_gNoUnregistered : ¬ UnregisteredPremiseRefuses gNoUnregistered :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.unregistered])]
    (fun h => (qUnregisteredPremiseRefuses_iff _).mp h) (by decide +kernel)

/-- **Kill of `refuted_premise_refuses`**.
$$\lnot\operatorname{RefutedPremiseRefuses}(g_{\texttt{refuted}})$$
A gate that passes a refuted premise is caught. -/
theorem RefutedPremiseRefuses_rejects_gNoRefuted : ¬ RefutedPremiseRefuses gNoRefuted :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.refuted])] (fun h => (qRefutedPremiseRefuses_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `untwinned_branch_refuses`**.
$$\lnot\operatorname{UntwinnedBranchRefuses}(g_{\texttt{unmarked}})$$
A gate that passes an unmarked TS branch is caught. -/
theorem UntwinnedBranchRefuses_rejects_gUnmarkedPass : ¬ UntwinnedBranchRefuses gUnmarkedPass :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.unmarked])] (fun h => (qUntwinnedBranchRefuses_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `proof_before_search_refuses`**.
$$\lnot\operatorname{ProofBeforeSearchRefuses}(g_{\texttt{proof-before-search}})$$
A gate that ignores the git order of search and proof is caught. -/
theorem ProofBeforeSearchRefuses_rejects_gNoSearch : ¬ ProofBeforeSearchRefuses gNoSearch :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.searchOrder])] (fun h => (qProofBeforeSearchRefuses_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `ratchet_refuses_growth`**.
$$\lnot\operatorname{RatchetRefusesGrowth}(g_{\texttt{growth}})$$
A gate that lets the legacy count grow is caught. -/
theorem RatchetRefusesGrowth_rejects_gNoRatchet : ¬ RatchetRefusesGrowth gNoRatchet :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.ratchet])] (fun h => (qRatchetRefusesGrowth_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `missing_fact_not_pass`** (the design note's `gPendingPass`).
$$\lnot\operatorname{MissingFactPending}(g_{\mathrm{failOpen}})$$
A gate that reads a missing kills file as "no kills needed" is caught. -/
theorem MissingFactPending_rejects_gPendingPass : ¬ MissingFactPending gPendingPass :=
  refutes_of_search _ _ _ [(.ratchet, factsOf [.missingKills])] (fun h => (qMissingFactPending_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `gate_mono`**.
$$\lnot\operatorname{GateMono}(g_{\mathrm{oneSignoff}})$$
A gate that refuses a duplicate agreeing signoff turns a pass into a refusal when evidence is added, and is caught. -/
theorem GateMono_rejects_gOneSignoff : ¬ GateMono gOneSignoff :=
  refutes_of_search _ _ _ [(.ratchet, base, ⟨[], [⟨"P", "hP", .math, false⟩], [], ⟨false, false, false⟩⟩)]
    (fun h => (qGateMono_iff _).mp h) (by decide +kernel)

/-- **Kill of `stage_mono`**.
$$\lnot\operatorname{StageMono}(g_{1 \mapsto 3})$$
A stage table where stage 1 is stricter than stage 2 is caught. -/
theorem StageMono_rejects_gNewTasksRatchet : ¬ StageMono gNewTasksRatchet :=
  refutes_of_search _ _ _ [(.newTasks, .allNew, factsOf [.ratchet])] (fun h => (qStageMono_iff _).mp h)
    (by decide +kernel)

/-- **Kill of `shadow_passes`**.
$$\lnot\operatorname{ShadowPasses}(g_{0 \mapsto 3})$$
A shadow stage that enforces is caught. -/
theorem ShadowPasses_rejects_gShadowEnforces : ¬ ShadowPasses gShadowEnforces :=
  refutes_of_search _ _ _ [factsOf [.unproved]] (fun h => (qShadowPasses_iff _).mp h) (by decide +kernel)

end FwTest.Mutants.LeanFirst
