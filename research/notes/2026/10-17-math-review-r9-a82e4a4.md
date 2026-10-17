---
title: Math review round 9 at a82e4a4 (new Fw.Measure.Freeze and Classes; rows changed by the round-8 fixes)
date: 2026-10-17
status: CONFIRMED
round: 9
---

# Math review round 9 at a82e4a4

Two math-reviewer agents (workflow `review-r9`, read-only) back-translated the 155 pending or stale declarations at
a82e4a4: the freeze rule (freeze-lean), the unit-aware classes (pixel-tolerance), and every row that math-r8-fix changed.
Method as in rounds 3 to 8. The lead wrote this record from the agents' structured verdicts; `stmtHash` and
`mathHash` come from `lake exe mathview` at a82e4a4.

## Counts

| Batch | Reviewed | Agree | Disagree |
|---|---|---|---|
| A | 90 | 84 | 6 |
| B | 65 | 64 | 1 |
| **Total** | 155 | 148 | 7 |

Batch A: Fw.Measure.Freeze, Classes, SelfCheck, Snapshot. Batch B: Fw.Store.Layout and Reduce, Fw.Gate.Items, Compare
and State, Fw.Obs.Health, Fw.Console.Alert, Fw.Board, Fw.Site.BreakpointMatrix.
Not returned by an agent, still pending: none.
Pattern: a bound variable that shadows a function of the same name (k, \delta, f) is still the main finding. Fixes go
to a lean-prover task (math-r9-fix).

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Measure.Freeze.Level` | agree | 3931117990 | 9782038254347367418 |  |
| `Fw.Measure.Freeze.Level.rank` | agree | 12065404202427427432 | 12530798667557316465 |  |
| `Fw.Measure.Freeze.Level.worse` | agree | 2711626381368143205 | 13890429428044484822 |  |
| `Fw.Measure.Freeze.levelOf` | agree | 11873340837789204166 | 11791456084856692656 |  |
| `Fw.Measure.Freeze.Level.rank_inj` | agree | 13359174566943166822 | 13773647793367856768 |  |
| `Fw.Measure.Freeze.Level.rank_le_two` | agree | 6121174068176533992 | 6540769557924962998 |  |
| `Fw.Measure.Freeze.Level.rank_worse` | agree | 6531867188679120407 | 4126729647085703251 |  |
| `Fw.Measure.Freeze.levelOf_mono` | disagree | 7789742885192530527 | 16789625670256144499 | The hypothesis is written \operatorname{le}(c, c'), but Class.le is defined in the math as c \preceq c', so le is never defined. Fix: \forall c, c' \in \mathrm{Class}:\ c \preceq c' \Rightarrow \operatorname{rank}(\operatorname{lvl}(c)) \le \operatorname{rank}(\operatorname{lvl}(c')) |
| `Fw.Measure.Freeze.Entry` | agree | 3931117990 | 4638586851758342521 |  |
| `Fw.Measure.Freeze.Table` | agree | 3931117990 | 6567909456366469467 |  |
| `Fw.Measure.Freeze.entry?` | agree | 3567485898132737402 | 13856063943542483588 |  |
| `Fw.Measure.Freeze.levelIn` | agree | 14833771650818029659 | 5116825484465575843 |  |
| `Fw.Measure.Freeze.worstOf` | agree | 571255142188768083 | 2684711973492753585 |  |
| `Fw.Measure.Freeze.typesOf` | agree | 9127776472969993149 | 18384756853693185613 |  |
| `Fw.Measure.Freeze.kOf` | agree | 17881290912926013825 | 17306978372173485894 |  |
| `Fw.Measure.Freeze.tOf` | agree | 17881290912926013825 | 18300333507501651915 |  |
| `Fw.Measure.Freeze.tBoundOf` | agree | 918168195304017601 | 18241227124585687430 |  |
| `Fw.Measure.Freeze.FRow` | agree | 3931117990 | 15507356496724911082 |  |
| `Fw.Measure.Freeze.freezeCore` | agree | 3030066734578338189 | 7592684293844112526 |  |
| `Fw.Measure.Freeze.toTable` | agree | 15660252411839054142 | 18137648646157487141 |  |
| `Fw.Measure.Freeze.tally` | agree | 17638897491882838887 | 4931531273903676189 |  |
| `Fw.Measure.Freeze.ranks` | agree | 14151356361555723362 | 4134796325575959481 |  |
| `Fw.Measure.Freeze.rank_worstOf` | agree | 5113598014899815941 | 9748480056329752739 |  |
| `Fw.Measure.Freeze.maxOf_congr` | agree | 15382282624976159384 | 4959347905617739585 |  |
| `Fw.Measure.Freeze.worstOf_congr` | agree | 2969937940117812782 | 15708713738690632162 |  |
| `Fw.Measure.Freeze.worstOf_perm` | agree | 17443311636746322522 | 14038787744720008935 |  |
| `Fw.Measure.Freeze.worstOf_append_self` | agree | 14682463232757727650 | 9989462973569655556 |  |
| `Fw.Measure.Freeze.worstOf_single` | agree | 11021908197747743188 | 10081497442742499424 |  |
| `Fw.Measure.Freeze.worstOf_replicate` | agree | 17266239348445947616 | 3199923572701090308 |  |
| `Fw.Measure.Freeze.le_worstOf` | agree | 15429392332793304632 | 11659971924011798698 |  |
| `Fw.Measure.Freeze.worstOf_attained` | agree | 9400234032235499275 | 13967804790478615166 |  |
| `Fw.Measure.Freeze.worstOf_mono` | agree | 1128536191585899126 | 4982573004276298759 |  |
| `Fw.Measure.Freeze.worstOf_cons` | agree | 9084187196168765738 | 4238499100100620209 |  |
| `Fw.Measure.Freeze.worstOf_missing` | agree | 15428966666704807328 | 5813809543334430889 |  |
| `Fw.Measure.Freeze.mem_keysOf` | agree | 7497367487681006663 | 14913777690795061892 |  |
| `Fw.Measure.Freeze.entry_isSome_iff` | agree | 16760976103119140598 | 9798527455680151719 |  |
| `Fw.Measure.Freeze.mem_typesOf` | agree | 18176276226885681769 | 8400115820796662462 |  |
| `Fw.Measure.Freeze.freezeCore_types` | agree | 2295468911931953690 | 13714296569117292641 |  |
| `Fw.Measure.Freeze.freezeCore_row` | agree | 8290898866649778594 | 10235700314507387186 |  |
| `Fw.Measure.Freeze.levelIn_of` | agree | 9722730694456763075 | 10078504894463393587 |  |
| `Fw.Measure.Freeze.worstOf_refreeze` | agree | 6021580943207881284 | 3100859958590824075 |  |
| `Fw.Measure.Freeze.tableOf` | disagree | 6026270764118609014 | 19781973226200501 | \beta_\tau uses \operatorname{tBound}_{p,q}, but the bound is defined in the math as \operatorname{tb}_{p,q}, and tBound is also the name of the Entry field. Fix: \beta_\tau = \operatorname{tb}_{p,q}(\mathrm{px}, R_\tau) when \operatorname{unit}(\tau) = \mathrm{px}; the rest is unchanged. |
| `Fw.Measure.Freeze.worstOf_single_classify` | agree | 1282234566076230782 | 9808944068522462724 |  |
| `Fw.Measure.Freeze.minRuns` | agree | 421340980 | 4681242566546811634 |  |
| `Fw.Measure.Freeze.RunTable` | agree | 3931117990 | 13998335823092352513 |  |
| `Fw.Measure.Freeze.freeze` | agree | 18101540872976449343 | 8696353345072965639 |  |
| `Fw.Measure.Freeze.freeze_ok_iff` | agree | 924014859540743201 | 2894241464194429854 |  |
| `Fw.Measure.Freeze.freeze_few` | agree | 3324851719825503311 | 9645222295924898576 |  |
| `Fw.Measure.Freeze.freeze_mixed` | agree | 15456167705596592146 | 18168807936614634682 |  |
| `Fw.Measure.TypeUnit` | agree | 3931117990 | 2235832424639837229 |  |
| `Fw.Measure.unitOf` | agree | 16341781227321910795 | 12019621558906096264 |  |
| `Fw.Measure.PxTol` | agree | 3931117990 | 18102917987830339263 |  |
| `Fw.Measure.pxTolDefault` | agree | 7824068412078794506 | 11664331346493970930 |  |
| `Fw.Measure.minAbsTotal` | agree | 988627104220465608 | 7032424111592370977 |  |
| `Fw.Measure.tBound` | agree | 600470516768757794 | 8016825684745911048 |  |
| `Fw.Measure.policyFor` | agree | 15241101419757106399 | 973705619359714226 |  |
| `Fw.Measure.classifyU` | agree | 9114322155518590257 | 6117255407455578098 |  |
| `Fw.Measure.classifyU_count` | agree | 15851648044524817932 | 419381517239888485 |  |
| `Fw.Measure.tMax_le_tBound` | agree | 9973975863044421936 | 16374573222061509036 |  |
| `Fw.Measure.le_tBound_px_iff` | agree | 3081437399843285333 | 14115341277771873366 |  |
| `Fw.Measure.classify_policy_mono` | agree | 7106044286707765843 | 2799514537488262941 |  |
| `Fw.Measure.classifyU_le_classify` | agree | 14827853703426709492 | 2908394677810305532 |  |
| `Fw.Measure.classifyU_sound` | agree | 15585124777145290049 | 11667131230859467519 |  |
| `Fw.Measure.classifyU_strictest` | agree | 959590367125257606 | 7893259030694461739 |  |
| `Fw.Measure.classifyU_quarantined_iff` | agree | 4870194317399369249 | 920009034467435685 |  |
| `Fw.Measure.minAbsTotal_le` | agree | 1122905045264540321 | 202056847980522234 |  |
| `Fw.Measure.minAbsTotal_mem` | agree | 9561826815551651863 | 17299252629052510996 |  |
| `Fw.Measure.tBound_anti` | agree | 18214539534158191703 | 13683700868647905119 |  |
| `Fw.Measure.classify_nil` | agree | 18342863287464109837 | 17284873885678294005 |  |
| `Fw.Measure.classifyU_mono` | agree | 5621919096108464197 | 5302081513541823718 |  |
| `Fw.Measure.classifyU_tol_mono` | agree | 15905840354041516920 | 2992096888392729865 |  |
| `Fw.Measure.classifyAllU` | disagree | 16521735710886973749 | 10856938341118164372 | The bound type name k shadows the function k(R) (kObs): (k, ..., k(R_k), t(R_k)). Fix: bind \tau: [(\tau, \operatorname{classify}_{p,q}(\operatorname{unit}(\tau), R_\tau), k(R_\tau), t(R_\tau))]_{\tau \in \operatorname{keys}(\mathcal{R})}, R_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{R}} |
| `Fw.Measure.classifyAllU_types` | agree | 1467818203430195636 | 3782256075346325888 |  |
| `Fw.Measure.classifyAllU_row` | disagree | 1948536465565102654 | 9731293890321531743 | The bound k (the type) shadows the function k(R): 'k' = k(R_k)'. Fix: \forall p, q, \mathcal{R}, (\tau, c, k', t') \in \operatorname{classifyAll}_{p,q}(\mathcal{R}):\ c = \operatorname{classify}_{p,q}(\operatorname{unit}(\tau), R_\tau) \land k' = k(R_\tau) \land t' = t(R_\tau), with R_\tau = [\operatorname{series}_\tau(r)]_{r} |
| `Fw.Measure.classifyAllU_eq_of_counts` | agree | 13458612755930668949 | 18345431045868041849 |  |
| `Fw.Measure.classifyAllU_sound` | agree | 1352540795582499994 | 5907156189956789798 |  |
| `Fw.Measure.SelfCheck.SClass.name` | agree | 13127854298390031049 | 14493412157360723244 |  |
| `Fw.Measure.SelfCheck.obs` | agree | 13764121343766628012 | 6451251566146636659 |  |
| `Fw.Measure.SelfCheck.classOf_gc` | agree | 18318202972652009784 | 4362332858911305058 |  |
| `Fw.Measure.SelfCheck.diffVs_le_maxDiff` | agree | 16807322748350060472 | 10105861197124506433 |  |
| `Fw.Measure.SelfCheck.maxDiff_zero_iff` | agree | 14290114658272089634 | 10102092346327753789 |  |
| `Fw.Measure.SelfCheck.maxDiff_zero_iff_holds` | agree | 14702442132771712696 | 4994101390215938616 |  |
| `Fw.Measure.SelfCheck.check_sound` | disagree | 9696374925345326298 | 10435776308188722103 | The r7a fix (quantifiers, o_k) is correct, but the bound row field \delta shadows the function \delta (maxDiff): '\delta = \delta(R_k)'. Fix: bind (k, c, d, s, T) \in \operatorname{check}_\theta(\mathcal{R}) and write d = \delta(R_k); the rest is unchanged. |
| `Fw.Measure.SelfCheck.aligned_iff` | agree | 4142485415083933725 | 13394195922028927921 |  |
| `Fw.Measure.Snapshot.census` | agree | 17835941456747689167 | 9893394105918860579 |  |
| `Fw.Measure.Snapshot.census_names` | agree | 8121439739817002489 | 17109237336978265302 |  |
| `Fw.Measure.Snapshot.subsets_le` | agree | 7465810611349501855 | 102537571764651217 |  |
| `Fw.Measure.Snapshot.invalidated_of_rects` | agree | 1778365682846686269 | 15717541928890882118 |  |
| `Fw.Measure.Snapshot.rectArea_nonneg` | agree | 9498472848102837070 | 9883573508134624774 |  |
| `Fw.Measure.Snapshot.layers_additive` | disagree | 18198750520460587736 | 11773357471700717262 | The where-clause defining \Sigma^{draw}, \Sigma^{area}, \Sigma^{rects} sits after the $$ block, and the export's math and english fields drop it, so the exported math still leaves them undefined. Fix: move the definitions inside the $$, e.g. ',\quad \Sigma^{\mathrm{draw}}(L) = \sum_{l \in L,\ l.\mathrm{draws}} l.w \cdot l.h, ...' |
| `Fw.Store.isPart` | agree | 1526413716 | 16446138187370973060 |  |
| `Fw.Store.Manifest` | agree | 3931117990 | 13088134285687833762 |  |
| `Fw.Store.Manifest.problems` | agree | 16980040380588802030 | 8510283948881589798 |  |
| `Fw.Store.Manifest.valid_engine` | agree | 16509435146596952617 | 16962361947294862728 |  |
| `Fw.Store.Manifest.valid_entries` | agree | 15145975031043084535 | 8858658578465547250 |  |
| `Fw.Store.keyPairs` | agree | 15686914387374822767 | 517226728480673750 |  |
| `Fw.Store.keyPairs_inj` | agree | 17010061834014906365 | 16265178126524410485 |  |
| `Fw.Store.Request` | agree | 3931117990 | 4817376055578882622 |  |
| `Fw.Store.defaultPreset` | agree | 3265150928 | 7853710114533308619 |  |
| `Fw.Store.workflowInputs` | agree | 4535232382063731544 | 10547819822097561342 |  |
| `Fw.Store.fwInput` | agree | 1872990192 | 272213312632578993 |  |
| `Fw.Store.dispatchInputs` | agree | 824302957720216723 | 16876237838788327786 |  |
| `Fw.Store.blocked_none_sound` | agree | 1383900420832994748 | 5970156037551084381 |  |
| `Fw.Store.blocked_chromium` | agree | 1049073398592183973 | 11898405084434720136 |  |
| `Fw.Store.needs_dispatched` | agree | 1779297444039252038 | 2044467139561547091 |  |
| `Fw.Store.reqProblems` | agree | 7537011300159061116 | 4522873517875473538 |  |
| `Fw.Store.jobsOf` | agree | 6604317619944379008 | 16953966158126104369 |  |
| `Fw.Store.plan_nil_of_problems` | agree | 6181321260584923314 | 1976131971054035846 |  |
| `Fw.Store.plan_engines` | agree | 15283223376690268072 | 10638819243604636246 |  |
| `Fw.Store.reqProblems_nil_flags` | agree | 3722452588465976350 | 5473700258224445453 |  |
| `Fw.Store.plan_key_inj` | agree | 3265048476176011818 | 14712210406756088362 |  |
| `Fw.Store.exReq` | agree | 7619898758398151716 | 4990641376264551281 |  |
| `Fw.Gate.skipNames` | agree | 11555861478417778681 | 8868081456509596543 |  |
| `Fw.Gate.itemAt` | agree | 2446168784246779235 | 17090774190720055412 |  |
| `Fw.Gate.roleItems` | agree | 12342393303111460954 | 2836593327769302414 |  |
| `Fw.Gate.partItems` | agree | 15031121831213897308 | 5864064034895174323 |  |
| `Fw.Gate.partVerdict` | agree | 7893687298892105603 | 925958031163963872 |  |
| `Fw.Gate.mapRole` | agree | 2717344167870345556 | 11048713381279979199 |  |
| `Fw.Gate.setStyle` | agree | 11148855631069627049 | 2377056210807684676 |  |
| `Fw.Gate.itemAt_congr` | agree | 17321295562065302563 | 16167497155781417473 |  |
| `Fw.Gate.partVerdict_setStyle` | agree | 13237576824762848685 | 3715770335823144625 |  |
| `Fw.Gate.wellFormed` | agree | 4951868388565863431 | 5825552578779075206 |  |
| `Fw.Obs.Health.Params` | agree | 3931117990 | 8273850266985480562 |  |
| `Fw.Obs.Health.hungB` | agree | 8316707178756615866 | 6666882566365682050 |  |
| `Fw.Obs.Health.Stall` | agree | 13713126026905233672 | 10369875417336052799 |  |
| `Fw.Obs.Health.agentAlerts` | agree | 2551001111656038662 | 15489508168100554485 |  |
| `Fw.Obs.Health.wait_not_hang` | agree | 8651281492013428234 | 11438137116666789335 |  |
| `Fw.Obs.Health.sysAlerts` | disagree | 16308028834015433257 | 8433135608825304818 | Last row reuses n: the where-clause fixes n = nLive(p,t,A), but the permissionWait row binds ∃n. noteAt(ℓ)=n and its detail mins(t∸n) then reads as nLive. Fix: rename to ν: [(team.permissionWait, lead, “notification mins(t∸ν) min ago, …”) \| ∃ν. noteAt(ℓ)=ν ∧ permB(ℓ)]. |
| `Fw.Obs.Health.agent_alert_live` | agree | 2017912558867600265 | 2342908065013654430 |  |
| `Fw.Obs.Health.lockOrphan_iff` | agree | 12523414071249067102 | 10008030715282362679 |  |
| `Fw.Obs.Health.counts_total` | agree | 6723951722095234019 | 7425350008754314613 |  |
| `Fw.Console.Alert.attrib` | agree | 14553851645859233164 | 5947899986563623106 |  |
| `Fw.Console.Alert.slugChar` | agree | 510109451 | 13598717532547342325 |  |
| `Fw.Console.Alert.cut` | agree | 652675199 | 3564318370096979983 |  |
| `Fw.Console.Alert.title` | agree | 14957312256939327105 | 4859539321871798770 |  |
| `Fw.Console.Alert.subject` | agree | 193007194097963620 | 3702303958834260131 |  |
| `Fw.Console.Alert.act` | agree | 4609870720942665069 | 10334853408125660805 |  |
| `Fw.Gate.digitsVal` | agree | 948478879 | 1750747103775592911 |  |
| `Fw.Gate.expPart` | agree | 1320672793 | 15584582365162789922 |  |
| `Fw.Gate.unsignedNum` | agree | 450868400 | 7809679962936112743 |  |
| `Fw.Gate.numAt` | agree | 2666144811576536047 | 11348090137479593462 |  |
| `Fw.Gate.styleValueEq` | agree | 2494698578 | 1773529625978942621 |  |
| `Fw.Gate.beq_swap` | agree | 2553745957 | 9332419743249359817 |  |
| `Fw.Gate.sameSide` | agree | 2778088320 | 12699980802069151442 |  |
| `Fw.Gate.envChecks` | agree | 244413007985771538 | 16679478755887772215 |  |
| `Fw.Gate.stateParts` | agree | 9570663333227417342 | 1724177602706972358 |  |
| `Fw.Gate.reachRows` | agree | 10795105114329123498 | 4583717701734789073 |  |
| `Fw.Gate.evalState` | agree | 7578581819863067945 | 9932332521753885951 |  |
| `Fw.Gate.stale` | agree | 14469740175532349809 | 13302256718791004998 |  |
| `Fw.Console.boardCard` | agree | 5498730827532609432 | 2815966937537370494 |  |
| `Fw.Console.Board` | agree | 3931117990 | 14938694477424496556 |  |
| `Fw.Site.Breakpoints.matrix_blocks` | agree | 15144106818494550027 | 10357105151866319671 |  |
| `Fw.Site.Breakpoints.matrix_ids_nodup` | agree | 5984117894114421953 | 2380992808973264675 |  |
| `Fw.Store.obsOf` | agree | 6269551216281122112 | 2733431843139770261 |  |
| `Fw.Store.reduceOk_sound` | agree | 18284368218795928819 | 3198938284469033961 |  |
