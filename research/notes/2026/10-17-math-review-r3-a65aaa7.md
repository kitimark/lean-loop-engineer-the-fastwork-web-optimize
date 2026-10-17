---
title: Math review batch at a65aaa7 (Null fixes, Fw/Site breakpoints, Fw/Parts pilot parts)
date: 2026-10-17
status: CONFIRMED
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

| Declaration | Verdict | stmtHash | Note |
|---|---|---|---|
| `Fw.Null.falseBetterProb` | agree | 860301984 |  |
| `Fw.Null.land_null_prob` | agree | 7959650623826516976 |  |
| `Fw.Null.null_prob_5v5` | disagree | 18075036907877158627 | The theorem only covers the enumerated ranks 0..9 (falseBetterProb(5,5) = 1/252 = pNull(5,5)). The English says that for |
| `Fw.Null.null_prob_3v3` | disagree | 6489614198802959727 | Same problem as 5v5. The theorem is about the ranks 0..5 only, but the English says 'if the 6 run values are distinct .. |
| `Fw.Null.null_bound_4v4_5v5` | agree | 13590118229325669411 |  |
| `Fw.Null.binom` | agree | 9906956 |  |
| `Fw.Null.binom_zero_right` | agree | 15351676995500341385 |  |
| `Fw.Null.arr_length` | agree | 6098919412702702742 |  |
| `Fw.Null.binom_eq_zero` | agree | 10213509599131773290 |  |
| `Fw.Null.binom_pos` | agree | 13944111334432034498 |  |
| `Fw.Null.binom_succ_mul` | agree | 10610575094240758861 |  |
| `Fw.Null.choose_eq_binom` | agree | 7601004443219580183 |  |
| `Fw.Null.arr_length_choose` | agree | 4696931272336502918 |  |
| `Fw.Null.pAt_le_choose` | agree | 2593624135157745674 |  |
| `Fw.Null.mem_arr_iff` | agree | 4456310157590566565 |  |
| `Fw.Null.sel_cons` | agree | 6845860071509534681 |  |
| `Fw.Null.length_sel` | agree | 10014879156367004796 |  |
| `Fw.Null.count_true_add_false` | agree | 1890346558 |  |
| `Fw.Null.winsAt_tooFew` | agree | 5460991786832817118 |  |
| `Fw.Null.pAt_le_pNull` | agree | 4997353542246541774 |  |
| `Fw.Null.countP_lt_getElem` | agree | 423003686 |  |
| `Fw.Null.exists_threshold` | agree | 1817194464 |  |
| `Fw.Null.sel_map` | agree | 3332777758037570543 |  |
| `Fw.Null.winsAt_distinct` | agree | 15444386159274227470 |  |
| `Fw.Null.pAt_distinct` | agree | 14518739939440582959 |  |
| `Fw.Null.idx` | agree | 194866052 |  |
| `Fw.Null.idx_nodup` | agree | 15745456884505072103 |  |
| `Fw.Null.sel_range'_zipIdx` | agree | 3224315198428932811 |  |
| `Fw.Null.sel_idx` | agree | 11853072681352084826 |  |
| `Fw.Null.wins_eq_winsAt` | agree | 3750686122587801333 |  |
| `Fw.Null.falseBetterProb_eq_pAt` | agree | 3857949560676488909 |  |
| `Fw.Null.falseBetterProb_eq_pNull` | agree | 6902466217297490824 |  |
| `Fw.DeviceQueue.aged_beats_newer` | agree | 15459606977995552882 |  |
| `Fw.DeviceQueue.aged_not_overtaken` | agree | 4576601346776850582 |  |
| `Fw.DeviceQueue.unfit_never_starts` | agree | 8527852579920561340 |  |
| `Fw.Console.apply_idem` | agree | 3457108694390581116 |  |
| `Fw.Console.step_twice` | agree | 9714917595780000811 |  |
| `Fw.Null.arr` | agree | 2156174291 |  |
| `Fw.Null.choose` | agree | 9906956 |  |
| `Fw.Null.mem_sel` | agree | 265976095466000211 |  |
| `Fw.Null.count_le_of_imp` | agree | 3203879953 |  |
| `Fw.Null.eq_of_imp_count` | agree | 1807836024 |  |
| `Fw.Null.exists_true_false` | agree | 3957103838 |  |
| `Fw.Null.better_labeling_unique` | agree | 16412428810120312908 |  |
| `Fw.Null.mem_arr` | agree | 5155449431602400388 |  |
| `Fw.Null.arr_nodup` | agree | 4314025201853021758 |  |
| `Fw.Null.pAt_le` | agree | 15759822915449477623 |  |
| `Fw.Screen.leRun_spec` | disagree | 4317423620043076293 | The theorem proves only one direction: leRun(A,B) = true ⇒ \|A\| = \|B\| ∧ ∀(a,b) ∈ zip(A,B): leVec(a,b) = true. The math sa |
| `Fw.Screen.screen_sound` | agree | 4893661066027004847 |  |
| `Fw.Screen.screen_worse` | agree | 4520597471776880158 |  |
| `Fw.DeviceQueue.pickFrom_mem` | agree | 16251276072432502774 |  |
| `Fw.DeviceQueue.pickFrom_min` | agree | 13753620637482727604 |  |
| `Fw.DeviceQueue.pick_mem` | agree | 998680076973344239 |  |
| `Fw.DeviceQueue.pick_min` | agree | 3776949175604853632 |  |
| `Fw.DeviceQueue.dispatch_sound` | agree | 12218688316977063020 |  |
| `Fw.DeviceQueue.dispatch_conserving` | agree | 8192037010574851540 |  |
| `Fw.DeviceQueue.tick` | agree | 16832978777630894550 |  |
| `Fw.DeviceQueue.tick_kills_at_end` | agree | 6102650412667366667 |  |
| `Fw.ArtifactKey.key_sound` | agree | 1180814373860987346 |  |
| `Fw.Console.check` | agree | 15525871426033652860 |  |
| `Fw.Console.cardRefusal` | disagree | 8236380120697394169 | The case logic matches the Lean, but three rows contain the typo ';\\' (Fw/Console.lean lines 263-265). Inside a cases e |
| `Fw.Console.step_seen` | agree | 14915868186065857208 |  |
| `Fw.Console.refused_keeps` | agree | 17583266435552637075 |  |
| `Fw.Console.reject_keeps` | agree | 2648021860265739531 |  |
| `Fw.Console.accepted_may` | agree | 3788779216404152911 |  |
| `Fw.Console.unauthorized_rejected` | agree | 7476724112126248501 |  |
| `Fw.Console.only_user_answers` | agree | 16272176427751620566 |  |
| `Fw.Console.landed_fact_accepted` | agree | 7264281319390737123 |  |
| `Fw.Console.mapCards_inv` | agree | 16293827612537708154 |  |
| `Fw.Console.built_resets` | agree | 11911687894591051117 |  |
| `Fw.Console.stale_mono` | agree | 3129061074166289019 |  |
| `Fw.Console.stale_live` | agree | 15962886855132078421 |  |
| `Fw.Console.landed_not_stale` | agree | 7533175139842912656 |  |
| `Fw.Console.running_not_stale` | agree | 15847615884454301378 |  |
| `Fw.Console.row_land_iff` | agree | 5531654149564628976 |  |
| `Fw.Console.needsYou_open` | agree | 7477213801324521095 |  |
| `Fw.Site.Breakpoints.Px` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Px.ofNat` | agree | 4072333195054466277 |  |
| `Fw.Site.Breakpoints.Px.half` | agree | 4072333195054466277 |  |
| `Fw.Site.Breakpoints.Px.LeNat` | agree | 7096535915876601691 |  |
| `Fw.Site.Breakpoints.Px.GeNat` | agree | 7096535915876601691 |  |
| `Fw.Site.Breakpoints.Px.GtNat` | agree | 7096535915876601691 |  |
| `Fw.Site.Breakpoints.Hover` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Pointer` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Motion` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Scheme` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.MediaType` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.ForcedColors` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Env` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Feature` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.MQ` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Feature.holds` | agree | 1045050589320357167 |  |
| `Fw.Site.Breakpoints.Feature.hoverKw` | agree | 8517941519576676982 |  |
| `Fw.Site.Breakpoints.Feature.pointerKw` | disagree | 11541671350412343288 | The math only says what set the output lies in, not which value maps to which keyword. Corrected: $$ \mathrm{kw}(\text{n |
| `Fw.Site.Breakpoints.Feature.motionKw` | disagree | 10586389568885586912 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{no-preference}) = \texttt{no-prefer |
| `Fw.Site.Breakpoints.Feature.schemeKw` | disagree | 12677653796522396360 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{light}) = \texttt{light},\ \mathrm{ |
| `Fw.Site.Breakpoints.Feature.mediaTypeKw` | disagree | 4995273271618187308 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{screen}) = \texttt{screen},\ \mathr |
| `Fw.Site.Breakpoints.Feature.forcedColorsKw` | disagree | 9962850937898875830 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{kw}(\text{none}) = \texttt{none},\ \mathrm{kw |
| `Fw.Site.Breakpoints.Feature.css` | agree | 8655417565931657463 |  |
| `Fw.Site.Breakpoints.Feature.legacyCss` | disagree | 15912396429203590419 | The math lists only the three width cases and has no '…'. It leaves out the device-width case and the fallback for every |
| `Fw.Site.Breakpoints.Feature.widthCuts` | agree | 17771451994150807742 |  |
| `Fw.Site.Breakpoints.Feature.dwCuts` | agree | 17771451994150807742 |  |
| `Fw.Site.Breakpoints.Feature.featureName` | agree | 8655417565931657463 |  |
| `Fw.Site.Breakpoints.Axis` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Axis.str` | agree | 3612700067922898447 |  |
| `Fw.Site.Breakpoints.MQ.eval` | agree | 11779340078485218536 |  |
| `Fw.Site.Breakpoints.MQ.Holds` | agree | 7906256111189110998 |  |
| `Fw.Site.Breakpoints.MQ.css` | agree | 15542615623404991604 |  |
| `Fw.Site.Breakpoints.MQ.legacyCss` | disagree | 2243106494055417421 | The math gives the value only when every feature has a legacy form. It never says the result is ⊥ (none) when some featu |
| `Fw.Site.Breakpoints.MQ.widthEdges` | agree | 2986497978992311516 |  |
| `Fw.Site.Breakpoints.MQ.dwEdges` | agree | 2986497978992311516 |  |
| `Fw.Site.Breakpoints.MQ.armIsTouch` | agree | 17516449953543559167 |  |
| `Fw.Site.Breakpoints.MQ.pushNew` | agree | 2877742376 |  |
| `Fw.Site.Breakpoints.MQ.taggedEdges` | disagree | 16124553710885778221 | The math writes the axis as a(f), a function of the feature alone. In the Lean it depends on the arm: the same width fea |
| `Fw.Site.Breakpoints.MQ.features` | agree | 2886370339541503022 |  |
| `Fw.Site.Breakpoints.MQ.insertSorted` | agree | 3621448303 |  |
| `Fw.Site.Breakpoints.MQ.edgesPx` | agree | 2986497978992311516 |  |
| `Fw.Site.Breakpoints.touchArm` | agree | 9701560748527292498 |  |
| `Fw.Site.Breakpoints.combo` | disagree | 7068410760301491265 | The math covers only the default dw = true. The English mentions dw = false, but the math does not. Corrected: $$ C_{N,d |
| `Fw.Site.Breakpoints.rmReduce` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.rmNopref` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.hoverHover` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.hoverNone` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.dark` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe400` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe461` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe480` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe600` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wGt600` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.w601to1279` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.w601to1511` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe640` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wGt640` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.w641to1000` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe720` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe860` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wGe861` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wGe861Nopref` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.w861to1000` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe960` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe1000` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wGe1001` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wGe1001Nopref` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe1100` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.wLe1200` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.c860` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.c1000` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.c1030` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.c1000Nodw` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.Kind` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Kind.str` | disagree | 14237671609296049918 | The math gives only the output set, not the mapping. Corrected: $$ \mathrm{str}(\text{css}) = \texttt{css-media},\ \math |
| `Fw.Site.Breakpoints.Entry` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.catalogue` | agree | 2307031085274928783 |  |
| `Fw.Site.Breakpoints.SameSide` | agree | 16249358684548411117 |  |
| `Fw.Site.Breakpoints.Agree` | agree | 17755211834335375684 |  |
| `Fw.Site.Breakpoints.Feature.holds_congr` | agree | 15427665126541568443 |  |
| `Fw.Site.Breakpoints.MQ.eval_congr` | agree | 2769574148000741954 |  |
| `Fw.Site.Breakpoints.sameSide_ofNat` | agree | 2427931563976877356 |  |
| `Fw.Site.Breakpoints.MQ.eval_ofNat_congr` | agree | 9126441099284617255 |  |
| `Fw.Site.Breakpoints.MQ.eval_const_on_band` | agree | 3118446114352664925 |  |
| `Fw.Site.Breakpoints.exEnv` | agree | 4590214137206919927 |  |
| `Fw.Site.BreakpointGen.pxJson` | agree | 18278780146456355905 |  |
| `Fw.Site.BreakpointGen.condJson` | agree | 441864611213246692 |  |
| `Fw.Site.BreakpointGen.probeJson` | agree | 2913516311795064609 |  |
| `Fw.Site.BreakpointGen.backingTheorems` | agree | 4017531403 |  |
| `Fw.Site.BreakpointGen.gapsJson` | disagree | 2092839459 | The math leaves out the 'open' field [N, N+1] that each row carries, and writes the four N as a set although the Lean gi |
| `Fw.Site.BreakpointGen.genJson` | disagree | 2092839459 | The math leaves out four of the nine keys: schema, generatedBy, inventory and backingTheorems. Corrected: $$ \mathrm{gen |
| `Fw.Site.BreakpointGen.getK` | agree | 2948302846 |  |
| `Fw.Site.BreakpointGen.natList` | disagree | 2570588240 | The math gives only the type of the result and never says what the function returns. Corrected: $$ \mathrm{natList}(j) = |
| `Fw.Site.BreakpointGen.strList` | disagree | 3487363897 | The math gives only the type, and the notation Σ^{**} is unclear. Corrected: $$ \mathrm{strList}(j) = \begin{cases} (s_1 |
| `Fw.Site.BreakpointGen.checkCond` | disagree | 3212968224274080051 | The '…' hides three checks that are not like the ones listed. These are the id equality, edges_px, and the legacy check, |
| `Fw.Site.BreakpointGen.checkInventory` | disagree | 3987208917 | Math: the right-hand side does not require exactly 30 inventory rows with ids starting 'mq.', so an inventory with 31 su |
| `Fw.Site.BreakpointGen.opBreakpointsGen` | disagree | 1343264538 | The math does not cover the case with no inventory key (or a request that is not a JSON object). Then mismatches is [].  |
| `Fw.Site.BreakpointGen.argOf` | disagree | 3629300436 | The math does not say which occurrence of the flag is used or what happens when there is none. Corrected: $$ \mathrm{arg |
| `Fw.Site.BreakpointGen.genText` | agree | 3265150928 |  |
| `Fw.Site.BreakpointGen.run` | disagree | 3653997261 | The math treats the inventory I as always present, although the check only runs when --inventory is given. It also leave |
| `Fw.Site.Breakpoints.catalogue_length` | agree | 4813953101150116340 |  |
| `Fw.Site.Breakpoints.catalogue_ids_nodup` | agree | 11735603663353112962 |  |
| `Fw.Site.Breakpoints.catalogue_queries_nodup` | agree | 5985161206020350712 |  |
| `Fw.Site.Breakpoints.catalogue_css` | disagree | 8822227599840045762 | The middle component reads ts_i = ts_i, which is trivially true. The Lean pins every TS id to a listed literal, and brea |
| `Fw.Site.Breakpoints.catalogue_edges` | agree | 9848713756460049940 |  |
| `Fw.Site.Breakpoints.catalogue_axis_edges` | disagree | 493148645378441950 | The Lean compares widthEdges/dwEdges with q.taggedEdges, i.e. E(q_i). It never mentions the inventory E^inv_i; that equa |
| `Fw.Site.Breakpoints.rmReduce_iff` | agree | 2754482394943459131 |  |
| `Fw.Site.Breakpoints.rmNopref_iff` | agree | 14229560986329898882 |  |
| `Fw.Site.Breakpoints.hoverHover_iff` | agree | 775586282956546733 |  |
| `Fw.Site.Breakpoints.hoverNone_iff` | agree | 15053463479868867122 |  |
| `Fw.Site.Breakpoints.dark_iff` | agree | 12749693712054367962 |  |
| `Fw.Site.Breakpoints.wLe400_iff` | agree | 2965619652168841648 |  |
| `Fw.Site.Breakpoints.wLe461_iff` | agree | 7180751918635845506 |  |
| `Fw.Site.Breakpoints.wLe480_iff` | agree | 5950459630504777352 |  |
| `Fw.Site.Breakpoints.wLe600_iff` | agree | 1582575865107752650 |  |
| `Fw.Site.Breakpoints.wGt600_iff` | agree | 5903782200731548089 |  |
| `Fw.Site.Breakpoints.w601to1279_iff` | agree | 15938534828435662945 |  |
| `Fw.Site.Breakpoints.w601to1511_iff` | agree | 10319793824664559752 |  |
| `Fw.Site.Breakpoints.wLe640_iff` | agree | 13023787175379663349 |  |
| `Fw.Site.Breakpoints.wGt640_iff` | agree | 17329696634209206890 |  |
| `Fw.Site.Breakpoints.w641to1000_iff` | agree | 12158101632812959265 |  |
| `Fw.Site.Breakpoints.wLe720_iff` | agree | 86482789400940946 |  |
| `Fw.Site.Breakpoints.wLe860_iff` | agree | 7224345695466649736 |  |
| `Fw.Site.Breakpoints.wGe861_iff` | agree | 13701415924194183267 |  |
| `Fw.Site.Breakpoints.wGe861Nopref_iff` | agree | 7528226886334929428 |  |
| `Fw.Site.Breakpoints.w861to1000_iff` | agree | 4925604542099827639 |  |
| `Fw.Site.Breakpoints.wLe960_iff` | agree | 6706114282794223290 |  |
| `Fw.Site.Breakpoints.wLe1000_iff` | agree | 12860161655917198931 |  |
| `Fw.Site.Breakpoints.wGe1001_iff` | agree | 13993003391255503040 |  |
| `Fw.Site.Breakpoints.wGe1001Nopref_iff` | agree | 4037338309459686413 |  |
| `Fw.Site.Breakpoints.wLe1100_iff` | agree | 12320026628569895851 |  |
| `Fw.Site.Breakpoints.wLe1200_iff` | agree | 8717295903794055551 |  |
| `Fw.Site.Breakpoints.c860_iff` | agree | 6700993748852649631 |  |
| `Fw.Site.Breakpoints.c1000_iff` | agree | 10267009939020725391 |  |
| `Fw.Site.Breakpoints.c1030_iff` | agree | 13003440398790140928 |  |
| `Fw.Site.Breakpoints.c1000Nodw_iff` | agree | 17615162045923827680 |  |
| `Fw.Site.Breakpoints.MQ.eval_indep_height_dpr` | disagree | 150953926199545787 | The math is right. The English claims too much with 'so these inputs only affect the raster'. The theorem only says no m |
| `Fw.Site.Breakpoints.Touch` | agree | 14266252618192763646 |  |
| `Fw.Site.Breakpoints.c860_le_c1000_le_c1030` | agree | 14480883672605441850 |  |
| `Fw.Site.Breakpoints.c1000Nodw_vs_c1000` | agree | 8452300592367822839 |  |
| `Fw.Site.Breakpoints.overlap_c860_wGe861` | agree | 15619124058865174504 |  |
| `Fw.Site.Breakpoints.overlap_c1000_wGe1001` | agree | 5505353354389532623 |  |
| `Fw.Site.Breakpoints.overlap_c1000_wGe1001Nopref` | agree | 8103832356393367813 |  |
| `Fw.Site.Breakpoints.c860_not_wLe860` | agree | 9330387832644829921 |  |
| `Fw.Site.Breakpoints.wLe860_imp_c860` | agree | 14005366252993884281 |  |
| `Fw.Site.Breakpoints.DeskDeck` | agree | 14266252618192763646 |  |
| `Fw.Site.Breakpoints.deskDeck_iff` | agree | 8476236492704102088 |  |
| `Fw.Site.Breakpoints.touchTablet_overlap` | agree | 7870894823190629306 |  |
| `Fw.Site.Breakpoints.smallScreen_overlap` | agree | 17816055609093782216 |  |
| `Fw.Site.Breakpoints.SplashSkip` | agree | 14266252618192763646 |  |
| `Fw.Site.Breakpoints.gap_iff` | agree | 14532106663806335115 |  |
| `Fw.Site.Breakpoints.no_gap_ofNat` | agree | 14323967264928370365 |  |
| `Fw.Site.Breakpoints.gap600` | disagree | 5885734290117569880 | The hypothesis is e.width = Px.half 600. Px is an unnormalised structure, so this means numerator 1201 and denominator 2 |
| `Fw.Site.Breakpoints.gap640` | disagree | 859655106780548044 | The hypothesis e.width = Px.half 640 is structural (numerator 1281, denominator 2), not equality of the rational value 6 |
| `Fw.Site.Breakpoints.gap860` | disagree | 15712535485144737834 | The hypothesis e.width = Px.half 860 is structural (numerator 1721, denominator 2), not equality of the value 860.5. Cor |
| `Fw.Site.Breakpoints.gap1000` | disagree | 3115260695612167849 | The hypothesis e.width = Px.half 1000 is structural (numerator 2001, denominator 2), not equality of the value 1000.5. C |
| `Fw.Site.Breakpoints.Block` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Block.str` | agree | 14168622413134744325 |  |
| `Fw.Site.Breakpoints.Probe` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.Probe.id` | agree | 8465850341170074759 |  |
| `Fw.Site.Breakpoints.widthEdgePairs` | agree | 403126073 |  |
| `Fw.Site.Breakpoints.touchRmEdges` | agree | 403126073 |  |
| `Fw.Site.Breakpoints.deskEnv` | agree | 13031211126417946932 |  |
| `Fw.Site.Breakpoints.touchEnv` | agree | 13031211126417946932 |  |
| `Fw.Site.Breakpoints.touchDpr` | agree | 4072333195054466277 |  |
| `Fw.Site.Breakpoints.pairProbes` | disagree | 16401344891349483061 | 'w \in (N, N{+}1)' reads as the open interval. That is the fractional-gap notation used in the same modules (the invento |
| `Fw.Site.Breakpoints.pairProbes` | agree | 16401344891349483061 |  |
| `Fw.Site.Breakpoints.matrix` | agree | 15486733467404255180 |  |
| `Fw.Site.Breakpoints.blockBreakdown` | agree | 7698384732413646544 |  |
| `Fw.Site.Breakpoints.matrix_length` | agree | 3305579835702638752 |  |
| `Fw.Site.Breakpoints.matrix_blocks` | agree | 16420743716010329879 |  |
| `Fw.Site.Breakpoints.matrix_ids_nodup` | agree | 10290266427220732949 |  |
| `Fw.Site.Breakpoints.hasWidth` | agree | 2666108497517128351 |  |
| `Fw.Site.Breakpoints.matrix_edge_pairs` | agree | 10748462675558628444 |  |
| `Fw.Site.Breakpoints.axisOf` | agree | 1778201040280022379 |  |
| `Fw.Site.Breakpoints.observesFlip` | agree | 13822093860133976471 |  |
| `Fw.Site.Breakpoints.matrix_observes_every_edge` | agree | 4823667171189682963 |  |
| `Fw.Site.Breakpoints.matrix_pairs_agree` | disagree | 10417332680251401871 | The Lean ranges over b in [desk, deskRm, touch, touchRm]. The math's bare '\forall b' claims every block, and the Englis |
| `Fw.Site.Breakpoints.matrix_fractional_in_gaps` | disagree | 1505920974450493977 | The math is right. 'The four fractional loads really probe the four gaps' claims too much: the theorem shows each fracti |
| `Fw.Site.Breakpoints.NeutralEntry` | agree | 3931117990 |  |
| `Fw.Site.Breakpoints.printQ` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.forcedColorsActive` | agree | 8816633351296686329 |  |
| `Fw.Site.Breakpoints.neutral` | agree | 10308141888981362892 |  |
| `Fw.Site.Breakpoints.neutral_css` | agree | 9704173492473577609 |  |
| `Fw.Site.Breakpoints.neutral_inert` | agree | 5438528989706219869 |  |
| `Fw.Site.Breakpoints.matrix_neutral_inert` | agree | 1345100223142578434 |  |
| `Fw.Site.Breakpoints.matrix_neutral_hover_both_sides` | agree | 4240768969314310128 |  |
| `Fw.Site.Breakpoints.matrix_cross_no_touch_arm` | disagree | 2621992028648124515 | The range of the bound C in '\bigwedge_{C}' is not given. The Lean checks exactly [c860, c1000, c1030, c1000Nodw]. Corre |
| `Fw.Site.Breakpoints.matrix_dw_arm` | disagree | 9061226785275071384 | The math leaves out the viewport-1001 clause the Lean proves: at screen 501, c860 and c1000 fail, and c1030 holds iff w  |
| `Fw.Site.Breakpoints.matrix_landscape_overlaps` | disagree | 4628356883600564126 | The math is right. The parenthetical 'The inventory's phone-landscape.why claims both overlap pairs' is out of date. bre |
| `Fw.Parts.EngineScroll.Entry` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.entryLe` | agree | 7361448915956510373 |  |
| `Fw.Parts.EngineScroll.orderCallbacks` | agree | 18222743277433483376 |  |
| `Fw.Parts.EngineScroll.entryLe_trans` | disagree | 7988356497936731972 | e_1, e_2, e_3 are free in the math, but Lean quantifies them. Corrected: $$\forall e_1, e_2, e_3:\ e_1 \sqsubseteq e_2 \ |
| `Fw.Parts.EngineScroll.entryLe_total` | agree | 8123712358316786938 |  |
| `Fw.Parts.EngineScroll.orderCallbacks_perm` | disagree | 6168987457941083824 | The math is right. The English 'Every registered callback runs exactly once per frame' says more than the theorem. The t |
| `Fw.Parts.EngineScroll.orderCallbacks_registration` | agree | 4358173630867911925 |  |
| `Fw.Parts.EngineScroll.Op` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.Step` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.Variant` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.faithfulFrom` | disagree | 13361383562450084038 | The math leaves out the empty-list case of the definition and uses an undefined subscript notation. Corrected: $$\operat |
| `Fw.Parts.EngineScroll.readsFrom` | agree | 13361383562450084038 |  |
| `Fw.Parts.EngineScroll.writesFrom` | agree | 13361383562450084038 |  |
| `Fw.Parts.EngineScroll.framePlan` | agree | 3561092999718987953 |  |
| `Fw.Parts.EngineScroll.Step.isRead` | agree | 6140234412873888924 |  |
| `Fw.Parts.EngineScroll.isRead_read` | disagree | 10519647688549933100 | k is free in the math. Corrected: $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{R}, k)) = \top$$ |
| `Fw.Parts.EngineScroll.isRead_write` | disagree | 8786802114933493103 | k is free in the math. Corrected: $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{W}, k)) = \bot$$ |
| `Fw.Parts.EngineScroll.filter_read_faithfulFrom` | agree | 15122301350270294261 |  |
| `Fw.Parts.EngineScroll.filter_write_faithfulFrom` | agree | 14318510705280555961 |  |
| `Fw.Parts.EngineScroll.batched_eq_partition` | agree | 4683570198628503505 |  |
| `Fw.Parts.EngineScroll.Access` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.Access.isRead` | agree | 14356600851718168051 |  |
| `Fw.Parts.EngineScroll.Role` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.forced` | agree | 7731021215424982811 |  |
| `Fw.Parts.EngineScroll.styleRole` | agree | 11192358764639391462 |  |
| `Fw.Parts.EngineScroll.layoutRole` | agree | 11192358764639391462 |  |
| `Fw.Parts.EngineScroll.Sound` | agree | 6140436841068638694 |  |
| `Fw.Parts.EngineScroll.styleRole_sound` | agree | 14715537200707048301 |  |
| `Fw.Parts.EngineScroll.layoutRole_sound` | agree | 2352389380107183149 |  |
| `Fw.Parts.EngineScroll.forced_mono` | disagree | 1609423361076244931 | d and e are free in the math, but Lean has ∀ d e : Bool. Corrected: $$\forall \rho, as, d, e:\quad (d \Rightarrow e) \Ri |
| `Fw.Parts.EngineScroll.forced_writes_only` | agree | 12837629268961068228 |  |
| `Fw.Parts.EngineScroll.forced_append_writes` | agree | 8210279408565696474 |  |
| `Fw.Parts.EngineScroll.forced_filter_reads` | agree | 10897686221862582129 |  |
| `Fw.Parts.EngineScroll.batched_le_faithful` | agree | 14708927038877790630 |  |
| `Fw.Parts.EngineScroll.batched_le_one` | disagree | 6523135455901997002 | The math leaves out the Lean hypothesis hr : ∀ a, a.isRead = true → role a ≠ dirty (no read dirties). Without it the sta |
| `Fw.Parts.EngineScroll.Step.access` | agree | 12367190869288398446 |  |
| `Fw.Parts.EngineScroll.planLayouts` | agree | 3995576727389197860 |  |
| `Fw.Parts.EngineScroll.framePlan_batched_le` | agree | 14350644170192163772 |  |
| `Fw.Parts.EngineScroll.planLayouts_faithfulFrom` | agree | 8390892567058049100 |  |
| `Fw.Parts.EngineScroll.countTrue` | agree | 27352352 |  |
| `Fw.Parts.EngineScroll.planLayouts_faithful_formula` | agree | 11815096367988426006 |  |
| `Fw.Parts.EngineScroll.framePlan_faithful_cost` | agree | 17862655528411164068 |  |
| `Fw.Parts.EngineScroll.shouldSchedule` | agree | 3551570259 |  |
| `Fw.Parts.EngineScroll.Ev` | agree | 3931117990 |  |
| `Fw.Parts.EngineScroll.runs` | agree | 14736101280669439234 |  |
| `Fw.Parts.EngineScroll.countEv` | agree | 6537709587684904777 |  |
| `Fw.Parts.EngineScroll.runs_le` | disagree | 8233303483154169168 | The second clause is weaker than the Lean. Lean proves runs(p,es) ≤ [p] + #scroll(es) for every p, not only for p = ⊥. C |
| `Fw.Parts.EngineScroll.listenerAction` | agree | 2016497146 |  |
| `Fw.Parts.EngineScroll.attachedAfter` | agree | 2274047319 |  |
| `Fw.Parts.EngineScroll.listener_invariant` | agree | 11026370579894701198 |  |
| `Fw.Parts.EngineScroll.navAccesses` | agree | 18349000911985273043 |  |
| `Fw.Parts.EngineScroll.heroExitAccesses` | agree | 18349000911985273043 |  |
| `Fw.Parts.EngineScroll.pilotFrame` | agree | 18349000911985273043 |  |
| `Fw.Parts.NavHitTest.Rect` | agree | 3931117990 |  |
| `Fw.Parts.NavHitTest.hitPoint` | agree | 14901957181138238253 |  |
| `Fw.Parts.NavHitTest.hitPoint_inside` | agree | 12884417283242980729 |  |
| `Fw.Parts.NavHitTest.HitFlags` | agree | 3931117990 |  |
| `Fw.Parts.NavHitTest.classifyHit` | agree | 16629056394570413191 |  |
| `Fw.Parts.NavHitTest.classifyHit_eq` | agree | 17028922986975454499 |  |
| `Fw.Parts.NavHitTest.Hit` | agree | 3931117990 |  |
| `Fw.Parts.NavHitTest.findIdx` | agree | 2759821197 |  |
| `Fw.Parts.NavHitTest.faithfulHit` | agree | 2559627907622085960 |  |
| `Fw.Parts.NavHitTest.firstOutside` | agree | 2055347128 |  |
| `Fw.Parts.NavHitTest.allowHit` | agree | 9085161766822827013 |  |
| `Fw.Parts.NavHitTest.findIdx?_congr'` | disagree | 4217177856 | p, q and xs are free in the math. Corrected: $$\forall p, q, xs:\ (\forall x \in xs:\ p(x) = q(x)) \Rightarrow \operator |
| `Fw.Parts.NavHitTest.findIdx_congr` | disagree | 6186552227763706826 | p, q and xs are free in the math. Corrected: $$\forall p, q, xs:\ (\forall x \in xs:\ p(x) = q(x)) \Rightarrow \operator |
| `Fw.Parts.NavHitTest.firstOutside_eq_faithful` | agree | 11932167822771133009 |  |
| `Fw.Parts.NavHitTest.firstOutside_ne_faithful` | agree | 13287047492367256617 |  |
| `Fw.Parts.NavHitTest.allowHit_eq_faithful` | agree | 11334693612211646547 |  |
| `Fw.Parts.NavHitTest.isOnDark` | agree | 1391933274 |  |
| `Fw.Parts.NavHitTest.hitSkip_morph` | agree | 7721065760113074209 |  |
| `Fw.Parts.NavHitTest.expanded_masks` | agree | 10477559439836665216 |  |
| `Fw.Parts.NavHitTest.changed` | agree | 603921427 |  |
| `Fw.Parts.NavHitTest.changed_write` | agree | 13611140602711103690 |  |
| `Fw.Parts.Golden.decimal?` | disagree | 2024033954 | The math does not say which e is chosen (the least one), how m is computed, or when the result is none. The English 'ter |
| `Fw.Parts.Golden.ratWire` | agree | 893280584 |  |
| `Fw.Parts.Golden.rin` | disagree | 893280584 | The case split is on dec(q) ≠ none (q.den divides 10^40), not on 'terminating'. A terminating q such as 2^{-41} goes to  |
| `Fw.Parts.Golden.jint` | agree | 1534267800 |  |
| `Fw.Parts.Golden.jnat` | agree | 3511535342 |  |
| `Fw.Parts.Golden.line` | agree | 477717292 |  |
| `Fw.Parts.Golden.entryJ` | agree | 18382492738451195971 |  |
| `Fw.Parts.Golden.stepJ` | agree | 16558358169714686327 |  |
| `Fw.Parts.Golden.variantName` | agree | 4419265992218905131 |  |
| `Fw.Parts.Golden.accessName` | agree | 14049959673292335267 |  |
| `Fw.Parts.Golden.writerPatterns` | agree | 944135888 |  |
| `Fw.Parts.Golden.engineLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.engineSpecLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.navLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.navSpecLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.springJ` | disagree | 12560250465617194318 | The math leaves out the Bool parameter `wire`, which picks the encoding. Corrected: $$\operatorname{springJ}(\mathit{wir |
| `Fw.Parts.Golden.t0Ms` | agree | 630578061 |  |
| `Fw.Parts.Golden.countdownLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.exitLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.exitSpecLines` | agree | 4017531403 |  |
| `Fw.Parts.Golden.main` | disagree | 3812987455 | The math claims a .spec.jsonl for every pilot part, but main writes no hero.countdown.spec.jsonl (7 files, not 8). Corre |
| `Fw.Parts.HeroCountdown.targetMs` | agree | 630578061 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds` | agree | 3357052557 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds_ceil` | agree | 9623017684188239461 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds_past` | agree | 17252441141463935142 |  |
| `Fw.Parts.HeroCountdown.remainingSeconds_antitone` | agree | 13263800469960812416 |  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds` | agree | 3208536212 |  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds_range` | agree | 3273925259 |  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds_sum` | agree | 1830475066 |  |
| `Fw.Parts.HeroCountdown.lexLe` | disagree | 1402962434 | The Lean def is on all of List ℕ × List ℕ and is False whenever either list does not have length 4 (`\| _, _ => False`).  |
| `Fw.Parts.HeroCountdown.unitsFromSeconds_mono` | agree | 1927385860548826942 |  |
| `Fw.Parts.HeroCountdown.countdown_mono_in_time` | agree | 8324429637704214165 |  |
| `Fw.Parts.HeroCountdown.digitCount` | agree | 2546708756 |  |
| `Fw.Parts.HeroCountdown.lt_pow_digitCount` | agree | 14210050943293497059 |  |
| `Fw.Parts.HeroCountdown.places` | agree | 3208536212 |  |
| `Fw.Parts.HeroCountdown.mag` | agree | 957469855 |  |
| `Fw.Parts.HeroCountdown.digitPlaces` | agree | 1794447402 |  |
| `Fw.Parts.HeroCountdown.digitAt` | agree | 3304664491 |  |
| `Fw.Parts.HeroCountdown.digitAt_lt_ten` | agree | 11308452361819927381 |  |
| `Fw.Parts.HeroCountdown.fromDigits` | agree | 434822048 |  |
| `Fw.Parts.HeroCountdown.foldl_places` | agree | 18257629500236174244 |  |
| `Fw.Parts.HeroCountdown.digits_spell_value` | agree | 3348882306738503192 |  |
| `Fw.Parts.HeroCountdown.fmod10` | agree | 3498294262 |  |
| `Fw.Parts.HeroCountdown.fmod10_bounds` | agree | 6106058782299224832 |  |
| `Fw.Parts.HeroCountdown.fmod10_eq` | agree | 1550200648620087179 |  |
| `Fw.Parts.HeroCountdown.faceDelta` | agree | 4102075218 |  |
| `Fw.Parts.HeroCountdown.faceDelta_bounds` | agree | 1765657586838722558 |  |
| `Fw.Parts.HeroCountdown.faceDelta_congr` | agree | 18054021516022710787 |  |
| `Fw.Parts.HeroCountdown.int_eq_zero_of_lt_one` | agree | 2143994458 |  |
| `Fw.Parts.HeroCountdown.eq_of_congr10` | agree | 2201938567 |  |
| `Fw.Parts.HeroCountdown.faceOffsetPx` | agree | 1846951230 |  |
| `Fw.Parts.HeroCountdown.stripOffsetCells` | agree | 3498294262 |  |
| `Fw.Parts.HeroCountdown.stripEntryDigit` | agree | 2367048215 |  |
| `Fw.Parts.HeroCountdown.strip_shows_same` | agree | 946933924082827303 |  |
| `Fw.Parts.HeroCountdown.faceDelta_settled` | disagree | 7983538969637958331 | The math (faceDelta(k,d)=0 iff k=d for d,k in {0..9}) is exact. The English overclaims: 'only face d is in the window' m |
| `Fw.Parts.HeroCountdown.Spring` | agree | 3931117990 |  |
| `Fw.Parts.HeroCountdown.springSlice` | agree | 12098467325916994228 |  |
| `Fw.Parts.HeroCountdown.springLoop` | agree | 2350163406469253958 |  |
| `Fw.Parts.HeroCountdown.slices` | agree | 957469855 |  |
| `Fw.Parts.HeroCountdown.ratAbs` | agree | 3498294262 |  |
| `Fw.Parts.HeroCountdown.SpringResult` | agree | 3931117990 |  |
| `Fw.Parts.HeroCountdown.springStep` | agree | 17526496671657834267 |  |
| `Fw.Parts.HeroCountdown.springStep_done` | agree | 17086857977841775218 |  |
| `Fw.Parts.HeroCountdown.slices_nonpos` | disagree | 16536093956796953355 | The theorem only states slices(dt)=0 for dt in Q with dt <= 0. The math quantifies s and x* even though they do not appe |
| `Fw.Parts.HeroCountdown.ariaLabel` | agree | 2463753768 |  |
| `Fw.Parts.HeroCountdown.labelsEn` | agree | 4017531403 |  |
| `Fw.Parts.HeroCountdown.cellHeight` | agree | 2426920303 |  |
| `Fw.Parts.HeroCountdown.Metrics` | agree | 3931117990 |  |
| `Fw.Parts.HeroCountdown.countdownMetrics` | agree | 9743733877825822238 |  |
| `Fw.Parts.HeroCountdown.countdownMetrics_cell` | agree | 17717589558074875997 |  |
| `Fw.Parts.HeroExit.div_mul_pos` | agree | 2447392552 |  |
| `Fw.Parts.HeroExit.div_unit` | agree | 1761855220 |  |
| `Fw.Parts.HeroExit.div_mono` | agree | 600061581 |  |
| `Fw.Parts.HeroExit.exitRange` | agree | 4035929107 |  |
| `Fw.Parts.HeroExit.exitClamp` | agree | 4035929107 |  |
| `Fw.Parts.HeroExit.exitOpacity` | agree | 1069553462 |  |
| `Fw.Parts.HeroExit.exitRange_pos` | agree | 7689710378224765277 |  |
| `Fw.Parts.HeroExit.exitOpacity_mem` | agree | 2643469646727665790 |  |
| `Fw.Parts.HeroExit.exitOpacityAt` | agree | 563956569 |  |
| `Fw.Parts.HeroExit.exitOpacity_antitone` | agree | 3718962435805654583 |  |
| `Fw.Parts.HeroExit.exitOpacity_lipschitz` | agree | 14359126316545583578 |  |
| `Fw.Parts.HeroExit.exitOpacity_before` | agree | 6793370726980835582 |  |
| `Fw.Parts.HeroExit.exitOpacity_after` | agree | 1353755058741054087 |  |
| `Fw.Parts.HeroExit.exitOpacity_linear` | agree | 15504784150233815547 |  |
| `Fw.Parts.HeroExit.exitScatter` | agree | 3498294262 |  |
| `Fw.Parts.HeroExit.pointerOff` | agree | 3512254526 |  |
| `Fw.Parts.HeroExit.ExitFrame` | agree | 3931117990 |  |
| `Fw.Parts.HeroExit.exitFrame` | agree | 17265211571709300474 |  |
| `Fw.Parts.HeroExit.pointerOff_mono` | disagree | 659160663682231139 | The math (upward closure in y) is exact. The English 'There is a single scroll position past which the hero ignores taps |
| `Fw.Parts.HeroExit.navHeroProgress` | agree | 1069553462 |  |
| `Fw.Parts.HeroExit.navHeroProgress_eq` | agree | 515290461520100446 |  |
| `Fw.Parts.HeroExit.pill_threshold` | agree | 8915026869638937394 |  |
| `Fw.Parts.HeroExit.pointerOff_after_pill` | agree | 1694717317344030805 |  |
| `Fw.Parts.HeroExit.le600` | agree | 3512254526 |  |
| `Fw.Parts.HeroExit.trackHeightPx` | agree | 4174302566 |  |
| `Fw.Parts.HeroExit.heroHeightPx` | agree | 1979205980 |  |
| `Fw.Parts.HeroExit.exitRange_200vh` | agree | 3558768072629428061 |  |
| `Fw.Parts.HeroExit.copyOpacity` | agree | 4035929107 |  |
| `Fw.Parts.HeroExit.copyBlurPx` | agree | 1018237883 |  |
| `Fw.Parts.HeroExit.copyTranslateYPx` | agree | 1018237883 |  |
| `Fw.Parts.HeroExit.cueBlurPx` | agree | 3498294262 |  |
| `Fw.Parts.HeroExit.cueTranslateYPx` | agree | 1979205980 |  |
| `Fw.Parts.HeroExit.cueBlurPxFull` | agree | 3940620593 |  |
| `Fw.Parts.HeroExit.cueTranslateYPxFull` | agree | 3940620593 |  |
| `Fw.Parts.HeroExit.cue_ts_eq_full` | agree | 7831753282674862612 |  |
| `Fw.Parts.HeroExit.cardOpacity` | agree | 3498294262 |  |
| `Fw.Parts.HeroExit.cardTranslate` | agree | 563956569 |  |
| `Fw.Parts.HeroExit.consumers_range` | agree | 18030891850317274653 |  |
| `Fw.Parts.HeroExit.consumers_mono` | agree | 14216743761854297805 |  |
| `Fw.Parts.HeroExit.band_edge_jump` | agree | 9314435668886194708 |  |
