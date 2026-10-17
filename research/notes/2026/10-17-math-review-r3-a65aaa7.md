---
title: Math review batch at a65aaa7 (Null fixes, Fw/Site breakpoints, Fw/Parts pilot parts)
date: 2026-10-17
status: CONFIRMED
round: 3
---

# Math review batch at a65aaa7

Five math-reviewer agents (workflow, read-only) back-translated every declaration that was new, changed, or had a
reworded docstring since `10-17-math-review-fwcore.md`: the Null gap proofs and the 7 overclaim fixes, the reworded
docstrings (only the $$ text changed), `Fw/Site` (breakpoint model, facts, matrix, generator) and `Fw/Parts` (the four
pilot parts and the golden generator). Method as in the fwcore record: write the math from the Lean first, then compare
clause by clause (quantifiers, hypotheses, ≤ vs <, truncation, structural vs value equality, English overclaims).
The lead wrote this record from the agents' structured verdicts; `stmtHash` comes from `lake exe mathview` at a65aaa7.

## Counts

| Group | Reviewed | Agree | Disagree |
|---|---|---|---|
| Null / Spec / Console (incl. reworded) | 76 | 72 | 4 |
| Site.Breakpoints + BreakpointGen | 100 | 81 | 19 |
| Site.BreakpointFacts + Matrix | 90 | 77 | 13 |
| Parts EngineScroll + NavHitTest + Golden | 95 | 81 | 14 |
| Parts HeroCountdown + HeroExit | 89 | 85 | 4 |
| **Total** | 450 | 396 | 54 |

Patterns in the 54 disagreements: free variables that the Lean quantifies (fix: add ∀); helper definitions whose
math gives only the output type, not the mapping; English that claims more than the theorem (e.g. "runs exactly once
per frame" for a permutation lemma, "a single threshold exists" for an upward-closure lemma); structural vs value
equality on `Px.half` (the gap theorems hold for the representation 1201/2, not for every value 600.5); LaTeX row
breaks (`;\\`) that render wrong in `Console.cardRefusal`; one stale English sentence about the inventory.

## Disagreements (exact corrections)

- `Fw.Null.null_prob_5v5` (english): The theorem only covers the enumerated ranks 0..9 (falseBetterProb(5,5) = 1/252 = pNull(5,5)). The English says that for any 10 distinct values the probability is exactly 1/252, and it gives no citation for that; land_null_prob cites pAt_distinct for the same claim. Fix: '... a false "better" has probability exactly 1/252 (all 252 rank assignments enumerated through `verdict`; any distinct values: `pAt_distinct`); with ties it is at most 1/252 (`null_bound_4v4_5v5`).' The math is fine.
- `Fw.Null.null_prob_3v3` (english): Same problem as 5v5. The theorem is about the ranks 0..5 only, but the English says 'if the 6 run values are distinct ... exactly 1/20' with no citation. Fix: '... a false "better" has probability exactly 1/20 (all 20 rank assignments enumerated through `verdict`; any distinct values: `pAt_distinct`); with ties it is at most 1/20 (`pAt_le_pNull`).' The math is fine.
- `Fw.Screen.leRun_spec` (english): The theorem proves only one direction: leRun(A,B) = true ⇒ |A| = |B| ∧ ∀(a,b) ∈ zip(A,B): leVec(a,b) = true. The math says this correctly. The English "`leRun` means `leVec` frame by frame" reads as ⇔, and the converse is not proved. Fix: "If `leRun` holds, the runs have equal frame counts and `leVec` holds frame by frame."
- `Fw.Console.cardRefusal` (math): The case logic matches the Lean, but three rows contain the typo ';\\' (Fw/Console.lean lines 263-265). Inside a cases environment, '\\' is a row break. So the review row breaks before 'texttt{"reviewer owns or built this card"}', and that text renders as plain letters. The swipe and land-request rows break the same way before 'bot', which renders as the letters 'bot'. Fix: line 263 ';\\texttt{"reviewer owns or built this card"}' becomes ';\ \texttt{"reviewer owns or built this card"}'. Lines 264 and 265 ';\\bot \text{ if } ...' become ';\ \bot \text{ if } ...'.
- `Fw.Site.Breakpoints.Feature.pointerKw` (math): The math only says what set the output lies in, not which value maps to which keyword. Corrected: $$ \mathrm{kw}(\text{none}) = \texttt{none},\ \mathrm{kw}(\text{coarse}) = \texttt{coarse},\ \mathrm{kw}(\text{fine}) = \texttt{fine} $$
- `Fw.Site.Breakpoints.Feature.motionKw` (math): The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{no-preference}) = \texttt{no-preference},\ \mathrm{kw}(\text{reduce}) = \texttt{reduce} $$
- `Fw.Site.Breakpoints.Feature.schemeKw` (math): The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{light}) = \texttt{light},\ \mathrm{kw}(\text{dark}) = \texttt{dark} $$
- `Fw.Site.Breakpoints.Feature.mediaTypeKw` (math): The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{screen}) = \texttt{screen},\ \mathrm{kw}(\text{print}) = \texttt{print} $$
- `Fw.Site.Breakpoints.Feature.forcedColorsKw` (math): The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{none}) = \texttt{none},\ \mathrm{kw}(\text{active}) = \texttt{active} $$
- `Fw.Site.Breakpoints.Feature.legacyCss` (math): The math lists only the three width cases and has no '…'. It leaves out the device-width case and the fallback for every other feature. Corrected: $$ \mathrm{legacy}(w \le N) = \texttt{(max-width: }N\texttt{px)},\ \mathrm{legacy}(w > N) = \bot,\ \mathrm{legacy}(w \ge N{+}1) = \texttt{(min-width: }N{+}1\texttt{px)},\ \mathrm{legacy}(d_w \le N) = \texttt{(max-device-width: }N\texttt{px)},\ \mathrm{legacy}(f) = \mathrm{css}(f) \text{ otherwise} $$
- `Fw.Site.Breakpoints.MQ.legacyCss` (math): The math gives the value only when every feature has a legacy form. It never says the result is ⊥ (none) when some feature lacks one, which is what mapM does. Corrected: $$ \mathrm{legacy}(q) = \begin{cases} \mathrm{join}_{\texttt{, }}\big(\mathrm{join}_{\texttt{ and }}(\mathrm{legacy}(f_{ij}))_j\big)_i & \forall i,j.\ \mathrm{legacy}(f_{ij}) \ne \bot \\ \bot & \text{otherwise} \end{cases} $$
- `Fw.Site.Breakpoints.MQ.taggedEdges` (math): The math writes the axis as a(f), a function of the feature alone. In the Lean it depends on the arm: the same width feature gets width(touch) inside a touch arm and width elsewhere. The math also does not fix the order (arms in order, then features in order, keeping first occurrences). Corrected: $$ E(q) = \mathrm{dedup}_{\text{first}}\,[(a(A_i,f), N) \mid i \text{ in order},\ f \in A_i \text{ in order},\ N \in E_w(f) \mathbin{+\!\!+} E_d(f)],\quad a(A,f) = \begin{cases} \text{device-width} & f = (d_w \le N) \\ \text{width(touch)} & f \text{ a width test} \land \mathrm{touchArm}(A) \\ \text{width} & f \text{ a width test} \land \neg\mathrm{touchArm}(A) \end{cases} $$
- `Fw.Site.Breakpoints.combo` (math): The math covers only the default dw = true. The English mentions dw = false, but the math does not. Corrected: $$ C_{N,dw} = \begin{cases} (w \le N) \lor (d_w \le 500) \lor (\eta = \mathrm{none} \land \pi = \mathrm{coarse} \land w \le 1200) & dw = \mathrm{true} \\ (w \le N) \lor (\eta = \mathrm{none} \land \pi = \mathrm{coarse} \land w \le 1200) & dw = \mathrm{false} \end{cases} $$ (arms in this order)
- `Fw.Site.Breakpoints.Kind.str` (math): The math gives only the output set, not the mapping. Corrected: $$ \mathrm{str}(\text{css}) = \texttt{css-media},\ \mathrm{str}(\text{js}) = \texttt{js-matchMedia},\ \mathrm{str}(\text{css+js}) = \texttt{css-media+js-matchMedia} $$
- `Fw.Site.BreakpointGen.gapsJson` (math): The math leaves out the 'open' field [N, N+1] that each row carries, and writes the four N as a set although the Lean gives them as an ordered list. Corrected: $$ \mathrm{gaps} = \big(\{\mathrm{lower}{=}\mathrm{css}(w \le N),\ \mathrm{upper}{=}\mathrm{css}(w \ge N{+}1),\ \mathrm{open}{=}[N, N{+}1],\ \mathrm{probe}{=}N + \tfrac12\}\big)_{N = 600, 640, 860, 1000} $$
- `Fw.Site.BreakpointGen.genJson` (math): The math leaves out four of the nine keys: schema, generatedBy, inventory and backingTheorems. Corrected: $$ \mathrm{genJson} = \{\mathrm{schema}{=}\texttt{fw.breakpoints.gen/1},\ \mathrm{generatedBy},\ \mathrm{inventory},\ \mathrm{backingTheorems},\ \mathrm{conditions},\ \mathrm{edgePairs},\ \mathrm{fractionalGaps},\ \mathrm{neutral},\ \mathrm{matrix}\} $$
- `Fw.Site.BreakpointGen.natList` (math): The math gives only the type of the result and never says what the function returns. Corrected: $$ \mathrm{natList}(j) = \begin{cases} (n_1,\dots,n_k) & j = [n_1,\dots,n_k],\ n_i \in \mathbb{N} \\ \bot & \text{otherwise} \end{cases} $$
- `Fw.Site.BreakpointGen.strList` (math): The math gives only the type, and the notation Σ^{**} is unclear. Corrected: $$ \mathrm{strList}(j) = \begin{cases} (s_1,\dots,s_k) & j = [s_1,\dots,s_k],\ s_i \text{ strings} \\ \bot & \text{otherwise} \end{cases} $$
- `Fw.Site.BreakpointGen.checkCond` (math): The '…' hides three checks that are not like the ones listed. These are the id equality, edges_px, and the legacy check, which only applies when equivalentForms has an entry starting with '('. Edges also require each inventory pair to be [a, a+1]. Corrected: $$ \mathrm{checkCond}(c, r) = [\,] \iff r.\mathrm{id} = c.\mathrm{id} \land r.\mathrm{condition} = \mathrm{css}(q) \land r.\mathrm{kind} = \mathrm{str}(\kappa) \land r.\mathrm{features} = \mathrm{features}(q) \land r.\mathrm{edges} = [(\mathrm{str}(a), [N, N{+}1])]_{(a,N) \in E(q)} \land r.\mathrm{edges\_px} = \mathrm{edgesPx}(q) \land \big(\exists s \in r.\mathrm{equivalentForms}.\ s \text{ starts with } \texttt{(} \Rightarrow \mathrm{legacy}(q) \ne \bot \land \mathrm{legacy}(q) \in r.\mathrm{equivalentForms}\big) $$
- `Fw.Site.BreakpointGen.checkInventory` (both): Math: the right-hand side does not require exactly 30 inventory rows with ids starting 'mq.', so an inventory with 31 such rows satisfies it but the code reports a mismatch. Each row comparison is checkCond = [], not row equality. 'M agrees with I.matrix' is vague. Corrected: $$ \mathrm{checkInventory}(I) = [\,] \iff |R| = 30 \land \forall i < 30.\ \mathrm{checkCond}(c_i, R_i) = [\,] \land I.\mathrm{edgePairs} = [[N,N{+}1]]_{N \in \mathrm{widthEdgePairs}} \land I.\mathrm{deviceWidthPairs} = [[500,501]] \land I.\text{touch-rm.at} = [[N,N{+}1]]_{N \in \mathrm{touchRmEdges}} \land I.\mathrm{estimate.loadsPerEngine} = |M| \land \forall (b,n) \in \mathrm{blockBreakdown}.\ I.\mathrm{estimate.breakdown}[b] = n $$ Here R is the list of I.conditions rows whose id starts with 'mq.', in order, and all I.* fields are under I.matrix. English: 'The generator refuses to write unless this list is empty' is too strong. run checks only when --inventory is given, and opBreakpointsGen always returns gen.
- `Fw.Site.BreakpointGen.opBreakpointsGen` (math): The math does not cover the case with no inventory key (or a request that is not a JSON object). Then mismatches is []. The result is always ok. Corrected: $$ \mathrm{op}(\mathit{req}) = \mathrm{ok}\,\{\mathrm{gen} = \mathrm{genJson},\ \mathrm{mismatches} = \begin{cases} \mathrm{checkInventory}(\mathit{req}.\mathrm{inventory}) & \text{inventory} \in \mathit{req} \\ [\,] & \text{otherwise} \end{cases}\} $$
- `Fw.Site.BreakpointGen.argOf` (math): The math does not say which occurrence of the flag is used or what happens when there is none. Corrected: $$ \mathrm{argOf}(l, k) = \begin{cases} l_{i+1} & i = \min\{i \mid l_i = k,\ i+1 < |l|\} \\ \bot & \text{no such } i \end{cases} $$
- `Fw.Site.BreakpointGen.run` (math): The math treats the inventory I as always present, although the check only runs when --inventory is given. It also leaves out exit code 2 for an inventory file that does not parse. Corrected: $$ \mathrm{run}(\mathit{args}) = \begin{cases} 2 & \texttt{--inventory } P \text{ given} \land P \text{ does not parse as JSON} \\ 1 & \texttt{--inventory } P \text{ given} \land \mathrm{checkInventory}(I_P) \ne [\,] \\ 0 & \text{else if } \texttt{--check } f \text{ given} \land \mathrm{bytes}(f) = \mathrm{utf8}(\mathrm{genText}) \\ 1 & \text{else if } \texttt{--check } f \text{ given} \\ 0,\ \text{stdout} := \mathrm{genText} & \text{otherwise} \end{cases} $$ (an unreadable file raises an IO error)
- `Fw.Site.Breakpoints.catalogue_css` (math): The middle component reads ts_i = ts_i, which is trivially true. The Lean pins every TS id to a listed literal, and breakpoints.json has no TS-id field. Correct to: $$ \forall i < 30.\ (\mathrm{id}_i, \mathrm{ts}_i, \mathrm{css}(q_i)) = (\mathrm{id}^{inv}_i, t_i, s^{inv}_i),\quad t = (\texttt{rmReduce}, \texttt{rmNopref}, \dots, \texttt{c1000Nodw}) $$ where t is the list of TS ids written in the theorem.
- `Fw.Site.Breakpoints.catalogue_axis_edges` (math): The Lean compares widthEdges/dwEdges with q.taggedEdges, i.e. E(q_i). It never mentions the inventory E^inv_i; that equality is catalogue_edges. Also bound i. Correct to: $$ \forall i < 30.\ \{N \mid N \in E_w(q_i)\} = \{N \mid (a, N) \in E(q_i),\ a \in \{\text{width}, \text{width(touch)}\}\} \land \{N \mid N \in E_d(q_i)\} = \{N \mid (\text{device-width}, N) \in E(q_i)\} $$ (and E(q_i) = E^{inv}_i by catalogue_edges).
- `Fw.Site.Breakpoints.MQ.eval_indep_height_dpr` (english): The math is right. The English claims too much with 'so these inputs only affect the raster'. The theorem only says no media condition reads height, device height or DPR. Height does change layout: the inventory's height-probes exist for the profile clamp knees at 823/900 and the vh-band JS gates (README 11-breakpoints l.140). Replace with: 'The page has no height, device-height or resolution media query, so these inputs never change a media condition (height can still change layout through vh units and JS viewport-height reads).'
- `Fw.Site.Breakpoints.gap600` (math): The hypothesis is e.width = Px.half 600. Px is an unnormalised structure, so this means numerator 1201 and denominator 2 exactly, not 'w has value 600.5' (2402/4 is not covered). The math claims more than the Lean. Correct to: $$ (p_w, q_w) = (1201, 2)\ (w = \tfrac{1201}{2}) \Rightarrow e \not\models (w \le 600) \land e \not\models (601 \le w \le 1279) \land e \not\models (601 \le w \le 1511) \land e \models (w > 600) $$ Alternatively, weaken the Lean hypothesis to 2 num = 1201 den.
- `Fw.Site.Breakpoints.gap640` (math): The hypothesis e.width = Px.half 640 is structural (numerator 1281, denominator 2), not equality of the rational value 640.5. Correct to: $$ (p_w, q_w) = (1281, 2)\ (w = \tfrac{1281}{2}) \Rightarrow e \not\models (w \le 640) \land e \not\models (641 \le w \le 1000) \land e \models (w > 640) $$
- `Fw.Site.Breakpoints.gap860` (math): The hypothesis e.width = Px.half 860 is structural (numerator 1721, denominator 2), not equality of the value 860.5. Correct to: $$ (p_w, q_w) = (1721, 2)\ (w = \tfrac{1721}{2}) \Rightarrow e \not\models (w \le 860) \land e \not\models (w \ge 861) \land e \not\models (w \ge 861 \land \mu = \text{no-preference}) \land e \not\models (861 \le w \le 1000) $$
- `Fw.Site.Breakpoints.gap1000` (math): The hypothesis e.width = Px.half 1000 is structural (numerator 2001, denominator 2), not equality of the value 1000.5. Correct to: $$ (p_w, q_w) = (2001, 2)\ (w = \tfrac{2001}{2}) \Rightarrow e \not\models (w \le 1000) \land e \not\models (w \ge 1001) \land e \not\models (w \ge 1001 \land \mu = \text{no-preference}) \land e \not\models (641 \le w \le 1000) \land e \not\models (861 \le w \le 1000) $$
- `Fw.Site.Breakpoints.pairProbes` (math): 'w \in (N, N{+}1)' reads as the open interval. That is the fractional-gap notation used in the same modules (the inventory's 'open': [N, N+1]), and it contains no integer. The Lean takes the two-element list [N, N+1] in that order, and the tag is toString w. Correct to: $$ \mathrm{pairs}(b, E, f) = [(b, \mathrm{str}(w), f(w)) \mid N \leftarrow E,\ w \leftarrow [N, N{+}1]] $$
- `Fw.Site.Breakpoints.matrix_pairs_agree` (both): The Lean ranges over b in [desk, deskRm, touch, touchRm]. The math's bare '\forall b' claims every block, and the English names only desk, desk-rm and touch. Math: $$ \forall b \in \{\text{desk}, \text{desk-rm}, \text{touch}, \text{touch-rm}\}\ \forall N \in E_{15}\ \forall p, p' \in M_b.\ w(p) = N \land w(p') = N{+}1 \Rightarrow p \sim p' $$ English: 'In the desk, desk-rm, touch and touch-rm blocks, the probes at N and N+1 agree on every discrete feature.'
- `Fw.Site.Breakpoints.matrix_fractional_in_gaps` (english): The math is right. 'The four fractional loads really probe the four gaps' claims too much: the theorem shows each fractional-gaps probe lies in some gap N in {600,640,860,1000}. It does not show that the four loads cover four distinct gaps. Replace with: 'Every fractional load lies strictly inside one of the gaps at 600, 640, 860, 1000.'
- `Fw.Site.Breakpoints.matrix_cross_no_touch_arm` (math): The range of the bound C in '\bigwedge_{C}' is not given. The Lean checks exactly [c860, c1000, c1030, c1000Nodw]. Correct to: $$ \forall p \in M_{\text{cross}}.\ \neg\mathrm{touch}(p) \land (w(p) = 1200 \Rightarrow \textstyle\bigwedge_{C \in \{C_{860}, C_{1000}, C_{1030}, C^{nodw}_{1000}\}} p \not\models C) \land (w(p) = 1024 \Rightarrow p \models C_{1030} \land p \not\models C_{860} \land p \not\models C_{1000} \land p \not\models C^{nodw}_{1000}) $$
- `Fw.Site.Breakpoints.matrix_dw_arm` (math): The math leaves out the viewport-1001 clause the Lean proves: at screen 501, c860 and c1000 fail, and c1030 holds iff w = 1001. It also leaves s unbound in 'p_{v,s}'. Correct to: $$ \forall p \in M_{\text{dw}}.\ p \not\models C^{nodw}_{1000} \land \big(d_w(p) = 500 \Rightarrow p \models C_{860} \land p \models C_{1000} \land p \models C_{1030}\big) \land \big(d_w(p) \ne 500 \Rightarrow p \not\models C_{860} \land p \not\models C_{1000} \land (p \models C_{1030} \iff w(p) = 1001)\big) $$
- `Fw.Site.Breakpoints.matrix_landscape_overlaps` (english): The math is right. The parenthetical 'The inventory's phone-landscape.why claims both overlap pairs' is out of date. breakpoints.json phone-landscape.why (and README 11-breakpoints l.123) now says 'the mq.c860 + mq.w-ge-861 overlap only ... NOT in the mq.c1000 + mq.w-ge-1001 overlap'. Replace with: '(As the inventory's phone-landscape.why states, the C1000 / >=1001 overlap needs a viewport of at least 1001 px with a small screen or touch; the touch probes at 1031 and 1200 and the dw-arm-isolate probes with screen 500 provide it.)'
- `Fw.Parts.EngineScroll.entryLe_trans` (math): e_1, e_2, e_3 are free in the math, but Lean quantifies them. Corrected: $$\forall e_1, e_2, e_3:\ e_1 \sqsubseteq e_2 \land e_2 \sqsubseteq e_3 \Rightarrow e_1 \sqsubseteq e_3$$
- `Fw.Parts.EngineScroll.orderCallbacks_perm` (english): The math is right. The English 'Every registered callback runs exactly once per frame' says more than the theorem. The theorem only says the sorted id list is a permutation of the registered ids. It says nothing about running or frames, and in the original only `active` (IO-gated) entries run in iE. Suggested English: 'The frame order lists every registered callback exactly once (as often as it is registered); nothing is dropped or duplicated.'
- `Fw.Parts.EngineScroll.faithfulFrom` (math): The math leaves out the empty-list case of the definition and uses an undefined subscript notation. Corrected: $$\operatorname{faithfulFrom}(k, [\,]) = [\,],\quad \operatorname{faithfulFrom}(k, w :: ws) = (\mathrm{R}, k) :: \big([(\mathrm{W}, k) \mid w] \mathbin{+\!\!+} \operatorname{faithfulFrom}(k + 1, ws)\big)$$
- `Fw.Parts.EngineScroll.isRead_read` (math): k is free in the math. Corrected: $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{R}, k)) = \top$$
- `Fw.Parts.EngineScroll.isRead_write` (math): k is free in the math. Corrected: $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{W}, k)) = \bot$$
- `Fw.Parts.EngineScroll.forced_mono` (math): d and e are free in the math, but Lean has ∀ d e : Bool. Corrected: $$\forall \rho, as, d, e:\quad (d \Rightarrow e) \Rightarrow \operatorname{forced}_\rho(d, as) \le \operatorname{forced}_\rho(e, as)$$
- `Fw.Parts.EngineScroll.batched_le_one` (math): The math leaves out the Lean hypothesis hr : ∀ a, a.isRead = true → role a ≠ dirty (no read dirties). Without it the statement is false: with a sound ρ where RS is dirty and RL is check, the read-only list [RL,RS,RL,RS,RL] forces 2 or more. Corrected: $$\forall \rho \text{ sound with } (\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho(a) \ne \mathrm{dirty}),\ d,\ as:\quad \operatorname{forced}_\rho\big(d, \operatorname{filter}_{\mathrm{R}}(as) \mathbin{+\!\!+} \operatorname{filter}_{\mathrm{W}}(as)\big) \le 1$$ (ρ_S and ρ_L both meet this, so the English stands.)
- `Fw.Parts.EngineScroll.runs_le` (math): The second clause is weaker than the Lean. Lean proves runs(p,es) ≤ [p] + #scroll(es) for every p, not only for p = ⊥. Corrected: $$\forall p, es:\quad \operatorname{runs}(p, es) \le \#_{\mathrm{frame}}(es) \ \land\ \operatorname{runs}(p, es) \le [p] + \#_{\mathrm{scroll}}(es)$$
- `Fw.Parts.NavHitTest.findIdx?_congr'` (math): p, q and xs are free in the math. Corrected: $$\forall p, q, xs:\ (\forall x \in xs:\ p(x) = q(x)) \Rightarrow \operatorname{findIdx?}(p, xs) = \operatorname{findIdx?}(q, xs)$$
- `Fw.Parts.NavHitTest.findIdx_congr` (math): p, q and xs are free in the math. Corrected: $$\forall p, q, xs:\ (\forall x \in xs:\ p(x) = q(x)) \Rightarrow \operatorname{findIdx}(p, xs) = \operatorname{findIdx}(q, xs)$$
- `Fw.Parts.Golden.decimal?` (both): The math does not say which e is chosen (the least one), how m is computed, or when the result is none. The English 'terminating expansion (denominator 2^a 5^b)' is too broad: it is none when q.den does not divide 10^40, for example den = 2^41. Corrected: $$\operatorname{dec}(q) = \begin{cases} \operatorname{some}\big(q.\mathrm{num} \cdot \tfrac{10^{e}}{q.\mathrm{den}},\ e\big),\ e = \min\{e \le 40 : q.\mathrm{den} \mid 10^{e}\} & \text{if such } e \text{ exists} \\ \operatorname{none} & \text{otherwise} \end{cases}$$ where (m, e) stands for m·10^{-e}. English: 'denominator 2^a 5^b with a, b ≤ 40'.
- `Fw.Parts.Golden.rin` (math): The case split is on dec(q) ≠ none (q.den divides 10^40), not on 'terminating'. A terminating q such as 2^{-41} goes to the wire form. Corrected: $$\operatorname{rin}(q) = \begin{cases} n & \operatorname{dec}(q) = \operatorname{some}(n) \\ \operatorname{wire}(q) & \operatorname{dec}(q) = \operatorname{none} \end{cases}$$
- `Fw.Parts.Golden.springJ` (math): The math leaves out the Bool parameter `wire`, which picks the encoding. Corrected: $$\operatorname{springJ}(\mathit{wire}, (x, v)) = \{\mathrm{value}: \operatorname{enc}(x), \mathrm{velocity}: \operatorname{enc}(v)\},\quad \operatorname{enc} = \begin{cases} \operatorname{wire} & \mathit{wire} \\ \operatorname{rin} & \lnot\mathit{wire} \end{cases}$$
- `Fw.Parts.Golden.main` (math): The math claims a .spec.jsonl for every pilot part, but main writes no hero.countdown.spec.jsonl (7 files, not 8). Corrected: $$\mathit{files} = \{\mathit{part}.\mathrm{jsonl} \mid \mathit{part} \in \mathrm{pilot}\} \cup \{\mathit{part}.\mathrm{spec.jsonl} \mid \mathit{part} \in \{\text{engine.scroll}, \text{nav.hitTest}, \text{hero.exit}\}\}$$ written to args_0, default ../packages/contracts/golden/parts.
- `Fw.Parts.HeroCountdown.lexLe` (math): The Lean def is on all of List ℕ × List ℕ and is False whenever either list does not have length 4 (`| _, _ => False`). The math only gives the 4-tuple case. Corrected: $$[d,h,m,s] \preceq [d',h',m',s'] \iff d < d' \lor (d = d' \land (h < h' \lor (h = h' \land (m < m' \lor (m = m' \land s \le s'))))),\qquad x \preceq y \text{ is false if } |x| \ne 4 \lor |y| \ne 4$$
- `Fw.Parts.HeroCountdown.faceDelta_settled` (english): The math (faceDelta(k,d)=0 iff k=d for d,k in {0..9}) is exact. The English overclaims: 'only face d is in the window' means no other face lies in (-1,1), and the theorem does not prove that. It only proves no other face sits at offset 0. Corrected heading: 'Settled digits: with the spring at rest on digit d, face d sits at offset 0 and no other face does.'
- `Fw.Parts.HeroCountdown.slices_nonpos` (both): The theorem only states slices(dt)=0 for dt in Q with dt <= 0. The math quantifies s and x* even though they do not appear. The English ('the spring is only tested for settling, not moved') is a claim about springStep that this theorem does not state. Corrected math: $$\forall \mathit{dt} \in \mathbb{Q},\ \mathit{dt} \le 0:\quad \operatorname{slices}(\mathit{dt}) = 0$$ Corrected English: 'If no time passed, the slice loop runs zero times.'
- `Fw.Parts.HeroExit.pointerOff_mono` (english): The math (upward closure in y) is exact. The English 'There is a single scroll position past which the hero ignores taps' claims a threshold exists, and the theorem does not prove that. It proves only that the pointer-off set is upward closed. Corrected English: 'Once the hero ignores taps, scrolling further down keeps it that way; it never flickers back on while scrolling down.'

## Verdicts (parseable)

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Null.falseBetterProb` | agree | 860301984 | 18246701428279470872 |  |
| `Fw.Null.land_null_prob` | agree | 7959650623826516976 | 10274241804945386897 |  |
| `Fw.Null.null_prob_5v5` | disagree | 18075036907877158627 | 8090375151392571431 | The theorem only covers the enumerated ranks 0..9 (falseBetterProb(5,5) = 1/252 = pNull(5,5)). The English says that for |
| `Fw.Null.null_prob_3v3` | disagree | 6489614198802959727 | 16757962068206690347 | Same problem as 5v5. The theorem is about the ranks 0..5 only, but the English says 'if the 6 run values are distinct .. |
| `Fw.Null.null_bound_4v4_5v5` | agree | 13590118229325669411 | 2387390654398405284 |  |
| `Fw.Null.binom` | agree | 9906956 | 5823024778487332210 |  |
| `Fw.Null.binom_zero_right` | agree | 15351676995500341385 | 9457668809102399427 |  |
| `Fw.Null.arr_length` | agree | 6098919412702702742 | 495396059513349409 |  |
| `Fw.Null.binom_eq_zero` | agree | 10213509599131773290 | 10713044668094839439 |  |
| `Fw.Null.binom_pos` | agree | 13944111334432034498 | 7967021773663353857 |  |
| `Fw.Null.binom_succ_mul` | agree | 10610575094240758861 | 18281474805059896891 |  |
| `Fw.Null.choose_eq_binom` | agree | 7601004443219580183 | 16393561046972913840 |  |
| `Fw.Null.arr_length_choose` | agree | 4696931272336502918 | 11219419452301067370 |  |
| `Fw.Null.pAt_le_choose` | agree | 2593624135157745674 | 10397674691443998889 |  |
| `Fw.Null.mem_arr_iff` | agree | 4456310157590566565 | 13238645275385334125 |  |
| `Fw.Null.sel_cons` | agree | 6845860071509534681 | 2458434551907135219 |  |
| `Fw.Null.length_sel` | agree | 10014879156367004796 | 17961069411890538003 |  |
| `Fw.Null.count_true_add_false` | agree | 1890346558 | 14216318477969116577 |  |
| `Fw.Null.winsAt_tooFew` | agree | 5460991786832817118 | 6353922640392250626 |  |
| `Fw.Null.pAt_le_pNull` | agree | 4997353542246541774 | 14270096923482444083 |  |
| `Fw.Null.countP_lt_getElem` | agree | 423003686 | 12008705628860099073 |  |
| `Fw.Null.exists_threshold` | agree | 1817194464 | 5210659677448390242 |  |
| `Fw.Null.sel_map` | agree | 3332777758037570543 | 9894281739763811454 |  |
| `Fw.Null.winsAt_distinct` | agree | 15444386159274227470 | 6045980397004120313 |  |
| `Fw.Null.pAt_distinct` | agree | 14518739939440582959 | 3135888170788028918 |  |
| `Fw.Null.idx` | agree | 194866052 | 13573704031976519296 |  |
| `Fw.Null.idx_nodup` | agree | 15745456884505072103 | 8484953459549598301 |  |
| `Fw.Null.sel_range'_zipIdx` | agree | 3224315198428932811 | 5162688787453164139 |  |
| `Fw.Null.sel_idx` | agree | 11853072681352084826 | 3384292460705753627 |  |
| `Fw.Null.wins_eq_winsAt` | agree | 3750686122587801333 | 10520535513982396274 |  |
| `Fw.Null.falseBetterProb_eq_pAt` | agree | 3857949560676488909 | 7611457260255276482 |  |
| `Fw.Null.falseBetterProb_eq_pNull` | agree | 6902466217297490824 | 17834783797379212113 |  |
| `Fw.DeviceQueue.aged_beats_newer` | agree | 15459606977995552882 | 3044473729314025313 |  |
| `Fw.DeviceQueue.aged_not_overtaken` | agree | 4576601346776850582 | 12532766268007655846 |  |
| `Fw.DeviceQueue.unfit_never_starts` | agree | 8527852579920561340 | 15930351135489273451 |  |
| `Fw.Console.apply_idem` | agree | 3457108694390581116 | 17350574509467623372 |  |
| `Fw.Console.step_twice` | agree | 9714917595780000811 | 13501084726203568421 |  |
| `Fw.Null.arr` | agree | 2156174291 | 2589202223367481567 |  |
| `Fw.Null.choose` | agree | 9906956 | 6785585580338572609 |  |
| `Fw.Null.mem_sel` | agree | 265976095466000211 | 9918489393245196181 |  |
| `Fw.Null.count_le_of_imp` | agree | 3203879953 | 10791011985151573295 |  |
| `Fw.Null.eq_of_imp_count` | agree | 1807836024 | 310000122595895675 |  |
| `Fw.Null.exists_true_false` | agree | 3957103838 | 15548548269921291119 |  |
| `Fw.Null.better_labeling_unique` | agree | 16412428810120312908 | 14211307200205215247 |  |
| `Fw.Null.mem_arr` | agree | 5155449431602400388 | 8587700522456825788 |  |
| `Fw.Null.arr_nodup` | agree | 4314025201853021758 | 4621363604890153841 |  |
| `Fw.Null.pAt_le` | agree | 15759822915449477623 | 7453017060778645244 |  |
| `Fw.Screen.leRun_spec` | disagree | 4317423620043076293 | 5721913586232864076 | The theorem proves only one direction: leRun(A,B) = true ⇒ \|A\| = \|B\| ∧ ∀(a,b) ∈ zip(A,B): leVec(a,b) = true. The math sa |
| `Fw.Screen.screen_sound` | agree | 4893661066027004847 | 3335100849399610578 |  |
| `Fw.Screen.screen_worse` | agree | 4520597471776880158 | 14779797002242348607 |  |
| `Fw.DeviceQueue.pickFrom_mem` | agree | 16251276072432502774 | 12672013867452197373 |  |
| `Fw.DeviceQueue.pickFrom_min` | agree | 13753620637482727604 | 10984527286522363182 |  |
| `Fw.DeviceQueue.pick_mem` | agree | 998680076973344239 | 5870706574854754029 |  |
| `Fw.DeviceQueue.pick_min` | agree | 3776949175604853632 | 11624286298758956799 |  |
| `Fw.DeviceQueue.dispatch_sound` | agree | 12218688316977063020 | 2623105725337894431 |  |
| `Fw.DeviceQueue.dispatch_conserving` | agree | 8192037010574851540 | 2228315847433213823 |  |
| `Fw.DeviceQueue.tick` | agree | 16832978777630894550 | 1211511328602058743 |  |
| `Fw.DeviceQueue.tick_kills_at_end` | agree | 6102650412667366667 | 4805336010632654207 |  |
| `Fw.ArtifactKey.key_sound` | agree | 1180814373860987346 | 15672367594761772923 |  |
| `Fw.Console.check` | agree | 15525871426033652860 | 1408026207436213109 |  |
| `Fw.Console.cardRefusal` | disagree | 8236380120697394169 | 7980129319597830256 | The case logic matches the Lean, but three rows contain the typo ';\\' (Fw/Console.lean lines 263-265). Inside a cases e |
| `Fw.Console.step_seen` | agree | 14915868186065857208 | 11216555469254441713 |  |
| `Fw.Console.refused_keeps` | agree | 17583266435552637075 | 14597015446345141025 |  |
| `Fw.Console.reject_keeps` | agree | 2648021860265739531 | 16609953789167140387 |  |
| `Fw.Console.accepted_may` | agree | 3788779216404152911 | 6448429008062984428 |  |
| `Fw.Console.unauthorized_rejected` | agree | 7476724112126248501 | 2138980241924517838 |  |
| `Fw.Console.only_user_answers` | agree | 16272176427751620566 | 7323091736834615658 |  |
| `Fw.Console.landed_fact_accepted` | agree | 7264281319390737123 | 3772781372883951176 |  |
| `Fw.Console.mapCards_inv` | agree | 16293827612537708154 | 4554534862487776382 |  |
| `Fw.Console.built_resets` | agree | 11911687894591051117 | 6505061661035637133 |  |
| `Fw.Console.stale_mono` | agree | 3129061074166289019 | 14568287509504637235 |  |
| `Fw.Console.stale_live` | agree | 15962886855132078421 | 16162293123006880423 |  |
| `Fw.Console.landed_not_stale` | agree | 7533175139842912656 | 17614862804858788002 |  |
| `Fw.Console.running_not_stale` | agree | 15847615884454301378 | 10765127944274944300 |  |
| `Fw.Console.row_land_iff` | agree | 5531654149564628976 | 18397925734428084636 |  |
| `Fw.Console.needsYou_open` | agree | 7477213801324521095 | 12002383940004787762 |  |
| `Fw.Site.Breakpoints.Px` | agree | 3931117990 | 17913368723994033257 |  |
| `Fw.Site.Breakpoints.Px.ofNat` | agree | 4072333195054466277 | 4218959273499520746 |  |
| `Fw.Site.Breakpoints.Px.half` | agree | 4072333195054466277 | 16499777893144811672 |  |
| `Fw.Site.Breakpoints.Px.LeNat` | agree | 7096535915876601691 | 7637888402522670257 |  |
| `Fw.Site.Breakpoints.Px.GeNat` | agree | 7096535915876601691 | 17611007937974618023 |  |
| `Fw.Site.Breakpoints.Px.GtNat` | agree | 7096535915876601691 | 7980819648763043899 |  |
| `Fw.Site.Breakpoints.Hover` | agree | 3931117990 | 18351134373316711743 |  |
| `Fw.Site.Breakpoints.Pointer` | agree | 3931117990 | 10149763747088790074 |  |
| `Fw.Site.Breakpoints.Motion` | agree | 3931117990 | 17048717871345575880 |  |
| `Fw.Site.Breakpoints.Scheme` | agree | 3931117990 | 13187464513456196087 |  |
| `Fw.Site.Breakpoints.MediaType` | agree | 3931117990 | 14142715030995335188 |  |
| `Fw.Site.Breakpoints.ForcedColors` | agree | 3931117990 | 5390408427818019291 |  |
| `Fw.Site.Breakpoints.Env` | agree | 3931117990 | 11587783553451915881 |  |
| `Fw.Site.Breakpoints.Feature` | agree | 3931117990 | 1084075765945461713 |  |
| `Fw.Site.Breakpoints.MQ` | agree | 3931117990 | 13335900101434239382 |  |
| `Fw.Site.Breakpoints.Feature.holds` | agree | 1045050589320357167 | 5869202859517272361 |  |
| `Fw.Site.Breakpoints.Feature.hoverKw` | agree | 8517941519576676982 | 1988575617293561518 |  |
| `Fw.Site.Breakpoints.Feature.pointerKw` | disagree | 11541671350412343288 | 15828782371547614532 | The math only says what set the output lies in, not which value maps to which keyword. Corrected: $$ \mathrm{kw}(\text{n |
| `Fw.Site.Breakpoints.Feature.motionKw` | disagree | 10586389568885586912 | 238296465932856005 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{no-preference}) = \texttt{no-prefer |
| `Fw.Site.Breakpoints.Feature.schemeKw` | disagree | 12677653796522396360 | 11897486381515970296 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{light}) = \texttt{light},\ \mathrm{ |
| `Fw.Site.Breakpoints.Feature.mediaTypeKw` | disagree | 4995273271618187308 | 15148775077865961843 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{screen}) = \texttt{screen},\ \mathr |
| `Fw.Site.Breakpoints.Feature.forcedColorsKw` | disagree | 9962850937898875830 | 6784334329196682916 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{none}) = \texttt{none},\ \mathrm{kw |
| `Fw.Site.Breakpoints.Feature.css` | agree | 8655417565931657463 | 12613821948218408645 |  |
| `Fw.Site.Breakpoints.Feature.legacyCss` | disagree | 15912396429203590419 | 15172504506548772673 | The math lists only the three width cases and has no '…'. It leaves out the device-width case and the fallback for every |
| `Fw.Site.Breakpoints.Feature.widthCuts` | agree | 17771451994150807742 | 8745551637093008004 |  |
| `Fw.Site.Breakpoints.Feature.dwCuts` | agree | 17771451994150807742 | 10207311202358556161 |  |
| `Fw.Site.Breakpoints.Feature.featureName` | agree | 8655417565931657463 | 14342157525018269154 |  |
| `Fw.Site.Breakpoints.Axis` | agree | 3931117990 | 9738583367806792800 |  |
| `Fw.Site.Breakpoints.Axis.str` | agree | 3612700067922898447 | 12388166936947045993 |  |
| `Fw.Site.Breakpoints.MQ.eval` | agree | 11779340078485218536 | 5049488637625556602 |  |
| `Fw.Site.Breakpoints.MQ.Holds` | agree | 7906256111189110998 | 6171837664652772149 |  |
| `Fw.Site.Breakpoints.MQ.css` | agree | 15542615623404991604 | 16037427951425214626 |  |
| `Fw.Site.Breakpoints.MQ.legacyCss` | disagree | 2243106494055417421 | 353890614426776274 | The math gives the value only when every feature has a legacy form. It never says the result is ⊥ (none) when some featu |
| `Fw.Site.Breakpoints.MQ.widthEdges` | agree | 2986497978992311516 | 10899124213278307238 |  |
| `Fw.Site.Breakpoints.MQ.dwEdges` | agree | 2986497978992311516 | 917884874992023640 |  |
| `Fw.Site.Breakpoints.MQ.armIsTouch` | agree | 17516449953543559167 | 3310400158637631759 |  |
| `Fw.Site.Breakpoints.MQ.pushNew` | agree | 2877742376 | 15389177578021982458 |  |
| `Fw.Site.Breakpoints.MQ.taggedEdges` | disagree | 16124553710885778221 | 11986600012849574566 | The math writes the axis as a(f), a function of the feature alone. In the Lean it depends on the arm: the same width fea |
| `Fw.Site.Breakpoints.MQ.features` | agree | 2886370339541503022 | 18260272342773163506 |  |
| `Fw.Site.Breakpoints.MQ.insertSorted` | agree | 3621448303 | 9801337332292550907 |  |
| `Fw.Site.Breakpoints.MQ.edgesPx` | agree | 2986497978992311516 | 6011075562579555373 |  |
| `Fw.Site.Breakpoints.touchArm` | agree | 9701560748527292498 | 10366724026867719310 |  |
| `Fw.Site.Breakpoints.combo` | disagree | 7068410760301491265 | 17369913711900603903 | The math covers only the default dw = true. The English mentions dw = false, but the math does not. Corrected: $$ C_{N,d |
| `Fw.Site.Breakpoints.rmReduce` | agree | 8816633351296686329 | 12103809525754701885 |  |
| `Fw.Site.Breakpoints.rmNopref` | agree | 8816633351296686329 | 15902526936934564434 |  |
| `Fw.Site.Breakpoints.hoverHover` | agree | 8816633351296686329 | 18056308814776342983 |  |
| `Fw.Site.Breakpoints.hoverNone` | agree | 8816633351296686329 | 10338053248361448971 |  |
| `Fw.Site.Breakpoints.dark` | agree | 8816633351296686329 | 9765683402157157626 |  |
| `Fw.Site.Breakpoints.wLe400` | agree | 8816633351296686329 | 8348282254388277093 |  |
| `Fw.Site.Breakpoints.wLe461` | agree | 8816633351296686329 | 6866065992533391445 |  |
| `Fw.Site.Breakpoints.wLe480` | agree | 8816633351296686329 | 8608350100091586481 |  |
| `Fw.Site.Breakpoints.wLe600` | agree | 8816633351296686329 | 7035907848406943677 |  |
| `Fw.Site.Breakpoints.wGt600` | agree | 8816633351296686329 | 6549280118417019024 |  |
| `Fw.Site.Breakpoints.w601to1279` | agree | 8816633351296686329 | 205642769654403136 |  |
| `Fw.Site.Breakpoints.w601to1511` | agree | 8816633351296686329 | 12772587498518683264 |  |
| `Fw.Site.Breakpoints.wLe640` | agree | 8816633351296686329 | 16658005649325600011 |  |
| `Fw.Site.Breakpoints.wGt640` | agree | 8816633351296686329 | 3868533895650221904 |  |
| `Fw.Site.Breakpoints.w641to1000` | agree | 8816633351296686329 | 5988583579935811486 |  |
| `Fw.Site.Breakpoints.wLe720` | agree | 8816633351296686329 | 17897927911612877973 |  |
| `Fw.Site.Breakpoints.wLe860` | agree | 8816633351296686329 | 5495159713818591202 |  |
| `Fw.Site.Breakpoints.wGe861` | agree | 8816633351296686329 | 14734680160485232308 |  |
| `Fw.Site.Breakpoints.wGe861Nopref` | agree | 8816633351296686329 | 15294395659479859159 |  |
| `Fw.Site.Breakpoints.w861to1000` | agree | 8816633351296686329 | 11755047654490723727 |  |
| `Fw.Site.Breakpoints.wLe960` | agree | 8816633351296686329 | 18195377528901970709 |  |
| `Fw.Site.Breakpoints.wLe1000` | agree | 8816633351296686329 | 14727138538616522105 |  |
| `Fw.Site.Breakpoints.wGe1001` | agree | 8816633351296686329 | 9305892156487665895 |  |
| `Fw.Site.Breakpoints.wGe1001Nopref` | agree | 8816633351296686329 | 18038864468541252131 |  |
| `Fw.Site.Breakpoints.wLe1100` | agree | 8816633351296686329 | 3489898555729289401 |  |
| `Fw.Site.Breakpoints.wLe1200` | agree | 8816633351296686329 | 11067678022282510961 |  |
| `Fw.Site.Breakpoints.c860` | agree | 8816633351296686329 | 392218470426627935 |  |
| `Fw.Site.Breakpoints.c1000` | agree | 8816633351296686329 | 12744995402660615725 |  |
| `Fw.Site.Breakpoints.c1030` | agree | 8816633351296686329 | 16702239210242199732 |  |
| `Fw.Site.Breakpoints.c1000Nodw` | agree | 8816633351296686329 | 5360198305889974659 |  |
| `Fw.Site.Breakpoints.Kind` | agree | 3931117990 | 1538332671723031977 |  |
| `Fw.Site.Breakpoints.Kind.str` | disagree | 14237671609296049918 | 14133871259592331756 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{str}(\text{css}) = \texttt{css-media},\ \math |
| `Fw.Site.Breakpoints.Entry` | agree | 3931117990 | 5866205250412894519 |  |
| `Fw.Site.Breakpoints.catalogue` | agree | 2307031085274928783 | 18436331802551495131 |  |
| `Fw.Site.Breakpoints.SameSide` | agree | 16249358684548411117 | 3311577713843916803 |  |
| `Fw.Site.Breakpoints.Agree` | agree | 17755211834335375684 | 17110695323098672876 |  |
| `Fw.Site.Breakpoints.Feature.holds_congr` | agree | 15427665126541568443 | 1372352884779829982 |  |
| `Fw.Site.Breakpoints.MQ.eval_congr` | agree | 2769574148000741954 | 5022840840230383866 |  |
| `Fw.Site.Breakpoints.sameSide_ofNat` | agree | 2427931563976877356 | 5742775459670465447 |  |
| `Fw.Site.Breakpoints.MQ.eval_ofNat_congr` | agree | 9126441099284617255 | 15041643637860900866 |  |
| `Fw.Site.Breakpoints.MQ.eval_const_on_band` | agree | 3118446114352664925 | 13052081720480498599 |  |
| `Fw.Site.Breakpoints.exEnv` | agree | 4590214137206919927 | 3982056496327241229 |  |
| `Fw.Site.BreakpointGen.pxJson` | agree | 18278780146456355905 | 5533900041229543976 |  |
| `Fw.Site.BreakpointGen.condJson` | agree | 441864611213246692 | 11609201964289846669 |  |
| `Fw.Site.BreakpointGen.probeJson` | agree | 2913516311795064609 | 127007308320451734 |  |
| `Fw.Site.BreakpointGen.backingTheorems` | agree | 4017531403 | 5663475453270856160 |  |
| `Fw.Site.BreakpointGen.gapsJson` | disagree | 2092839459 | 9756626353826157365 | The math leaves out the 'open' field [N, N+1] that each row carries, and writes the four N as a set although the Lean gi |
| `Fw.Site.BreakpointGen.genJson` | disagree | 2092839459 | 14387693938956765762 | The math leaves out four of the nine keys: schema, generatedBy, inventory and backingTheorems. Corrected: $$ \mathrm{gen |
| `Fw.Site.BreakpointGen.getK` | agree | 2948302846 | 5447883481910106889 |  |
| `Fw.Site.BreakpointGen.natList` | disagree | 2570588240 | 2543672901565861589 | The math gives only the type of the result and never says what the function returns. Corrected: $$ \mathrm{natList}(j) = |
| `Fw.Site.BreakpointGen.strList` | disagree | 3487363897 | 3080262283568632794 | The math gives only the type, and the notation Σ^{**} is unclear. Corrected: $$ \mathrm{strList}(j) = \begin{cases} (s_1 |
| `Fw.Site.BreakpointGen.checkCond` | disagree | 3212968224274080051 | 17423548965854939597 | The '…' hides three checks that are not like the ones listed. These are the id equality, edges_px, and the legacy check, |
| `Fw.Site.BreakpointGen.checkInventory` | disagree | 3987208917 | 3127758603730612888 | Math: the right-hand side does not require exactly 30 inventory rows with ids starting 'mq.', so an inventory with 31 su |
| `Fw.Site.BreakpointGen.opBreakpointsGen` | disagree | 1343264538 | 6286672070050512260 | The math does not cover the case with no inventory key (or a request that is not a JSON object). Then mismatches is [].  |
| `Fw.Site.BreakpointGen.argOf` | disagree | 3629300436 | 895281299333129885 | The math does not say which occurrence of the flag is used or what happens when there is none. Corrected: $$ \mathrm{arg |
| `Fw.Site.BreakpointGen.genText` | agree | 3265150928 | 17298519193102583907 |  |
| `Fw.Site.BreakpointGen.run` | disagree | 3653997261 | 7163200129681442629 | The math treats the inventory I as always present, although the check only runs when --inventory is given. It also leave |
| `Fw.Site.Breakpoints.catalogue_length` | agree | 4813953101150116340 | 7030728792998956597 |  |
| `Fw.Site.Breakpoints.catalogue_ids_nodup` | agree | 11735603663353112962 | 5684205540886451768 |  |
| `Fw.Site.Breakpoints.catalogue_queries_nodup` | agree | 5985161206020350712 | 8754865114380858550 |  |
| `Fw.Site.Breakpoints.catalogue_css` | disagree | 8822227599840045762 | 15702825438584193916 | The middle component reads ts_i = ts_i, which is trivially true. The Lean pins every TS id to a listed literal, and brea |
| `Fw.Site.Breakpoints.catalogue_edges` | agree | 9848713756460049940 | 9122185286131912818 |  |
| `Fw.Site.Breakpoints.catalogue_axis_edges` | disagree | 493148645378441950 | 11140025371480368828 | The Lean compares widthEdges/dwEdges with q.taggedEdges, i.e. E(q_i). It never mentions the inventory E^inv_i; that equa |
| `Fw.Site.Breakpoints.rmReduce_iff` | agree | 2754482394943459131 | 7584782007608003535 |  |
| `Fw.Site.Breakpoints.rmNopref_iff` | agree | 14229560986329898882 | 7524539103782321107 |  |
| `Fw.Site.Breakpoints.hoverHover_iff` | agree | 775586282956546733 | 14771991988054180804 |  |
| `Fw.Site.Breakpoints.hoverNone_iff` | agree | 15053463479868867122 | 2141537838220511036 |  |
| `Fw.Site.Breakpoints.dark_iff` | agree | 12749693712054367962 | 12050536395175206127 |  |
| `Fw.Site.Breakpoints.wLe400_iff` | agree | 2965619652168841648 | 12095624671156203497 |  |
| `Fw.Site.Breakpoints.wLe461_iff` | agree | 7180751918635845506 | 3009193746424604063 |  |
| `Fw.Site.Breakpoints.wLe480_iff` | agree | 5950459630504777352 | 2890444435677667896 |  |
| `Fw.Site.Breakpoints.wLe600_iff` | agree | 1582575865107752650 | 2488361400122746458 |  |
| `Fw.Site.Breakpoints.wGt600_iff` | agree | 5903782200731548089 | 9093369686493627753 |  |
| `Fw.Site.Breakpoints.w601to1279_iff` | agree | 15938534828435662945 | 16805095677110804848 |  |
| `Fw.Site.Breakpoints.w601to1511_iff` | agree | 10319793824664559752 | 1491912045150198814 |  |
| `Fw.Site.Breakpoints.wLe640_iff` | agree | 13023787175379663349 | 15209079465613530810 |  |
| `Fw.Site.Breakpoints.wGt640_iff` | agree | 17329696634209206890 | 16345856757489724590 |  |
| `Fw.Site.Breakpoints.w641to1000_iff` | agree | 12158101632812959265 | 3829477812373001646 |  |
| `Fw.Site.Breakpoints.wLe720_iff` | agree | 86482789400940946 | 846881315338471373 |  |
| `Fw.Site.Breakpoints.wLe860_iff` | agree | 7224345695466649736 | 6861427111993433841 |  |
| `Fw.Site.Breakpoints.wGe861_iff` | agree | 13701415924194183267 | 15005580019362819742 |  |
| `Fw.Site.Breakpoints.wGe861Nopref_iff` | agree | 7528226886334929428 | 1456191556718755326 |  |
| `Fw.Site.Breakpoints.w861to1000_iff` | agree | 4925604542099827639 | 5952409371639538330 |  |
| `Fw.Site.Breakpoints.wLe960_iff` | agree | 6706114282794223290 | 18151929854002190315 |  |
| `Fw.Site.Breakpoints.wLe1000_iff` | agree | 12860161655917198931 | 10774773741908726030 |  |
| `Fw.Site.Breakpoints.wGe1001_iff` | agree | 13993003391255503040 | 9699831144982079301 |  |
| `Fw.Site.Breakpoints.wGe1001Nopref_iff` | agree | 4037338309459686413 | 10622786188020078057 |  |
| `Fw.Site.Breakpoints.wLe1100_iff` | agree | 12320026628569895851 | 5248620944943330341 |  |
| `Fw.Site.Breakpoints.wLe1200_iff` | agree | 8717295903794055551 | 14380878696931699295 |  |
| `Fw.Site.Breakpoints.c860_iff` | agree | 6700993748852649631 | 10578205592099745079 |  |
| `Fw.Site.Breakpoints.c1000_iff` | agree | 10267009939020725391 | 3816912159384076917 |  |
| `Fw.Site.Breakpoints.c1030_iff` | agree | 13003440398790140928 | 11085541817454224184 |  |
| `Fw.Site.Breakpoints.c1000Nodw_iff` | agree | 17615162045923827680 | 15158225093132319456 |  |
| `Fw.Site.Breakpoints.MQ.eval_indep_height_dpr` | disagree | 150953926199545787 | 6563898970126659575 | The math is right. The English claims too much with 'so these inputs only affect the raster'. The theorem only says no m |
| `Fw.Site.Breakpoints.Touch` | agree | 14266252618192763646 | 4955313774649117751 |  |
| `Fw.Site.Breakpoints.c860_le_c1000_le_c1030` | agree | 14480883672605441850 | 13288263363661589515 |  |
| `Fw.Site.Breakpoints.c1000Nodw_vs_c1000` | agree | 8452300592367822839 | 2588946546235549363 |  |
| `Fw.Site.Breakpoints.overlap_c860_wGe861` | agree | 15619124058865174504 | 7551590751571151976 |  |
| `Fw.Site.Breakpoints.overlap_c1000_wGe1001` | agree | 5505353354389532623 | 5672975125545795477 |  |
| `Fw.Site.Breakpoints.overlap_c1000_wGe1001Nopref` | agree | 8103832356393367813 | 4689635324421583922 |  |
| `Fw.Site.Breakpoints.c860_not_wLe860` | agree | 9330387832644829921 | 631779839815344266 |  |
| `Fw.Site.Breakpoints.wLe860_imp_c860` | agree | 14005366252993884281 | 9756319885564506205 |  |
| `Fw.Site.Breakpoints.DeskDeck` | agree | 14266252618192763646 | 4585273338417640567 |  |
| `Fw.Site.Breakpoints.deskDeck_iff` | agree | 8476236492704102088 | 14682267655037947780 |  |
| `Fw.Site.Breakpoints.touchTablet_overlap` | agree | 7870894823190629306 | 12529425425428079894 |  |
| `Fw.Site.Breakpoints.smallScreen_overlap` | agree | 17816055609093782216 | 6494744401423441924 |  |
| `Fw.Site.Breakpoints.SplashSkip` | agree | 14266252618192763646 | 9979945793054155416 |  |
| `Fw.Site.Breakpoints.gap_iff` | agree | 14532106663806335115 | 10699776103918571904 |  |
| `Fw.Site.Breakpoints.no_gap_ofNat` | agree | 14323967264928370365 | 6287846198421457298 |  |
| `Fw.Site.Breakpoints.gap600` | disagree | 5885734290117569880 | 5888495814066144102 | The hypothesis is e.width = Px.half 600. Px is an unnormalised structure, so this means numerator 1201 and denominator 2 |
| `Fw.Site.Breakpoints.gap640` | disagree | 859655106780548044 | 3458353333377916595 | The hypothesis e.width = Px.half 640 is structural (numerator 1281, denominator 2), not equality of the rational value 6 |
| `Fw.Site.Breakpoints.gap860` | disagree | 15712535485144737834 | 14037067147750904991 | The hypothesis e.width = Px.half 860 is structural (numerator 1721, denominator 2), not equality of the value 860.5. Cor |
| `Fw.Site.Breakpoints.gap1000` | disagree | 3115260695612167849 | 12091687982972599141 | The hypothesis e.width = Px.half 1000 is structural (numerator 2001, denominator 2), not equality of the value 1000.5. C |
| `Fw.Site.Breakpoints.Block` | agree | 3931117990 | 4008732936203006770 |  |
| `Fw.Site.Breakpoints.Block.str` | agree | 14168622413134744325 | 14292465339541664885 |  |
| `Fw.Site.Breakpoints.Probe` | agree | 3931117990 | 6165576610007902027 |  |
| `Fw.Site.Breakpoints.Probe.id` | agree | 8465850341170074759 | 9668786624141376097 |  |
| `Fw.Site.Breakpoints.widthEdgePairs` | agree | 403126073 | 5888596588119450596 |  |
| `Fw.Site.Breakpoints.touchRmEdges` | agree | 403126073 | 10454734159883904117 |  |
| `Fw.Site.Breakpoints.deskEnv` | agree | 13031211126417946932 | 17526056812000369902 |  |
| `Fw.Site.Breakpoints.touchEnv` | agree | 13031211126417946932 | 2423449777054291495 |  |
| `Fw.Site.Breakpoints.touchDpr` | agree | 4072333195054466277 | 12653607340602048890 |  |
| `Fw.Site.Breakpoints.pairProbes` | disagree | 16401344891349483061 | 18383834765937451996 | 'w \in (N, N{+}1)' reads as the open interval. That is the fractional-gap notation used in the same modules (the invento |
| `Fw.Site.Breakpoints.pairProbes` | agree | 16401344891349483061 | 18383834765937451996 |  |
| `Fw.Site.Breakpoints.matrix` | agree | 15486733467404255180 | 13653916063026081809 |  |
| `Fw.Site.Breakpoints.blockBreakdown` | agree | 7698384732413646544 | 13674782617055934619 |  |
| `Fw.Site.Breakpoints.matrix_length` | agree | 3305579835702638752 | 12633632089489600303 |  |
| `Fw.Site.Breakpoints.matrix_blocks` | agree | 16420743716010329879 | 761553771108041323 |  |
| `Fw.Site.Breakpoints.matrix_ids_nodup` | agree | 10290266427220732949 | 11659478660316274633 |  |
| `Fw.Site.Breakpoints.hasWidth` | agree | 2666108497517128351 | 7510817907250528709 |  |
| `Fw.Site.Breakpoints.matrix_edge_pairs` | agree | 10748462675558628444 | 2442337394939180661 |  |
| `Fw.Site.Breakpoints.axisOf` | agree | 1778201040280022379 | 9212656321647765602 |  |
| `Fw.Site.Breakpoints.observesFlip` | agree | 13822093860133976471 | 1652186333098463806 |  |
| `Fw.Site.Breakpoints.matrix_observes_every_edge` | agree | 4823667171189682963 | 14070448053342434491 |  |
| `Fw.Site.Breakpoints.matrix_pairs_agree` | disagree | 10417332680251401871 | 13335863064230611035 | The Lean ranges over b in [desk, deskRm, touch, touchRm]. The math's bare '\forall b' claims every block, and the Englis |
| `Fw.Site.Breakpoints.matrix_fractional_in_gaps` | disagree | 1505920974450493977 | 15451575781568732680 | The math is right. 'The four fractional loads really probe the four gaps' claims too much: the theorem shows each fracti |
| `Fw.Site.Breakpoints.NeutralEntry` | agree | 3931117990 | 4920592272229167550 |  |
| `Fw.Site.Breakpoints.printQ` | agree | 8816633351296686329 | 14606526390346402730 |  |
| `Fw.Site.Breakpoints.forcedColorsActive` | agree | 8816633351296686329 | 14940723290195971344 |  |
| `Fw.Site.Breakpoints.neutral` | agree | 10308141888981362892 | 9803264883327745291 |  |
| `Fw.Site.Breakpoints.neutral_css` | agree | 9704173492473577609 | 5037756441334796556 |  |
| `Fw.Site.Breakpoints.neutral_inert` | agree | 5438528989706219869 | 9135731963956735938 |  |
| `Fw.Site.Breakpoints.matrix_neutral_inert` | agree | 1345100223142578434 | 2377151723454644703 |  |
| `Fw.Site.Breakpoints.matrix_neutral_hover_both_sides` | agree | 4240768969314310128 | 8988459588365235361 |  |
| `Fw.Site.Breakpoints.matrix_cross_no_touch_arm` | disagree | 2621992028648124515 | 10163182486108700179 | The range of the bound C in '\bigwedge_{C}' is not given. The Lean checks exactly [c860, c1000, c1030, c1000Nodw]. Corre |
| `Fw.Site.Breakpoints.matrix_dw_arm` | disagree | 9061226785275071384 | 13670402725780723654 | The math leaves out the viewport-1001 clause the Lean proves: at screen 501, c860 and c1000 fail, and c1030 holds iff w  |
| `Fw.Site.Breakpoints.matrix_landscape_overlaps` | disagree | 4628356883600564126 | 15232440623728280208 | The math is right. The parenthetical 'The inventory's phone-landscape.why claims both overlap pairs' is out of date. bre |
| `Fw.Parts.EngineScroll.Entry` | agree | 3931117990 | 13136082261974217220 |  |
| `Fw.Parts.EngineScroll.entryLe` | agree | 7361448915956510373 | 7280085063765696089 |  |
| `Fw.Parts.EngineScroll.orderCallbacks` | agree | 18222743277433483376 | 9017105535742068182 |  |
| `Fw.Parts.EngineScroll.entryLe_trans` | disagree | 7988356497936731972 | 6955541538265254311 | e_1, e_2, e_3 are free in the math, but Lean quantifies them. Corrected: $$\forall e_1, e_2, e_3:\ e_1 \sqsubseteq e_2 \ |
| `Fw.Parts.EngineScroll.entryLe_total` | agree | 8123712358316786938 | 14718518098950122615 |  |
| `Fw.Parts.EngineScroll.orderCallbacks_perm` | disagree | 6168987457941083824 | 2993726948191173199 | The math is right. The English 'Every registered callback runs exactly once per frame' says more than the theorem. The t |
| `Fw.Parts.EngineScroll.orderCallbacks_registration` | agree | 4358173630867911925 | 16402863246396668929 |  |
| `Fw.Parts.EngineScroll.Op` | agree | 3931117990 | 651312304305826376 |  |
| `Fw.Parts.EngineScroll.Step` | agree | 3931117990 | 4284904822105904389 |  |
| `Fw.Parts.EngineScroll.Variant` | agree | 3931117990 | 13740656789669461774 |  |
| `Fw.Parts.EngineScroll.faithfulFrom` | disagree | 13361383562450084038 | 12738801718644345682 | The math leaves out the empty-list case of the definition and uses an undefined subscript notation. Corrected: $$\operat |
| `Fw.Parts.EngineScroll.readsFrom` | agree | 13361383562450084038 | 15921663904326860418 |  |
| `Fw.Parts.EngineScroll.writesFrom` | agree | 13361383562450084038 | 13278987639060303390 |  |
| `Fw.Parts.EngineScroll.framePlan` | agree | 3561092999718987953 | 15755387507619748817 |  |
| `Fw.Parts.EngineScroll.Step.isRead` | agree | 6140234412873888924 | 4628365162077644155 |  |
| `Fw.Parts.EngineScroll.isRead_read` | disagree | 10519647688549933100 | 11513432795927843524 | k is free in the math. Corrected: $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{R}, k)) = \top$$ |
| `Fw.Parts.EngineScroll.isRead_write` | disagree | 8786802114933493103 | 16964618874816422369 | k is free in the math. Corrected: $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{W}, k)) = \bot$$ |
| `Fw.Parts.EngineScroll.filter_read_faithfulFrom` | agree | 15122301350270294261 | 16390265700856763661 |  |
| `Fw.Parts.EngineScroll.filter_write_faithfulFrom` | agree | 14318510705280555961 | 8562865053523555435 |  |
| `Fw.Parts.EngineScroll.batched_eq_partition` | agree | 4683570198628503505 | 11872895364988165528 |  |
| `Fw.Parts.EngineScroll.Access` | agree | 3931117990 | 15515268580225977560 |  |
| `Fw.Parts.EngineScroll.Access.isRead` | agree | 14356600851718168051 | 5053365070435364917 |  |
| `Fw.Parts.EngineScroll.Role` | agree | 3931117990 | 14548222046652555450 |  |
| `Fw.Parts.EngineScroll.forced` | agree | 7731021215424982811 | 6774059146294152655 |  |
| `Fw.Parts.EngineScroll.styleRole` | agree | 11192358764639391462 | 15400810602902499961 |  |
| `Fw.Parts.EngineScroll.layoutRole` | agree | 11192358764639391462 | 9320526694881304273 |  |
| `Fw.Parts.EngineScroll.Sound` | agree | 6140436841068638694 | 6920015701987489222 |  |
| `Fw.Parts.EngineScroll.styleRole_sound` | agree | 14715537200707048301 | 9590366767461736998 |  |
| `Fw.Parts.EngineScroll.layoutRole_sound` | agree | 2352389380107183149 | 4639501744385448848 |  |
| `Fw.Parts.EngineScroll.forced_mono` | disagree | 1609423361076244931 | 18309345136554935165 | d and e are free in the math, but Lean has ∀ d e : Bool. Corrected: $$\forall \rho, as, d, e:\quad (d \Rightarrow e) \Ri |
| `Fw.Parts.EngineScroll.forced_writes_only` | agree | 12837629268961068228 | 419402851218256686 |  |
| `Fw.Parts.EngineScroll.forced_append_writes` | agree | 8210279408565696474 | 16587510636351789189 |  |
| `Fw.Parts.EngineScroll.forced_filter_reads` | agree | 10897686221862582129 | 16668146786846478239 |  |
| `Fw.Parts.EngineScroll.batched_le_faithful` | agree | 14708927038877790630 | 15683853759013258457 |  |
| `Fw.Parts.EngineScroll.batched_le_one` | disagree | 6523135455901997002 | 89302469352260000 | The math leaves out the Lean hypothesis hr : ∀ a, a.isRead = true → role a ≠ dirty (no read dirties). Without it the sta |
| `Fw.Parts.EngineScroll.Step.access` | agree | 12367190869288398446 | 14028107723387200286 |  |
| `Fw.Parts.EngineScroll.planLayouts` | agree | 3995576727389197860 | 5830101715445736921 |  |
| `Fw.Parts.EngineScroll.framePlan_batched_le` | agree | 14350644170192163772 | 14683707868801587258 |  |
| `Fw.Parts.EngineScroll.planLayouts_faithfulFrom` | agree | 8390892567058049100 | 7749458840270223647 |  |
| `Fw.Parts.EngineScroll.countTrue` | agree | 27352352 | 5946734372100834036 |  |
| `Fw.Parts.EngineScroll.planLayouts_faithful_formula` | agree | 11815096367988426006 | 14497560843329894117 |  |
| `Fw.Parts.EngineScroll.framePlan_faithful_cost` | agree | 17862655528411164068 | 16315447473930572305 |  |
| `Fw.Parts.EngineScroll.shouldSchedule` | agree | 3551570259 | 17243050119790503035 |  |
| `Fw.Parts.EngineScroll.Ev` | agree | 3931117990 | 3006507734219078377 |  |
| `Fw.Parts.EngineScroll.runs` | agree | 14736101280669439234 | 4549859440137463471 |  |
| `Fw.Parts.EngineScroll.countEv` | agree | 6537709587684904777 | 15653356184905089788 |  |
| `Fw.Parts.EngineScroll.runs_le` | disagree | 8233303483154169168 | 736149722842010692 | The second clause is weaker than the Lean. Lean proves runs(p,es) ≤ [p] + #scroll(es) for every p, not only for p = ⊥. C |
| `Fw.Parts.EngineScroll.listenerAction` | agree | 2016497146 | 14240603113125250750 |  |
| `Fw.Parts.EngineScroll.attachedAfter` | agree | 2274047319 | 17356470057419336222 |  |
| `Fw.Parts.EngineScroll.listener_invariant` | agree | 11026370579894701198 | 16679001197550592916 |  |
| `Fw.Parts.EngineScroll.navAccesses` | agree | 18349000911985273043 | 5575113539029520180 |  |
| `Fw.Parts.EngineScroll.heroExitAccesses` | agree | 18349000911985273043 | 2698869015546963712 |  |
| `Fw.Parts.EngineScroll.pilotFrame` | agree | 18349000911985273043 | 17696462361490173643 |  |
| `Fw.Parts.NavHitTest.Rect` | agree | 3931117990 | 11592689886998519875 |  |
| `Fw.Parts.NavHitTest.hitPoint` | agree | 14901957181138238253 | 483008109737672002 |  |
| `Fw.Parts.NavHitTest.hitPoint_inside` | agree | 12884417283242980729 | 7755074558089362657 |  |
| `Fw.Parts.NavHitTest.HitFlags` | agree | 3931117990 | 6295149498243224212 |  |
| `Fw.Parts.NavHitTest.classifyHit` | agree | 16629056394570413191 | 6015768713077094917 |  |
| `Fw.Parts.NavHitTest.classifyHit_eq` | agree | 17028922986975454499 | 11369140835404488455 |  |
| `Fw.Parts.NavHitTest.Hit` | agree | 3931117990 | 14431069963832512509 |  |
| `Fw.Parts.NavHitTest.findIdx` | agree | 2759821197 | 4895529513120707566 |  |
| `Fw.Parts.NavHitTest.faithfulHit` | agree | 2559627907622085960 | 17047429305611267917 |  |
| `Fw.Parts.NavHitTest.firstOutside` | agree | 2055347128 | 12673276988523015097 |  |
| `Fw.Parts.NavHitTest.allowHit` | agree | 9085161766822827013 | 11866787540770806659 |  |
| `Fw.Parts.NavHitTest.findIdx?_congr'` | disagree | 4217177856 | 2323674831342738034 | p, q and xs are free in the math. Corrected: $$\forall p, q, xs:\ (\forall x \in xs:\ p(x) = q(x)) \Rightarrow \operator |
| `Fw.Parts.NavHitTest.findIdx_congr` | disagree | 6186552227763706826 | 10069668151130869450 | p, q and xs are free in the math. Corrected: $$\forall p, q, xs:\ (\forall x \in xs:\ p(x) = q(x)) \Rightarrow \operator |
| `Fw.Parts.NavHitTest.firstOutside_eq_faithful` | agree | 11932167822771133009 | 2138444055339071427 |  |
| `Fw.Parts.NavHitTest.firstOutside_ne_faithful` | agree | 13287047492367256617 | 8680683814734379089 |  |
| `Fw.Parts.NavHitTest.allowHit_eq_faithful` | agree | 11334693612211646547 | 2427941324384001727 |  |
| `Fw.Parts.NavHitTest.isOnDark` | agree | 1391933274 | 43883344705230778 |  |
| `Fw.Parts.NavHitTest.hitSkip_morph` | agree | 7721065760113074209 | 1829093977769143342 |  |
| `Fw.Parts.NavHitTest.expanded_masks` | agree | 10477559439836665216 | 10242243511217096944 |  |
| `Fw.Parts.NavHitTest.changed` | agree | 603921427 | 10675336410336426620 |  |
| `Fw.Parts.NavHitTest.changed_write` | agree | 13611140602711103690 | 12703793463427434520 |  |
| `Fw.Parts.Golden.decimal?` | disagree | 2024033954 | 12816417557472301234 | The math does not say which e is chosen (the least one), how m is computed, or when the result is none. The English 'ter |
| `Fw.Parts.Golden.ratWire` | agree | 893280584 | 17761878822637526096 |  |
| `Fw.Parts.Golden.rin` | disagree | 893280584 | 13834034456686091330 | The case split is on dec(q) ≠ none (q.den divides 10^40), not on 'terminating'. A terminating q such as 2^{-41} goes to  |
| `Fw.Parts.Golden.jint` | agree | 1534267800 | 8273399970892538992 |  |
| `Fw.Parts.Golden.jnat` | agree | 3511535342 | 7734209034783774822 |  |
| `Fw.Parts.Golden.line` | agree | 477717292 | 6144997611862224268 |  |
| `Fw.Parts.Golden.entryJ` | agree | 18382492738451195971 | 1375674107390520305 |  |
| `Fw.Parts.Golden.stepJ` | agree | 16558358169714686327 | 116281743879757721 |  |
| `Fw.Parts.Golden.variantName` | agree | 4419265992218905131 | 17587896214586012135 |  |
| `Fw.Parts.Golden.accessName` | agree | 14049959673292335267 | 9236797059863521936 |  |
| `Fw.Parts.Golden.writerPatterns` | agree | 944135888 | 13392012587298054257 |  |
| `Fw.Parts.Golden.engineLines` | agree | 4017531403 | 3903101987649387740 |  |
| `Fw.Parts.Golden.engineSpecLines` | agree | 4017531403 | 16090284475868854635 |  |
| `Fw.Parts.Golden.navLines` | agree | 4017531403 | 3408725901353919124 |  |
| `Fw.Parts.Golden.navSpecLines` | agree | 4017531403 | 3098531875912161514 |  |
| `Fw.Parts.Golden.springJ` | disagree | 12560250465617194318 | 7978912492249368177 | The math leaves out the Bool parameter `wire`, which picks the encoding. Corrected: $$\operatorname{springJ}(\mathit{wir |
| `Fw.Parts.Golden.t0Ms` | agree | 630578061 | 15227524694899609444 |  |
| `Fw.Parts.Golden.countdownLines` | agree | 4017531403 | 18085937567024952797 |  |
| `Fw.Parts.Golden.exitLines` | agree | 4017531403 | 7625209251597076961 |  |
| `Fw.Parts.Golden.exitSpecLines` | agree | 4017531403 | 4503190025606636439 |  |
| `Fw.Parts.Golden.main` | disagree | 3812987455 | 7579714911868924699 | The math claims a .spec.jsonl for every pilot part, but main writes no hero.countdown.spec.jsonl (7 files, not 8). Corre |
| `Fw.Parts.HeroCountdown.targetMs` | agree | 630578061 | 15978403685823867803 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds` | agree | 3357052557 | 10544128757032558905 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds_ceil` | agree | 9623017684188239461 | 11475289230752726269 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds_past` | agree | 17252441141463935142 | 14990390657943840293 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds_antitone` | agree | 13263800469960812416 | 17519779216238147573 |  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds` | agree | 3208536212 | 2368455314040938816 |  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds_range` | agree | 3273925259 | 11741334515494598276 |  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds_sum` | agree | 1830475066 | 16433739100994605912 |  |
| `Fw.Parts.HeroCountdown.lexLe` | disagree | 1402962434 | 1662803660365996291 | The Lean def is on all of List ℕ × List ℕ and is False whenever either list does not have length 4 (`\| _, _ => False`).  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds_mono` | agree | 1927385860548826942 | 4956211331581661110 |  |
| `Fw.Parts.HeroCountdown.countdown_mono_in_time` | agree | 8324429637704214165 | 10283695407398294289 |  |
| `Fw.Parts.HeroCountdown.digitCount` | agree | 2546708756 | 11939971550041493597 |  |
| `Fw.Parts.HeroCountdown.lt_pow_digitCount` | agree | 14210050943293497059 | 7606965992535250023 |  |
| `Fw.Parts.HeroCountdown.places` | agree | 3208536212 | 7658089508256616403 |  |
| `Fw.Parts.HeroCountdown.mag` | agree | 957469855 | 13551498800875296178 |  |
| `Fw.Parts.HeroCountdown.digitPlaces` | agree | 1794447402 | 6538887783951081446 |  |
| `Fw.Parts.HeroCountdown.digitAt` | agree | 3304664491 | 11093340827106276884 |  |
| `Fw.Parts.HeroCountdown.digitAt_lt_ten` | agree | 11308452361819927381 | 9210303409490167636 |  |
| `Fw.Parts.HeroCountdown.fromDigits` | agree | 434822048 | 9665358387840743741 |  |
| `Fw.Parts.HeroCountdown.foldl_places` | agree | 18257629500236174244 | 3351231214693936283 |  |
| `Fw.Parts.HeroCountdown.digits_spell_value` | agree | 3348882306738503192 | 10633399060878605279 |  |
| `Fw.Parts.HeroCountdown.fmod10` | agree | 3498294262 | 17063299129824009012 |  |
| `Fw.Parts.HeroCountdown.fmod10_bounds` | agree | 6106058782299224832 | 1000563912578511022 |  |
| `Fw.Parts.HeroCountdown.fmod10_eq` | agree | 1550200648620087179 | 10323018422251647329 |  |
| `Fw.Parts.HeroCountdown.faceDelta` | agree | 4102075218 | 5207956290899229174 |  |
| `Fw.Parts.HeroCountdown.faceDelta_bounds` | agree | 1765657586838722558 | 16933511984894406305 |  |
| `Fw.Parts.HeroCountdown.faceDelta_congr` | agree | 18054021516022710787 | 11731162376860428568 |  |
| `Fw.Parts.HeroCountdown.int_eq_zero_of_lt_one` | agree | 2143994458 | 3584686622891554057 |  |
| `Fw.Parts.HeroCountdown.eq_of_congr10` | agree | 2201938567 | 279287903224600257 |  |
| `Fw.Parts.HeroCountdown.faceOffsetPx` | agree | 1846951230 | 11234495983182364852 |  |
| `Fw.Parts.HeroCountdown.stripOffsetCells` | agree | 3498294262 | 11353568215508930542 |  |
| `Fw.Parts.HeroCountdown.stripEntryDigit` | agree | 2367048215 | 6606428159155033724 |  |
| `Fw.Parts.HeroCountdown.strip_shows_same` | agree | 946933924082827303 | 12433305422466753535 |  |
| `Fw.Parts.HeroCountdown.faceDelta_settled` | disagree | 7983538969637958331 | 17866929992854893961 | The math (faceDelta(k,d)=0 iff k=d for d,k in {0..9}) is exact. The English overclaims: 'only face d is in the window' m |
| `Fw.Parts.HeroCountdown.Spring` | agree | 3931117990 | 6544562720986835741 |  |
| `Fw.Parts.HeroCountdown.springSlice` | agree | 12098467325916994228 | 9502649675924519396 |  |
| `Fw.Parts.HeroCountdown.springLoop` | agree | 2350163406469253958 | 2703986969234574163 |  |
| `Fw.Parts.HeroCountdown.slices` | agree | 957469855 | 12297703337979706279 |  |
| `Fw.Parts.HeroCountdown.ratAbs` | agree | 3498294262 | 11923493873152212331 |  |
| `Fw.Parts.HeroCountdown.SpringResult` | agree | 3931117990 | 12418431285804984741 |  |
| `Fw.Parts.HeroCountdown.springStep` | agree | 17526496671657834267 | 4792247394591197546 |  |
| `Fw.Parts.HeroCountdown.springStep_done` | agree | 17086857977841775218 | 13661597356171087234 |  |
| `Fw.Parts.HeroCountdown.slices_nonpos` | disagree | 16536093956796953355 | 15106274446571096950 | The theorem only states slices(dt)=0 for dt in Q with dt <= 0. The math quantifies s and x* even though they do not appe |
| `Fw.Parts.HeroCountdown.ariaLabel` | agree | 2463753768 | 4632749565695311003 |  |
| `Fw.Parts.HeroCountdown.labelsEn` | agree | 4017531403 | 13718671715006492690 |  |
| `Fw.Parts.HeroCountdown.cellHeight` | agree | 2426920303 | 6557140348374864337 |  |
| `Fw.Parts.HeroCountdown.Metrics` | agree | 3931117990 | 5038958578659315733 |  |
| `Fw.Parts.HeroCountdown.countdownMetrics` | agree | 9743733877825822238 | 9889054164900024029 |  |
| `Fw.Parts.HeroCountdown.countdownMetrics_cell` | agree | 17717589558074875997 | 9433042980584616937 |  |
| `Fw.Parts.HeroExit.div_mul_pos` | agree | 2447392552 | 795816694990809383 |  |
| `Fw.Parts.HeroExit.div_unit` | agree | 1761855220 | 4318214647312413276 |  |
| `Fw.Parts.HeroExit.div_mono` | agree | 600061581 | 2469386771337766469 |  |
| `Fw.Parts.HeroExit.exitRange` | agree | 4035929107 | 17968987789875862624 |  |
| `Fw.Parts.HeroExit.exitClamp` | agree | 4035929107 | 11150360151934525084 |  |
| `Fw.Parts.HeroExit.exitOpacity` | agree | 1069553462 | 10865294257246399257 |  |
| `Fw.Parts.HeroExit.exitRange_pos` | agree | 7689710378224765277 | 15909458982433205179 |  |
| `Fw.Parts.HeroExit.exitOpacity_mem` | agree | 2643469646727665790 | 1154398951461625141 |  |
| `Fw.Parts.HeroExit.exitOpacityAt` | agree | 563956569 | 12531325526447457108 |  |
| `Fw.Parts.HeroExit.exitOpacity_antitone` | agree | 3718962435805654583 | 11080285931620227962 |  |
| `Fw.Parts.HeroExit.exitOpacity_lipschitz` | agree | 14359126316545583578 | 14768115260019608338 |  |
| `Fw.Parts.HeroExit.exitOpacity_before` | agree | 6793370726980835582 | 7580502863627149988 |  |
| `Fw.Parts.HeroExit.exitOpacity_after` | agree | 1353755058741054087 | 11710589526764897853 |  |
| `Fw.Parts.HeroExit.exitOpacity_linear` | agree | 15504784150233815547 | 3325341088217390124 |  |
| `Fw.Parts.HeroExit.exitScatter` | agree | 3498294262 | 5572940411083010391 |  |
| `Fw.Parts.HeroExit.pointerOff` | agree | 3512254526 | 8772121914088039637 |  |
| `Fw.Parts.HeroExit.ExitFrame` | agree | 3931117990 | 12601307950358710811 |  |
| `Fw.Parts.HeroExit.exitFrame` | agree | 17265211571709300474 | 14147267583668657368 |  |
| `Fw.Parts.HeroExit.pointerOff_mono` | disagree | 659160663682231139 | 4046721262918979518 | The math (upward closure in y) is exact. The English 'There is a single scroll position past which the hero ignores taps |
| `Fw.Parts.HeroExit.navHeroProgress` | agree | 1069553462 | 592422008255103116 |  |
| `Fw.Parts.HeroExit.navHeroProgress_eq` | agree | 515290461520100446 | 5475362855020847145 |  |
| `Fw.Parts.HeroExit.pill_threshold` | agree | 8915026869638937394 | 10018046756220763295 |  |
| `Fw.Parts.HeroExit.pointerOff_after_pill` | agree | 1694717317344030805 | 1780990278998805907 |  |
| `Fw.Parts.HeroExit.le600` | agree | 3512254526 | 12310471514231097616 |  |
| `Fw.Parts.HeroExit.trackHeightPx` | agree | 4174302566 | 16543498520810198505 |  |
| `Fw.Parts.HeroExit.heroHeightPx` | agree | 1979205980 | 7893636074051702496 |  |
| `Fw.Parts.HeroExit.exitRange_200vh` | agree | 3558768072629428061 | 15671064533990716389 |  |
| `Fw.Parts.HeroExit.copyOpacity` | agree | 4035929107 | 1828898674383265073 |  |
| `Fw.Parts.HeroExit.copyBlurPx` | agree | 1018237883 | 2328871480761766185 |  |
| `Fw.Parts.HeroExit.copyTranslateYPx` | agree | 1018237883 | 4481433714250446198 |  |
| `Fw.Parts.HeroExit.cueBlurPx` | agree | 3498294262 | 10144800049802057800 |  |
| `Fw.Parts.HeroExit.cueTranslateYPx` | agree | 1979205980 | 12852665742412586194 |  |
| `Fw.Parts.HeroExit.cueBlurPxFull` | agree | 3940620593 | 1096153556372270977 |  |
| `Fw.Parts.HeroExit.cueTranslateYPxFull` | agree | 3940620593 | 17323592666237764688 |  |
| `Fw.Parts.HeroExit.cue_ts_eq_full` | agree | 7831753282674862612 | 5002982563940319138 |  |
| `Fw.Parts.HeroExit.cardOpacity` | agree | 3498294262 | 1543999893092785140 |  |
| `Fw.Parts.HeroExit.cardTranslate` | agree | 563956569 | 9813137111308945784 |  |
| `Fw.Parts.HeroExit.consumers_range` | agree | 18030891850317274653 | 9913926571115196603 |  |
| `Fw.Parts.HeroExit.consumers_mono` | agree | 14216743761854297805 | 5647813343167162115 |  |
| `Fw.Parts.HeroExit.band_edge_jump` | agree | 9314435668886194708 | 8711869443506120266 |  |
