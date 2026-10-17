---
title: Math review round 8 (planned as 7b) at fee88b2 (Fw.Obs, Fw.Console, Fw.Gate, Fw.Site, Fw.Store, Fw.Plan)
date: 2026-10-17
status: CONFIRMED
round: 8
---

# Math review round 8 (7b) at fee88b2

Four math-reviewer agents (workflow `review-r7b`, read-only) back-translated the pending or stale declarations in the
modules that round 7a left for watch-fix, gate-unreachable and lean-console-gaps, which have landed. Method as in
rounds 3 to 6. The lead wrote this record from the agents' structured verdicts; `stmtHash` and `mathHash` come from
`lake exe mathview` at fee88b2 (none of these modules changed between the review and fee88b2).

## Counts

| Batch | Reviewed | Agree | Disagree |
|---|---|---|---|
| A | 165 | 150 | 15 |
| B | 114 | 99 | 15 |
| C | 91 | 83 | 8 |
| D | 132 | 121 | 11 |
| **Total** | 502 | 453 | 49 |

Batch A: Fw.Obs.Health, Fw.Console.Alert, Land and Self, Fw.Ops.Obs and SpawnGuard. Batch B: Fw.Gate.Items, Reach
and State. Batch C: Fw.Gate.Compare and Rule, Fw.Site.BreakpointMatrix. Batch D: Fw.Console, Fw.Store.Layout and
Reduce, Fw.Plan.Core, Graph and Trailer, Fw.Board. Not returned by an agent, still pending: `Fw.Gate.reachRows`, `Fw.Store.keyPairs_inj`.
Patterns: a bound variable that shadows a field accessor (f), free variables the Lean takes from a record (o.now,
o.agents), English that says 'at or above' where the Lean is strict, list entries written without their subject and
detail. Fixes go to a lean-prover task (math-r7b-fix).

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Obs.Health.msPerMin` | agree | 421340980 | 2684429733604708084 |  |
| `Fw.Obs.Health.Params` | disagree | 3931117990 | 17830128812282798617 | English 'an alert needs a value at or above them' is wrong for ctxResumeMax, ctxWarn, agentCap, worktreesMax: they alert only strictly above (ctxMax < ctx, cap < nLive, wtMax < wt). Fix: split 'at or above' (idle, stall, hang, err, simMax) from 'above' (ctxMax, ctxWarn, cap, wtMax); rename tuple entry disk to \mathit{diskMin} as Looser/sysAlerts use. |
| `Fw.Obs.Health.Inflight` | agree | 3931117990 | 12718568455046797851 |  |
| `Fw.Obs.Health.Kind` | agree | 3931117990 | 7671431677820155116 |  |
| `Fw.Obs.Health.Agent` | agree | 3931117990 | 2530950468919850704 |  |
| `Fw.Obs.Health.Lead` | agree | 3931117990 | 3899393453207615495 |  |
| `Fw.Obs.Health.Mem` | agree | 3931117990 | 14600495764922322902 |  |
| `Fw.Obs.Health.SimLock` | agree | 3931117990 | 13532372016163726120 |  |
| `Fw.Obs.Health.Container` | agree | 3931117990 | 5320996421811216559 |  |
| `Fw.Obs.Health.CiRun` | agree | 3931117990 | 6508280033193833790 |  |
| `Fw.Obs.Health.System` | agree | 3931117990 | 8857495039097456668 |  |
| `Fw.Obs.Health.Obs` | agree | 3931117990 | 17295960870593403591 |  |
| `Fw.Obs.Health.State` | agree | 3931117990 | 9669559645006763445 |  |
| `Fw.Obs.Health.ended` | agree | 3110582116051970131 | 13993818496509776555 |  |
| `Fw.Obs.Health.live` | agree | 3110582116051970131 | 10295335389412038138 |  |
| `Fw.Obs.Health.idleNewer` | agree | 8551619227348951392 | 4640811358830845741 |  |
| `Fw.Obs.Health.parkedB` | agree | 8551619227348951392 | 7522665333697556152 |  |
| `Fw.Obs.Health.waitTool` | agree | 1526413716 | 3604139706919387411 |  |
| `Fw.Obs.Health.hasLiveChild` | agree | 8316707178756615866 | 14392425969250817176 |  |
| `Fw.Obs.Health.hungB` | disagree | 8316707178756615866 | 4365707009079488192 | The bound f shadows the field accessor f(a): '\exists f.\ f(a) = f' is ill-formed. Fix: \exists \varphi.\ f(a) = \varphi \wedge \neg(\operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p,t,A,a)) \wedge \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(\varphi). |
| `Fw.Obs.Health.stallB` | agree | 8316707178756615866 | 6956289022177918473 |  |
| `Fw.Obs.Health.Stall` | disagree | 13713126026905233672 | 9066345243305732318 | Same shadowing: '\forall f.\ f(a) = f \Rightarrow ...' binds f over the accessor f(a). Fix: \forall \varphi.\ f(a) = \varphi \Rightarrow \neg(\operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p,t,A,a)) \wedge \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(\varphi). |
| `Fw.Obs.Health.stallB_iff` | agree | 11832454729948233668 | 15079691544746084728 |  |
| `Fw.Obs.Health.state` | agree | 12000183375573839353 | 9461907585866080809 |  |
| `Fw.Obs.Health.state_done` | agree | 517028830649820532 | 9698610606211261175 |  |
| `Fw.Obs.Health.state_parked` | agree | 9399921766698374509 | 16131560956269103721 |  |
| `Fw.Obs.Health.state_stalled` | agree | 9473948987809948387 | 5925339557931948512 |  |
| `Fw.Obs.Health.state_idle` | agree | 18156093393982242699 | 17521238547687540091 |  |
| `Fw.Obs.Health.state_active` | agree | 11250322312559684528 | 9215518640639651386 |  |
| `Fw.Obs.Health.state_cases` | agree | 11746485321625538100 | 17408583295417334668 |  |
| `Fw.Obs.Health.stalled_facts` | agree | 6357687736903951458 | 11294754436099573796 |  |
| `Fw.Obs.Health.Code` | agree | 3931117990 | 9462086494725823903 |  |
| `Fw.Obs.Health.Code.all` | agree | 13868259281224494680 | 9936956092217581843 |  |
| `Fw.Obs.Health.Code.name` | agree | 11631494382631388703 | 673598348780169085 |  |
| `Fw.Obs.Health.Code.rank` | agree | 18325369036093252867 | 10518242707059999681 |  |
| `Fw.Obs.Health.Code.isAgent` | agree | 2602050631673214916 | 14082125650049244551 |  |
| `Fw.Obs.Health.Code.rank_inj` | agree | 7661049378025962274 | 10658484976796441068 |  |
| `Fw.Obs.Health.Code.names_sorted` | agree | 13479867492743485651 | 7094568006162713856 |  |
| `Fw.Obs.Health.Alert` | agree | 3931117990 | 6926997613123000894 |  |
| `Fw.Obs.Health.Alert.Lt` | agree | 2318244964088570881 | 14333645836301886658 |  |
| `Fw.Obs.Health.Alert.lt_irrefl` | agree | 17214577392989489105 | 7442225201608369200 |  |
| `Fw.Obs.Health.Alert.lt_trans` | agree | 9809125471555557788 | 4702423519244826258 |  |
| `Fw.Obs.Health.str_trich` | agree | 2341504549 | 13502507671843997241 |  |
| `Fw.Obs.Health.Alert.lt_trich` | agree | 4903838357458409855 | 8090497465254313091 |  |
| `Fw.Obs.Health.ins` | agree | 843059999180670076 | 8816338872740756689 |  |
| `Fw.Obs.Health.sortU` | agree | 5906421067637429853 | 867576292352490826 |  |
| `Fw.Obs.Health.mem_ins` | agree | 10298017713889458159 | 17643666095272352657 |  |
| `Fw.Obs.Health.sorted_ins` | agree | 3418577732444862670 | 16545681272094160464 |  |
| `Fw.Obs.Health.mem_sortU` | agree | 9651259906846744222 | 9781167020989237374 |  |
| `Fw.Obs.Health.sorted_sortU` | agree | 1643086969851275381 | 3372194369719061795 |  |
| `Fw.Obs.Health.eq_of_sorted` | agree | 3050274392731062935 | 8375397716919783049 |  |
| `Fw.Obs.Health.when` | agree | 4727253004200389241 | 3662261055572717720 |  |
| `Fw.Obs.Health.mem_when` | agree | 10042522640973013759 | 8608347469694431344 |  |
| `Fw.Obs.Health.mins` | agree | 2546708756 | 13395004212294379903 |  |
| `Fw.Obs.Health.agentAlerts` | disagree | 2551001111656038662 | 742074980515632469 | Details are '·' (sortU orders and dedups by them) and ctx = ⊥ ↦ 0 is not in the math. Fix: ctx = ctx(a) or 0; details: ctxHigh/ctxWarn '{ctx} context tokens', errStreak '{errTail} failed tool calls in a row', stalled 'no event for mins(t∸last) min', toolHang '{tool(f)} running for mins(t∸since(f)) min'. |
| `Fw.Obs.Health.agentAlerts_quiet` | agree | 8965651914371646745 | 4887904349731640802 |  |
| `Fw.Obs.Health.agentAlerts_subject` | agree | 1049181678243290863 | 1098985629841540026 |  |
| `Fw.Obs.Health.wait_not_hang` | disagree | 8651281492013428234 | 6474243648165402745 | Bound f shadows the accessor: '\forall p,t,A,a,f:\ f(a) = f \wedge \operatorname{waitTool}(\mathit{tool}(f))'. Fix: quantify \varphi: \forall p,t,A,a,\varphi:\ f(a) = \varphi \wedge \operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p,t,A,a) \Rightarrow ... (rest unchanged). |
| `Fw.Obs.Health.names` | agree | 2897656940039933049 | 4278654720360327244 |  |
| `Fw.Obs.Health.orphanB` | agree | 18394221653272560529 | 3563457232577479256 |  |
| `Fw.Obs.Health.ciFailing` | agree | 2257108148251214360 | 3248022000525743499 |  |
| `Fw.Obs.Health.ciLatest` | agree | 10857079173471549776 | 1980321117661384519 |  |
| `Fw.Obs.Health.dockerOrphanB` | agree | 4490910577699250597 | 5722006365842322406 |  |
| `Fw.Obs.Health.nLive` | agree | 8811231367553955062 | 13201091310844451852 |  |
| `Fw.Obs.Health.nKind` | agree | 2682460244884983734 | 7281617881823481581 |  |
| `Fw.Obs.Health.nHelpers` | agree | 8811231367553955062 | 10922916051641963846 |  |
| `Fw.Obs.Health.permB` | agree | 17921415961902365917 | 2559255911131399445 |  |
| `Fw.Obs.Health.sysAlerts` | disagree | 16308028834015433257 | 4415827478798817800 | Entries give only the code: subject and detail are left out, and diskMin, mem, ci, docker are not the Params/Σ names (disk, m, R, C). Fix: write each entry as (code, subject, detail), e.g. (overCap, team, '{n} live agents: …'), (diskLow, disk, '{disk} GB free'), (ci.failed, wf@br, 'latest run {concl}'), (docker.orphan, name(c), 'container {id}'). |
| `Fw.Obs.Health.raw` | agree | 16308028834015433257 | 15341379247224383097 |  |
| `Fw.Obs.Health.Counts` | agree | 3931117990 | 14666837810804433010 |  |
| `Fw.Obs.Health.Row` | agree | 3931117990 | 14663297571930065741 |  |
| `Fw.Obs.Health.Report` | agree | 3931117990 | 5027274408994435046 |  |
| `Fw.Obs.Health.countState` | agree | 11139865005182954705 | 12487850935271664477 |  |
| `Fw.Obs.Health.health` | agree | 9605697993393128981 | 6661678729058238768 |  |
| `Fw.Obs.Health.mem_alerts` | agree | 16664079470986842179 | 15232610699692105777 |  |
| `Fw.Obs.Health.alerts_sorted` | agree | 18142087699627099855 | 1376499503771854075 |  |
| `Fw.Obs.Health.sysAlerts_notAgent` | agree | 2462106080085728303 | 17373712011679423790 |  |
| `Fw.Obs.Health.agent_alert_live` | disagree | 2017912558867600265 | 1063584130125538729 | t and A are free in the body; the Lean uses o.now and o.agents. Fix: add 'where o = (t, A, \ell, \Sigma)' (or write \mathit{now}(o), A(o)). |
| `Fw.Obs.Health.mem_sys_of_notAgent` | agree | 7710266335951500735 | 830446132325176468 |  |
| `Fw.Obs.Health.lockOrphan_iff` | disagree | 12523414071249067102 | 10464465960846158207 | t, A and L are free; the Lean uses o.now, o.agents, o.system.simLock. Fix: add 'where o = (t, A, \ell, \Sigma) and L is \Sigma's simulator lock'. |
| `Fw.Obs.Health.permissionWait_iff` | agree | 10845916847905053660 | 16264938098809884539 |  |
| `Fw.Obs.Health.Looser` | agree | 7336182166998326322 | 16818190893867440362 |  |
| `Fw.Obs.Health.ended_congr` | agree | 15762612536180789636 | 5922926811319297441 |  |
| `Fw.Obs.Health.hasLiveChild_congr` | agree | 16600561500739617251 | 3482160036916270357 |  |
| `Fw.Obs.Health.hungB_mono` | agree | 15308287176058481166 | 3814597111591542474 |  |
| `Fw.Obs.Health.stalled_mono` | agree | 3629611401974780150 | 9951933780815473475 |  |
| `Fw.Obs.Health.agentAlerts_mono` | agree | 2942740798656636702 | 3614779771315532367 |  |
| `Fw.Obs.Health.sysAlerts_mono` | agree | 16050250667288219599 | 7441194937117156192 |  |
| `Fw.Obs.Health.health_mono` | agree | 8641465989479328335 | 4606515234495517265 |  |
| `Fw.Obs.Health.agent_perm` | agree | 17944837039780870334 | 7321460069574324351 |  |
| `Fw.Obs.Health.sysAlerts_perm` | agree | 3755644903532910175 | 2245304166891056950 |  |
| `Fw.Obs.Health.health_perm` | agree | 3549524114073146000 | 6281113955932983520 |  |
| `Fw.Obs.Health.counts_total` | disagree | 6723951722095234019 | 9371765056050235729 | n_active … n_done and A are not tied to p, o (∀ p, o binds nothing in the body). Fix: \forall p, o:\ \sum_{s \in \mathcal S} \operatorname{health}(p, o).n_s = \|A\| where o = (t, A, \ell, \Sigma). |
| `Fw.Obs.Health.a0` | agree | 14464811820722794384 | 11293167204618870779 |  |
| `Fw.Obs.Health.tm0` | agree | 14464811820722794384 | 2729007161167824217 |  |
| `Fw.Ops.Obs.obsKey` | agree | 3653987902 | 4337466578244775868 |  |
| `Fw.Ops.Obs.obsKey_tool_ts` | agree | 6301592682750844634 | 15289603661199567305 |  |
| `Fw.Ops.Obs.obsKey_no_tool` | agree | 7652136766854769074 | 16078037283116786509 |  |
| `Fw.Ops.Obs.Line` | agree | 3931117990 | 4854717308230908720 |  |
| `Fw.Ops.Obs.isCall` | agree | 3078031980841224024 | 17570420326520268530 |  |
| `Fw.Ops.Obs.group` | agree | 2134468339321588760 | 9977559760746418387 |  |
| `Fw.Ops.Obs.Row` | agree | 3931117990 | 13971280663285094711 |  |
| `Fw.Ops.Obs.uniqAux` | agree | 3553002594 | 14534794398204965042 |  |
| `Fw.Ops.Obs.uniq` | agree | 599762674 | 7069665735514304692 |  |
| `Fw.Ops.Obs.groups` | agree | 11129774289423288396 | 8604050277104438247 |  |
| `Fw.Ops.Obs.rowFor` | agree | 12395764007199298622 | 17803151080127531534 |  |
| `Fw.Ops.Obs.summarize` | agree | 15844100457499090696 | 10413161530664102787 |  |
| `Fw.Ops.Obs.mem_uniqAux` | agree | 11363604384938123857 | 13330919215756326059 |  |
| `Fw.Ops.Obs.uniqAux_nodup` | agree | 7978664337245222934 | 17232422872048814015 |  |
| `Fw.Ops.Obs.mem_groups` | agree | 6903488826236449973 | 9114000116056935740 |  |
| `Fw.Ops.Obs.groups_nodup` | agree | 3816998892721794296 | 4130233899018765179 |  |
| `Fw.Ops.Obs.summarize_row` | agree | 10164920551069232570 | 11747913115183631673 |  |
| `Fw.Ops.Obs.summarize_skip` | agree | 10563178828551938894 | 7502664839488168196 |  |
| `Fw.Ops.SpawnGuard.wantKind` | agree | 7931090831631464474 | 5021242912661007680 |  |
| `Fw.Ops.SpawnGuard.kindMismatch_fields` | agree | 15996508227583316907 | 15599175555519851847 |  |
| `Fw.Console.Alert.Kind` | agree | 3931117990 | 12750855476821181945 |  |
| `Fw.Console.Alert.Kind.name` | agree | 2486821045216230978 | 17312761310039142546 |  |
| `Fw.Console.Alert.Ev` | agree | 3931117990 | 7678921409608593097 |  |
| `Fw.Console.Alert.Flight` | agree | 3931117990 | 5605429748641815654 |  |
| `Fw.Console.Alert.kindOf` | agree | 8388989222191175423 | 15677695989077480437 |  |
| `Fw.Console.Alert.closer` | agree | 1526413716 | 18054359047919842193 |  |
| `Fw.Console.Alert.attrib` | disagree | 14553851645859233164 | 11711113460957627171 | F_a is written as a set {f ∈ fs : …}, but it is the filtered list whose head f_1 is returned; rows 1 and 2 overlap (Lean takes row 1). Fix: F_a = [f \in \mathit{fs} \mid f.\mathit{agent} \ne \bot], and make row 2 'else if F_a = f_1 :: R \wedge \forall g \in R: g.agent = f_1.agent'. |
| `Fw.Console.Alert.attrib_sound` | agree | 4425322041400653604 | 3005981708105809953 |  |
| `Fw.Console.Alert.attrib_lead_only` | agree | 1990106671272665849 | 15712992840901515049 |  |
| `Fw.Console.Alert.slugChar` | disagree | 510109451 | 10532823866423188450 | 'alphanumeric' reads as Unicode, but Lean's Char.isAlphanum is ASCII only (é ↦ _). Fix: c if c ∈ {A–Z, a–z, 0–9, _} (ASCII letters and digits, or _); _ otherwise. |
| `Fw.Console.Alert.slug` | agree | 598018293 | 11464705277534043629 |  |
| `Fw.Console.Alert.stepId` | agree | 3765493733 | 3170369961357747379 |  |
| `Fw.Console.Alert.cut` | disagree | 652675199 | 2660354629896210791 | The math covers only lists that contain a '-'. Lean gives cut(ℓ) = (ℓ, []) when ℓ has no '-', and parse relies on that. Fix: add '; \operatorname{cut}(\ell) = (\ell, [\,]) for \ell without -'. |
| `Fw.Console.Alert.decode` | agree | 948478879 | 11290201451673670590 |  |
| `Fw.Console.Alert.parse` | agree | 3940711077 | 9655198127963684661 |  |
| `Fw.Console.Alert.digit_val` | agree | 3534714561 | 3892530543582169718 |  |
| `Fw.Console.Alert.decode_toDigits` | agree | 10120710754980939710 | 13819979436178730187 |  |
| `Fw.Console.Alert.cut_append` | agree | 17564950040413877838 | 5260831536730030749 |  |
| `Fw.Console.Alert.slug_no_dash` | agree | 5151155941096005794 | 6636210917223666863 |  |
| `Fw.Console.Alert.parse_stepId` | agree | 14560678228820670457 | 1279903961604880473 |  |
| `Fw.Console.Alert.Alert` | agree | 3931117990 | 13845791553634872086 |  |
| `Fw.Console.Alert.Out` | agree | 3931117990 | 7053005270264233133 |  |
| `Fw.Console.Alert.title` | disagree | 14957312256939327105 | 11406477986262456159 | '…' hides the text. Also w is clip_60(who), and the tool is clip_40(tool, or 'a tool' when ⊥). Fix: give the full tails ': answer its prompt in the Claude Code terminal, then press Done', ': answer it in the Claude Code terminal, then press Done', '; the lead restarts it from its handoff', with the clips. |
| `Fw.Console.Alert.subject` | disagree | 193007194097963620 | 8704187737668620372 | Rows 1 and 2 overlap when e.agent = ⊥, e.event = StopFailure and attrib(fs) = f; Lean takes row 1. Fix row 2: e.agent = \bot \wedge e.event \ne \texttt{StopFailure} \wedge \operatorname{attrib}(fs) = f. |
| `Fw.Console.Alert.owner` | agree | 1380837422 | 9800861203817218551 |  |
| `Fw.Console.Alert.closes` | agree | 15666496827720297228 | 10272022307691455322 |  |
| `Fw.Console.Alert.act` | disagree | 4609870720942665069 | 10779297099982584292 | post is prose and leaves the alert's fields out. Fix: post = (stepId(a,e.ts), alert:·stepId(a,e.ts), title(k, ty or main, tool), k, slug(a)) if kindOf(e)=k, subject(e,fs)=(a,ty,tool) and ¬∃ id∈opn: owner(id)=slug(a); else ⊥. |
| `Fw.Console.Alert.closeKey` | agree | 3438944622 | 7849040274584700098 |  |
| `Fw.Console.Alert.post_event` | agree | 12618075357038714362 | 4654150820684021482 |  |
| `Fw.Console.Alert.lead_notification_silent` | agree | 14113381613894903010 | 4703544854625068656 |  |
| `Fw.Console.Alert.post_names_agent` | agree | 12738637631642697067 | 12088863496750844939 |  |
| `Fw.Console.Alert.no_second_alert` | agree | 16712637730378290027 | 4768946208385511697 |  |
| `Fw.Console.Alert.close_sound` | agree | 9739798695904931250 | 17985250516417338222 |  |
| `Fw.Console.Alert.close_complete` | agree | 3787210563835156692 | 846285691764586733 |  |
| `Fw.Console.Alert.closer_no_post` | agree | 11481025933021513704 | 2107515480625044346 |  |
| `Fw.Console.Self.Source` | agree | 3931117990 | 15760211035243921998 |  |
| `Fw.Console.Self.sources` | agree | 2745721970054525506 | 4961910825275762841 |  |
| `Fw.Console.Self.Source.name` | agree | 14847578579620420554 | 9354929813512610493 |  |
| `Fw.Console.Self.Source.ofName` | agree | 8840110856974872363 | 2469344387065941069 |  |
| `Fw.Console.Self.actor` | agree | 15771604483641864092 | 2367916864796493939 |  |
| `Fw.Console.Self.evType` | agree | 15719876717805104422 | 3224680630630892539 |  |
| `Fw.Console.Self.may_self` | agree | 6757061179305994913 | 3685124784384326897 |  |
| `Fw.Console.Self.actor_machine` | agree | 14139344383494998978 | 1144148981756492777 |  |
| `Fw.Console.Self.ofName_name` | agree | 18119002264327905753 | 5540372072546130793 |  |
| `Fw.Console.Land.Need` | agree | 3931117990 | 13105186499477857785 |  |
| `Fw.Console.Land.Need.name` | agree | 14096521271075862393 | 1087911493003067870 |  |
| `Fw.Console.Land.landNeeds` | agree | 10760173304480901341 | 14576535240110499274 |  |
| `Fw.Console.Land.landNeeds_nil_iff` | agree | 5495352862005613372 | 13695802214520294328 |  |
| `Fw.Console.Land.landRefusal` | agree | 13314429704869243837 | 17797040739397065740 |  |
| `Fw.Console.Land.landRefusal_none_iff` | agree | 18408170094573375484 | 1728653659573288795 |  |
| `Fw.Gate.Requested` | agree | 3931117990 | 1473882667948216347 |  |
| `Fw.Gate.Viewport` | agree | 3931117990 | 15431650611868908476 |  |
| `Fw.Gate.Observed` | agree | 3931117990 | 13183408047381553109 |  |
| `Fw.Gate.leOpt` | agree | 1856241084 | 12601333406832779522 |  |
| `Fw.Gate.sameSide` | disagree | 2778088320 | 14005359436731231733 | a is in Q_⊥ (leOpt), but the math writes (a ≤ n), which is undefined for a = ⊥ (Lean: false, so a missing width matches only a b above every edge). Fix: \forall n \in E,\ \operatorname{le}(a, n) = (b \le n), with a \in \mathbb Q_\bot. |
| `Fw.Gate.envChecks` | disagree | 244413007985771538 | 2982815823549876036 | ⊤/⊥ stand for true/false, but in Observed (B_⊥) ⊥ means 'not reported', so (⊤, ⊥) reads as 'hoverNone unreported'. Lean needs some false. Fix: write (\mathrm{true}, \mathrm{false}) / (\mathrm{false}, \mathrm{true}) and widthExact = \mathrm{true} etc.; keep ⊥ for 'unreported' only. |
| `Fw.Gate.envDeviations` | agree | 7252744124836149915 | 8740657985086483513 |  |
| `Fw.Gate.envDeviations_eq_nil_iff` | agree | 12487437570037211184 | 4361328362173594746 |  |
| `Fw.Gate.TVal` | agree | 3931117990 | 5682223058096786720 |  |
| `Fw.Gate.TMap` | agree | 3931117990 | 14659207703835982355 |  |
| `Fw.Gate.TruthRaw` | agree | 3931117990 | 14909657077423739769 |  |
| `Fw.Gate.TCls` | agree | 3931117990 | 10894850739552860761 |  |
| `Fw.Gate.TItem` | agree | 3931117990 | 9068211680775604300 |  |
| `Fw.Gate.eqS` | agree | 18050702602631618067 | 7948430999986794331 |  |
| `Fw.Gate.truthKey` | agree | 8520712792063237529 | 5081954695229824023 |  |
| `Fw.Gate.neutralKey` | agree | 3878491080605243392 | 17609438127251774384 |  |
| `Fw.Gate.truthItems` | agree | 1926222517230186316 | 16770827036690865009 |  |
| `Fw.Gate.truthItems_lean_na` | agree | 10223862993371187750 | 8110548910478320785 |  |
| `Fw.Gate.truthItems_ar_iff` | agree | 1464943672418635512 | 2431613007079145942 |  |
| `Fw.Gate.truthRows` | agree | 17163195668237893557 | 7108097852117485924 |  |
| `Fw.Gate.rowVerdicts` | agree | 12692137915205943766 | 14524603050573385897 |  |
| `Fw.Gate.Arm` | agree | 3931117990 | 7868266737363151685 |  |
| `Fw.Gate.StateIn` | agree | 3931117990 | 15979733374398220209 |  |
| `Fw.Gate.Ctx` | agree | 3931117990 | 7406815388189628232 |  |
| `Fw.Gate.hoverOf` | agree | 615380642750175571 | 8482144984559367388 |  |
| `Fw.Gate.pointerOf` | agree | 9298557440434389492 | 10441361007647951172 |  |
| `Fw.Gate.pairIn` | agree | 3020978727967985963 | 8897086048255468784 |  |
| `Fw.Gate.reqReason` | agree | 550936066468061080 | 7867523235878526323 |  |
| `Fw.Gate.stateReach` | agree | 4771687800179082548 | 6299302027384187638 |  |
| `Fw.Gate.pxRat` | agree | 11341079365120662912 | 7029384929322351702 |  |
| `Fw.Gate.requestOf` | agree | 10160742110842269259 | 13797509879322094804 |  |
| `Fw.Gate.matrix_reqReason` | agree | 12248709119727640182 | 10725015831682826753 |  |
| `Fw.Gate.StateOut` | agree | 3931117990 | 7401683089990279722 |  |
| `Fw.Gate.isCompared` | agree | 5355151840449015310 | 11283833715460953728 |  |
| `Fw.Gate.failsS` | agree | 8910557538446748158 | 10147329704696717860 |  |
| `Fw.Gate.StateOut.itemFails` | agree | 6897494532492758697 | 7262107161709646619 |  |
| `Fw.Gate.stateParts` | disagree | 9570663333227417342 | 11929816167503569694 | Π_P and A are never defined, and the Lean uses props [] when P has no entry. Fix: \operatorname{partItems}(C.A, P, o[P.\mathrm{id}], r[P.\mathrm{id}], \Pi_P) with \Pi_P = C.\mathrm{props}[P.\mathrm{id}] if present, else [\,]; o[k] = first entry with key k, else ⊥. |
| `Fw.Gate.evalState` | disagree | 7578581819863067945 | 2911068300559347194 | dev(q, o) leaves out viewport, observed and C.E (dev takes 4 arguments). o, r, e, e^N are not tied to s, and the compared field is missing. Fix: \operatorname{dev}(s.q, v_O, o_O, C.E); T = truthItems(T_O, T_R, s.E, s.E_N, ach); add compared = [(p, \|[it ∈ I \| compared(it)]\|) \| (p, I) ∈ Π]. |
| `Fw.Gate.evalState_part_row` | agree | 4579026130376067883 | 13593684273057147147 |  |
| `Fw.Gate.evalState_verdict` | agree | 17155183123358586328 | 16917279961246283905 |  |
| `Fw.Gate.evalState_fail_iff` | agree | 13556817935795008125 | 6065973086498805348 |  |
| `Fw.Gate.evalState_pass_iff` | agree | 9928472884915646864 | 15119396863783324316 |  |
| `Fw.Gate.evalState_part_fail` | agree | 1722072831815375335 | 3569929446862836455 |  |
| `Fw.Gate.evalState_unreachable` | agree | 9275302148289388884 | 8307177975435560755 |  |
| `Fw.Gate.evalState_unreachable_iff` | agree | 4626437669693665085 | 8171918499999065205 |  |
| `Fw.Gate.stale` | disagree | 14469740175532349809 | 7480096109967300505 | The Lean counts list entries (countP), but the math uses set-builder \|{it \| …}\|. Fix: with I = \bigoplus_{P \in C.\mathrm{parts}} \operatorname{partItems}(\dots), \operatorname{stale} = (\|[\,it \in I \mid \operatorname{compared}(it)\,]\|,\ \|[\,it \in I \mid it.\mathrm{cls} \ne \mathrm{info} \wedge it.\mathrm{status} \in \{\mathrm{differ},\mathrm{missing}\}\,]\|). |
| `Fw.Gate.blockCell` | agree | 14725887784290190694 | 11055706553699045191 |  |
| `Fw.Gate.tally_perm` | agree | 11974214154685267532 | 7304582746163801437 |  |
| `Fw.Gate.blockCell_perm` | agree | 5923522171925480508 | 11313458858744540044 |  |
| `Fw.Gate.SkipPrefix` | agree | 3931117990 | 9282359884344750495 |  |
| `Fw.Gate.SkipSet` | agree | 3931117990 | 11721704386042517962 |  |
| `Fw.Gate.BoxRel` | agree | 3931117990 | 3524975109665664829 |  |
| `Fw.Gate.RoleSpec` | agree | 3931117990 | 3577938797584050674 |  |
| `Fw.Gate.PartSpec` | agree | 3931117990 | 7245709671930786930 |  |
| `Fw.Gate.Anchors` | agree | 3931117990 | 1586144581947660299 |  |
| `Fw.Gate.Rect` | agree | 3931117990 | 2326261568509990645 |  |
| `Fw.Gate.Item` | agree | 3931117990 | 13085253344139000005 |  |
| `Fw.Gate.RoleRaw` | agree | 3931117990 | 507791923787361620 |  |
| `Fw.Gate.PartRaw` | agree | 3931117990 | 4780230022613524031 |  |
| `Fw.Gate.RoleProps` | agree | 3931117990 | 534599348474102921 |  |
| `Fw.Gate.PartProps` | agree | 3931117990 | 16716705349484641539 |  |
| `Fw.Gate.Cls` | agree | 3931117990 | 6771866026142492678 |  |
| `Fw.Gate.PItem` | agree | 3931117990 | 14876157053925839959 |  |
| `Fw.Gate.prefixes` | agree | 14944146099145959729 | 15677945334384352840 |  |
| `Fw.Gate.isSkipped` | agree | 3410401882 | 5509391964383449917 |  |
| `Fw.Gate.skipNames` | disagree | 11555861478417778681 | 4405039813751462308 | props_A(s) is undefined, and the Lean takes the FIRST skip set with that name (find?), or [] if there is none. Fix: \operatorname{props}_A(s) = S.P for the first S \in A.\mathcal S with S.\mathrm{name} = s, else [\,]. |
| `Fw.Gate.comparedProps` | agree | 17704309939270020256 | 16918193004750548184 |  |
| `Fw.Gate.infoProps` | agree | 12824214084430371768 | 2436655721933777256 |  |
| `Fw.Gate.dimOf` | agree | 6425693087859443616 | 7582249032504110591 |  |
| `Fw.Gate.relRect` | agree | 10224925861320987544 | 2196319248685883348 |  |
| `Fw.Gate.boxDim` | agree | 12501410697805431399 | 5784067740437044092 |  |
| `Fw.Gate.itemAt` | disagree | 2446168784246779235 | 14573504070584253824 | Arguments are left out: the Lean itemAt takes ρ (RoleSpec), C, I, q_o, q_r, i, x, y, but the math has itemAt(i,x,y) with dims, C, I, q_o, q_r free, and x_p is undefined. Fix: \operatorname{itemAt}_{\rho,C,I,q_o,q_r}(i,x,y), d \in \rho.\mathrm{dims}, x_p = x.\sigma[p] (first entry, ⊥ if absent); each item is (cls, ρ.role, i, key, status, δ). |
| `Fw.Gate.pairs` | agree | 7901436507639787696 | 7934767831328491958 |  |
| `Fw.Gate.refRect` | agree | 10782760444359958978 | 2726794719980222099 |  |
| `Fw.Gate.roleItems` | disagree | 12342393303111460954 | 18151152246825459886 | roleItems(o, r) leaves out A, ρ, props, q_o, q_r (the Lean has 7 arguments, as in mem_roleItems), and the pairs(itemAt, …) arguments are not given. Fix: \operatorname{roleItems}(A,\rho,\mathit{props},q_o,q_r,o,r) = \operatorname{count}(o.n,r.n) :: \operatorname{pairs}(\operatorname{itemAt}_{\rho,C,I,q_o,q_r},0,o.\mathrm{items},r.\mathrm{items}), with C = compared(A,ρ,props.restated or []) and I = infoProps(A,props.originOnly or []). |
| `Fw.Gate.partItems` | disagree | 15031121831213897308 | 7902681351308202546 | The props argument Π is left out (Lean partItems has 5 arguments; stateParts and the theorems use 5), and so are the roleItems arguments. Fix: \operatorname{partItems}(A,P,o,r,\Pi) = \bigoplus_{\rho \in P.\mathrm{roles}} \operatorname{roleItems}(A,\rho,\Pi[\rho],\operatorname{ref}(o,\rho.b),\operatorname{ref}(r,\rho.b),o[\rho],r[\rho]), with o[ρ] = ⊥ if o = ⊥. |
| `Fw.Gate.partVerdict` | disagree | 7893687298892105603 | 432204438251231011 | The props argument is left out: partVerdict(A,P,o,r) for a 5-argument Lean def. Fix: \operatorname{partVerdict}(A,P,o,r,\Pi) = \operatorname{cell}([\,it.\mathrm{status} \mid it \in \operatorname{partItems}(A,P,o,r,\Pi)\,]). |
| `Fw.Gate.mem_pairs` | agree | 12834144817104164845 | 2187977319040040940 |  |
| `Fw.Gate.mem_roleItems` | agree | 4839669944729371454 | 5851116329319593746 |  |
| `Fw.Gate.partItems_na_iff` | agree | 7939619990882610819 | 15066744007188003271 |  |
| `Fw.Gate.partVerdict_pass_iff` | agree | 1814917220899672640 | 6931456551155205748 |  |
| `Fw.Gate.partVerdict_fail_iff` | agree | 690907169096060410 | 18059250344464660742 |  |
| `Fw.Gate.partItems_style_not_skipped` | agree | 7061655638260559603 | 2662129106613436543 |  |
| `Fw.Gate.AgreeOff` | agree | 15136324417804351424 | 6647627185599724125 |  |
| `Fw.Gate.mapRole` | disagree | 2717344167870345556 | 15725878361870937511 | With repeated keys, the Lean edits EVERY entry with key ρ, but P[ρ] means only the first one. Fix: \operatorname{mapRole}_{\rho,g}(P) = [\,(k, k = \rho\ ?\ R \text{ with items } [g(x) \mid x \in R.\mathrm{items}] : R) \mid (k, R) \in P\,]. |
| `Fw.Gate.setStyle` | disagree | 11148855631069627049 | 2173281964887567194 | The math gives only the style lookup. It does not say the box is kept (Lean: rect unchanged), or that v = ⊥ removes p. Fix: add \operatorname{setStyle}_{p,v}(x).\mathrm{rect} = x.\mathrm{rect}, with v \in \mathrm{String}_\bot (v = ⊥ removes p). |
| `Fw.Gate.lookup_filter_ne` | agree | 2653031159 | 9795650123968234624 |  |
| `Fw.Gate.setStyle_agree` | agree | 10636811320467395585 | 12432052487458971272 |  |
| `Fw.Gate.lookup_mapRole` | agree | 17661359139842171361 | 3810819136672297315 |  |
| `Fw.Gate.refRect_mapRole` | agree | 8215581878451644409 | 12677926901121710741 |  |
| `Fw.Gate.pairs_congr` | agree | 3734124891185895049 | 17889726105126736625 |  |
| `Fw.Gate.itemAt_congr` | disagree | 17321295562065302563 | 15609753782414636046 | The ∀ q ∈ C reaches to the end of the formula, so it parses as rect ∧ rect ∧ ∀q,(… ⟹ st = st), not as an implication. itemAt also drops rs, C, I, refO, refR. Fix: (x.rect = x'.rect ∧ y.rect = y'.rect ∧ (∀ q ∈ C, x[q] = x'[q] ∧ y[q] = y'[q])) ⟹ st(itemAt_{rs,C,I,refO,refR}(i,x,y)) = st(itemAt_{…}(i,x',y')). |
| `Fw.Gate.flatMap_congr'` | agree | 3397308229 | 10480716625529895904 |  |
| `Fw.Gate.partItems_skip_invariant` | agree | 7845505858371810873 | 4774204275321571750 |  |
| `Fw.Gate.partVerdict_setStyle` | disagree | 13237576824762848685 | 7475691345853754242 | set_{ρ,p,v} is undefined. Fix: write \operatorname{mapRole}_{\rho,\operatorname{setStyle}_{p,v}}(o) and \operatorname{mapRole}_{\rho,\operatorname{setStyle}_{p,w}}(r) (mapped through the option), with v, w \in \mathrm{String}_\bot. |
| `Fw.Gate.partVerdict_perm` | agree | 15925983126529518965 | 3441338652329361707 |  |
| `Fw.Gate.wellFormed` | disagree | 4951868388565863431 | 13494589527193046392 | Unparenthesised ∀ q ∈ A.skipPrefixes reaches over every later conjunct, so with no prefixes the formula is vacuously true (the Lean conjoins the clauses independently). The same holds for ∀ s. Fix: (\forall q \in A.\mathrm{skipPrefixes},\ q.\mathrm{why} \ne \varepsilon) \wedge (\forall s \in A.\mathrm{skipSets},\ s.\mathrm{why} \ne \varepsilon) \wedge (\forall P \dots). |
| `Fw.Gate.Port` | agree | 3931117990 | 4095405090016048188 |  |
| `Fw.Gate.Port.pairs` | agree | 4591014358300668353 | 9316291384177615472 |  |
| `Fw.Gate.Port.wholeWidth` | agree | 17502299275738696862 | 15281158443346543066 |  |
| `Fw.Gate.Port.wholeDevPx` | agree | 17502299275738696862 | 17531939730371855806 |  |
| `Fw.Gate.Port.reason` | agree | 4320423382348615091 | 7792907084057384279 |  |
| `Fw.Gate.envReason` | agree | 5809964378188786053 | 12769814182607520706 |  |
| `Fw.Gate.Port.reason_eq_none_iff` | agree | 10635070309596151184 | 7521386034823440058 |  |
| `Fw.Gate.glib_pairs` | agree | 6673752686825717134 | 10231408104846795045 |  |
| `Fw.Gate.matrix_cross_probes` | agree | 7760102475535048591 | 10035366240923909252 |  |
| `Fw.Gate.cross_pairs_not_webkit` | agree | 6181473765321622221 | 4953000975154555305 |  |
| `Fw.Gate.matrix_outside_pairs_iff` | agree | 256046749380064644 | 17625270125195191606 |  |
| `Fw.Gate.Px.whole_no_gap` | agree | 14290962951084356217 | 2751622892079321310 |  |
| `Fw.Gate.Px.whole_not_in_gap` | agree | 2013526036529369524 | 2400248667642902459 |  |
| `Fw.Gate.matrix_fractional_webkit` | agree | 414798270437915264 | 7931641201597603306 |  |
| `Fw.Gate.matrix_cross_webkit` | agree | 13648506481855641776 | 7276011510783331718 |  |
| `Fw.Gate.matrix_webkit_unreachable_iff` | agree | 14964435094079199432 | 569202654726065981 |  |
| `Fw.Gate.matrix_chromium_reachable` | agree | 10932284593653156466 | 10957702633113735902 |  |
| `Fw.Gate.Status` | agree | 3931117990 | 4210293858187125945 |  |
| `Fw.Gate.Reason` | agree | 3931117990 | 11943769298522100866 |  |
| `Fw.Gate.Verdict` | agree | 3931117990 | 2304992153793796399 |  |
| `Fw.Gate.Verdict.isUnreachable` | agree | 6138056473337363831 | 13095775624152133913 |  |
| `Fw.Gate.Verdict.isComparable` | agree | 6138056473337363831 | 8774990653289791954 |  |
| `Fw.Gate.cellVerdict` | agree | 1394682493048234744 | 7892167002850619368 |  |
| `Fw.Gate.toStatus` | agree | 5059799422104545611 | 6615530337483945494 |  |
| `Fw.Gate.unreachableReason` | agree | 18012004528603540082 | 14021930059078022296 |  |
| `Fw.Gate.rollup` | agree | 5043963585549239635 | 6950225568300694484 |  |
| `Fw.Gate.Tally` | agree | 3931117990 | 18003161138685395896 |  |
| `Fw.Gate.tally` | agree | 18270309733754706011 | 16624608267037903860 |  |
| `Fw.Gate.cellVerdict_isUnreachable` | agree | 11832494216900767961 | 12621858516814094158 |  |
| `Fw.Gate.cellVerdict_eq` | agree | 8790275986847385012 | 11664291875721219722 |  |
| `Fw.Gate.cellVerdict_nc_iff` | agree | 3182805872036614164 | 3830620690190362294 |  |
| `Fw.Gate.cellVerdict_fail_iff` | agree | 9727607750103856479 | 1603535654806542456 |  |
| `Fw.Gate.cellVerdict_pass_iff` | agree | 5374379005934446562 | 3762492401293314122 |  |
| `Fw.Gate.cellVerdict_congr` | agree | 10041232970434170495 | 4315685395856758954 |  |
| `Fw.Gate.cellVerdict_perm` | agree | 13049169359755857278 | 2738121254869258426 |  |
| `Fw.Gate.cellVerdict_filter_na` | agree | 9867758280812060989 | 4676200898630087349 |  |
| `Fw.Gate.toStatus_spec` | agree | 16669383812152622142 | 10636883809454121662 |  |
| `Fw.Gate.cellVerdict_map_fail_iff` | agree | 8961827208235058660 | 13569767566506715048 |  |
| `Fw.Gate.cellVerdict_map_nc_iff` | agree | 7472179704842944784 | 668476856541055209 |  |
| `Fw.Gate.cellVerdict_map_pass_iff` | agree | 6666352775334707660 | 2988293738356089352 |  |
| `Fw.Gate.rollup_cases` | agree | 1020716227073237398 | 17264147998933554305 |  |
| `Fw.Gate.rollup_of_reachable` | agree | 8049433071510238022 | 16106562268381117333 |  |
| `Fw.Gate.rollup_no_unreachable` | agree | 2081890999153432912 | 6747091973055272409 |  |
| `Fw.Gate.unreachableReason_mem` | agree | 1954756890947944884 | 10223550858554048452 |  |
| `Fw.Gate.rollup_unreachable_iff` | agree | 12273015271365247593 | 651654032220978428 |  |
| `Fw.Gate.rollup_unreachable_mem` | agree | 8694064390102938370 | 4935543335483014870 |  |
| `Fw.Gate.rollup_fail_iff` | agree | 10945785386269186525 | 14560304339028304205 |  |
| `Fw.Gate.rollup_pass_iff` | agree | 18203145332562377304 | 11131766655103482909 |  |
| `Fw.Gate.rollup_nc_iff` | agree | 3497425836435787860 | 191833377778892662 |  |
| `Fw.Gate.rollup_congr` | agree | 11792183400248195168 | 15514218951006092328 |  |
| `Fw.Gate.rollup_perm` | agree | 7985949666886137182 | 3686385940866104645 |  |
| `Fw.Gate.rollup_flatten` | agree | 10783965268657700895 | 7946098685412988961 |  |
| `Fw.Gate.rollup_filter_unreachable` | agree | 9278317385369035153 | 12454958165655223486 |  |
| `Fw.Gate.tally_fail_iff` | agree | 2312120836271641342 | 6849408525712481254 |  |
| `Fw.Gate.tally_pass_iff` | agree | 15707228070079972197 | 6662975506431253845 |  |
| `Fw.Gate.tally_unreachable_iff` | agree | 15916356232442176389 | 7160897739103595901 |  |
| `Fw.Gate.tally_nc_iff` | agree | 6230768842507129305 | 2219040322147569043 |  |
| `Fw.Gate.tally_counts` | agree | 5752991173960345155 | 18377092211356062451 |  |
| `Fw.Gate.tally_filter_unreachable` | agree | 930076442547192951 | 12680391956604654677 |  |
| `Fw.Gate.Dec` | agree | 3931117990 | 14805495041422065237 |  |
| `Fw.Gate.pow10` | agree | 2497287081 | 4880080132802334285 |  |
| `Fw.Gate.Dec.val` | agree | 600185000805927476 | 3092779001313371255 |  |
| `Fw.Gate.takeDigits` | agree | 652675199 | 2833695841137264352 |  |
| `Fw.Gate.digitsVal` | disagree | 948478879 | 6746040954519239925 | d_i is never defined. The Lean folds 10n + (code(c) ∸ code('0')) over any characters, with truncated subtraction. Fix: $$\operatorname{digitsVal}(c_1\dots c_k)=\sum_{i=1}^{k}(\operatorname{code}(c_i)\dot-\operatorname{code}(\texttt0))\cdot10^{k-i}$$ (for digits this is the digit value). |
| `Fw.Gate.signSplit` | agree | 2012596447 | 13864205882385435728 |  |
| `Fw.Gate.signSplit_len` | agree | 14506609251725975868 | 15189509776599438199 |  |
| `Fw.Gate.expPart` | disagree | 1320672793 | 16897259408609764044 | The math allows only e, but the Lean also accepts E. It also leaves out that the digit run is maximal (takeDigits is greedy) and that the sign is optional. Fix: cs=c::cs', c∈{e,E}, (σ,u)=signSplit(cs'), (d,r)=takeDigits(u), d≠[] ⇒ ((-1)^σ·digitsVal(d), r); ⊥ otherwise. |
| `Fw.Gate.takeDigits_len` | agree | 12220992377880482539 | 500860031424438076 |  |
| `Fw.Gate.expPart_lt` | agree | 3947699055980019098 | 10174816576230084146 |  |
| `Fw.Gate.withExp` | agree | 3514446782 | 7963133204173201822 |  |
| `Fw.Gate.unsignedNum` | disagree | 450868400 | 14882473444781561933 | Neither 'cs = d1 . d2 r' nor 'cs = d1 r' says the digit runs are maximal, so '12' could split as d1=1, r=2. Fix: (d1,r1)=takeDigits(cs); if r1='.'::r2 with (d2,r)=takeDigits(r2) and d1++d2≠[], withExp(digitsVal(d1++d2), -\|d2\|, r); else if d1≠[], withExp(digitsVal(d1),0,r1); else ⊥. |
| `Fw.Gate.numAt` | disagree | 2666144811576536047 | 7983119528288197948 | The cases are not exhaustive: head(cs)≠'-' (or cs=[]) with unsigned(cs)=⊥ gives ⊥ in the Lean, and the math has no case for it. Fix: replace the second case with '⊥ otherwise' and order the cases as first match: ((1,m,e),r) if cs='-'cs' ∧ unsigned(cs')=(m,e,r); ((0,m,e),r) if head(cs)≠'-' ∧ unsigned(cs)=(m,e,r); ⊥ otherwise. |
| `Fw.Gate.withExp_len` | agree | 9276416819956236096 | 15400911783070855957 |  |
| `Fw.Gate.numAt_lt` | agree | 9570755919656030773 | 11144856703322550321 |  |
| `Fw.Gate.scan` | agree | 3423221481214371652 | 6776079846783677650 |  |
| `Fw.Gate.near` | agree | 3059603916 | 17197667812408806966 |  |
| `Fw.Gate.tolStyle` | agree | 1901972866 | 4261386200642488758 |  |
| `Fw.Gate.tolBox` | agree | 1901972866 | 9561801931531314844 |  |
| `Fw.Gate.styleValueEq` | disagree | 2494698578 | 18244995847261618681 | skel, nums and a_i are undefined, and 'forall i' has no range. Fix: add 'where (skel(a), nums(a)) = scan(chars(a))' and write '\forall i < \|nums(a)\|,\ \|val(nums(a)_i) - val(nums(b)_i)\| \le 10^{-3}'. |
| `Fw.Gate.styleStatus` | agree | 11353464852974977639 | 14702900162705017673 |  |
| `Fw.Gate.boxStatus` | agree | 4582495815591256266 | 10458680004423415441 |  |
| `Fw.Gate.countStatus` | agree | 10379292326654774936 | 11924284667450759215 |  |
| `Fw.Gate.beq_swap` | disagree | 2553745957 | 3803618758360370907 | The math leaves out the type and the LawfulBEq hypothesis that the Lean needs. Fix: $$\forall \alpha \text{ with a lawful } {==},\ \forall a, b \in \alpha,\quad (a == b) = (b == a)$$ |
| `Fw.Gate.near_comm` | agree | 14423173931615090183 | 3223045410965578661 |  |
| `Fw.Gate.styleValueEq_comm` | agree | 13173459830816731664 | 6532582151870620436 |  |
| `Fw.Gate.styleValueEq_refl` | agree | 3237875156415001974 | 4179709096067846756 |  |
| `Fw.Gate.styleValueEq_none` | agree | 7764115292175719084 | 12034622145995519726 |  |
| `Fw.Gate.boxStatus_equal_iff` | agree | 1032267652782555694 | 5474764919707874693 |  |
| `Fw.Gate.status_comm` | agree | 4642192953418273558 | 6432377790915234420 |  |
| `Fw.Gate.status_ne_na` | agree | 6039511601076070444 | 10697179045613194635 |  |
| `Fw.Site.Breakpoints.matrix_length` | agree | 5377811708920391300 | 12633632089489600303 |  |
| `Fw.Site.Breakpoints.matrix_blocks` | disagree | 15144106818494550027 | 761553771108041323 | The set-builder count should be a list-filter length (r5 pattern). '\sum n' also sits inside the scope of \forall (b,n). Fix: $$\big(\forall (b,n)\in\mathrm{breakdown}.\ \|[p\in M\mid \mathrm{blk}(p)=b]\|=n\big)\land\textstyle\sum_{(b,n)\in\mathrm{breakdown}} n=\|M\|$$ |
| `Fw.Site.Breakpoints.matrix_ids_nodup` | disagree | 5984117894114421953 | 11659478660316274633 | i, j are free and p_i is undefined. Fix: $$\forall i, j < \|M\|,\quad i \ne j \Rightarrow \mathrm{id}(M_i) \ne \mathrm{id}(M_j)$$ |
| `Fw.Site.Breakpoints.matrix_edge_pairs` | agree | 4084752774002263836 | 2442337394939180661 |  |
| `Fw.Site.Breakpoints.matrix_observes_every_edge` | agree | 1144167395363643359 | 14070448053342434491 |  |
| `Fw.Site.Breakpoints.matrix_pairs_agree` | agree | 12654043116926945435 | 1768272704272684177 |  |
| `Fw.Site.Breakpoints.matrix_fractional_in_gaps` | agree | 11573598125057643513 | 15819671352292718311 |  |
| `Fw.Site.Breakpoints.Px.Whole` | agree | 16986785898287337475 | 11841008528147732993 |  |
| `Fw.Site.Breakpoints.Px.MulWhole` | agree | 12934011823224197864 | 17169781948713602017 |  |
| `Fw.Site.Breakpoints.Px.mulWhole_of_device_px` | agree | 4716446211572135431 | 12396485370532319920 |  |
| `Fw.Site.Breakpoints.matrix_width_dpr_whole` | agree | 4786292472678809296 | 10130323326171554255 |  |
| `Fw.Site.Breakpoints.matrix_whole_iff` | agree | 15482465790586369190 | 5347177938609620248 |  |
| `Fw.Site.Breakpoints.fractional_dpr_indep` | agree | 16554988923082604060 | 805980691290841309 |  |
| `Fw.Site.Breakpoints.matrix_neutral_inert` | agree | 9521931114566435866 | 2377151723454644703 |  |
| `Fw.Site.Breakpoints.matrix_neutral_hover_both_sides` | agree | 18123288127712913540 | 8988459588365235361 |  |
| `Fw.Site.Breakpoints.matrix_cross_no_touch_arm` | agree | 14773696074287928463 | 9094769987826049720 |  |
| `Fw.Site.Breakpoints.matrix_dw_arm` | agree | 14207893115397754128 | 4054279373528793813 |  |
| `Fw.Site.Breakpoints.matrix_landscape_overlaps` | agree | 5712598231363848962 | 10992514935117077027 |  |
| `Fw.Store.Engine` | agree | 3931117990 | 16411709675448809780 |  |
| `Fw.Store.Engine.name` | agree | 9005330454381169292 | 11429436597321536617 |  |
| `Fw.Store.Engine.ofName` | agree | 11146445518374645252 | 14198280902223101931 |  |
| `Fw.Store.Engine.ofName_name` | agree | 964647291742980192 | 15267970371977830809 |  |
| `Fw.Store.Engine.name_inj` | agree | 4943367523764308117 | 2991340138587845762 |  |
| `Fw.Store.canonEngines` | agree | 15834325002669434814 | 13851765488121020422 |  |
| `Fw.Store.mem_canonEngines` | agree | 13234918327024408533 | 15261792531427142037 |  |
| `Fw.Store.canonEngines_nodup` | agree | 2520567635590758168 | 7253543772698350416 |  |
| `Fw.Store.isHexChar` | agree | 3068939364 | 16287238683324935558 |  |
| `Fw.Store.isHex` | agree | 780105970 | 2326502082154135505 |  |
| `Fw.Store.pathChars` | agree | 1531304644 | 657739723818737175 |  |
| `Fw.Store.objectPath` | agree | 3438944622 | 7255808984628112680 |  |
| `Fw.Store.objectPath_inj` | agree | 12277619542821806863 | 8516573363462079075 |  |
| `Fw.Store.isId` | agree | 1526413716 | 2045666885244081660 |  |
| `Fw.Store.safeName` | agree | 1526413716 | 6934354624342040472 |  |
| `Fw.Store.safeName_no_dotdot` | agree | 14177408695417943058 | 14701747864788511969 |  |
| `Fw.Store.Entry` | agree | 3931117990 | 18384270403027979867 |  |
| `Fw.Store.Manifest` | disagree | 3931117990 | 15126533717981792260 | '\mathrm{Engine}' is the 2-element type, but the field is a String (wire name; valid_engine applies ofName to it). Fw and image are strings/pairs too. Fix: \mathrm{String}_{engine}\times\mathrm{String}_{preset}\times(\mathrm{String}\times\mathrm{String})^{*}_{fw}\times\mathrm{String}^{4}_{profile,gitSha,image,runId}\times\mathrm{Entry}^{*} |
| `Fw.Store.flagsOk` | agree | 1845090702 | 503806560223763049 |  |
| `Fw.Store.flagsOk_nodup` | agree | 14301205091659995122 | 884271662035341649 |  |
| `Fw.Store.imageOk` | agree | 1526413716 | 16016394284963669064 |  |
| `Fw.Store.entriesSorted` | agree | 8919077983848714737 | 15831149991340409612 |  |
| `Fw.Store.entriesSorted_nodup` | agree | 12006485292719872844 | 9383286811542811752 |  |
| `Fw.Store.Manifest.problems` | disagree | 16980040380588802030 | 22081738514254941 | Prose '[each violated rule]' leaves out the messages and their order, and 'digits-only run id' drops the Lean's runId ≠ ε (an empty id is refused). Also sorted is checked before safe. Fix: write the 11 conditional rows in order, e.g. [\texttt{runId: not digits} \mid runId=\varepsilon \lor \exists c\in runId: c\notin 0..9]. |
| `Fw.Store.Manifest.valid` | agree | 3606507427596993575 | 11799464836401939062 |  |
| `Fw.Store.Manifest.valid_engine` | agree | 267712054306483811 | 16962361947294862728 |  |
| `Fw.Store.Manifest.valid_entries` | agree | 2304970495041240877 | 8858658578465547250 |  |
| `Fw.Store.Req` | agree | 3931117990 | 1379159758277995333 |  |
| `Fw.Store.flagPairs` | agree | 2441344125 | 15752460045643942715 |  |
| `Fw.Store.flagPairs_inj` | agree | 3315889974800784343 | 17839346451246930906 |  |
| `Fw.Store.keyPairs` | disagree | 15686914387374822767 | 11553387682097316935 | Values are written '·', so the math never says which field fills each pair, and keyPairs_inj depends on that. Fix: [(v,"1"),(engine,\operatorname{name}(r.engine)),(preset,r.preset),(profile,r.profile),(sha,r.sha),(image,r.image)] \mathbin{+\!\!+} \operatorname{flagPairs}(r.fw). |
| `Fw.Store.Request` | disagree | 3931117990 | 3837434744696620823 | engines is a list of names (String*), not Engines. images is an association list (String×String)* where the first match wins (imageOf), which may hold unknown names or repeats, so it is not a partial function Engine ⇀ Image. Fix: \mathrm{String}\times\mathrm{Flags}\times\mathrm{String}^{*}\times\mathrm{String}\times\mathbb{N}\times\mathrm{String}\times(\mathrm{String}\times\mathrm{String})^{*}. |
| `Fw.Store.defaultPreset` | disagree | 3265150928 | 6102076884470611852 | The math gives a triple (original, [], swipe-v1), but the def is just the string "original". Fix: $$\mathrm{defaultPreset} = \texttt{original}$$ |
| `Fw.Store.defaultProfile` | agree | 3265150928 | 12156128889965632074 |  |
| `Fw.Store.defaultImage` | agree | 9005330454381169292 | 10206178745525665405 |  |
| `Fw.Store.imageOf` | agree | 14236183900610463124 | 10245355946179982796 |  |
| `Fw.Store.workflowOf` | agree | 9005330454381169292 | 6984703856073495188 |  |
| `Fw.Store.workflowInputs` | agree | 4535232382063731544 | 12651193233789816827 |  |
| `Fw.Store.needs` | agree | 7537011300159061116 | 1099288179083153206 |  |
| `Fw.Store.dispatchInputs` | agree | 824302957720216723 | 10981601103615453026 |  |
| `Fw.Store.blocked` | agree | 3378084018045744923 | 3551923338541519983 |  |
| `Fw.Store.blocked_none_sound` | agree | 14384674071420559695 | 5970156037551084381 |  |
| `Fw.Store.Job` | agree | 3931117990 | 7390504974134662726 |  |
| `Fw.Store.reqProblems` | disagree | 7537011300159061116 | 10209920155186834399 | 'strictly increasing after sorting by part' is wrong: the Lean checks flagsOk(q.fw) in the given order and sorts nothing. The prose also leaves out the messages and their order. Fix: list the 9 conditional rows in order, with [\texttt{fw: a part appears twice} \mid \neg\operatorname{flagsOk}(q.fw)]. |
| `Fw.Store.jobsOf` | disagree | 6604317619944379008 | 7049489361484578026 | job(e,q) is never defined, and engines(q) is really filterMap ofName q.engines (unknown names dropped). Fix: [(e,\operatorname{workflow}(e),\operatorname{dispatch}(e,q),\operatorname{keyPairs}(e,q.preset,q.fw,q.profile,q.sha,\operatorname{imageOf}(q,e)),\operatorname{blocked}(e,q)) : e\in\operatorname{canon}([\operatorname{ofName}(n)\ne\bot : n\in q.engines])] |
| `Fw.Store.plan` | agree | 6604317619944379008 | 7176712309154729460 |  |
| `Fw.Store.plan_nil_of_problems` | agree | 5465808158069326090 | 1976131971054035846 |  |
| `Fw.Store.plan_engines` | agree | 8547973888600971360 | 10638819243604636246 |  |
| `Fw.Store.reqProblems_nil_flags` | agree | 5405623343845468443 | 5473700258224445453 |  |
| `Fw.Store.plan_key_inj` | agree | 15011578410845782310 | 14712210406756088362 |  |
| `Fw.Store.manifestPath` | agree | 3438944622 | 1566164820178038664 |  |
| `Fw.Store.cacheOf` | agree | 689004724 | 8757769034798268542 |  |
| `Fw.Store.exReq` | disagree | 7619898758398151716 | 2138139888242016742 | The math states only a property (reqProblems = []), not the value the def computes. Fix: $$\mathrm{exReq} = (\texttt{original}, [\,], [\texttt{webkit},\texttt{chromium},\texttt{webkit}], \texttt{swipe-v1}, 3, \texttt{0123…4567}, [\,])$$ and keep reqProblems(exReq) = [] as a remark. |
| `Fw.Store.obsOf` | disagree | 6269551216281122112 | 13610082472417347643 | series_k(B_1), series_k(V_1) is undefined for an empty B or V, where the Lean uses headD [] (the empty run, so the series is []). Fix: \operatorname{series}_k(\operatorname{hd}_{[]}(B)), \operatorname{series}_k(\operatorname{hd}_{[]}(V)) with hd_{[]}([]) = [], and keys of the flattened B ++ V. |
| `Fw.Store.reduceOk` | agree | 7870473980156990440 | 6300768754003775858 |  |
| `Fw.Store.failing` | agree | 10680470987856455624 | 2881780232871281315 |  |
| `Fw.Store.obsOf_types` | agree | 4655378293258734645 | 5573973159401145867 |  |
| `Fw.Store.reduceOk_iff` | agree | 3570464703780321370 | 4118180385804658962 |  |
| `Fw.Store.failing_eq_nil_iff` | agree | 15904794644459462314 | 15268724854058944870 |  |
| `Fw.Store.reduceOk_sound` | agree | 18284368218795928819 | 16501703253157190005 |  |
| `Fw.Store.overall` | agree | 3367087299 | 16329134358591868849 |  |
| `Fw.Store.overall_iff` | agree | 18031288705289452848 | 5261177219203327698 |  |
| `Fw.Console.Body` | agree | 3931117990 | 14661888362176850496 |  |
| `Fw.Console.EvType` | agree | 3931117990 | 10054173663814265292 |  |
| `Fw.Console.EvType.name` | agree | 4541525649188196040 | 3059676772035066445 |  |
| `Fw.Console.Body.type` | agree | 9448451351061715352 | 12056997216992026056 |  |
| `Fw.Console.State` | agree | 3931117990 | 17682154533786218245 |  |
| `Fw.Console.mayList` | agree | 10668220558469755330 | 3633990719908589772 |  |
| `Fw.Console.may` | agree | 9116011405709589900 | 16152540979048317927 |  |
| `Fw.Console.cardRefusal` | agree | 8424025268993938622 | 3016009726952741496 |  |
| `Fw.Console.cardStep` | agree | 14873985222447604784 | 12369250004502769471 |  |
| `Fw.Console.cardOf` | agree | 12182609073572615578 | 8891323723871593345 |  |
| `Fw.Console.stepRefusal` | agree | 18133271573826468041 | 2881867432891951741 |  |
| `Fw.Console.check` | agree | 2990180966253351366 | 15993064369310846725 |  |
| `Fw.Console.accept` | agree | 6862568570152911046 | 16903303583580757326 |  |
| `Fw.Console.step` | agree | 17306261129526053524 | 16349693843614797547 |  |
| `Fw.Console.apply` | agree | 6862568570152911046 | 16188065797220658840 |  |
| `Fw.Console.project` | agree | 10122301612494852194 | 14153054597789465295 |  |
| `Fw.Console.step_seen` | agree | 2393782690477594344 | 11216555469254441713 |  |
| `Fw.Console.refused_keeps` | agree | 17923012544511669331 | 14597015446345141025 |  |
| `Fw.Console.reject_keeps` | agree | 6773583200770308847 | 16609953789167140387 |  |
| `Fw.Console.apply_idem` | agree | 3786667092133757040 | 17350574509467623372 |  |
| `Fw.Console.step_twice` | agree | 14743989078989258383 | 13501084726203568421 |  |
| `Fw.Console.accepted_may` | agree | 16673422763477258471 | 6448429008062984428 |  |
| `Fw.Console.unauthorized_rejected` | agree | 6994818746479984769 | 2138980241924517838 |  |
| `Fw.Console.only_user_answers` | agree | 10259445785239290490 | 7323091736834615658 |  |
| `Fw.Console.landed_fact_accepted` | agree | 14774768735950615871 | 3772781372883951176 |  |
| `Fw.Console.project_append` | agree | 3397257406513289240 | 7328535922169628367 |  |
| `Fw.Console.Inv` | agree | 33710354348958182 | 16262640497794126337 |  |
| `Fw.Console.cardStep_inv` | agree | 3206858886547955415 | 12598546974232632004 |  |
| `Fw.Console.inv_init` | agree | 15994614831687694691 | 12731406418473595965 |  |
| `Fw.Console.accept_inv` | agree | 16469353773489973092 | 2478315476095461140 |  |
| `Fw.Console.apply_inv` | agree | 11827005878967686646 | 12192267181112390734 |  |
| `Fw.Console.project_inv` | agree | 7526862755477267939 | 14130064532324766021 |  |
| `Fw.Console.land_requires` | agree | 8613980846578978540 | 3583517742071750831 |  |
| `Fw.Console.landReq_ready` | agree | 17622307450249592589 | 16035548478844858102 |  |
| `Fw.Console.review_independent` | agree | 14124763918680957975 | 6433155003542643736 |  |
| `Fw.Console.built_resets` | agree | 15275432381577646374 | 6505061661035637133 |  |
| `Fw.Console.check_plan` | agree | 3723927731726314343 | 1125438156083529201 |  |
| `Fw.Console.accept_plan_cases` | agree | 14752519214940261948 | 3603246383575820240 |  |
| `Fw.Console.apply_plan_cases` | agree | 5192109630725356741 | 3217855224756634437 |  |
| `Fw.Console.apply_plan_inv` | agree | 8573549882375729012 | 3520209679925620182 |  |
| `Fw.Console.project_plan_inv` | agree | 3597414984791934482 | 11148362462608569001 |  |
| `Fw.Console.apply_isDone` | agree | 3750972424265258988 | 13530144770595374912 |  |
| `Fw.Console.project_isDone` | agree | 15711887727430551902 | 12930952371495767017 |  |
| `Fw.Plan.Trailer.isBlank` | agree | 3068939364 | 7809826404690145050 |  |
| `Fw.Plan.Trailer.isIdChar` | agree | 3068939364 | 16249936322694399596 |  |
| `Fw.Plan.Trailer.isEol` | agree | 3068939364 | 16091792073271265041 |  |
| `Fw.Plan.Trailer.trailerOf` | agree | 2479964713 | 10010244613353378080 |  |
| `Fw.Plan.Trailer.trailers` | agree | 1961493383 | 12034828624017950354 |  |
| `Fw.Plan.Trailer.Commit` | agree | 3931117990 | 6284795167705099423 |  |
| `Fw.Plan.Trailer.Verdict` | agree | 3931117990 | 10373070223751148160 |  |
| `Fw.Plan.Trailer.Verdict.name` | agree | 1103213623856342308 | 14118494023577505578 |  |
| `Fw.Plan.Trailer.pairs` | agree | 9276139756612768745 | 6500864573504804933 |  |
| `Fw.Plan.Trailer.verdict` | agree | 14464294475767120829 | 14757643290679383216 |  |
| `Fw.Plan.Trailer.judge` | agree | 5357669490075100788 | 12222866424725771824 |  |
| `Fw.Plan.Trailer.verdicts` | agree | 3866095392489583276 | 2695483280277182680 |  |
| `Fw.Plan.Trailer.facts` | agree | 437315313943810256 | 3388652937224028462 |  |
| `Fw.Plan.Trailer.firstSha` | agree | 361667379 | 4587843150625859519 |  |
| `Fw.Plan.Trailer.mem_judge_done` | agree | 1557594345429944939 | 11110653587359034068 |  |
| `Fw.Plan.Trailer.mem_facts_iff` | agree | 129249588696419363 | 15572726822510674203 |  |
| `Fw.Plan.Trailer.judge_done_nodup` | agree | 4251809938430000839 | 16593212137498862524 |  |
| `Fw.Plan.Trailer.facts_nodup` | agree | 16910166545940428405 | 9988011552140476557 |  |
| `Fw.Plan.check` | agree | 594116433317874102 | 474548437176521132 |  |
| `Fw.Plan.msView` | agree | 3665224364769316189 | 12490262543854697044 |  |
| `Fw.Plan.view` | agree | 8606534878737370153 | 8175759126723189171 |  |
| `Fw.Plan.view_criticalPath` | agree | 4674057372163889314 | 266280941462876783 |  |
| `Fw.Plan.tab` | agree | 10056531092951660662 | 4577314633274215886 |  |
| `Fw.Console.boardCard` | disagree | 5498730827532609432 | 3453752085009086693 | The r7a list-count fix is right, but 'm is the first step s with …' names no list. The Lean searches σ.steps (find?). Fix: 'm is the first s \in \sigma.\mathit{steps} with \operatorname{isOpen}(s.\mathit{status}) \land s.\mathit{card} = c.\mathit{id} (or \bot)'. |
| `Fw.Console.Board` | disagree | 3931117990 | 10968018830302668015 | The structure's math repeats the board() function and never gives the type. Fix: $$\mathrm{Board} = (\mathit{seq}, \mathit{now}, \mathit{cards}, \mathit{steps}, \mathit{needsYou}) \in \mathbb{N}\times\mathbb{N}\times\mathrm{BoardCard}^{*}\times\mathrm{Step}^{*}\times\mathrm{NeedsYou}^{*}$$ |
| `Fw.Console.board` | agree | 54855381088658253 | 16951426925497675440 |  |
| `Fw.Console.needsYou_open` | agree | 12380582029402214694 | 9353502330102105722 |  |
