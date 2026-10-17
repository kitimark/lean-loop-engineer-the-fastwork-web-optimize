---
title: Math review round 4 at 740b06c (round-3 fixes, Fw/Measure)
date: 2026-10-17
status: CONFIRMED
round: 4
---

# Math review round 4 at 740b06c

Four math-reviewer agents (workflow `math-review-r4`, read-only) back-translated the 258 declarations that were stale
or pending in the Math view at 740b06c: the 54 round-3 fixes plus 3 changed neighbours, and all of `Fw/Measure`
(Classes, Tolerance, WebKit, Zones). Method as in round 3: write the math from the Lean first, then compare clause by
clause. The lead wrote this record from the agents' structured verdicts; `stmtHash` and `mathHash` come from
`lake exe mathview` at 740b06c.

## Counts

| Group | Reviewed | Agree | Disagree |
|---|---|---|---|
| Fixes from round 3 (Null, Site, Parts, Console, Screen) | 57 | 54 | 3 |
| Measure.Classes + Tolerance | 72 | 66 | 6 |
| Measure.WebKit | 62 | 31 | 31 |
| Measure.Zones | 67 | 36 | 31 |
| **Total** | 258 | 187 | 71 |

Patterns: 44 of the 71 disagreements are free variables in the $$ math that the Lean quantifies (fix: write the
∀, the round-3 convention). The Classes/Tolerance reviewer read top-level free variables as universal, so that group
was not checked for this pattern; the fix pass applies it there too and round 5 re-checks it. The rest: set-builder
cardinalities that merge duplicates where the Lean counts list entries; truncated ℕ subtraction; overlapping case
conditions where the Lean is first-match; empty-list cases left out; types stated tighter than the Lean (fixed
lengths); English that claims more than the theorem (null_prob exactness without distinct values, gap1000,
stable_frames_unsound frame count, inv_stats non-empty).

## Disagreements (exact corrections)

- `Fw.Null.null_prob_5v5` (english): The first clause says equal likelihood alone gives exactly 1/252, but exactness needs distinct run values (with ties it is only <= 1/252, as the same sentence then says). Match land_null_prob: "5 vs 5 runs: if the 10 run values are distinct and every labeling is equally likely (the L3 premise), a false \"better\" has probability exactly 1/252 (...; any distinct values: `pAt_distinct`); with ties it is at most 1/252 (`null_bound_4v4_5v5`)." The math $$\operatorname{falseBetterProb}(5, 5) = 1/252 = \operatorname{pNull}(5, 5)$$ is fine.
- `Fw.Null.null_prob_3v3` (english): Same issue as null_prob_5v5: the exact 1/20 needs distinct values. Fix: "3 vs 3 runs (v1's minimum): if the 6 run values are distinct and every labeling is equally likely (the L3 premise), a false \"better\" has probability exactly 1/20 (...); with ties it is at most 1/20 (`pAt_le_pNull`)." The math is fine.
- `Fw.Site.Breakpoints.gap1000` (english): "no width rule at the 1000 edge matches on either side" claims too much. c1000 and c1000Nodw also have the width edge 1000 (catalogue_edges). At 1000.5 they lose their (width<=1000px) arm but can still match through (device-width<=500px) or the touch arm, for all e, and the theorem says nothing about them. Fix: "At 1000.5 px (in any representation) none of the five rules (width<=1000px), (width>=1001px), (width>=1001px) and no-preference, 641-1000 and 861-1000 matches; the combos c1000 / c1000-nodw lose their (width<=1000px) arm but can still match through the device-width or touch arm." The math is fine.
- `Fw.Measure.Class.le` (english): The math matches the Lean. The English "`c.le c'` when every pair within `c` is within `c'`" reads as a characterisation, but le is only sound for that (within_mono), not complete. Within(stable(0,t)) forces diff = 0, so every stable(0,5) pair is within det and within stable(0,0), yet le(stable(0,5), det) = le(stable(0,5), stable(0,0)) = false. Fix: "The syntactic strictness order: `c.le c'` implies every pair within `c` is within `c'` (`within_mono`); the converse fails for stable(0, t) (deterministic ≤ stable k t ≤ stable k' t' (k ≤ k', t ≤ t') ≤ quarantined)."
- `Fw.Measure.classify` (math): The case conditions overlap. When k(R) = 0 (and so t(R) = 0 ≤ t_max), both the det row and the stable row hold, and they give different values (det vs stable(0,0)). The Lean is first-match (if/else if), and the math does not say so. Corrected: $$\operatorname{classify}_p(R) = \begin{cases} \mathrm{det} & k(R) = 0 \\ \mathrm{stable}(k(R), t(R)) & 1 \le k(R) \le k_{\max} \ \land\ t(R) \le t_{\max} \\ \mathrm{quar} & \text{otherwise} \end{cases}$$
- `Fw.Measure.Admissible` (math): k and t are free in the disjunction. The Lean binds them by matching on c. Corrected: $$\operatorname{adm}_p(c) \iff c = \mathrm{det} \ \lor\ c = \mathrm{quar} \ \lor\ \exists k, t \in \mathbb{N}:\ (c = \mathrm{stable}(k, t) \land k \le k_{\max} \land t \le t_{\max})$$
- `Fw.Measure.valAt_cons_zero` (both): The theorem proves only valAt (x :: r) 0 = x. The docstring also states (x::r)[i+1] = r[i] and [][i] = 0, which are the separate theorems valAt_cons_succ and valAt_nil. The English "at 0 and at a successor index" overclaims in the same way. Corrected: $$\forall x \in \mathbb{Z}, r \in \mathbb{Z}^{*}:\ (x :: r)[0] = x$$ English: "The padded value of a non-empty series at index 0."
- `Fw.Measure.stable_frames_unsound` (english): The math (∀ k ≥ 2) matches the Lean. The English "With one frame allowed to differ and no total gap" is wrong. The witness v = [0,1], v' = [1,0] differs in two frames, which is why the theorem needs k ≥ 2. With k = 1 and t = 0 no frame can differ, because one changed frame changes the total, so the claim would fail there. Fix: "With two frames allowed to differ (k ≥ 2) and no total gap, frame-by-frame dominance of the observed runs does not carry over (a unit of work moved one frame earlier in the variant's unseen run)."
- `Fw.Measure.margin_sound` (math): The quantifier "∀ k, t, b, b', v, v' ∈ ℤ^*" puts k and t in ℤ^*. In the Lean, k, t : ℕ and only the four runs are Series = ℤ^*. Corrected: $$\forall k, t \in \mathbb{N},\ b, b', v, v' \in \mathbb{Z}^{*}:\ \operatorname{Within}(\mathrm{stable}(k, t), b, b') \land \operatorname{Within}(\mathrm{stable}(k, t), v, v') \land \Sigma v + \operatorname{margin}(k, t) \le \Sigma b \;\Rightarrow\; \Sigma v' \le \Sigma b'$$
- `Fw.Measure.WebKit.Tally` (math): The field counts is List Nat, so the type does not fix its length at |T|. Only tally's output has |T| entries. Corrected: $$\mathrm{Tally} = \mathbb{N}^{*} \times \mathbb{Z} \times (\Sigma^{*} \times \mathbb{N})^{*}$$ (tally fills counts with |T| entries).
- `Fw.Measure.WebKit.countType` (math): Lean is the length of a list filter, so equal rows count once each. The guard has two identical Layout rows and gets 2. Set-builder |{r ∈ R | ...}| would merge them into 1. Corrected: $$n_\tau(R) = \big|\{\, i < |R| \mid R_i.\mathrm{type} = \tau \,\}\big|$$
- `Fw.Measure.WebKit.stepOf` (math): The subtraction is on ℕ and truncates. When no mark is ≤ s the Lean gives 0, but the math gives −1. The domain s ≥ m_0 appears only in the English. Corrected: $$\operatorname{step}(M, s) = \big|\{\, k < |M| \mid m_k \le s \,\}\big| \mathbin{\dot-} 1 \quad (= 0 \text{ when no } m_k \le s)$$
- `Fw.Measure.WebKit.Place` (math): Place is the three-constructor type, but the math describes the function place instead (see the place row for the fix). Corrected: $$\mathrm{Place} = \{\mathrm{before}, \mathrm{after}\} \cup \{\, \mathrm{step}(k) \mid k \in \mathbb{N} \,\}$$
- `Fw.Measure.WebKit.place` (math): The math only points to Place, and the cases there overlap: when e ≤ start < m_0, both before and after match. The Lean tests before first, so the result is before. m_0 = 0 for M = [] is also missing from the math. Corrected: $$\operatorname{place}(M, e, r) = \begin{cases} \mathrm{before} & r.\mathrm{start} = \bot \ \lor\ r.\mathrm{start} < m_0 \\ \mathrm{after} & m_0 \le r.\mathrm{start} \ \land\ e \le r.\mathrm{start} \\ \mathrm{step}(\operatorname{step}(M, r.\mathrm{start})) & m_0 \le r.\mathrm{start} < e \end{cases},\quad m_0 = \begin{cases} M_0 & M \ne [\,] \\ 0 & M = [\,] \end{cases}$$
- `Fw.Measure.WebKit.Reduced` (math): The fields are List (List Nat) and List Int. Their lengths are not fixed, and n is a free variable. Corrected: $$\mathrm{Reduced} = (\mathbb{N}^{*})^{*} \times \mathbb{Z}^{*} \times \mathrm{Tally} \times \mathbb{N}$$ (reduceSteps fills n = |M| rows of |T| counts).
- `Fw.Measure.WebKit.reduceSteps` (math): rowsBeforeFirstStep is the length of a list filter, so duplicate rows count once each. The set-builder in the math would merge them. Corrected last component: $$\big|[\, r \in R \mid \operatorname{place}(M, e, r) = \mathrm{before} \,]\big|$$ (list filter). The other components are right.
- `Fw.Measure.WebKit.place_step_lt` (math): M, e, r and k are free in the math, but the Lean quantifies them. Corrected: $$\forall M, e, r, k:\ M \ne [\,] \land \operatorname{place}(M, e, r) = \mathrm{step}(k) \;\Rightarrow\; k < |M|$$
- `Fw.Measure.WebKit.sum_partition_range` (math): κ, g, n and R are free in the math. Corrected: $$\forall \kappa : \alpha \to \mathbb{N},\ g : \alpha \to \mathbb{Z},\ n \in \mathbb{N},\ R \in \alpha^{*}:\ (\forall r \in R:\ \kappa(r) < n) \;\Rightarrow\; \sum_{z < n} \sum_{r \in R,\ \kappa(r) = z} g(r) = \sum_{r \in R} g(r)$$
- `Fw.Measure.WebKit.steps_partition` (math): R, M and e are free in the math. Corrected: $$\forall R, M, e, \tau:\ M \ne [\,] \;\Rightarrow\; \sum_{k < |M|} n_\tau(R_k) = n_\tau(W(R))$$
- `Fw.Measure.WebKit.rows_conserved` (math): R, M and e are free in the math. The two counts are lengths of list filters, so duplicate rows count once each, and set-builder |{r | ...}| would merge them. Corrected: $$\forall R, M, e:\ M \ne [\,] \Rightarrow |R| = \big|[r \in R \mid \operatorname{place}(M,e,r) = \mathrm{before}]\big| + \sum_{k < |M|} |R_k| + \big|[r \in R \mid \operatorname{place}(M,e,r) = \mathrm{after}]\big|$$
- `Fw.Measure.WebKit.WZone` (math): counts is List Int, so its length is not fixed, and w is free. Corrected: $$\mathrm{WZone} = \mathbb{N} \times \mathbb{N} \times \mathbb{N} \times \mathbb{Z}^{*} \times \mathbb{Z}$$ (zones_{h,w} fills counts with w entries).
- `Fw.Measure.WebKit.zoneIx_lt` (math): h and S are free in the math. Corrected: $$\forall h \in \mathbb{N},\ S,\ s \in S:\ \operatorname{zix}_h(s.y) < N_h(S)$$
- `Fw.Measure.WebKit.stats` (math): The math gives only the non-empty case, where min and max over an empty list are undefined. The Lean defines stats([]) = (0,0,0); only the English says so. Corrected: $$\operatorname{stats}(v_1, \dots, v_m) = \begin{cases} (0, 0, 0) & m = 0 \\ (\min_i v_i,\ \max_i v_i,\ \max_i |v_i|) & m \ge 1 \end{cases}$$
- `Fw.Measure.WebKit.classifyCells` (math): The det, stable and quar-by-max cases do not require equal lengths, so they overlap with the first quar case. R_1 is undefined for R = [], where the Lean uses headD [] and returns 0. Corrected: $$\operatorname{classifyCells}(R, \mathrm{tol}) = \begin{cases} 2 & \exists r \in R:\ |r| \ne |R_1| \\ \max{}^{*}_{i < |R_1|} \operatorname{status}(\operatorname{cell}_i(R)) & \text{otherwise} \end{cases},\quad R_1 = [\,] \text{ if } R = [\,]$$ (0 det, 1 stable, 2 quar)
- `Fw.Measure.WebKit.inv_step` (math): σ and v are free in the math. Corrected: $$\forall \sigma \in \mathbb{Z}^3,\ v \in \mathbb{Z}:\ \operatorname{Inv}(\sigma) \Rightarrow \operatorname{Inv}(\operatorname{st}(\sigma; v))$$
- `Fw.Measure.WebKit.inv_foldl` (both): Math: σ and V are free. Corrected: $$\forall V \in \mathbb{Z}^{*},\ \sigma \in \mathbb{Z}^3:\ \operatorname{Inv}(\sigma) \Rightarrow \operatorname{Inv}(\operatorname{foldl}(\operatorname{st}, \sigma, V))$$ English: the theorem says nothing about stats or non-empty lists (that is inv_stats). Fix: 'Folding st over any list from a start that satisfies the invariant keeps the invariant.'
- `Fw.Measure.WebKit.inv_stats` (both): The Lean has no non-empty hypothesis: it proves ∀ vs, Inv(stats vs), and stats([]) = (0,0,0) satisfies Inv. The math and the English ("of a non-empty list") state a weaker result than the Lean. Corrected: $$\forall V \in \mathbb{Z}^{*}:\ \operatorname{Inv}(\operatorname{stats}(V))$$ English: 'The stats of any list satisfy the invariant (stats([]) = (0,0,0)).'
- `Fw.Measure.WebKit.stats_snoc` (math): V and x are free in the math. Corrected: $$\forall V \in \mathbb{Z}^{*},\ x \in \mathbb{Z}:\ V \ne [\,] \Rightarrow \operatorname{stats}(V \mathbin{+\!\!+} [x]) = \operatorname{st}(\operatorname{stats}(V); x)$$
- `Fw.Measure.WebKit.spread_step` (math): ℓ, h, b and x are free in the math. Corrected: $$\forall (\ell, h, b) \in \mathbb{Z}^3,\ x \in \mathbb{Z}:\ \operatorname{Inv}(\ell, h, b) \land (\ell', h', b') = \operatorname{st}(\ell, h, b; x) \Rightarrow 0 \le b' - b \le (h' - \ell') - (h - \ell)$$
- `Fw.Measure.WebKit.cellStatus_snoc` (math): tol, V and x are free in the math. a is arbitrary, and r ≤ 1 is the Lean's num_r ≤ den_r. Corrected: $$\forall \mathrm{tol} = (a, r),\ V \in \mathbb{Z}^{*},\ x \in \mathbb{Z}:\ r \le 1 \land V \ne [\,] \Rightarrow \operatorname{status}_{\mathrm{tol}}(V) \le \operatorname{status}_{\mathrm{tol}}(V \mathbin{+\!\!+} [x])$$
- `Fw.Measure.WebKit.maxOf_map_le` (math): f, g and L are free in the math. Corrected: $$\forall f, g : \alpha \to \mathbb{N},\ L \in \alpha^{*}:\ (\forall x \in L:\ f(x) \le g(x)) \Rightarrow \max{}^{*} f(L) \le \max{}^{*} g(L)$$
- `Fw.Measure.WebKit.classifyCells_snoc` (math): tol, R and x are free in the math. Corrected: $$\forall \mathrm{tol} = (a, r),\ R \in (\mathbb{Z}^{*})^{*},\ x \in \mathbb{Z}^{*}:\ r \le 1 \land R \ne [\,] \Rightarrow \operatorname{classifyCells}(R, \mathrm{tol}) \le \operatorname{classifyCells}(R \mathbin{+\!\!+} [x], \mathrm{tol})$$
- `Fw.Measure.WebKit.const_of_spread_zero` (math): V is free in the math. Corrected: $$\forall V \in \mathbb{Z}^{*}:\ (\ell, h, b) = \operatorname{stats}(V) \land h - \ell = 0 \Rightarrow \forall u, v \in V:\ u = v$$
- `Fw.Measure.WebKit.classifyCells_det_holds` (math): tol and R are free in the math. Corrected: $$\forall \mathrm{tol},\ R:\ \operatorname{classifyCells}(R, \mathrm{tol}) = 0 \Rightarrow \operatorname{Holds}(\mathrm{det}, R)$$
- `Fw.Measure.WebKit.classifyCells_det_iff` (math): tol and R are free in the math, and R_1 is undefined for R = [] (Lean: headD []). Corrected: $$\forall \mathrm{tol},\ R:\ \operatorname{classifyCells}(R, \mathrm{tol}) = 0 \iff (\forall r \in R:\ |r| = |R_1|) \land \forall i < |R_1|:\ \operatorname{status}(\operatorname{cell}_i(R)) = 0,\quad R_1 = [\,] \text{ if } R = [\,]$$
- `Fw.Measure.WebKit.keysOf_singletons` (math): The list x_1..x_m is free in the math. Corrected: $$\forall m,\ x_1, \dots, x_m \in \Sigma^{*}:\ \operatorname{keys}([[(x_1, 0)], \dots, [(x_m, 0)]]) = \operatorname{ins}(x_1, \operatorname{ins}(x_2, \dots \operatorname{ins}(x_m, [\,])))$$
- `Fw.Measure.WebKit.symDiff_terms_comm` (math): A and B are free; only K is quantified. Corrected: $$\forall A, B, K \in (\Sigma^{*})^{*}:\ \sum_{x \in K} |\#_x(A) - \#_x(B)| = \sum_{x \in K} |\#_x(B) - \#_x(A)|$$ (Note: symDiff(A,B) = symDiff(B,A) itself is not proved, since keys(A++B) = keys(B++A) is not shown.)
- `Fw.Measure.WebKit.CRow` (math): cls is a Nat, and the type does not restrict it to {0,1,2}. Corrected: $$\mathrm{CRow} = \Sigma^{*} \times \Sigma^{*} \times \Sigma^{*} \times \mathbb{N}$$ (classes used: 0, 1, 2).
- `Fw.Measure.WebKit.summarize` (math): The math never defines R_g, f_g, m_g or levels(R_g). Because keys can collide ("a|b"+"c" and "a"+"b|c"), f_g and m_g are the fields of the group's first row, and levels are sorted and distinct. Corrected: $$\operatorname{summarize}(R) = \Big[\big(R_g[0].f,\ R_g[0].m,\ [(\lambda, \operatorname{last}_\lambda(R_g))]_{\lambda \in \operatorname{sort}\{r.\mathrm{level} \mid r \in R_g\}},\ \max{}^{*}_\lambda \operatorname{last}_\lambda(R_g)\big)\Big]_{g \in \operatorname{firstSeen}([\kappa(r)]_{r \in R})},\ \kappa(r) = r.f \cdot \texttt{"|"} \cdot r.m,\ R_g = [r \in R \mid \kappa(r) = g]$$
- `Fw.Measure.WebKit.summarize_worst` (math): R is free in the math. Corrected: $$\forall R,\ e \in \operatorname{summarize}(R),\ (\lambda, c) \in e.\mathrm{levels}:\ c \le e.\mathrm{worst}$$
- `Fw.Measure.zoneId` (math): h is any natural number, including 0, and the math leaves h = 0 undefined (⌊y/0⌋). In Lean, (y : Int) / 0 = 0, so for h = 0 every swipe frame is in zone "y00000". For h > 0, Lean's Int `/` (Euclidean) equals the floor, as stated. Corrected: $$\operatorname{zone}_h(f) = \begin{cases} \texttt{"y"} \cdot \operatorname{pad}_5\big(\operatorname{dec}(\lfloor f.\mathrm{scrollY} / h \rfloor \cdot h)\big) & f.\mathrm{phase} = \texttt{"swipe"} \\ f.\mathrm{phase} & \text{otherwise} \end{cases}\quad(\lfloor y/0 \rfloor := 0,\ \text{so } h = 0 \text{ gives } \texttt{"y00000"})$$
- `Fw.Measure.insKey` (math): ins(k, L) = sort({k} ∪ L) only holds when L is sorted and has no duplicates. Counterexample: insKey "a" ["c","b"] = ["a","c","b"]. The precedent MQ.insertSorted states this condition. Corrected: $$\operatorname{ins}(k, [\,]) = [k],\quad \operatorname{ins}(k, x :: xs) = \begin{cases} k :: x :: xs & k < x \\ x :: xs & k = x \\ x :: \operatorname{ins}(k, xs) & \text{otherwise} \end{cases}$$ so that $$\operatorname{ins}(k, L) = \operatorname{sort}(\{k\} \cup L) \text{ for strictly increasing } L$$
- `Fw.Measure.sumBy_append` (math): g, A, B are free in the math, but Lean quantifies them. Corrected: $$\forall g, A, B:\ \operatorname{sumBy}(g, A \mathbin{+\!\!+} B) = \operatorname{sumBy}(g, A) + \operatorname{sumBy}(g, B)$$
- `Fw.Measure.sumBy_congr` (math): g, g', L are free in the math. Corrected: $$\forall g, g', L:\ (\forall x \in L:\ g(x) = g'(x)) \;\Rightarrow\; \sum_{x \in L} g(x) = \sum_{x \in L} g'(x)$$
- `Fw.Measure.sumBy_mono` (math): g, g', L are free in the math. Corrected: $$\forall g, g', L:\ (\forall x \in L:\ g(x) \le g'(x)) \;\Rightarrow\; \sum_{x \in L} g(x) \le \sum_{x \in L} g'(x)$$
- `Fw.Measure.sumBy_nonneg` (math): g, L are free in the math. Corrected: $$\forall g, L:\ (\forall x \in L:\ 0 \le g(x)) \;\Rightarrow\; 0 \le \sum_{x \in L} g(x)$$
- `Fw.Measure.sumBy_map` (math): g, f, L are free in the math, and f(L) means the mapped list. Corrected: $$\forall g, f, L:\ \sum_{y \in [f(x)]_{x \in L}} g(y) = \sum_{x \in L} g(f(x))$$
- `Fw.Measure.sumBy_one` (math): L is free in the math. Corrected: $$\forall L:\ \sum_{x \in L} 1 = |L|$$
- `Fw.Measure.tag_append` (math): h, y, A, B are free in the math. Corrected: $$\forall h, y, A, B:\ \operatorname{tag}_h(y, A \mathbin{+\!\!+} B) = \operatorname{tag}_h(y, A) \mathbin{+\!\!+} \operatorname{tag}_h(\operatorname{lastY}(y, A), B)$$
- `Fw.Measure.tag_ids` (math): h, y, F are free in the math. Corrected: $$\forall h, y, F:\ [r.\mathrm{id}]_{r \in \operatorname{tag}_h(y, F)} = [\operatorname{zone}_h(f)]_{f \in F}$$
- `Fw.Measure.sumBy_rows_tag` (math): h, y, F, Z, k are free in the math. Corrected: $$\forall h, y, F, Z, k:\ \sum_{r \in \operatorname{rows}(\operatorname{tag}_h(y, F), Z)} \operatorname{countIn}(r.\mathrm{counts}, k) = \sum_{f \in F,\ \operatorname{zone}_h(f) = Z} c_f(k)$$
- `Fw.Measure.length_rows_tag` (math): h, y, F, Z are free in the math. Also the set-builder |{f ∈ F | ...}| merges identical frames, but Lean takes the length of the filtered list, which counts repeats. Corrected: $$\forall h, y, F, Z:\ |\operatorname{rows}(\operatorname{tag}_h(y, F), Z)| = \big|[\, f \in F \mid \operatorname{zone}_h(f) = Z \,]\big|$$ (a list filter, repeats counted)
- `Fw.Measure.mem_insKey` (math): k, x, L are free in the math. Corrected: $$\forall k, x, L:\ x \in \operatorname{ins}(k, L) \iff x = k \lor x \in L$$
- `Fw.Measure.countIn_eq_zero_of_not_mem_foldr` (math): k, C, A are free in the math. Corrected: $$\forall k, C, A:\ k \notin \operatorname{foldr}(\operatorname{ins} \circ \pi_1, A, C) \;\Rightarrow\; \operatorname{countIn}(C, k) = 0 \land k \notin A$$
- `Fw.Measure.sumBy_eq_zero_of_not_mem_keys` (math): k, R are free in the math. Corrected: $$\forall k, R:\ k \notin \operatorname{keys}([r.\mathrm{counts}]_{r \in R}) \;\Rightarrow\; \sum_{r \in R} \operatorname{countIn}(r.\mathrm{counts}, k) = 0$$
- `Fw.Measure.lookup_map_keys` (math): g, k, K are free in the math. Corrected: $$\forall g, k, K:\ \operatorname{lookup}(k, [(j, g(j))]_{j \in K}) = \begin{cases} g(k) & k \in K \\ \bot & k \notin K \end{cases}$$
- `Fw.Measure.zoneOf_sum` (math): R, Z, k are free in the math. Corrected: $$\forall R, Z, k:\ \operatorname{sum}(\operatorname{zoneOf}(R, Z), k) = \sum_{r \in \operatorname{rows}(R, Z)} \operatorname{countIn}(r.\mathrm{counts}, k)$$
- `Fw.Measure.find_map_zoneOf` (math): R, Z, L are free in the math. Corrected: $$\forall R, Z, L:\ \operatorname{find}([\operatorname{zoneOf}(R, j)]_{j \in L}, Z) = \begin{cases} \operatorname{zoneOf}(R, Z) & Z \in L \\ \bot & Z \notin L \end{cases}$$
- `Fw.Measure.firstSeen_aux` (math): A and L are free in the math, and fold(A, L) is never defined. Corrected: $$\forall A, L:\ \operatorname{nodup}(A) \;\Rightarrow\; \operatorname{nodup}(\operatorname{fold}(A, L)) \land \forall y:\ \big(y \in \operatorname{fold}(A, L) \iff y \in A \lor y \in L\big),\quad \operatorname{fold}(A, L) = \operatorname{foldl}\big((acc, x) \mapsto (acc \text{ if } x \in acc \text{ else } acc \mathbin{+\!\!+} [x]),\ A,\ L\big)$$
- `Fw.Measure.firstSeen_nodup` (math): L is free in the math. Corrected: $$\forall L:\ \operatorname{nodup}(\operatorname{firstSeen}(L))$$
- `Fw.Measure.mem_firstSeen` (math): L, y are free in the math. Corrected: $$\forall L, y:\ y \in \operatorname{firstSeen}(L) \iff y \in L$$
- `Fw.Measure.sum_partition` (math): g, R, L are free in the math. Corrected: $$\forall g, R, L:\ \operatorname{nodup}(L) \land (\forall r \in R:\ r.\mathrm{id} \in L) \;\Rightarrow\; \sum_{Z \in L} \sum_{r \in \operatorname{rows}(R, Z)} g(r) = \sum_{r \in R} g(r)$$
- `Fw.Measure.rowsOf_eq_nil_of_not_mem` (math): R, Z are free in the math. Corrected: $$\forall R, Z:\ Z \notin [r.\mathrm{id}]_{r \in R} \;\Rightarrow\; \operatorname{rows}(R, Z) = [\,]$$
- `Fw.Measure.framesAt_spec` (math): The set-builder |{f ∈ F | zone_h(f) = Z}| merges identical frames (Frame has decidable equality, and nothing rules out repeats). Lean takes the length of the filtered list, which counts repeats. Corrected: $$\forall h, y_0, F, Z:\quad \operatorname{framesAt}(\operatorname{zoneSums}_h(y_0, F), Z) = \big|[\, f \in F \mid \operatorname{zone}_h(f) = Z \,]\big|$$ (a list filter, repeats counted)
- `Fw.Measure.sumBy_filter_below` (math): h, k, Z, F, G are free in the math. Corrected: $$\forall h, k, Z, F, G:\ \operatorname{below}_{h,k}(F, G) \;\Rightarrow\; \sum_{f \in F,\ \operatorname{zone}_h(f) = Z} c_f(k) \le \sum_{g \in G,\ \operatorname{zone}_h(g) = Z} c_g(k)$$
- `Fw.Measure.zoneIds_zoneSumsFrom` (math): h, y_0, F are free in the math. Corrected: $$\forall h, y_0, F:\ \operatorname{ids}(\operatorname{zoneSums}_h(y_0, F)) = \operatorname{firstSeen}([\operatorname{zone}_h(f)]_{f \in F})$$
- `Fw.Measure.sumBy_zones` (math): h, y_0, F, g are free in the math. Corrected: $$\forall h, y_0, F, g:\ \sum_{z \in \operatorname{zoneSums}_h(y_0, F)} g(z) = \sum_{Z \in \operatorname{firstSeen}(R.\mathrm{id})} g(\operatorname{zoneOf}(R, Z)),\quad R = \operatorname{tag}_h(y_0, F)$$
- `Fw.Measure.cover_tag` (math): h, y_0, F are free in the math (only r is quantified). Corrected: $$\forall h, y_0, F,\ \forall r \in R:\ r.\mathrm{id} \in \operatorname{firstSeen}(R.\mathrm{id}),\quad R = \operatorname{tag}_h(y_0, F)$$
- `Fw.Measure.sumBy_tag_counts` (math): k, h, y, F are free in the math. Corrected: $$\forall k, h, y, F:\ \sum_{r \in \operatorname{tag}_h(y, F)} \operatorname{countIn}(r.\mathrm{counts}, k) = \sum_{f \in F} c_f(k)$$
- `Fw.Measure.sumBy_tag_dy` (math): h, y, F are free in the math. Corrected: $$\forall h, y, F:\ \sum_{r \in \operatorname{tag}_h(y, F)} r.dy = \operatorname{lastY}(y, F) - y$$
- `Fw.Measure.length_tag` (math): h, y, F are free in the math. Corrected: $$\forall h, y, F:\ |\operatorname{tag}_h(y, F)| = |F|$$

## Verdicts (parseable)

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Console.cardRefusal` | agree | 8236380120697394169 | 3016009726952741496 |  |
| `Fw.Null.null_prob_5v5` | disagree | 18075036907877158627 | 9355045739629901629 | The first clause says equal likelihood alone gives exactly 1/252, but exactness needs distinct run values (with ties it is only <= 1/252, as the same sentence t… |
| `Fw.Null.null_prob_3v3` | disagree | 6489614198802959727 | 15081848359092500059 | Same issue as null_prob_5v5: the exact 1/20 needs distinct values. Fix: "3 vs 3 runs (v1's minimum): if the 6 run values are distinct and every labeling is equa… |
| `Fw.Screen.leRun_spec` | agree | 4317423620043076293 | 875053347934713390 |  |
| `Fw.Parts.EngineScroll.entryLe_trans` | agree | 7988356497936731972 | 13195380486420345597 |  |
| `Fw.Parts.EngineScroll.orderCallbacks_perm` | agree | 6168987457941083824 | 13032793476399179037 |  |
| `Fw.Parts.EngineScroll.faithfulFrom` | agree | 13361383562450084038 | 14162371919341285904 |  |
| `Fw.Parts.EngineScroll.isRead_read` | agree | 10519647688549933100 | 13537610738799735697 |  |
| `Fw.Parts.EngineScroll.isRead_write` | agree | 8786802114933493103 | 7422434309548672363 |  |
| `Fw.Parts.EngineScroll.forced_mono` | agree | 1609423361076244931 | 5749184494652702264 |  |
| `Fw.Parts.EngineScroll.batched_le_one` | agree | 6523135455901997002 | 8897919959083346836 |  |
| `Fw.Parts.EngineScroll.runs_le` | agree | 8233303483154169168 | 12774872160275936494 |  |
| `Fw.Parts.Golden.decimal?` | agree | 2024033954 | 4098142096112713776 |  |
| `Fw.Parts.Golden.rin` | agree | 893280584 | 9506526342032403998 |  |
| `Fw.Parts.Golden.springJ` | agree | 12560250465617194318 | 6276462255991230205 |  |
| `Fw.Parts.Golden.main` | agree | 3812987455 | 11517300361552183949 |  |
| `Fw.Parts.HeroCountdown.lexLe` | agree | 1402962434 | 14128721827429984543 |  |
| `Fw.Parts.HeroCountdown.faceDelta_settled` | agree | 7983538969637958331 | 3672407345240505969 |  |
| `Fw.Parts.HeroCountdown.slices_nonpos` | agree | 16536093956796953355 | 7867724789994148899 |  |
| `Fw.Parts.HeroExit.pointerOff_mono` | agree | 659160663682231139 | 9195431825643010837 |  |
| `Fw.Parts.HeroExit.pointerOff_iff_threshold` | agree | 1285128902116733194 | 6016708005945433385 |  |
| `Fw.Parts.NavHitTest.findIdx?_congr'` | agree | 4217177856 | 8731694008555896653 |  |
| `Fw.Parts.NavHitTest.findIdx_congr` | agree | 6186552227763706826 | 5443299223997205694 |  |
| `Fw.Site.Breakpoints.catalogue_css` | agree | 8822227599840045762 | 14225335966749815171 |  |
| `Fw.Site.Breakpoints.catalogue_axis_edges` | agree | 493148645378441950 | 7792706734556331233 |  |
| `Fw.Site.Breakpoints.MQ.eval_indep_height_dpr` | agree | 150953926199545787 | 3352347620954703567 |  |
| `Fw.Site.Breakpoints.half_bounds` | agree | 3383163746 | 11431468816090332876 |  |
| `Fw.Site.Breakpoints.half_value` | agree | 5992847468863877628 | 15178132251319678405 |  |
| `Fw.Site.Breakpoints.gap600` | agree | 14565080010824733291 | 12320213489295641386 |  |
| `Fw.Site.Breakpoints.gap640` | agree | 18301370700036341494 | 6500060015721566316 |  |
| `Fw.Site.Breakpoints.gap860` | agree | 4411682626545559550 | 17972449679329433541 |  |
| `Fw.Site.Breakpoints.gap1000` | disagree | 10826935179828543176 | 7229061038398974156 | "no width rule at the 1000 edge matches on either side" claims too much. c1000 and c1000Nodw also have the width edge 1000 (catalogue_edges). At 1000.5 they los… |
| `Fw.Site.BreakpointGen.gapsJson` | agree | 2092839459 | 13780039580705619405 |  |
| `Fw.Site.BreakpointGen.genJson` | agree | 2092839459 | 8991197318610729246 |  |
| `Fw.Site.BreakpointGen.natList` | agree | 2570588240 | 9930421278254239491 |  |
| `Fw.Site.BreakpointGen.strList` | agree | 3487363897 | 9908052869540241596 |  |
| `Fw.Site.BreakpointGen.checkCond` | agree | 3212968224274080051 | 529078410307044226 |  |
| `Fw.Site.BreakpointGen.checkInventory` | agree | 3987208917 | 6622594294072803693 |  |
| `Fw.Site.BreakpointGen.opBreakpointsGen` | agree | 1343264538 | 164188034664512376 |  |
| `Fw.Site.BreakpointGen.argOf` | agree | 3629300436 | 16237646108002900333 |  |
| `Fw.Site.BreakpointGen.run` | agree | 3653997261 | 5991713302583784062 |  |
| `Fw.Site.Breakpoints.pairProbes` | agree | 16401344891349483061 | 17366224304017924205 |  |
| `Fw.Site.Breakpoints.matrix_pairs_agree` | agree | 10417332680251401871 | 1768272704272684177 |  |
| `Fw.Site.Breakpoints.matrix_fractional_in_gaps` | agree | 17171578188877402721 | 15819671352292718311 |  |
| `Fw.Site.Breakpoints.matrix_cross_no_touch_arm` | agree | 2621992028648124515 | 9094769987826049720 |  |
| `Fw.Site.Breakpoints.matrix_dw_arm` | agree | 9061226785275071384 | 4054279373528793813 |  |
| `Fw.Site.Breakpoints.matrix_landscape_overlaps` | agree | 4628356883600564126 | 10992514935117077027 |  |
| `Fw.Site.Breakpoints.Feature.pointerKw` | agree | 11541671350412343288 | 17815465788808054094 |  |
| `Fw.Site.Breakpoints.Feature.motionKw` | agree | 10586389568885586912 | 2306461764654946686 |  |
| `Fw.Site.Breakpoints.Feature.schemeKw` | agree | 12677653796522396360 | 5427688803819990985 |  |
| `Fw.Site.Breakpoints.Feature.mediaTypeKw` | agree | 4995273271618187308 | 12963620337271466118 |  |
| `Fw.Site.Breakpoints.Feature.forcedColorsKw` | agree | 9962850937898875830 | 11802510120439339819 |  |
| `Fw.Site.Breakpoints.Feature.legacyCss` | agree | 15912396429203590419 | 14747348788280903975 |  |
| `Fw.Site.Breakpoints.MQ.legacyCss` | agree | 2243106494055417421 | 16533362097014052035 |  |
| `Fw.Site.Breakpoints.MQ.taggedEdges` | agree | 16124553710885778221 | 12050352000887298880 |  |
| `Fw.Site.Breakpoints.combo` | agree | 7068410760301491265 | 11126152878342150587 |  |
| `Fw.Site.Breakpoints.Kind.str` | agree | 14237671609296049918 | 5254706813857080133 |  |
| `Fw.Measure.Series` | agree | 3931117990 | 8014426146298487102 |  |
| `Fw.Measure.valAt` | agree | 10764466654117148250 | 13974146861007551326 |  |
| `Fw.Measure.total` | agree | 4587696976856426794 | 10993489209702932533 |  |
| `Fw.Measure.diffFrames` | agree | 2588641337302292350 | 11708550805832632497 |  |
| `Fw.Measure.totalGap` | agree | 2588641337302292350 | 13535674381526429992 |  |
| `Fw.Measure.Class` | agree | 3931117990 | 6581710696548384215 |  |
| `Fw.Measure.Within` | agree | 13759438952483374193 | 7339684100564064645 |  |
| `Fw.Measure.Holds` | agree | 16054560005063867397 | 7493705855799408583 |  |
| `Fw.Measure.Class.le` | disagree | 10815727072737250461 | 14180789566129654437 | The math matches the Lean. The English "`c.le c'` when every pair within `c` is within `c'`" reads as a characterisation, but le is only sound for that (within_… |
| `Fw.Measure.Class.join` | agree | 7794193819014089996 | 10073550095805100041 |  |
| `Fw.Measure.Policy` | agree | 3931117990 | 9736698329015991453 |  |
| `Fw.Measure.maxOf` | agree | 434822048 | 10237844431349101303 |  |
| `Fw.Measure.pairVals` | agree | 16103186588751732010 | 17158763360746075340 |  |
| `Fw.Measure.kObs` | agree | 988627104220465608 | 980293720900665489 |  |
| `Fw.Measure.tObs` | agree | 988627104220465608 | 8452683634133133380 |  |
| `Fw.Measure.classify` | disagree | 4365503056447931362 | 9023008384909542845 | The case conditions overlap. When k(R) = 0 (and so t(R) = 0 ≤ t_max), both the det row and the stable row hold, and they give different values (det vs stable(0,… |
| `Fw.Measure.Admissible` | disagree | 16612968250247939391 | 3927472856925670253 | k and t are free in the disjunction. The Lean binds them by matching on c. Corrected: $$\operatorname{adm}_p(c) \iff c = \mathrm{det} \ \lor\ c = \mathrm{quar} … |
| `Fw.Measure.diffFrames_comm` | agree | 9832651930358849516 | 10093625547579875715 |  |
| `Fw.Measure.diffFrames_self` | agree | 13776945001603516415 | 3988237298736447039 |  |
| `Fw.Measure.totalGap_comm` | agree | 38445351521967700 | 8085616502531999597 |  |
| `Fw.Measure.total_eq_of_diff_zero` | agree | 14599880234177823269 | 16565385499144204948 |  |
| `Fw.Measure.mem_pairVals` | agree | 6636699135471761656 | 17764821934155877809 |  |
| `Fw.Measure.of_mem_pairVals` | agree | 8757058033327226236 | 16737009977237268040 |  |
| `Fw.Measure.le_maxOf` | agree | 402788507859230878 | 17482754263663440217 |  |
| `Fw.Measure.maxOf_le` | agree | 4325398493808774828 | 366375956445507947 |  |
| `Fw.Measure.le_obs` | agree | 13451303423807748807 | 577793414778211986 |  |
| `Fw.Measure.obs_le` | agree | 2468621134342217711 | 8217069725951622565 |  |
| `Fw.Measure.within_mono` | agree | 1699827784220943821 | 15345413975201679593 |  |
| `Fw.Measure.holds_mono` | agree | 10676587161903304707 | 2754660496152678313 |  |
| `Fw.Measure.holds_subset` | agree | 17155374148971640426 | 15975629871286370895 |  |
| `Fw.Measure.Class.le_refl` | agree | 13089584920594821784 | 11436010686628040 |  |
| `Fw.Measure.Class.le_trans` | agree | 10523488849215488257 | 2378734897263366231 |  |
| `Fw.Measure.Class.le_join_left` | agree | 8324382287689039865 | 7733251794799080131 |  |
| `Fw.Measure.Class.le_join_right` | agree | 6346572487297769485 | 10989661070277225874 |  |
| `Fw.Measure.holds_det_iff_stable00` | agree | 18250282196054310647 | 7992335654395390351 |  |
| `Fw.Measure.det_stable00` | agree | 11224227588773349213 | 14658776205029866078 |  |
| `Fw.Measure.classify_sound` | agree | 9616284482856295541 | 4012542464996358166 |  |
| `Fw.Measure.classify_admissible` | agree | 18297489415135096639 | 4991057618168268781 |  |
| `Fw.Measure.classify_strictest` | agree | 11428526557708847476 | 8061625474665239370 |  |
| `Fw.Measure.classify_mono` | agree | 14757049227725465340 | 2924933139488083200 |  |
| `Fw.Measure.classify_snoc` | agree | 2569619300972292591 | 6477449849102580537 |  |
| `Fw.Measure.classify_det_iff` | agree | 14399541946162217212 | 14256819643835041058 |  |
| `Fw.Measure.classify_quarantined_iff` | agree | 15996570500039815650 | 9030249749724158049 |  |
| `Fw.Measure.seriesOf` | agree | 2746302477118921082 | 4850861151809288713 |  |
| `Fw.Measure.ClassRow` | agree | 3931117990 | 10256140277886487059 |  |
| `Fw.Measure.classifyAll` | agree | 16067410090206305269 | 14261555124949279672 |  |
| `Fw.Measure.classifyAll_sound` | agree | 6873814951814830351 | 9567023756382778507 |  |
| `Fw.Measure.leFrames` | agree | 3724062887287186556 | 1838505397188375272 |  |
| `Fw.Measure.valAt_cons_zero` | disagree | 15777937534269648769 | 13674790091123098354 | The theorem proves only valAt (x :: r) 0 = x. The docstring also states (x::r)[i+1] = r[i] and [][i] = 0, which are the separate theorems valAt_cons_succ and va… |
| `Fw.Measure.valAt_cons_succ` | agree | 5530680968361843191 | 454429055067753879 |  |
| `Fw.Measure.valAt_nil` | agree | 6897084323336475097 | 11211494646556060400 |  |
| `Fw.Measure.forall_nat_split` | agree | 1857868817 | 4761358811662976654 |  |
| `Fw.Measure.leFrames_iff` | agree | 3436778916155502439 | 11865290325752627775 |  |
| `Fw.Measure.diffFrames_zero_iff` | agree | 16317357657340798212 | 1259960801943701610 |  |
| `Fw.Measure.total_le_of_leFrames` | agree | 9093671103659679626 | 11548072297564685237 |  |
| `Fw.Measure.det_frames_sound` | agree | 12514747838885657695 | 9899843403784856506 |  |
| `Fw.Measure.stable_frames_unsound` | disagree | 18233019987136091141 | 9020471761761710375 | The math (∀ k ≥ 2) matches the Lean. The English "With one frame allowed to differ and no total gap" is wrong. The witness v = [0,1], v' = [1,0] differs in two … |
| `Fw.Measure.marginOf` | agree | 3918299765 | 10392852677020927064 |  |
| `Fw.Measure.margin_sound` | disagree | 8168097739944979335 | 6092905124250883100 | The quantifier "∀ k, t, b, b', v, v' ∈ ℤ^*" puts k and t in ℤ^*. In the Lean, k, t : ℕ and only the four runs are Series = ℤ^*. Corrected: $$\forall k, t \in \m… |
| `Fw.Measure.SoundMargin` | agree | 412604790 | 3731698498807703029 |  |
| `Fw.Measure.margin_exact` | agree | 17039175815529580735 | 16715223550391407495 |  |
| `Fw.Measure.quarantined_unsound` | agree | 2074991694798680659 | 3578321273920363351 |  |
| `Fw.Measure.TypeObs` | agree | 3931117990 | 16187770155048382383 |  |
| `Fw.Measure.typeOk` | agree | 12035746382597398677 | 16016597312226212029 |  |
| `Fw.Measure.noMoreWork` | agree | 3276332724036600858 | 17309204925753244029 |  |
| `Fw.Measure.Promise` | agree | 13759438952483374193 | 16808882695540736359 |  |
| `Fw.Measure.typeOk_sound` | agree | 7133921010868635016 | 7709027319130539388 |  |
| `Fw.Measure.noMoreWork_sound` | agree | 9997276766248713760 | 4602900827515007076 |  |
| `Fw.Measure.promise_total` | agree | 5128735658350405641 | 15258223858555528222 |  |
| `Fw.Measure.Entry` | agree | 3931117990 | 14780378097101043419 |  |
| `Fw.Measure.runCost` | agree | 8648311689744204822 | 2497688248009539032 |  |
| `Fw.Measure.noMoreWork_cost` | agree | 7157085185538849944 | 14421433527454327799 |  |
| `Fw.Measure.WebKit.countTypes` | agree | 4017531403 | 1629645803444354788 |  |
| `Fw.Measure.WebKit.ignored` | agree | 4017531403 | 7099757618162973054 |  |
| `Fw.Measure.WebKit.ratAbs` | agree | 3498294262 | 13328977217117694402 |  |
| `Fw.Measure.WebKit.quadArea` | agree | 1378365008 | 3336243202457279508 |  |
| `Fw.Measure.WebKit.roundHalfUp` | agree | 2426920303 | 11985094345688703093 |  |
| `Fw.Measure.WebKit.Row` | agree | 3931117990 | 6218121210375597778 |  |
| `Fw.Measure.WebKit.Tally` | disagree | 3931117990 | 11726899707435229563 | The field counts is List Nat, so the type does not fix its length at /T/. Only tally's output has /T/ entries. Corrected: $$\mathrm{Tally} = \mathbb{N}^{*} \tim… |
| `Fw.Measure.WebKit.countType` | disagree | 587461394105216975 | 13279728340686801692 | Lean is the length of a list filter, so equal rows count once each. The guard has two identical Layout rows and gets 2. Set-builder /{r ∈ R / ...}/ would merge … |
| `Fw.Measure.WebKit.tally` | agree | 4578681049693924863 | 10265481444545566807 |  |
| `Fw.Measure.WebKit.stepOf` | disagree | 1413513732 | 12703991057816573628 | The subtraction is on ℕ and truncates. When no mark is ≤ s the Lean gives 0, but the math gives −1. The domain s ≥ m_0 appears only in the English. Corrected: $… |
| `Fw.Measure.WebKit.Place` | disagree | 3931117990 | 14011712722111919043 | Place is the three-constructor type, but the math describes the function place instead (see the place row for the fix). Corrected: $$\mathrm{Place} = \{\mathrm{… |
| `Fw.Measure.WebKit.place` | disagree | 7936059542731249505 | 17913039631209419226 | The math only points to Place, and the cases there overlap: when e ≤ start < m_0, both before and after match. The Lean tests before first, so the result is bef… |
| `Fw.Measure.WebKit.window` | agree | 16641314665286082544 | 12736370197298190331 |  |
| `Fw.Measure.WebKit.stepRows` | agree | 5835232174677393451 | 3552020281019634712 |  |
| `Fw.Measure.WebKit.Reduced` | disagree | 3931117990 | 5012861652292607112 | The fields are List (List Nat) and List Int. Their lengths are not fixed, and n is a free variable. Corrected: $$\mathrm{Reduced} = (\mathbb{N}^{*})^{*} \times … |
| `Fw.Measure.WebKit.reduceSteps` | disagree | 7182257889439989746 | 18030968742563023962 | rowsBeforeFirstStep is the length of a list filter, so duplicate rows count once each. The set-builder in the math would merge them. Corrected last component: $… |
| `Fw.Measure.WebKit.stepOf_lt` | agree | 11567297100293502361 | 6371570612684797816 |  |
| `Fw.Measure.WebKit.place_step_lt` | disagree | 14129300563033836998 | 2662499425929607879 | M, e, r and k are free in the math, but the Lean quantifies them. Corrected: $$\forall M, e, r, k:\ M \ne [\,] \land \operatorname{place}(M, e, r) = \mathrm{ste… |
| `Fw.Measure.WebKit.sum_partition_range` | disagree | 10114943881604380211 | 15321832300687314110 | κ, g, n and R are free in the math. Corrected: $$\forall \kappa : \alpha \to \mathbb{N},\ g : \alpha \to \mathbb{Z},\ n \in \mathbb{N},\ R \in \alpha^{*}:\ (\fo… |
| `Fw.Measure.WebKit.steps_partition` | disagree | 973303652374035453 | 257866411312556575 | R, M and e are free in the math. Corrected: $$\forall R, M, e, \tau:\ M \ne [\,] \;\Rightarrow\; \sum_{k < /M/} n_\tau(R_k) = n_\tau(W(R))$$ |
| `Fw.Measure.WebKit.rows_conserved` | disagree | 14502404216174526813 | 9138162562318705395 | R, M and e are free in the math. The two counts are lengths of list filters, so duplicate rows count once each, and set-builder /{r / ...}/ would merge them. Co… |
| `Fw.Measure.WebKit.WZone` | disagree | 3931117990 | 196512662589351469 | counts is List Int, so its length is not fixed, and w is free. Corrected: $$\mathrm{WZone} = \mathbb{N} \times \mathbb{N} \times \mathbb{N} \times \mathbb{Z}^{*… |
| `Fw.Measure.WebKit.Step` | agree | 3931117990 | 14562544416973158185 |  |
| `Fw.Measure.WebKit.zoneIx` | agree | 953163936 | 8229831401075118362 |  |
| `Fw.Measure.WebKit.zoneSteps` | agree | 13624341915618992376 | 10934012663441649533 |  |
| `Fw.Measure.WebKit.zoneCount` | agree | 11432152151713540776 | 16165362460679771507 |  |
| `Fw.Measure.WebKit.zoneRec` | agree | 11394160494920720258 | 11298229361554828120 |  |
| `Fw.Measure.WebKit.zones` | agree | 17668835354764103384 | 5439926787719517861 |  |
| `Fw.Measure.WebKit.zoneIx_lt` | disagree | 5521191523064346135 | 18269966051854653209 | h and S are free in the math. Corrected: $$\forall h \in \mathbb{N},\ S,\ s \in S:\ \operatorname{zix}_h(s.y) < N_h(S)$$ |
| `Fw.Measure.WebKit.zones_partition` | agree | 3704583921729781407 | 18236784810231335714 |  |
| `Fw.Measure.WebKit.zones_steps_total` | agree | 16715927980077552237 | 5797188634932485263 |  |
| `Fw.Measure.WebKit.zoneSteps_append` | agree | 12981102834297813669 | 5246185034414615771 |  |
| `Fw.Measure.WebKit.Tol` | agree | 3931117990 | 1670262409934758360 |  |
| `Fw.Measure.WebKit.absI` | agree | 2367048215 | 8657354315477588721 |  |
| `Fw.Measure.WebKit.stStep` | agree | 3413034288 | 7586365207992119945 |  |
| `Fw.Measure.WebKit.stats` | disagree | 2988002467 | 17118491399132884585 | The math gives only the non-empty case, where min and max over an empty list are undefined. The Lean defines stats([]) = (0,0,0); only the English says so. Corr… |
| `Fw.Measure.WebKit.cellStatus` | agree | 7250131399031699143 | 3500172237288031716 |  |
| `Fw.Measure.WebKit.cellVals` | agree | 12882999424964909710 | 5575082572768765110 |  |
| `Fw.Measure.WebKit.classifyCells` | disagree | 11158056407918044845 | 8400440796912890734 | The det, stable and quar-by-max cases do not require equal lengths, so they overlap with the first quar case. R_1 is undefined for R = [], where the Lean uses h… |
| `Fw.Measure.WebKit.Inv` | agree | 4047045415 | 16156846080971897788 |  |
| `Fw.Measure.WebKit.inv_step` | disagree | 13438233413361943372 | 1699298544458670972 | σ and v are free in the math. Corrected: $$\forall \sigma \in \mathbb{Z}^3,\ v \in \mathbb{Z}:\ \operatorname{Inv}(\sigma) \Rightarrow \operatorname{Inv}(\opera… |
| `Fw.Measure.WebKit.inv_foldl` | disagree | 15576517556166428745 | 9373477919545655806 | Math: σ and V are free. Corrected: $$\forall V \in \mathbb{Z}^{*},\ \sigma \in \mathbb{Z}^3:\ \operatorname{Inv}(\sigma) \Rightarrow \operatorname{Inv}(\operato… |
| `Fw.Measure.WebKit.inv_stats` | disagree | 2975618593375659832 | 14031962829201004334 | The Lean has no non-empty hypothesis: it proves ∀ vs, Inv(stats vs), and stats([]) = (0,0,0) satisfies Inv. The math and the English ("of a non-empty list") sta… |
| `Fw.Measure.WebKit.stats_snoc` | disagree | 16122121228540269532 | 17855712070131395924 | V and x are free in the math. Corrected: $$\forall V \in \mathbb{Z}^{*},\ x \in \mathbb{Z}:\ V \ne [\,] \Rightarrow \operatorname{stats}(V \mathbin{+\!\!+} [x])… |
| `Fw.Measure.WebKit.spread_step` | disagree | 1951591541450519475 | 13664673788709296931 | ℓ, h, b and x are free in the math. Corrected: $$\forall (\ell, h, b) \in \mathbb{Z}^3,\ x \in \mathbb{Z}:\ \operatorname{Inv}(\ell, h, b) \land (\ell', h', b')… |
| `Fw.Measure.WebKit.cellStatus_snoc` | disagree | 2041925030879651644 | 16477978892348315935 | tol, V and x are free in the math. a is arbitrary, and r ≤ 1 is the Lean's num_r ≤ den_r. Corrected: $$\forall \mathrm{tol} = (a, r),\ V \in \mathbb{Z}^{*},\ x … |
| `Fw.Measure.WebKit.maxOf_map_le` | disagree | 4129911459868968161 | 16638598954630091990 | f, g and L are free in the math. Corrected: $$\forall f, g : \alpha \to \mathbb{N},\ L \in \alpha^{*}:\ (\forall x \in L:\ f(x) \le g(x)) \Rightarrow \max{}^{*}… |
| `Fw.Measure.WebKit.classifyCells_snoc` | disagree | 7429653682100254942 | 17230184478377151475 | tol, R and x are free in the math. Corrected: $$\forall \mathrm{tol} = (a, r),\ R \in (\mathbb{Z}^{*})^{*},\ x \in \mathbb{Z}^{*}:\ r \le 1 \land R \ne [\,] \Ri… |
| `Fw.Measure.WebKit.const_of_spread_zero` | disagree | 1196543588850179280 | 14140411441297560470 | V is free in the math. Corrected: $$\forall V \in \mathbb{Z}^{*}:\ (\ell, h, b) = \operatorname{stats}(V) \land h - \ell = 0 \Rightarrow \forall u, v \in V:\ u … |
| `Fw.Measure.WebKit.classifyCells_det_holds` | disagree | 1868862034747537152 | 18304743388789934006 | tol and R are free in the math. Corrected: $$\forall \mathrm{tol},\ R:\ \operatorname{classifyCells}(R, \mathrm{tol}) = 0 \Rightarrow \operatorname{Holds}(\math… |
| `Fw.Measure.WebKit.classifyCells_stable` | agree | 18209405775035080899 | 10340977071279584074 |  |
| `Fw.Measure.WebKit.classifyCells_det_iff` | disagree | 10142406327214317105 | 11815687482208067990 | tol and R are free in the math, and R_1 is undefined for R = [] (Lean: headD []). Corrected: $$\forall \mathrm{tol},\ R:\ \operatorname{classifyCells}(R, \mathr… |
| `Fw.Measure.WebKit.occ` | agree | 699084544 | 1127644009050505970 |  |
| `Fw.Measure.WebKit.symDiff` | agree | 1246785510 | 17436626081197191530 |  |
| `Fw.Measure.WebKit.keysOf_singletons` | disagree | 6918812425755989884 | 7045737885941799459 | The list x_1..x_m is free in the math. Corrected: $$\forall m,\ x_1, \dots, x_m \in \Sigma^{*}:\ \operatorname{keys}([[(x_1, 0)], \dots, [(x_m, 0)]]) = \operato… |
| `Fw.Measure.WebKit.symDiff_self` | agree | 973726059248565645 | 750908521517437591 |  |
| `Fw.Measure.WebKit.symDiff_terms_comm` | disagree | 3593551289043951633 | 11467163868004345526 | A and B are free; only K is quantified. Corrected: $$\forall A, B, K \in (\Sigma^{*})^{*}:\ \sum_{x \in K} /\#_x(A) - \#_x(B)/ = \sum_{x \in K} /\#_x(B) - \#_x(… |
| `Fw.Measure.WebKit.CRow` | disagree | 3931117990 | 11780753257447439495 | cls is a Nat, and the type does not restrict it to {0,1,2}. Corrected: $$\mathrm{CRow} = \Sigma^{*} \times \Sigma^{*} \times \Sigma^{*} \times \mathbb{N}$$ (cla… |
| `Fw.Measure.WebKit.Summary` | agree | 3931117990 | 14581027554369348178 |  |
| `Fw.Measure.WebKit.lastCls` | agree | 3154223693106111497 | 14176723685796351798 |  |
| `Fw.Measure.WebKit.summarize` | disagree | 17346974674929751393 | 1086771375312670676 | The math never defines R_g, f_g, m_g or levels(R_g). Because keys can collide ("a/b"+"c" and "a"+"b/c"), f_g and m_g are the fields of the group's first row, an… |
| `Fw.Measure.WebKit.summarize_worst` | disagree | 7403079843117610682 | 18260868658633241004 | R is free in the math. Corrected: $$\forall R,\ e \in \operatorname{summarize}(R),\ (\lambda, c) \in e.\mathrm{levels}:\ c \le e.\mathrm{worst}$$ |
| `Fw.Measure.Counts` | agree | 3931117990 | 14445462944785417468 |  |
| `Fw.Measure.Frame` | agree | 3931117990 | 3764810916004302957 |  |
| `Fw.Measure.sumBy` | agree | 2363184799 | 3873646219579512839 |  |
| `Fw.Measure.countIn` | agree | 7468465064302734687 | 11610226530059421903 |  |
| `Fw.Measure.Frame.count` | agree | 9818418828417099188 | 15027022876477057139 |  |
| `Fw.Measure.padStart5` | agree | 3438944622 | 7184427246833425548 |  |
| `Fw.Measure.zoneId` | disagree | 7442719906477834373 | 15144697335481971854 | h is any natural number, including 0, and the math leaves h = 0 undefined (⌊y/0⌋). In Lean, (y : Int) / 0 = 0, so for h = 0 every swipe frame is in zone "y00000… |
| `Fw.Measure.Tagged` | agree | 3931117990 | 207772434089840483 |  |
| `Fw.Measure.tag` | agree | 3554641214305825399 | 14554269060324356986 |  |
| `Fw.Measure.lastY` | agree | 12131609919347228003 | 11176866921214805245 |  |
| `Fw.Measure.firstSeen` | agree | 1429689486 | 13896687492586194032 |  |
| `Fw.Measure.insKey` | disagree | 1154949025 | 13662554290939322117 | ins(k, L) = sort({k} ∪ L) only holds when L is sorted and has no duplicates. Counterexample: insKey "a" ["c","b"] = ["a","c","b"]. The precedent MQ.insertSorted… |
| `Fw.Measure.keysOf` | agree | 3271801499984301465 | 15242499733184864800 |  |
| `Fw.Measure.Zone` | agree | 3931117990 | 121002532145582998 |  |
| `Fw.Measure.rowsOf` | agree | 11783146615145213500 | 7523825444387045872 |  |
| `Fw.Measure.zoneOf` | agree | 15138341313643436141 | 154511149906822466 |  |
| `Fw.Measure.zoneSumsFrom` | agree | 817235657417520223 | 16447646743060196277 |  |
| `Fw.Measure.zoneSums` | agree | 1938756300488351363 | 13108079204138617074 |  |
| `Fw.Measure.Zone.sum` | agree | 16987816154879908971 | 9364316356149972145 |  |
| `Fw.Measure.findZone` | agree | 285537589827492965 | 6779667917508701874 |  |
| `Fw.Measure.sumAt` | agree | 10124932978587318197 | 679017933920258180 |  |
| `Fw.Measure.framesAt` | agree | 175487819333116675 | 12147755084460564372 |  |
| `Fw.Measure.scrolledAt` | agree | 13373192800844073947 | 11822424019257115132 |  |
| `Fw.Measure.sumBy_append` | disagree | 15647582540199657352 | 7634297552515337971 | g, A, B are free in the math, but Lean quantifies them. Corrected: $$\forall g, A, B:\ \operatorname{sumBy}(g, A \mathbin{+\!\!+} B) = \operatorname{sumBy}(g, A… |
| `Fw.Measure.sumBy_zero` | agree | 3005806748163994366 | 15788597419452479112 |  |
| `Fw.Measure.sumBy_congr` | disagree | 14406787293401102937 | 8715966928199624648 | g, g', L are free in the math. Corrected: $$\forall g, g', L:\ (\forall x \in L:\ g(x) = g'(x)) \;\Rightarrow\; \sum_{x \in L} g(x) = \sum_{x \in L} g'(x)$$ |
| `Fw.Measure.sumBy_mono` | disagree | 281945892509906224 | 8826048672116695711 | g, g', L are free in the math. Corrected: $$\forall g, g', L:\ (\forall x \in L:\ g(x) \le g'(x)) \;\Rightarrow\; \sum_{x \in L} g(x) \le \sum_{x \in L} g'(x)$$ |
| `Fw.Measure.sumBy_nonneg` | disagree | 8970722563538727727 | 5743495331649433976 | g, L are free in the math. Corrected: $$\forall g, L:\ (\forall x \in L:\ 0 \le g(x)) \;\Rightarrow\; 0 \le \sum_{x \in L} g(x)$$ |
| `Fw.Measure.sumBy_map` | disagree | 432525635984642504 | 17237679957262913849 | g, f, L are free in the math, and f(L) means the mapped list. Corrected: $$\forall g, f, L:\ \sum_{y \in [f(x)]_{x \in L}} g(y) = \sum_{x \in L} g(f(x))$$ |
| `Fw.Measure.sumBy_one` | disagree | 15911232535078067984 | 16399149443206357635 | L is free in the math. Corrected: $$\forall L:\ \sum_{x \in L} 1 = /L/$$ |
| `Fw.Measure.tag_append` | disagree | 13391686364065910876 | 3291925009806698346 | h, y, A, B are free in the math. Corrected: $$\forall h, y, A, B:\ \operatorname{tag}_h(y, A \mathbin{+\!\!+} B) = \operatorname{tag}_h(y, A) \mathbin{+\!\!+} \… |
| `Fw.Measure.tag_ids` | disagree | 9452240659416139499 | 5448031005014554982 | h, y, F are free in the math. Corrected: $$\forall h, y, F:\ [r.\mathrm{id}]_{r \in \operatorname{tag}_h(y, F)} = [\operatorname{zone}_h(f)]_{f \in F}$$ |
| `Fw.Measure.sumBy_rows_tag` | disagree | 7499317909518203148 | 1032959823208659083 | h, y, F, Z, k are free in the math. Corrected: $$\forall h, y, F, Z, k:\ \sum_{r \in \operatorname{rows}(\operatorname{tag}_h(y, F), Z)} \operatorname{countIn}(… |
| `Fw.Measure.length_rows_tag` | disagree | 2995601724491961856 | 14459437772967160773 | h, y, F, Z are free in the math. Also the set-builder /{f ∈ F / ...}/ merges identical frames, but Lean takes the length of the filtered list, which counts repe… |
| `Fw.Measure.mem_insKey` | disagree | 9340818374163425608 | 8957306898094377224 | k, x, L are free in the math. Corrected: $$\forall k, x, L:\ x \in \operatorname{ins}(k, L) \iff x = k \lor x \in L$$ |
| `Fw.Measure.countIn_eq_zero_of_not_mem_foldr` | disagree | 15522053012292330328 | 11323250682245979792 | k, C, A are free in the math. Corrected: $$\forall k, C, A:\ k \notin \operatorname{foldr}(\operatorname{ins} \circ \pi_1, A, C) \;\Rightarrow\; \operatorname{c… |
| `Fw.Measure.sumBy_eq_zero_of_not_mem_keys` | disagree | 3745710538136767383 | 12591190969917731005 | k, R are free in the math. Corrected: $$\forall k, R:\ k \notin \operatorname{keys}([r.\mathrm{counts}]_{r \in R}) \;\Rightarrow\; \sum_{r \in R} \operatorname{… |
| `Fw.Measure.lookup_map_keys` | disagree | 876736841 | 8325566213219090060 | g, k, K are free in the math. Corrected: $$\forall g, k, K:\ \operatorname{lookup}(k, [(j, g(j))]_{j \in K}) = \begin{cases} g(k) & k \in K \\ \bot & k \notin K… |
| `Fw.Measure.zoneOf_sum` | disagree | 15830398160613585906 | 7804485245080462618 | R, Z, k are free in the math. Corrected: $$\forall R, Z, k:\ \operatorname{sum}(\operatorname{zoneOf}(R, Z), k) = \sum_{r \in \operatorname{rows}(R, Z)} \operat… |
| `Fw.Measure.find_map_zoneOf` | disagree | 6978991901957499161 | 17023576536054372404 | R, Z, L are free in the math. Corrected: $$\forall R, Z, L:\ \operatorname{find}([\operatorname{zoneOf}(R, j)]_{j \in L}, Z) = \begin{cases} \operatorname{zoneO… |
| `Fw.Measure.firstSeen_aux` | disagree | 1992975206 | 14707127673488328221 | A and L are free in the math, and fold(A, L) is never defined. Corrected: $$\forall A, L:\ \operatorname{nodup}(A) \;\Rightarrow\; \operatorname{nodup}(\operato… |
| `Fw.Measure.firstSeen_nodup` | disagree | 25374702463417174 | 814667366695708318 | L is free in the math. Corrected: $$\forall L:\ \operatorname{nodup}(\operatorname{firstSeen}(L))$$ |
| `Fw.Measure.mem_firstSeen` | disagree | 3226367232712550972 | 14707581962583840468 | L, y are free in the math. Corrected: $$\forall L, y:\ y \in \operatorname{firstSeen}(L) \iff y \in L$$ |
| `Fw.Measure.sum_partition` | disagree | 16698476959894021456 | 3626798343614627264 | g, R, L are free in the math. Corrected: $$\forall g, R, L:\ \operatorname{nodup}(L) \land (\forall r \in R:\ r.\mathrm{id} \in L) \;\Rightarrow\; \sum_{Z \in L… |
| `Fw.Measure.rowsOf_eq_nil_of_not_mem` | disagree | 18413942491248102189 | 8151026003839348827 | R, Z are free in the math. Corrected: $$\forall R, Z:\ Z \notin [r.\mathrm{id}]_{r \in R} \;\Rightarrow\; \operatorname{rows}(R, Z) = [\,]$$ |
| `Fw.Measure.sumAt_spec` | agree | 14179301698661247950 | 16045836411047804371 |  |
| `Fw.Measure.framesAt_spec` | disagree | 8933016369799741017 | 7504710359057295666 | The set-builder /{f ∈ F / zone_h(f) = Z}/ merges identical frames (Frame has decidable equality, and nothing rules out repeats). Lean takes the length of the fi… |
| `Fw.Measure.scrolledAt_spec` | agree | 13312673421429944628 | 13867008734063234616 |  |
| `Fw.Measure.sumAt_append` | agree | 4978639268474994394 | 14391126537437651169 |  |
| `Fw.Measure.framesAt_append` | agree | 10894020383906586562 | 13913991084744218829 |  |
| `Fw.Measure.scrolledAt_append` | agree | 7917110587966209521 | 15923297206593720792 |  |
| `Fw.Measure.Below` | agree | 10712902426828193137 | 15186456023747192853 |  |
| `Fw.Measure.sumBy_filter_below` | disagree | 11156018339986313942 | 15292390029403180745 | h, k, Z, F, G are free in the math. Corrected: $$\forall h, k, Z, F, G:\ \operatorname{below}_{h,k}(F, G) \;\Rightarrow\; \sum_{f \in F,\ \operatorname{zone}_h(… |
| `Fw.Measure.sumAt_mono` | agree | 17203619871442308649 | 13693987324545988915 |  |
| `Fw.Measure.sumAt_le_append` | agree | 106177196382023718 | 8356418990667013539 |  |
| `Fw.Measure.zoneIds` | agree | 2864162613904101359 | 1329251473925570975 |  |
| `Fw.Measure.zoneIds_zoneSumsFrom` | disagree | 3067824238693863970 | 13228228692034602861 | h, y_0, F are free in the math. Corrected: $$\forall h, y_0, F:\ \operatorname{ids}(\operatorname{zoneSums}_h(y_0, F)) = \operatorname{firstSeen}([\operatorname… |
| `Fw.Measure.zoneIds_nodup` | agree | 10930554745055776754 | 17090399159875049726 |  |
| `Fw.Measure.mem_zoneIds` | agree | 8939176101732797496 | 16593724981982066030 |  |
| `Fw.Measure.sumBy_zones` | disagree | 3535941583735736722 | 4063904698474402967 | h, y_0, F, g are free in the math. Corrected: $$\forall h, y_0, F, g:\ \sum_{z \in \operatorname{zoneSums}_h(y_0, F)} g(z) = \sum_{Z \in \operatorname{firstSeen… |
| `Fw.Measure.cover_tag` | disagree | 1343907616655754875 | 9766472531033745401 | h, y_0, F are free in the math (only r is quantified). Corrected: $$\forall h, y_0, F,\ \forall r \in R:\ r.\mathrm{id} \in \operatorname{firstSeen}(R.\mathrm{i… |
| `Fw.Measure.sumBy_tag_counts` | disagree | 8071384096479203838 | 4267764215188938535 | k, h, y, F are free in the math. Corrected: $$\forall k, h, y, F:\ \sum_{r \in \operatorname{tag}_h(y, F)} \operatorname{countIn}(r.\mathrm{counts}, k) = \sum_{… |
| `Fw.Measure.sumBy_tag_dy` | disagree | 16969251380269620173 | 1016893082455807073 | h, y, F are free in the math. Corrected: $$\forall h, y, F:\ \sum_{r \in \operatorname{tag}_h(y, F)} r.dy = \operatorname{lastY}(y, F) - y$$ |
| `Fw.Measure.length_tag` | disagree | 16755015601265272645 | 16100959423228762153 | h, y, F are free in the math. Corrected: $$\forall h, y, F:\ /\operatorname{tag}_h(y, F)/ = /F/$$ |
| `Fw.Measure.zones_sum_total` | agree | 16377541806263083133 | 12321851548313729846 |  |
| `Fw.Measure.zones_frames_total` | agree | 2054604037808507236 | 9300001380296445683 |  |
| `Fw.Measure.zones_scrolled_total` | agree | 10746777261946277577 | 11669154050920431339 |  |
