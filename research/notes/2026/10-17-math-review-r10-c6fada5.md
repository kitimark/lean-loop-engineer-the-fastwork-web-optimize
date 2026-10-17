---
title: Math review round 10 at c6fada5 (slow-work watch, store key v2, gate probe scope, N1 and SPK-q rules)
date: 2026-10-17
status: CONFIRMED
round: 10
---

# Math review round 10 at c6fada5

Three math-reviewer agents (workflow `review-r10`, read-only) back-translated the 334 pending or stale declarations at
c6fada5: watch-slow and watch-proc-allow (Fw.Obs.Health), store-target (Fw.Store.Layout), gate-probe-scope
(Fw.Gate.Scope, ScopeGen) and n1-lean (Fw.Measure.Neutral, Arms, Splits). Method as in rounds 3 to 9; ShadowLint now
makes the most common earlier finding a build error. The lead wrote this record from the agents' structured verdicts; `stmtHash` and
`mathHash` come from `lake exe mathview` at c6fada5.

## Counts

| Batch | Reviewed | Agree | Disagree |
|---|---|---|---|
| A | 141 | 141 | 0 |
| B | 95 | 92 | 3 |
| C | 98 | 97 | 1 |
| **Total** | 334 | 330 | 4 |

Batch A: Fw.Obs.Health. Batch B: Fw.Store.Layout, Fw.Gate.Scope and ScopeGen. Batch C: Fw.Measure.Neutral, Arms,
Splits, and stale Classes, Freeze, SelfCheck, Snapshot.
Not returned by an agent, still pending: none.
Fixes for any disagree row go to a lean-prover task (math-r10-fix).

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Obs.Health.Params` | agree | 3931117990 | 17291640389547325169 |  |
| `Fw.Obs.Health.CiRun` | agree | 3931117990 | 487727765477891661 |  |
| `Fw.Obs.Health.Proc` | agree | 3931117990 | 15857008745633192786 |  |
| `Fw.Obs.Health.System` | agree | 3931117990 | 7230369119026472014 |  |
| `Fw.Obs.Health.Obs` | agree | 3931117990 | 15434921155042941012 |  |
| `Fw.Obs.Health.State` | agree | 3931117990 | 1942921322909214625 |  |
| `Fw.Obs.Health.stopped` | agree | 3911148813278998491 | 3640539256852217216 |  |
| `Fw.Obs.Health.goneB` | agree | 3911148813278998491 | 7152250050100000155 |  |
| `Fw.Obs.Health.ended` | agree | 3911148813278998491 | 7286415717945112520 |  |
| `Fw.Obs.Health.live` | agree | 3911148813278998491 | 10295335389412038138 |  |
| `Fw.Obs.Health.hasLiveChild` | agree | 6513208058986165826 | 14392425969250817176 |  |
| `Fw.Obs.Health.hungB` | agree | 6513208058986165826 | 6666882566365682050 |  |
| `Fw.Obs.Health.stallB` | agree | 6513208058986165826 | 6956289022177918473 |  |
| `Fw.Obs.Health.Stall` | agree | 6686990894627867648 | 10369875417336052799 |  |
| `Fw.Obs.Health.stallB_iff` | agree | 8001562040812431565 | 15079691544746084728 |  |
| `Fw.Obs.Health.state` | agree | 5745084788174259048 | 15336378807950153118 |  |
| `Fw.Obs.Health.state_done` | agree | 17157936997173632713 | 1619917251329189295 |  |
| `Fw.Obs.Health.state_gone` | agree | 12638629844610137371 | 5723093121694422971 |  |
| `Fw.Obs.Health.state_parked` | agree | 12146292974705681041 | 16131560956269103721 |  |
| `Fw.Obs.Health.state_stalled` | agree | 11525098882216265963 | 5925339557931948512 |  |
| `Fw.Obs.Health.state_idle` | agree | 15406822469624718163 | 17521238547687540091 |  |
| `Fw.Obs.Health.state_active` | agree | 17891964226661470832 | 9215518640639651386 |  |
| `Fw.Obs.Health.state_cases` | agree | 11344332110595874929 | 13621267757664634033 |  |
| `Fw.Obs.Health.stalled_facts` | agree | 17752623655703323734 | 11294754436099573796 |  |
| `Fw.Obs.Health.Code` | agree | 3931117990 | 9742752954003922578 |  |
| `Fw.Obs.Health.Code.all` | agree | 2815448594388719383 | 2018857015791146461 |  |
| `Fw.Obs.Health.Code.name` | agree | 11405008451885626864 | 673598348780169085 |  |
| `Fw.Obs.Health.Code.rank` | agree | 16004891908716986636 | 10518242707059999681 |  |
| `Fw.Obs.Health.Code.isAgent` | agree | 6307298079091521691 | 13831943248137647491 |  |
| `Fw.Obs.Health.Code.rank_inj` | agree | 10352836200752695966 | 10658484976796441068 |  |
| `Fw.Obs.Health.Code.names_sorted` | agree | 7618668066668705505 | 5175374510684102072 |  |
| `Fw.Obs.Health.Alert` | agree | 3931117990 | 2443311939687971582 |  |
| `Fw.Obs.Health.Alert.Lt0` | agree | 7089559679543866550 | 5614484898716173013 |  |
| `Fw.Obs.Health.Alert.Lt` | agree | 7089559679543866550 | 16743795955948581549 |  |
| `Fw.Obs.Health.Alert.lt_irrefl` | agree | 15409862612278810919 | 7442225201608369200 |  |
| `Fw.Obs.Health.Alert.lt0_trans` | agree | 14619583811313955991 | 7109636080872043126 |  |
| `Fw.Obs.Health.Alert.lt_trans` | agree | 7032495557004473818 | 4702423519244826258 |  |
| `Fw.Obs.Health.Alert.lt_trich` | agree | 4659879002509710905 | 8090497465254313091 |  |
| `Fw.Obs.Health.ins` | agree | 14915826666009153051 | 8816338872740756689 |  |
| `Fw.Obs.Health.sortU` | agree | 205947004175554346 | 867576292352490826 |  |
| `Fw.Obs.Health.mem_ins` | agree | 16018156305996268867 | 17643666095272352657 |  |
| `Fw.Obs.Health.sorted_ins` | agree | 10521118562147697698 | 16545681272094160464 |  |
| `Fw.Obs.Health.mem_sortU` | agree | 17876537190033209682 | 9781167020989237374 |  |
| `Fw.Obs.Health.sorted_sortU` | agree | 11591336103895152977 | 3372194369719061795 |  |
| `Fw.Obs.Health.eq_of_sorted` | agree | 4521268528713603985 | 8375397716919783049 |  |
| `Fw.Obs.Health.when` | agree | 9631544361215409006 | 3662261055572717720 |  |
| `Fw.Obs.Health.mem_when` | agree | 9972472236772515416 | 8608347469694431344 |  |
| `Fw.Obs.Health.slowB` | agree | 6513208058986165826 | 15925927130956092608 |  |
| `Fw.Obs.Health.toolDetail` | agree | 13259034516551261431 | 16004025564820983393 |  |
| `Fw.Obs.Health.agentAlerts` | agree | 12005986194624880873 | 11533665488892289521 |  |
| `Fw.Obs.Health.newGone` | agree | 15886084543337046395 | 12939162746506298817 |  |
| `Fw.Obs.Health.goneAlert` | agree | 17427087172529382459 | 865208488167693824 |  |
| `Fw.Obs.Health.tiedTo` | agree | 2423821251 | 2301233497919426377 |  |
| `Fw.Obs.Health.critAgent` | agree | 16225131397636173464 | 15080250546655163157 |  |
| `Fw.Obs.Health.critCi` | agree | 8541072198425125433 | 18157796020421832846 |  |
| `Fw.Obs.Health.mark` | agree | 1577695694784688314 | 5380050567819541941 |  |
| `Fw.Obs.Health.agentAll` | agree | 17427087172529382459 | 3104113364748556551 |  |
| `Fw.Obs.Health.agentAlerts_quiet` | agree | 8772164771625872566 | 11738841508231850423 |  |
| `Fw.Obs.Health.agentAlerts_subject` | agree | 16573416694056042425 | 17605273568604044913 |  |
| `Fw.Obs.Health.agentAlerts_not_gone` | agree | 8946603758370661141 | 11715241315441985454 |  |
| `Fw.Obs.Health.agentAll_subject` | agree | 13741336747907011707 | 6303838114783367242 |  |
| `Fw.Obs.Health.gone_alerts` | agree | 5550276840580461133 | 1321420494732784476 |  |
| `Fw.Obs.Health.goneAlert_iff` | agree | 5505448028364397305 | 524538743691229483 |  |
| `Fw.Obs.Health.wait_not_hang` | agree | 14486939553017047216 | 6110057869423756873 |  |
| `Fw.Obs.Health.orphanB` | agree | 17067262508538979177 | 3563457232577479256 |  |
| `Fw.Obs.Health.ciFailing` | agree | 8665852422421761757 | 3248022000525743499 |  |
| `Fw.Obs.Health.ciLatest` | agree | 17916688985849988373 | 1980321117661384519 |  |
| `Fw.Obs.Health.ciRunning` | agree | 8665852422421761757 | 8877366236460523011 |  |
| `Fw.Obs.Health.ciSlowB` | agree | 11532364698942457370 | 13529139998569103785 |  |
| `Fw.Obs.Health.ciFinishedB` | agree | 2198790572013112100 | 98048410521932551 |  |
| `Fw.Obs.Health.dockerOrphanB` | agree | 16364899408172882221 | 5722006365842322406 |  |
| `Fw.Obs.Health.keepProgs` | agree | 4017531403 | 15810652869667757515 |  |
| `Fw.Obs.Health.declaredB` | agree | 15995485918808521771 | 14097866796257615358 |  |
| `Fw.Obs.Health.ownerLiveB` | agree | 13525873258822898085 | 1568034451642280044 |  |
| `Fw.Obs.Health.procLongB` | agree | 17100533617391071586 | 12060546037882106785 |  |
| `Fw.Obs.Health.nLive` | agree | 14000119965224875118 | 13201091310844451852 |  |
| `Fw.Obs.Health.nLive_gone` | agree | 2011539269964847021 | 6826989993160479451 |  |
| `Fw.Obs.Health.nKind` | agree | 1972948609071285678 | 7281617881823481581 |  |
| `Fw.Obs.Health.nHelpers` | agree | 14000119965224875118 | 10922916051641963846 |  |
| `Fw.Obs.Health.permB` | agree | 17921415961902365917 | 1596581060504198026 |  |
| `Fw.Obs.Health.sOver` | agree | 14374870197216445338 | 13020254773655679909 |  |
| `Fw.Obs.Health.sDisk` | agree | 14374870197216445338 | 4224939386117546645 |  |
| `Fw.Obs.Health.sMem` | agree | 4796439020672042040 | 15431459040675860845 |  |
| `Fw.Obs.Health.sLoad` | agree | 14374870197216445338 | 7014004190052239284 |  |
| `Fw.Obs.Health.sLockLong` | agree | 14374870197216445338 | 8764143274978202148 |  |
| `Fw.Obs.Health.sOrphan` | agree | 14374870197216445338 | 924316348324556259 |  |
| `Fw.Obs.Health.sCiFailed` | agree | 4796439020672042040 | 6374536403521959581 |  |
| `Fw.Obs.Health.sCiSlow` | agree | 14374870197216445338 | 11430688285250878656 |  |
| `Fw.Obs.Health.sCiFin` | agree | 14374870197216445338 | 17035029706994098486 |  |
| `Fw.Obs.Health.sDocker` | agree | 14374870197216445338 | 3419149666367069134 |  |
| `Fw.Obs.Health.procAlert` | agree | 9536340134237720430 | 15612943684183457763 |  |
| `Fw.Obs.Health.procAlert_code` | agree | 16340854776081851063 | 11028656074659766482 |  |
| `Fw.Obs.Health.sProc` | agree | 14374870197216445338 | 17042695866813383021 |  |
| `Fw.Obs.Health.sWt` | agree | 14374870197216445338 | 5435798486697102117 |  |
| `Fw.Obs.Health.sPerm` | agree | 4796439020672042040 | 12304183833196539852 |  |
| `Fw.Obs.Health.sysAlerts` | agree | 14374870197216445338 | 5517377766495741301 |  |
| `Fw.Obs.Health.raw` | agree | 14374870197216445338 | 12680589456518220346 |  |
| `Fw.Obs.Health.Counts` | agree | 3931117990 | 13160974942874121433 |  |
| `Fw.Obs.Health.Row` | agree | 3931117990 | 9992227032542628734 |  |
| `Fw.Obs.Health.Report` | agree | 3931117990 | 7826683926659600082 |  |
| `Fw.Obs.Health.countState` | agree | 6468663731198752944 | 12487850935271664477 |  |
| `Fw.Obs.Health.health` | agree | 3078395100424359978 | 10973831720360454803 |  |
| `Fw.Obs.Health.mem_alerts` | agree | 10390656310839185754 | 15232610699692105777 |  |
| `Fw.Obs.Health.alerts_sorted` | agree | 15585205391511689638 | 12608048796447155491 |  |
| `Fw.Obs.Health.crit_first` | agree | 12457927055157304527 | 2319439206253193187 |  |
| `Fw.Obs.Health.sysPiece` | agree | 4341752641014798849 | 3337133613035840886 |  |
| `Fw.Obs.Health.sysAlerts_eq` | agree | 12482476394121803945 | 3769422723822900236 |  |
| `Fw.Obs.Health.piece_code` | agree | 16750233696679371620 | 11533090793394023060 |  |
| `Fw.Obs.Health.mem_sys` | agree | 10950970150742854061 | 2574664773491244340 |  |
| `Fw.Obs.Health.sysAlerts_notAgent` | agree | 5624560937196843216 | 17373712011679423790 |  |
| `Fw.Obs.Health.agent_alert_live` | agree | 16399334639487768597 | 11709874275649080919 |  |
| `Fw.Obs.Health.mem_sys_of_notAgent` | agree | 7200260947349618226 | 830446132325176468 |  |
| `Fw.Obs.Health.sys_code_iff` | agree | 16284321865724800924 | 9978293688378043093 |  |
| `Fw.Obs.Health.when_ne_nil` | agree | 16572724592969631037 | 242632615010216788 |  |
| `Fw.Obs.Health.lockOrphan_iff` | agree | 455890709255593875 | 6145073535690002857 |  |
| `Fw.Obs.Health.permissionWait_iff` | agree | 9905905581898126217 | 11094342511218806873 |  |
| `Fw.Obs.Health.loadHigh_iff` | agree | 14138485613268492395 | 1089371317904405446 |  |
| `Fw.Obs.Health.ciSlow_raised` | agree | 1941105867335715353 | 10779687419346444664 |  |
| `Fw.Obs.Health.procLong_iff` | agree | 763493244842200275 | 17238893066381302638 |  |
| `Fw.Obs.Health.ownerLive_quiet` | agree | 15761471956408225223 | 18249663945543331331 |  |
| `Fw.Obs.Health.declared_quiet` | agree | 18024456028796553106 | 13034740787172688442 |  |
| `Fw.Obs.Health.procLong_sound` | agree | 7609572009534865790 | 13649739311347120700 |  |
| `Fw.Obs.Health.orphan_raised` | agree | 10603293156440087055 | 2774290599226026316 |  |
| `Fw.Obs.Health.Looser` | agree | 3363696517603068826 | 17506954860322648941 |  |
| `Fw.Obs.Health.ended_congr` | agree | 5311826278242014936 | 3195860421639962857 |  |
| `Fw.Obs.Health.hasLiveChild_congr` | agree | 921270129377917461 | 7308806975550936385 |  |
| `Fw.Obs.Health.hungB_mono` | agree | 17902231361658373178 | 3814597111591542474 |  |
| `Fw.Obs.Health.slowB_mono` | agree | 18434388461068964441 | 14175010013110693139 |  |
| `Fw.Obs.Health.stalled_mono` | agree | 992664341950850147 | 9951933780815473475 |  |
| `Fw.Obs.Health.agentAlerts_mono` | agree | 16171517031478330175 | 18169582892285958961 |  |
| `Fw.Obs.Health.agentAll_mono` | agree | 17671676465031452044 | 13525683078235611280 |  |
| `Fw.Obs.Health.when_sub` | agree | 8319922716618798500 | 6701064581288698264 |  |
| `Fw.Obs.Health.fm_sub` | agree | 13066660817328884454 | 15729025558924540562 |  |
| `Fw.Obs.Health.sysPiece_mono` | agree | 16545618847695809493 | 7944501539196364132 |  |
| `Fw.Obs.Health.sysAlerts_mono` | agree | 14583341472271788003 | 7441194937117156192 |  |
| `Fw.Obs.Health.health_mono` | agree | 17345301611197950436 | 14998244962817020747 |  |
| `Fw.Obs.Health.agent_perm` | agree | 17201125571378081689 | 2680297655996587229 |  |
| `Fw.Obs.Health.sysAlerts_perm` | agree | 11723544825120768585 | 6526216577029399178 |  |
| `Fw.Obs.Health.health_perm` | agree | 11557858786435538839 | 17583007677715167307 |  |
| `Fw.Obs.Health.counts_total` | agree | 8238879045004597772 | 14922062432982441943 |  |
| `Fw.Obs.Health.ci0` | agree | 2067514863878375939 | 12689592310932648391 |  |
| `Fw.Store.Target` | agree | 3931117990 | 11448915670111407504 |  |
| `Fw.Store.Target.name` | agree | 1243403137452154702 | 1309860767994165297 |  |
| `Fw.Store.Target.ofName` | agree | 12894096999425614092 | 4813934046317424591 |  |
| `Fw.Store.Target.ofName_name` | agree | 15566864095622786465 | 10904841690260626912 |  |
| `Fw.Store.Target.name_ofName` | agree | 4249157100129736062 | 5488177933022229455 |  |
| `Fw.Store.Target.name_inj` | agree | 16848332174500519243 | 10017972418549019774 |  |
| `Fw.Store.targetFits` | agree | 4184484811 | 7517750153094352807 |  |
| `Fw.Store.Manifest` | agree | 3931117990 | 1442939617495547473 |  |
| `Fw.Store.flagsOk_nodup` | agree | 14301205091659995122 | 17261401044502139137 |  |
| `Fw.Store.entriesSorted_nodup` | agree | 12006485292719872844 | 11685522074151692461 |  |
| `Fw.Store.Manifest.problems` | agree | 15787804681029681817 | 14781076148159935941 |  |
| `Fw.Store.Manifest.valid` | agree | 4476099538644966184 | 11799464836401939062 |  |
| `Fw.Store.Manifest.valid_engine` | agree | 7378208033943687809 | 6472031710634932257 |  |
| `Fw.Store.Manifest.valid_target` | agree | 14433806695334170099 | 11465284131111962600 |  |
| `Fw.Store.Manifest.valid_entries` | agree | 16702998094865244471 | 4087870921622139503 |  |
| `Fw.Store.Req` | agree | 3931117990 | 18418882517755778073 |  |
| `Fw.Store.flagPairs_inj` | agree | 3315889974800784343 | 11946696940447581613 |  |
| `Fw.Store.keyPairs` | agree | 919338815391956541 | 8653047874460323279 |  |
| `Fw.Store.keyPairs_inj` | agree | 390601425186476378 | 16265178126524410485 |  |
| `Fw.Store.keyPairs_target_ne` | agree | 1945119481177213699 | 1787022293239511037 |  |
| `Fw.Store.Manifest.req` | agree | 6693610090247466971 | 7554693517455526380 |  |
| `Fw.Store.Manifest.valid_req` | agree | 15097760994265765808 | 8244538737341224141 |  |
| `Fw.Store.Request` | agree | 3931117990 | 2529281938485132667 |  |
| `Fw.Store.imageOf` | agree | 6900539350158925072 | 10245355946179982796 |  |
| `Fw.Store.needs` | agree | 14342561531611864824 | 17105838384483914379 |  |
| `Fw.Store.dispatchInputs` | agree | 5682569929766528783 | 3062055607614530021 |  |
| `Fw.Store.dispatch_target` | agree | 12447002055226368138 | 7949655271913782698 |  |
| `Fw.Store.blocked` | agree | 10477098277576543639 | 3551923338541519983 |  |
| `Fw.Store.blocked_none_sound` | agree | 5492811054493077082 | 4405739072657643879 |  |
| `Fw.Store.blocked_chromium` | agree | 3100692168741566667 | 11898405084434720136 |  |
| `Fw.Store.needs_dispatched` | agree | 9497170610226716953 | 2044467139561547091 |  |
| `Fw.Store.reqProblems` | agree | 14342561531611864824 | 8038361999141032014 |  |
| `Fw.Store.jobsFor` | agree | 4603948912347364288 | 16958430793784875468 |  |
| `Fw.Store.jobsOf` | agree | 8839827005414299044 | 16730150797403403935 |  |
| `Fw.Store.plan` | agree | 8839827005414299044 | 7176712309154729460 |  |
| `Fw.Store.plan_nil_of_problems` | agree | 694981192224891196 | 16621789452966051202 |  |
| `Fw.Store.reqProblems_nil_target` | agree | 17615304742007437813 | 15536459670791710570 |  |
| `Fw.Store.plan_eq_jobsFor` | agree | 10682462072106583192 | 15689467073616593984 |  |
| `Fw.Store.plan_engines` | agree | 17609501204378172698 | 9722658219989709541 |  |
| `Fw.Store.reqProblems_nil_flags` | agree | 17154621971091442969 | 16655749630961754440 |  |
| `Fw.Store.plan_key_inj` | agree | 17162122325670144344 | 4166356797226775385 |  |
| `Fw.Store.plan_key_target` | agree | 10446789299059371157 | 14663678781146129209 |  |
| `Fw.Store.plan_key_target_ne` | agree | 14334987426004901708 | 11140678258589355177 |  |
| `Fw.Store.exReq` | agree | 11120880034559040512 | 9125650431711540897 |  |
| `Fw.Store.exRw` | agree | 11120880034559040512 | 14491520054790598907 |  |
| `Fw.Gate.collapse` | agree | 599762674 | 9806276730102550253 |  |
| `Fw.Gate.collapse_const` | agree | 11675051697308321774 | 1969597511987467884 |  |
| `Fw.Gate.Sweep` | agree | 3931117990 | 14117663438771994492 |  |
| `Fw.Gate.stopVerdicts` | agree | 10404663946635699685 | 6972309567659466903 |  |
| `Fw.Gate.stopVerdicts_const` | agree | 5971556750390634408 | 7765407587057498525 |  |
| `Fw.Gate.keyedVerdict` | agree | 8727060792945269246 | 8368073737437785976 |  |
| `Fw.Gate.scopedVerdict` | agree | 2895962295890730795 | 11015500073969728038 |  |
| `Fw.Gate.scoped_verdict_eq` | agree | 406934986055205595 | 14962999240286962372 |  |
| `Fw.Gate.ExtraCond` | agree | 3931117990 | 15441982737738283781 |  |
| `Fw.Gate.Knee` | agree | 3931117990 | 18397931902475504252 |  |
| `Fw.Gate.PartUse` | agree | 3931117990 | 11121725363234409737 |  |
| `Fw.Gate.lookupCond` | agree | 14495758136727000856 | 18159072758179209617 |  |
| `Fw.Gate.PartUse.conds` | agree | 2084787825064061858 | 9505125668456093744 |  |
| `Fw.Gate.PartUse.edgeQueries` | agree | 15358138883787002296 | 1188303642041514697 |  |
| `Fw.Gate.kneeQuery` | agree | 6120822610566934692 | 11565028349055600048 |  |
| `Fw.Gate.PartUse.queries` | agree | 15358138883787002296 | 15129716721349545968 |  |
| `Fw.Gate.PartUse.key` | agree | 14637994152420270809 | 18440791978572231325 |  |
| `Fw.Gate.floor320` | agree | 5262252293930091712 | 8380209411677787251 |  |
| `Fw.Gate.pilotParts` | disagree | 13871602926479079190 | 11869107999210002303 | Math gives only a merged set C (no mq. prefix), so engine.scroll's split C_orig=[mq.rm-reduce], C_rw=[] is lost; owners (hero.exit: [hero.exit, hero, hero.cue]) and D are left out. Fix: per part list (id, O, C_orig, C_rw, X, Kn) as ordered lists with full ids; say D is listed in the source. |
| `Fw.Gate.pilot_conds_known` | agree | 15927697423633235781 | 7526050284835420810 |  |
| `Fw.Gate.ports` | agree | 6767601373379155314 | 5164451540608541413 |  |
| `Fw.Gate.edgePair` | agree | 2289432174161615643 | 7120848624855010519 |  |
| `Fw.Gate.seeds` | agree | 14219110928732994938 | 14994619634946746621 |  |
| `Fw.Gate.needed` | agree | 16991297303825032864 | 18431430074930410735 |  |
| `Fw.Gate.greedy` | agree | 16460611792845414594 | 5569313093785742647 |  |
| `Fw.Gate.scopeProbes` | agree | 14219110928732994938 | 14037746764282096685 |  |
| `Fw.Gate.scopeProbes_sub` | agree | 2596595520160455548 | 15634069777605788061 |  |
| `Fw.Gate.deskStop` | agree | 13215252911707847088 | 10934630155337630129 |  |
| `Fw.Gate.touchStop` | agree | 13215252911707847088 | 8249773949877452968 |  |
| `Fw.Gate.phoneStop` | agree | 8239808936255826894 | 12416019773610507411 |  |
| `Fw.Gate.deskSweepWidths` | agree | 403126073 | 17685419164856039344 |  |
| `Fw.Gate.sweeps` | agree | 2369959075150141818 | 5500692938569798307 |  |
| `Fw.Gate.sweeps_reachable` | agree | 13204779708549550526 | 11080185393850965622 |  |
| `Fw.Gate.keyMoves` | agree | 8279740472136292209 | 11762371854983419358 |  |
| `Fw.Gate.scopeSweeps` | agree | 16683140507724882601 | 17547900958467650127 |  |
| `Fw.Gate.scope_covers` | agree | 2734256785770422735 | 17128440888733101845 |  |
| `Fw.Gate.scope_sweeps_covered` | agree | 15763507816639614192 | 6346691640250470344 |  |
| `Fw.Gate.scope_observes_edges` | agree | 6683307426566409572 | 16622346301872691559 |  |
| `Fw.Gate.matrix_some_reachable` | agree | 13305289361614954407 | 8055988138237597549 |  |
| `Fw.Gate.mem_ports` | agree | 6567499579052284792 | 5418674233196702834 |  |
| `Fw.Gate.scope_sound` | agree | 12397250490073128850 | 8618996965993508778 |  |
| `Fw.Gate.scope_union_sound` | agree | 5883846990535893353 | 3169694580590222245 |  |
| `Fw.Gate.ScopeGen.envJson` | agree | 1166953398426433671 | 9998657770299994513 |  |
| `Fw.Gate.ScopeGen.probeIds` | agree | 5114876264563310449 | 16063631436968892213 |  |
| `Fw.Gate.ScopeGen.partJson` | agree | 7119585981829393055 | 11789667303579381407 |  |
| `Fw.Gate.ScopeGen.unionJson` | disagree | 2092839459 | 5805303802412252389 | Math defines only S_∪ and K_∪, not the output, which holds their ids and matches by id. Fix: \operatorname{unionJson}=\{\mathrm{probes}: \operatorname{ids}(S_\cup),\ \mathrm{sweeps}: [\mathrm{id}(w) \mid w \in K_\cup]\}, S_\cup=[p\in M \mid \exists u\in\mathrm{pilot}, q\in S(u): \mathrm{id}(q)=\mathrm{id}(p)], K_\cup likewise |
| `Fw.Gate.ScopeGen.hypothesisText` | disagree | 3265150928 | 12057462172528094828 | 'the text of hypothesis H of Fw.Gate.Scope' is wrong: the string is a separate paraphrase. It leaves out the clamp-in-vw detail and adds 'The full matrix (no --parts) stays the gate of record.' Fix: H = a fixed English string beginning 'H: on a fixed engine port...' and ending with that sentence. |
| `Fw.Gate.ScopeGen.scopeJson` | agree | 2092839459 | 17804515367101031736 |  |
| `Fw.Gate.ScopeGen.scopeText` | agree | 3265150928 | 15257993540773902833 |  |
| `Fw.Gate.ScopeGen.run` | agree | 3653997261 | 2849180156853236915 |  |
| `Fw.Measure.Neutral.Win` | agree | 3931117990 | 9972488223547985835 |  |
| `Fw.Measure.Neutral.eps` | agree | 1901972866 | 11327295598808630221 |  |
| `Fw.Measure.Neutral.lastPreroll` | agree | 1921754875 | 8541532172332169227 |  |
| `Fw.Measure.Neutral.lastFrame` | agree | 2828897928 | 11096628982888123690 |  |
| `Fw.Measure.Neutral.firstAtOrAfter` | agree | 1413513732 | 1213698777244170036 |  |
| `Fw.Measure.Neutral.winOf` | agree | 12197926323331556738 | 10486060656277516586 |  |
| `Fw.Measure.Neutral.N0Event` | agree | 3931117990 | 3736684163821195704 |  |
| `Fw.Measure.Neutral.n0Keys` | agree | 4017531403 | 15204906208001485431 |  |
| `Fw.Measure.Neutral.isCssom` | agree | 1526413716 | 11788870957967857414 |  |
| `Fw.Measure.Neutral.frameCounts` | agree | 11448666195570211865 | 4158399508644663873 |  |
| `Fw.Measure.Neutral.eventsIn` | agree | 3049210346785270596 | 2437401792396670275 |  |
| `Fw.Measure.Neutral.perFrame` | agree | 18043569113889148921 | 10933945771702007216 |  |
| `Fw.Measure.Neutral.N0Win` | agree | 3931117990 | 9572086423725285605 |  |
| `Fw.Measure.Neutral.Verdict` | agree | 3931117990 | 10134481525346432283 |  |
| `Fw.Measure.Neutral.required` | agree | 4017531403 | 7467957985567660663 |  |
| `Fw.Measure.Neutral.recorded` | agree | 2056086338020105899 | 1349713056391549552 |  |
| `Fw.Measure.Neutral.idxFrom` | agree | 6608871024369276538 | 3727825083809956073 |  |
| `Fw.Measure.Neutral.unrecorded` | agree | 17393326932419085748 | 13825625974280612041 |  |
| `Fw.Measure.Neutral.nonzero` | agree | 15429377567042353462 | 3404732600861691746 |  |
| `Fw.Measure.Neutral.verdict` | agree | 677680716645512778 | 9771665464897421407 |  |
| `Fw.Measure.Neutral.firstAtOrAfter_lt` | agree | 2255822047047735476 | 9030489402660745903 |  |
| `Fw.Measure.Neutral.winOf_frame` | agree | 14699643692200560412 | 7103088851684218943 |  |
| `Fw.Measure.Neutral.winOf_nil` | agree | 5441847964076541616 | 206465841768505000 |  |
| `Fw.Measure.Neutral.winOf_load_iff` | agree | 3365930770639935298 | 12695638559555683464 |  |
| `Fw.Measure.Neutral.frameCounts_sum` | agree | 8951240596067823363 | 3972681295265125791 |  |
| `Fw.Measure.Neutral.count_frame_range` | agree | 9935337838917304768 | 15500819891223351309 |  |
| `Fw.Measure.Neutral.n0_conservation` | agree | 605804057128110874 | 14632711178005875878 |  |
| `Fw.Measure.Neutral.idxFrom_eq_nil` | agree | 4794265537847705298 | 12106724629411259460 |  |
| `Fw.Measure.Neutral.Pointwise` | agree | 3937795166 | 18119168167663642687 |  |
| `Fw.Measure.Neutral.Pointwise.imp` | agree | 16998280327090574605 | 12308484801954945222 |  |
| `Fw.Measure.Neutral.idxFrom_congr` | agree | 1142422755963370366 | 10548642844081182689 |  |
| `Fw.Measure.Neutral.any_congr_mem` | agree | 1554462038 | 11250956949039754651 |  |
| `Fw.Measure.Neutral.unrecorded_eq_nil` | agree | 15487986698145318950 | 18174775593538955529 |  |
| `Fw.Measure.Neutral.nonzero_eq_nil` | agree | 8060676006048159738 | 3118945419553935086 |  |
| `Fw.Measure.Neutral.verdict_pass_iff` | agree | 12159231544897897217 | 13234435800448598161 |  |
| `Fw.Measure.Neutral.verdict_load` | agree | 5075774309166667708 | 13874913865454114217 |  |
| `Fw.Measure.Neutral.verdict_svg` | agree | 8723526333422206272 | 11824684393805302502 |  |
| `Fw.Measure.Arms.overlay` | agree | 3265150928 | 1131519277932605907 |  |
| `Fw.Measure.Arms.byDesign` | agree | 797747579 | 4960984655723819046 |  |
| `Fw.Measure.Arms.isByDesign` | agree | 1526413716 | 12312586542532078423 |  |
| `Fw.Measure.Arms.reasonOf` | agree | 1380837422 | 9838929718329009294 |  |
| `Fw.Measure.Arms.Role` | agree | 3931117990 | 11501629338713151445 |  |
| `Fw.Measure.Arms.roleOf` | agree | 6276320302623685512 | 6114165078438622337 |  |
| `Fw.Measure.Arms.gateTypes` | agree | 6417291288919564052 | 12014996775387092532 |  |
| `Fw.Measure.Arms.roleTally` | agree | 11809629388046054528 | 17594498855982010128 |  |
| `Fw.Measure.Arms.levelAt?` | agree | 10422365793732104323 | 13960867877131609470 |  |
| `Fw.Measure.Arms.crossLevel` | agree | 15680162519150529572 | 1096885952375395238 |  |
| `Fw.Measure.Arms.roleOf_byDesign_iff` | agree | 11732348875782154118 | 14489671137046923171 |  |
| `Fw.Measure.Arms.roleOf_gate_iff` | agree | 14405960736293531731 | 16010308821423880359 |  |
| `Fw.Measure.Arms.roleOf_finding_iff` | agree | 15061707682332089279 | 6669208523846178451 |  |
| `Fw.Measure.Arms.mem_gateTypes` | agree | 3292170034297511874 | 13833581441674663527 |  |
| `Fw.Measure.Arms.overlay_not_gate` | agree | 4437695342920076400 | 3425021434840590913 |  |
| `Fw.Measure.Arms.byDesign_split` | agree | 12176458533604295819 | 5474679255660420549 |  |
| `Fw.Measure.Arms.isByDesign_iff_reason` | agree | 12605120809618582311 | 9877279848240382989 |  |
| `Fw.Measure.Arms.roleTally_sum` | agree | 1282554401776405572 | 17529780816022154329 |  |
| `Fw.Measure.Arms.worse_det` | agree | 9344750250560046556 | 8473301761862988660 |  |
| `Fw.Measure.Arms.crossLevel_eq` | agree | 13400404344888830760 | 17843910309015331594 |  |
| `Fw.Measure.Arms.crossLevel_comm` | agree | 17932378072433056508 | 16561159571338274498 |  |
| `Fw.Measure.Arms.crossLevel_one_arm` | agree | 7999315957248505145 | 2637889265472882654 |  |
| `Fw.Measure.Arms.countIn_absent` | agree | 17953404430625376485 | 13939357895619245993 |  |
| `Fw.Measure.Arms.diffFrames_zero` | agree | 7074788425174699131 | 15755989735031571518 |  |
| `Fw.Measure.Arms.classifyU_absent` | agree | 5970050260556622160 | 2791022601823739945 |  |
| `Fw.Measure.Arms.levelAt_tableOf` | agree | 11399849873330017951 | 6735831823085225838 |  |
| `Fw.Measure.Arms.crossLevel_classify` | disagree | 997109006968769150 | 6950227512289456664 | The 'where A_tau = ..., B_tau = ...' clause sits after the $$ block, and the export's math drops it, so A_tau and B_tau are undefined (the r9 layers_additive pattern). Fix: inside the $$ add ',\quad A_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{A}},\ B_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{B}}'. |
| `Fw.Measure.Splits.Split` | agree | 3931117990 | 12191487650830086113 |  |
| `Fw.Measure.Splits.detector` | agree | 3265150928 | 11022125781958404344 |  |
| `Fw.Measure.Splits.svgHost` | agree | 3265150928 | 5728934922960527164 |  |
| `Fw.Measure.Splits.svgKey` | agree | 3265150928 | 17783581537514976779 |  |
| `Fw.Measure.Splits.splits` | agree | 4280965138178098313 | 17388076634546769562 |  |
| `Fw.Measure.Splits.Slice` | agree | 3931117990 | 4234662872027057219 |  |
| `Fw.Measure.Splits.counted` | agree | 1526413716 | 12514682749038691158 |  |
| `Fw.Measure.Splits.outers` | agree | 15361593890648802987 | 1122684978030930704 |  |
| `Fw.Measure.Splits.inside` | agree | 282384931905870383 | 8567140893121352559 |  |
| `Fw.Measure.Splits.typeOf` | agree | 10369431143331302284 | 8954594233462141047 |  |
| `Fw.Measure.Splits.mine` | agree | 278384262104347308 | 13960619484875866414 |  |
| `Fw.Measure.Splits.splitCounts` | agree | 13160102935139664543 | 14482617099614451823 |  |
| `Fw.Measure.Splits.splitTable` | agree | 13413711068514181361 | 5609744232319697611 |  |
| `Fw.Measure.Splits.n1Keys` | agree | 4017531403 | 9845233573470038712 |  |
| `Fw.Measure.Splits.n1Excluded` | agree | 4017531403 | 8623125033964565385 |  |
| `Fw.Measure.Splits.n1Gated` | agree | 4017531403 | 1393130833744202072 |  |
| `Fw.Measure.Splits.inside_ph` | agree | 16520701597466387886 | 13707863529287459662 |  |
| `Fw.Measure.Splits.inside_nil` | agree | 16286352373784499182 | 18143599827407534031 |  |
| `Fw.Measure.Splits.splitCounts_sum` | agree | 6867358078284312730 | 8953076673208357156 |  |
| `Fw.Measure.Splits.splitCounts_no_outer` | agree | 16538923675464497442 | 13648952936923004250 |  |
| `Fw.Measure.Splits.typeOf_key` | agree | 12361948362821007450 | 15545179753521272661 |  |
| `Fw.Measure.Splits.splits_types_nodup` | agree | 17974132453922106468 | 96612330872749929 |  |
| `Fw.Measure.Splits.n1Excluded_eq` | agree | 12155641371004963540 | 3904881260436849419 |  |
| `Fw.Measure.Splits.svg_not_gated` | agree | 2891313174550971654 | 16560845190765651030 |  |
| `Fw.Measure.Splits.n1_net` | agree | 2995920846245523634 | 10561983381168181912 |  |
| `Fw.Measure.Splits.countIn_gated_svg` | agree | 2625640872780484704 | 15882563436278345978 |  |
| `Fw.Measure.obs_le` | agree | 2468621134342217711 | 18172890178111379381 |  |
| `Fw.Measure.classifyAll` | agree | 16067410090206305269 | 8662847514049915829 |  |
| `Fw.Measure.classifyAllU` | agree | 16521735710886973749 | 15502735881771142366 |  |
| `Fw.Measure.classifyAllU_row` | agree | 1948536465565102654 | 17020404322953569475 |  |
| `Fw.Measure.Freeze.levelOf_mono` | agree | 7789742885192530527 | 10910809059405389835 |  |
| `Fw.Measure.Freeze.tableOf` | agree | 6026270764118609014 | 12046252468404757775 |  |
| `Fw.Measure.SelfCheck.check_sound` | agree | 9696374925345326298 | 7715462396168413135 |  |
| `Fw.Measure.Snapshot.layers_additive` | agree | 18198750520460587736 | 15312979963196914044 |  |
