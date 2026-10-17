---
title: Math review round 6 at 77b381c (re-review of the 62 round-5 fixes)
date: 2026-10-17
status: CONFIRMED
round: 6
---

# Math review round 6 at 77b381c

One math-reviewer agent (workflow `wave-ready-2`, read-only) re-reviewed the 62 declarations that round 5 marked
disagree and lean-math-fix-r5 fixed (69d7773). Method as in rounds 3 to 5: write the math from the Lean first, then
compare clause by clause. The lead wrote this record from the agent's structured verdicts; `stmtHash` and `mathHash`
come from `lake exe mathview` at 77b381c (cache key ff5b9f9cb0611ae7), after confirming the 61 agreed declarations did not
change since the review.

## Counts

| Reviewed | Agree | Disagree |
|---|---|---|
| 62 | 61 | 1 |

The one disagree is new, not a bad round-5 fix: `Fw.Sched.Admit.Inv` had a doubled backslash before `\forall`
(a row break inside `aligned`, which dropped the quantifier of the fresh-seq clause). Fixed in 77b381c; round 7
re-reviews it with the declarations added since (Fw/Plan, Fw/Gate, Fw/Obs, Fw/Measure).

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Sched.Admit.eq_of_nodup_map` | agree | 436139848 | 14207339253105805063 | Hypothesis is now that [f(c) \| c in l] has no repeats, plus a,b in l and f(a)=f(b), giving a=b. Matches the Lean. |
| `Fw.Sched.Admit.nodup_map_sublist` | agree | 645536096 | 763465470828201413 | Sublist plus a repeat-free image gives a repeat-free image of the sublist. Matches List.Pairwise.sublist. |
| `Fw.Sched.Admit.nodup_admit` | agree | 9158011613192942020 | 16863170379646716655 | Both no-repeats clauses are now about mapped lists. x' :: R ++ [y in Q \| id(y) != id(x)] matches the Lean, which parses as x' :: (run ++ filter). f(x')=f(x) and x in Q are both present. |
| `Fw.Sched.Admit.writeAt` | agree | 221296761862308444 | 13613044683743189588 | Scan order is fixed: the first y in Run (findSome?) with not(x~y) and a conflict, then the first p' in W(x) that conflicts with some q in W(y). Otherwise bottom. |
| `Fw.Sched.Admit.devAt` | agree | 11968143927411640709 | 15159223982402197585 | Run is scanned first (findSome?), then the first v in V(x) with v in V(y). Unrelated is required. Otherwise bottom. |
| `Fw.Sched.Admit.Inv` | disagree | The round-5 fix (no repeats in the mapped id/seq lists) is right, and the other clauses match the fields fresh, started, deps, writes, devs and budget. New break: the source has `\ \\forall x \in ...` (a doubled backslash, Admit.lean around line 562). Inside aligned, `\\` is a row break, so the fresh clause renders as a new right-aligned row reading 'forall x ∈ Run++Q: seq(x)<next' in italic letters, and the quantifier is lost. Fix: change `\\forall` to `\forall`, giving $$\ldots \text{ have no repeats},\ \forall x \in \mathit{Run} \mathbin{+\!\!+} Q:\ \mathit{seq}(x) < \mathit{next},\ \ldots$$ Fixed by the lead in 77b381c (single backslash); round 7 re-reviews it. |
| `Fw.Sched.Admit.psi` | agree | 17279220915337067317 | 12700098444351214090 | Sum of two list-filter lengths. Repeats are counted, which matches the Lean. |
| `Fw.Sched.Admit.Base` | agree | 16197377537675326756 | 1890392545194599604 | Every conjunct is now bracketed, and the eight clauses match the fields inv, zAged, zReady, znext, gnext, qG, rG and zq one to one. |
| `Fw.Sched.Admit.Ex.B4` | agree | 11142282837834494097 | 7282701421917824291 | The English now says these are small abstract numbers, not the tenths/MB scale. B=(4,8,0,0) matches cores, ram, cleanBuild and docker (defaults 0). |
| `Fw.Sched.Admit.Cex.σi` | agree | 17639440263550986050 | 5435669810055783989 | Run=[r1,e], Done=[], Q=[o,z], t=0, next=7. done and t are the State defaults. |
| `Fw.Sched.Admit.Cex.cmds` | agree | 13592552919542134372 | 8679465937024746063 | The 8 commands appear in the same order, each finish with the flag true. |
| `Fw.Sched.Admit.Cex.rest` | agree | 13592552919542134372 | 509022889985243014 | tick(26), finish(o,true). Matches the Lean. |
| `Fw.Sched.ParMetrics.sortS_sorted` | agree | 9847209347818384789 | 2409296374668966454 | Now indexes sortS(l). Pairwise <= on s over all i<j. |
| `Fw.Sched.ParMetrics.mergeGo_ok` | agree | 13357520133464333054 | 16734060114975675629 | o is bound (forall o in g). All four hypotheses are present. Pairwise e < s for i<j. |
| `Fw.Sched.ParMetrics.mergeGo_cover` | agree | 1894653855042681847 | 1963305733035335544 | Brackets now give A ⇒ [B ⇔ C]. p in c means covers(c,p). |
| `Fw.Sched.ParMetrics.merge_disjoint_sorted` | agree | 15879058867578421040 | 13470221484657453370 | m = merge(l) is bound. The math covers all pairs i<j, and the English says 'any later one'. |
| `Fw.Sched.ParMetrics.div_le_of_le_mul` | agree | 653433142 | 4729978802529562827 | States the division in Q with values cast to Q and x/0=0. Matches (x:Rat)/(y:Rat) ≤ (k:Rat). |
| `Fw.Sched.ParMetrics.speedup` | agree | 15651464537387123000 | 6351616310095364125 | A Nat sum cast to Q, divided by (b ∸ a) cast to Q, in Q, with x/0=0. |
| `Fw.Sched.ParMetrics.busyAt` | agree | 6618854042646415590 | 8818914149166766904 | List-filter length with repeats counted. The 'exists i in l covering p' condition matches l.any covers. |
| `Fw.Sched.ParMetrics.points` | agree | 16012442667506301285 | 10336527632763755784 | Filters the list a :: b :: flattened [s_i, e_i] on a <= p <= b, then sorts it. Repeats are kept, matching mergeSort. |
| `Fw.Sched.ParMetrics.segSum` | agree | 1457435609 | 3615953101809314220 | Uses truncated subtraction q ∸ p with an Iverson bracket on f(p), and 0 for lists shorter than 2. |
| `Fw.Sched.ParMetrics.serialShare` | agree | 15651464537387123000 | 18397307791323301988 | serial cast to Q, divided by (b ∸ a) cast to Q, with x/0=0. |
| `Fw.Sched.ParMetrics.stretch` | agree | 860301984 | 14218237832277043553 | d/d_solo in Q with x/0=0, which matches the English. |
| `Fw.Sched.ParMetrics.cp` | agree | 11534204576069871869 | 16802984433652248563 | ok(maxl of the d values of D) with maxl([])=0 when kahn(n,[],[0,n)) gives D, and cycle when it gives bottom. Fuel is n, as in the Lean. |
| `Fw.Serve.Tbl.empty_ok` | agree | 15666290570809750230 | 18050664196657645193 | alpha and key are quantified. |
| `Fw.Serve.Tbl.ok_unique` | agree | 4756260597300652464 | 4590980125155537240 | key, T, i and j are quantified. i,j < \|rows\| and the equal-key hypothesis are present. |
| `Fw.Serve.Tbl.has_eq` | agree | 8829925721849814737 | 4125939832359251191 | Quantified. Ok ⇒ (has ⇔ exists x in rows with key(x)=k), which matches the Bool equality with rows.any. |
| `Fw.Serve.Tbl.get?_eq` | agree | 15890265255252164933 | 66026314127004233 | Quantified over key, T and k. get = find over rows. |
| `Fw.Serve.Tbl.push_rows` | agree | 8915394780415350774 | 13260081937636243865 | Quantified. rows ++ [a]. |
| `Fw.Serve.Tbl.push_eq` | agree | 10904644283189860795 | 2308273579211163893 | Quantified. (rows ++ [a], I[key(a) ↦ \|rows\|]). |
| `Fw.Serve.Tbl.modify_eq` | agree | 11530726228494533973 | 14714258274340028200 | Quantified over T, k and f. The three cases include the out-of-range index (rows unchanged), which matches Array.modify. The none case gives T. |
| `Fw.Serve.Tbl.push_ok` | agree | 16992309065471658143 | 10955712726903381681 | Quantified. Ok and not has(T, key(a)) give Ok(push). |
| `Fw.Serve.Tbl.modify_rows` | agree | 2094035929265395706 | 627305016419931012 | Quantified over key, T, k and f. Ok ⇒ rows = map (if key x = k then f x else x). |
| `Fw.Serve.Tbl.modify_ok` | agree | 11815221007861748621 | 13629217548915683685 | Quantified. The id-preserving f hypothesis is present. |
| `Fw.Serve.runIdx_get` | agree | 6661357699925464799 | 5580252424565554262 | getD 0 is stated as 'absent = 0'. List-filter length, card = c and status running. Matches. |
| `Fw.Serve.query_after_run` | agree | 15157486654980598879 | 14481526622348463316 | cs = [c1..cn] is bound and no reset is allowed. ev(c1) ++ ... ++ ev(cn) = cs.flatMap events. Matches. |
| `Fw.Serve.Tbl.modify` | agree | 2758336468504801195 | 9410392846038374404 | The out-of-range case (rows, I) is added. Matches the match on idx[k]? and Array.modify. |
| `Fw.Serve.runIdx` | agree | 3149088961631741452 | 11551911712532721137 | n_c is a list-filter count. There is no entry when n_c = 0, which matches the foldr that inserts only for running runs. |
| `Fw.Serve.fastRow` | agree | 17560804047737547872 | 18067433450064323334 | sigma is gone. m = O(c.id) (bottom if absent) and rho = R(c.id) (0 if absent). The 11 fields match BoardCard in order, and stale = not landed ∧ rho=0 ∧ m=bottom ∧ STALE ≤ now ∸ lastAt. |
| `Fw.Ops.Meter.step_complete` | agree | 11251114897714883634 | 2590181205438230667 | p, sigma, now, O, o and r are all quantified. w and F_0 are defined inline (w=0 when omega=0), matching the hypothesis (if now/ω = s.window then s.fired else []). |
| `Fw.Ops.Meter.step_sound` | agree | 8388803732366841906 | 6113542853070472481 | Quantified. There exists o in O with o.agent = a and r(o). |
| `Fw.Ops.Meter.run_inv` | agree | 16279058002545642417 | 3766047391770356313 | Quantified over p, sigma and T, with the hypotheses bracketed. The conclusion (no repeats; w > σ.w or (w = σ.w and (a,r) not in σ.F)) matches, as does floor(t/0)=0. |
| `Fw.Ops.Meter.step` | agree | 16777480458224403722 | 13809211208027408910 | w = floor(now/ω) with w=0 when ω=0. F_0, N = fresh(F_0, cand), the new state (w, N ++ F_0) and the alerts (a,r,w) all match. |
| `Fw.Ops.PathCheck.inScope_iff` | agree | 369270830513400740 | 18353903242687839365 | S = (I,E) and x are quantified. The four conjuncts match. |
| `Fw.Ops.SpawnGuard.overRole_none` | agree | 14251551752926029052 | 8609772929738097166 | R and A are quantified. ⇔ forall (r,c) in R: #^r(A) <= c. |
| `Fw.Ops.SpawnGuard.check_none` | agree | 805829739956165195 | 15378615953665851504 | i is quantified. All conjuncts match the Lean. |
| `Fw.Ops.SpawnGuard.trap_worktree_role_as_teammate` | agree | 12434383979578912908 | 1263678196374941216 | i and rho are quantified. All three hypotheses are present. |
| `Fw.Ops.SpawnGuard.trap_exact` | agree | 5964047166111521356 | 3447210529468693927 | i and rho are quantified. All six hypotheses are present, and the result kindMismatch(worktree, teammate) matches. |
| `Fw.Ops.SpawnGuard.teammate_with_isolation_denied` | agree | 12394437821273403957 | 11658474587984605320 | i and rho are quantified, and the hypotheses match. |
| `Fw.Ops.SpawnGuard.accepted_nested_read_only` | agree | 8004628514037443770 | 6153455426946795844 | i and rho are quantified. The hypotheses role, accepted and d >= 1 give not edits. |
| `Fw.Ops.SpawnGuard.countKind` | agree | 15318421747809857204 | 1037833758645081820 | List-filter length. |
| `Fw.Ops.SpawnGuard.countSub` | agree | 14414273047122486095 | 6009095062531344497 | List-filter length, kind ≠ teammate. |
| `Fw.Ops.SpawnGuard.countRole` | agree | 10931890675436000845 | 15620714931482522894 | List-filter length, role = r. |
| `Fw.Ops.SpawnGuard.recentCount` | agree | 5236941062931335848 | 4718739622607950204 | List-filter length over H with s = spawner and now < t + Δ (windowSec). |
| `Fw.Ops.SpawnGuard.capFail` | agree | 7249119862315467034 | 8230591187853472063 | The negations of the earlier conditions are added, so the cases are disjoint. capRole(r) when overRole = r, and bottom when overRole = bottom, matching the map. |
| `Fw.Ops.SpawnGuard.roleCheck` | agree | 2061137161209727187 | 16714818395940745383 | The cases are disjoint, with the negations added. kindMismatch(ρ.runsAs, κ(q)) has its arguments in the right order. The last row is capFail(C, ν(q) :: A). |
| `Fw.Ops.SpawnGuard.excused` | agree | 13620722946369271513 | 7145884985402333391 | rho is bound by an existential on role(i). u ∧ runsAs = subagent ∧ not edits. |
| `Fw.Ops.SpawnGuard.check` | agree | 17876292504302604772 | 15734056732615730379 | The cases are disjoint, using U and not taken. The order unnamed, nameInUse, role matches the if-chain. |
| `Fw.Ops.Usage.ins_keys` | agree | 10574807479032757668 | 13889003097666296536 | r, t and x are quantified. |
| `Fw.Ops.Usage.lastWins` | agree | 443133856313385135 | 15164241927035425120 | The survivors are l_i with no later same id, in ascending i. This matches the foldl, which removes the earlier same-id entry and appends (checked on [a1,b1,a2] → [b1,a2]). |
| `Fw.Ops.Usage.exLines` | agree | 12153952940135557592 | 13161218310386876018 | The English now says output 3 then output 5, and the math adds 'all other fields 0', matching the Usage defaults. |
| `Fw.Measure.WebKit.reduceSteps` | agree | 7182257889439989746 | 4941174131017953887 | All four components are restored: per-step counts and paintArea for k < \|M\|, tally(W(R)), and the before-count. Matches the Lean. |
