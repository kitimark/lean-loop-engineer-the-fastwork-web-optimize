---
title: Math review round 11 at 3aa3a5b (zone baseline, store.ciRun, where-clauses moved into the math)
date: 2026-10-17
status: CONFIRMED
round: 11
---

# Math review round 11 at 3aa3a5b

Three math-reviewer agents (workflow `review-r11`, read-only) back-translated the 177 pending or stale declarations at
3aa3a5b: zone-baseline-lean (Fw.Measure.ZoneBaseline), store-cirun (Fw.Store.Ci), and the rows where-cleanup changed by
moving where-clauses into their $$ blocks. Method as in rounds 3 to 10; ShadowLint and WhereLint are build errors. The lead wrote this record from the agents' structured verdicts; `stmtHash` and
`mathHash` come from `lake exe mathview` at 3aa3a5b.

## Counts

| Batch | Reviewed | Agree | Disagree |
|---|---|---|---|
| A | 65 | 64 | 1 |
| B | 54 | 53 | 1 |
| C | 58 | 55 | 3 |
| **Total** | 177 | 172 | 5 |

Batch A: Fw.Measure.ZoneBaseline and stale Arms, Parts.Golden, Site. Batch B: Fw.Store.Ci and stale Store, Serve, Board,
Ops, Plan. Batch C: stale Fw.Obs.Health, Gate.*, Console.Alert.
Not returned by an agent, still pending: none.
Fixes for any disagree row go to a lean-prover task (math-r11-fix).

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Measure.ZoneBaseline.sortInts` | agree | 500692100 | 15427253015471892131 |  |
| `Fw.Measure.ZoneBaseline.lo` | agree | 3351561212 | 17979683725000663413 |  |
| `Fw.Measure.ZoneBaseline.hi` | agree | 3351561212 | 5332093301299481655 |  |
| `Fw.Measure.ZoneBaseline.base` | agree | 3351561212 | 14277489955491835337 |  |
| `Fw.Measure.ZoneBaseline.sortInts_pairwise` | agree | 5610008849724736989 | 18399018681906909457 |  |
| `Fw.Measure.ZoneBaseline.sortInts_perm` | agree | 7694553201809316093 | 16192829815070051352 |  |
| `Fw.Measure.ZoneBaseline.sortInts_eq_of_perm` | agree | 12836837341774181511 | 9665795953127663804 |  |
| `Fw.Measure.ZoneBaseline.headD_rel` | agree | 1715080305 | 7977732867321441229 |  |
| `Fw.Measure.ZoneBaseline.lo_le` | agree | 572995281146252433 | 15180603427156415446 |  |
| `Fw.Measure.ZoneBaseline.le_hi` | agree | 17684737712316365430 | 17396422054535222502 |  |
| `Fw.Measure.ZoneBaseline.headD_mem` | agree | 4086906642 | 14962453850440857427 |  |
| `Fw.Measure.ZoneBaseline.lo_mem` | agree | 5969358119147985591 | 8468556876751173483 |  |
| `Fw.Measure.ZoneBaseline.hi_mem` | agree | 18277453429577485142 | 12651226324262305233 |  |
| `Fw.Measure.ZoneBaseline.base_mem` | agree | 7815221052397133560 | 8449156104565043089 |  |
| `Fw.Measure.ZoneBaseline.lo_le_base` | agree | 12114641151163374990 | 8727716836585140290 |  |
| `Fw.Measure.ZoneBaseline.base_le_hi` | agree | 16323716786475029558 | 15987743382025737521 |  |
| `Fw.Measure.ZoneBaseline.lo_eq_hi_iff` | agree | 828188589530161544 | 3677477466684910461 |  |
| `Fw.Measure.ZoneBaseline.stats_perm` | agree | 6291898867255151683 | 8193927925270806345 |  |
| `Fw.Measure.ZoneBaseline.ZRun` | agree | 3931117990 | 16667826413266794604 |  |
| `Fw.Measure.ZoneBaseline.shape` | agree | 9900654969846731259 | 16295125312191706713 |  |
| `Fw.Measure.ZoneBaseline.Uniform` | agree | 1656664093363505549 | 8309047425388911801 |  |
| `Fw.Measure.ZoneBaseline.vals` | agree | 243044613811986766 | 2350681371498123185 |  |
| `Fw.Measure.ZoneBaseline.total` | agree | 13373192800844073947 | 4324315242639743730 |  |
| `Fw.Measure.ZoneBaseline.totalVals` | agree | 8338723646407520935 | 18384929651465782264 |  |
| `Fw.Measure.ZoneBaseline.sumsAt` | agree | 16079870375740477824 | 9553728954106469843 |  |
| `Fw.Measure.ZoneBaseline.zoneTypes` | agree | 421478526699068518 | 7529547035211331798 |  |
| `Fw.Measure.ZoneBaseline.allTypes` | agree | 4082052711710653486 | 6479340008967664638 |  |
| `Fw.Measure.ZoneBaseline.ids` | agree | 4082052711710653486 | 3562074321554076785 |  |
| `Fw.Measure.ZoneBaseline.Row` | agree | 3931117990 | 1533501108739537567 |  |
| `Fw.Measure.ZoneBaseline.row` | agree | 4489654538346057492 | 3360587603975003850 |  |
| `Fw.Measure.ZoneBaseline.Row.summary` | agree | 4553604185936793810 | 15977383899372033566 |  |
| `Fw.Measure.ZoneBaseline.isDet` | agree | 16966404901932839320 | 11091365941008527456 |  |
| `Fw.Measure.ZoneBaseline.drifts` | agree | 2879880948490508158 | 11332891965902104948 |  |
| `Fw.Measure.ZoneBaseline.zoneRows` | agree | 16413430456983044032 | 8756008779496045267 |  |
| `Fw.Measure.ZoneBaseline.totalRows` | agree | 15864801230702916988 | 3643121347583745798 |  |
| `Fw.Measure.ZoneBaseline.Baseline` | agree | 3931117990 | 16187635432396596521 |  |
| `Fw.Measure.ZoneBaseline.baseline` | agree | 4259188633739803217 | 8555931282971585001 |  |
| `Fw.Measure.ZoneBaseline.refusal` | disagree | 9797620571894752711 | 17038213827618571500 | The math only says when refusal = ⊥ (that is refusal_none plus its converse). It gives no message and no check order, so the value is unknown when it refuses (r4/r8 problems pattern). Fix: write first-match cases for R=r::R': \|R\|<3 → 'need at least three runs'; ids not distinct → 'run ids must be distinct'; zoneIds(r) not distinct → 'run r.id: a zone id occurs twice'; first r'∈R' with differing shapes → 'run r'.id: zone structure … differs from run r.id'; else ⊥. |
| `Fw.Measure.ZoneBaseline.zoneBaseline` | agree | 4892614759615569847 | 1851571499096736798 |  |
| `Fw.Measure.ZoneBaseline.refusal_none` | agree | 4658022731871848362 | 16007912910415636710 |  |
| `Fw.Measure.ZoneBaseline.zoneBaseline_ok` | agree | 492832024314068105 | 5074678757065799671 |  |
| `Fw.Measure.ZoneBaseline.mem_detDrift` | agree | 14087199963514701966 | 15015244269610247920 |  |
| `Fw.Measure.ZoneBaseline.det_lo_eq_hi_or_drift` | agree | 12243941428525619425 | 8047979725778964972 |  |
| `Fw.Measure.ZoneBaseline.det_total_lo_eq_hi_or_drift` | agree | 1012264541352751063 | 10831154977263698115 |  |
| `Fw.Measure.ZoneBaseline.lo_eq_hi_of_const` | agree | 9059016164047082018 | 12169773127266118219 |  |
| `Fw.Measure.ZoneBaseline.detDrift_nil_of_equal` | agree | 6421707666485113674 | 12420005315806652718 |  |
| `Fw.Measure.ZoneBaseline.sumBy_sumAt_ids` | agree | 9678233149479409333 | 3499262962438999124 |  |
| `Fw.Measure.ZoneBaseline.zoneIds_eq_ids` | agree | 10193094089668046973 | 11354846513291119454 |  |
| `Fw.Measure.ZoneBaseline.totals_eq_sum_zones` | agree | 4777357224622221743 | 135749551790403111 |  |
| `Fw.Measure.ZoneBaseline.total_zoneSums` | agree | 9429445574964050639 | 13611713333335546271 |  |
| `Fw.Measure.ZoneBaseline.mem_keysOf` | agree | 18006694555409454486 | 1416182049482884455 |  |
| `Fw.Measure.ZoneBaseline.mem_keysOf_perm` | agree | 1450006283572228552 | 1734979821828934494 |  |
| `Fw.Measure.ZoneBaseline.vals_eq_zero_of_not_mem` | agree | 14599925272392061992 | 16600601510619597224 |  |
| `Fw.Measure.ZoneBaseline.cellAt` | agree | 4201487070523348952 | 9145142873863022455 |  |
| `Fw.Measure.ZoneBaseline.totalAt` | agree | 11595863144782403103 | 14203865667667033952 |  |
| `Fw.Measure.ZoneBaseline.find?_beq` | agree | 1110523218 | 16695270615568041097 |  |
| `Fw.Measure.ZoneBaseline.cellAt_baseline` | agree | 13810448748802949187 | 12959210341518394655 |  |
| `Fw.Measure.ZoneBaseline.totalAt_baseline` | agree | 3589798262726792668 | 5939023788962945564 |  |
| `Fw.Measure.ZoneBaseline.summary_row_perm` | agree | 3310837817995224677 | 16841096662388913779 |  |
| `Fw.Measure.ZoneBaseline.ids_perm` | agree | 18196429908798114285 | 1221010440464208608 |  |
| `Fw.Measure.ZoneBaseline.baseline_perm` | agree | 2936917319507729839 | 2210979473301755932 |  |
| `Fw.Measure.Arms.crossLevel_classify` | agree | 997109006968769150 | 11340134460225823136 |  |
| `Fw.Parts.Golden.decimal?` | agree | 2024033954 | 5985803185150553101 |  |
| `Fw.Site.Breakpoints.catalogue_css` | agree | 8822227599840045762 | 15152776649434809439 |  |
| `Fw.Site.Breakpoints.matrix_ids_nodup` | agree | 5984117894114421953 | 12995577999100422570 |  |
| `Fw.Store.CiJob` | agree | 3931117990 | 4586865075945098819 |  |
| `Fw.Store.CiRun` | agree | 3931117990 | 17198641461545813001 |  |
| `Fw.Store.ciWorkflow` | agree | 3265150928 | 1186741270363023583 |  |
| `Fw.Store.Shard` | agree | 3931117990 | 41074479600142436 |  |
| `Fw.Store.Shard.artifact` | agree | 3522978568876931474 | 17230830517953330553 |  |
| `Fw.Store.Shard.dir` | agree | 3522978568876931474 | 251170181106054200 |  |
| `Fw.Store.isDigits` | agree | 1526413716 | 16720294458773557872 |  |
| `Fw.Store.shardOfJob` | agree | 10740618435833041861 | 8676470468167692013 |  |
| `Fw.Store.shardJobs` | agree | 7086921942435628396 | 316958494005473339 |  |
| `Fw.Store.orElse` | agree | 355955788 | 6477589933076671013 |  |
| `Fw.Store.runRefusals` | agree | 14392677923040597651 | 16138547884225065192 |  |
| `Fw.Store.ShardFacts` | agree | 3931117990 | 4237760273816522720 |  |
| `Fw.Store.Got` | agree | 3931117990 | 5325798780837514511 |  |
| `Fw.Store.factOf` | agree | 17619792069488334036 | 1937551827917102634 |  |
| `Fw.Store.jobRefusals` | agree | 17513684717075603458 | 1685514814333692253 |  |
| `Fw.Store.ciTargets` | agree | 2494334935530589452 | 11819413387270290896 |  |
| `Fw.Store.shardsOf` | agree | 421257418198141944 | 16245198936062589270 |  |
| `Fw.Store.factsOf` | agree | 10481362027392136547 | 7810579764990197056 |  |
| `Fw.Store.agrees` | agree | 10051070994308964583 | 17050866224531002220 |  |
| `Fw.Store.gotRefusals` | agree | 17113217539073734177 | 12030567307844286104 |  |
| `Fw.Store.ciRefusals` | agree | 17513684717075603458 | 18180141329278918007 |  |
| `Fw.Store.queryParams` | agree | 1401068528 | 11353374641041741143 |  |
| `Fw.Store.queryGet` | agree | 361667379 | 8569752196824255003 |  |
| `Fw.Store.flagOf` | agree | 4081869951 | 10689167793834691459 |  |
| `Fw.Store.searchConfig` | agree | 2112531760 | 17816869015890427082 |  |
| `Fw.Store.ciReq` | agree | 4911955817551939128 | 5811737681087160052 |  |
| `Fw.Store.CiTarget` | agree | 3931117990 | 8754095008862440004 |  |
| `Fw.Store.ciTarget` | agree | 13917584327225101188 | 15181874738355204729 |  |
| `Fw.Store.CiResult` | agree | 3931117990 | 10158529472531086485 |  |
| `Fw.Store.ciRun` | agree | 15519377299566593310 | 17386852383445600721 |  |
| `Fw.Store.ciRun_refused` | agree | 15717467943750616430 | 13549129768379225308 |  |
| `Fw.Store.ciRun_accepted_targets` | agree | 766757621429138037 | 14315105415030583512 |  |
| `Fw.Store.ciRun_accepted_run` | agree | 2615441273946550148 | 12763174278481777028 |  |
| `Fw.Store.mem_shardsOf` | agree | 6277170592103052614 | 5446095951523373413 |  |
| `Fw.Store.shardsOf_of_job` | agree | 17214083137143328376 | 14139340921209760989 |  |
| `Fw.Store.ciRun_accepted_got` | agree | 1219175970559087263 | 9917949442054797136 |  |
| `Fw.Store.ciRun_accepted_req` | agree | 7114199296833403331 | 17481455795362063871 |  |
| `Fw.Store.ciTargets_nodup` | agree | 11831219074352746190 | 10536149737533610998 |  |
| `Fw.Store.ciRun_targets_nodup` | agree | 11628576629700080111 | 9781914371381916234 |  |
| `Fw.Store.ciRun_shard_target` | agree | 1301417605922586270 | 8645152818205593607 |  |
| `Fw.Store.ciRun_req_target` | agree | 17935329616567849650 | 489930849162841664 |  |
| `Fw.Store.ciRun_key_ne` | agree | 1235985763962394250 | 12072277727304128062 |  |
| `Fw.Store.ciRun_keys_nodup` | agree | 16202621155693338994 | 17933600082147334751 |  |
| `Fw.Store.Manifest.problems` | agree | 15787804681029681817 | 7622985838642787240 |  |
| `Fw.Store.jobsFor` | agree | 4603948912347364288 | 3906296386620610535 |  |
| `Fw.Store.plan_engines` | agree | 17609501204378172698 | 12613677258131911648 |  |
| `Fw.Store.obsOf` | agree | 6269551216281122112 | 3076592676633303110 |  |
| `Fw.Store.reduceOk_sound` | agree | 18284368218795928819 | 8699926276474781402 |  |
| `Fw.Serve.touched` | disagree | 11227471014940213338 | 7589326655140360452 | The moved where-clause has a LaTeX error: '\text{ if none)},\\lfloor x \rfloor = [x]' puts a row break (\\) before the text 'lfloor', so the floor definition renders as broken text. Fix: '\text{ if none)},\ \lfloor x \rfloor = [x],\ \lfloor \bot \rfloor = [\,]'. The cases themselves match the Lean. |
| `Fw.Serve.fastRow` | agree | 17560804047737547872 | 5350589090280357091 |  |
| `Fw.Console.boardCard` | agree | 5498730827532609432 | 1950104207246497252 |  |
| `Fw.Ops.Identity.isReviewRole` | agree | 1526413716 | 2820399321683121194 |  |
| `Fw.Ops.Obs.obsKey` | agree | 3653987902 | 17264663750859767251 |  |
| `Fw.Plan.Trailer.trailers` | agree | 1961493383 | 3820458681579397744 |  |
| `Fw.Obs.Health.Proc` | agree | 3931117990 | 15854379351349474363 |  |
| `Fw.Obs.Health.agentAlerts` | agree | 12005986194624880873 | 9360505767570785766 |  |
| `Fw.Obs.Health.goneAlert` | agree | 17427087172529382459 | 5228912427894882161 |  |
| `Fw.Obs.Health.agentAll` | agree | 17427087172529382459 | 9511372181886415066 |  |
| `Fw.Obs.Health.gone_alerts` | agree | 5550276840580461133 | 362474756766694520 |  |
| `Fw.Obs.Health.goneAlert_iff` | agree | 5505448028364397305 | 12970407564178733194 |  |
| `Fw.Obs.Health.declaredB` | agree | 15995485918808521771 | 11651992961460587090 |  |
| `Fw.Obs.Health.procLongB` | agree | 17100533617391071586 | 7143986890186268411 |  |
| `Fw.Obs.Health.sOver` | agree | 14374870197216445338 | 12966150728956124 |  |
| `Fw.Obs.Health.sDisk` | agree | 14374870197216445338 | 8110990058409023356 |  |
| `Fw.Obs.Health.sMem` | agree | 4796439020672042040 | 5976564902315448921 |  |
| `Fw.Obs.Health.sLoad` | agree | 14374870197216445338 | 7538288736390674137 |  |
| `Fw.Obs.Health.sLockLong` | agree | 14374870197216445338 | 362834770661070847 |  |
| `Fw.Obs.Health.sOrphan` | agree | 14374870197216445338 | 3776646869377881056 |  |
| `Fw.Obs.Health.sCiFailed` | agree | 4796439020672042040 | 9943903991102098428 |  |
| `Fw.Obs.Health.sCiSlow` | agree | 14374870197216445338 | 10300616055072301066 |  |
| `Fw.Obs.Health.sCiFin` | agree | 14374870197216445338 | 7367276893057933490 |  |
| `Fw.Obs.Health.sDocker` | agree | 14374870197216445338 | 3179016733581253576 |  |
| `Fw.Obs.Health.procAlert` | agree | 9536340134237720430 | 16614887165163332877 |  |
| `Fw.Obs.Health.sProc` | agree | 14374870197216445338 | 4926157149240105936 |  |
| `Fw.Obs.Health.sWt` | agree | 14374870197216445338 | 6518070325881719471 |  |
| `Fw.Obs.Health.sPerm` | agree | 4796439020672042040 | 5033599249547538807 |  |
| `Fw.Obs.Health.health` | agree | 3078395100424359978 | 11076270097308816810 |  |
| `Fw.Obs.Health.agent_alert_live` | agree | 16399334639487768597 | 17288747780659679790 |  |
| `Fw.Obs.Health.lockOrphan_iff` | agree | 455890709255593875 | 6347361942316636268 |  |
| `Fw.Obs.Health.permissionWait_iff` | agree | 9905905581898126217 | 14634018850721075131 |  |
| `Fw.Obs.Health.loadHigh_iff` | agree | 14138485613268492395 | 4595383696662746244 |  |
| `Fw.Obs.Health.ciSlow_raised` | agree | 1941105867335715353 | 12397596282171794487 |  |
| `Fw.Obs.Health.procLong_iff` | agree | 763493244842200275 | 6725513079877011960 |  |
| `Fw.Obs.Health.ownerLive_quiet` | agree | 15761471956408225223 | 12279086931579697256 |  |
| `Fw.Obs.Health.declared_quiet` | agree | 18024456028796553106 | 13224274503060240086 |  |
| `Fw.Obs.Health.procLong_sound` | agree | 7609572009534865790 | 15187846142662956990 |  |
| `Fw.Obs.Health.orphan_raised` | agree | 10603293156440087055 | 4204060863739491012 |  |
| `Fw.Obs.Health.sysAlerts_perm` | agree | 11723544825120768585 | 11697426936849834265 |  |
| `Fw.Obs.Health.health_perm` | agree | 11557858786435538839 | 8948984543263823131 |  |
| `Fw.Obs.Health.counts_total` | agree | 8238879045004597772 | 10811731027631512424 |  |
| `Fw.Gate.skipNames` | agree | 11555861478417778681 | 10886274698235649507 |  |
| `Fw.Gate.itemAt` | agree | 2446168784246779235 | 2453447553794262804 |  |
| `Fw.Gate.roleItems` | agree | 12342393303111460954 | 9950893401967961819 |  |
| `Fw.Gate.partItems` | agree | 15031121831213897308 | 17149593978116609663 |  |
| `Fw.Gate.partVerdict_pass_iff` | disagree | 1814917220899672640 | 4588341614704271988 | The left side '\operatorname{partVerdict} = \mathrm{pass}' leaves out all five arguments. Fix: \operatorname{partVerdict}(A, \mathit{spec}, o, r, \mathit{props}) = \mathrm{pass} \iff ... |
| `Fw.Gate.pairs_congr` | disagree | 3734124891185895049 | 7772170095064497693 | h_1(xs), h_2(ys) apply an Item→Item function to a list; the Lean maps it over each element (xs.map h₁). Fix: \operatorname{pairs}(f, i, \operatorname{map}(h_1, xs), \operatorname{map}(h_2, ys)), or [h_1(x) \| x ∈ xs]. |
| `Fw.Gate.itemAt_congr` | agree | 17321295562065302563 | 10305757730632902854 |  |
| `Fw.Gate.partVerdict_setStyle` | agree | 13237576824762848685 | 17530040002760049312 |  |
| `Fw.Gate.envChecks` | agree | 244413007985771538 | 5153794857539173277 |  |
| `Fw.Gate.truthKey` | disagree | 8520712792063237529 | 4291149294003350348 | r_k, e_k, ℓ^o_k, ℓ^r_k are undefined, and 'a = x' merges absent with null (TVal=(B_⊥)_⊥): Lean a=some x≠⊥, b=lookup(r.T,k). Item fields left out. Fix: define a=⌈x⌉, b=r.T[k], e_k=m[k], ℓ^o_k=oLegacy[k], ℓ^r_k=r.legacy[k] (⊥=absent); items ar,lean,legacy; expect ⊥,e_k/null,null. |
| `Fw.Gate.stateParts` | agree | 9570663333227417342 | 1727567234147884605 |  |
| `Fw.Gate.evalState` | agree | 7578581819863067945 | 782753144242278674 |  |
| `Fw.Gate.evalState_pass_iff` | agree | 9928472884915646864 | 3504390954707519951 |  |
| `Fw.Gate.stale` | agree | 14469740175532349809 | 8371745112515336477 |  |
| `Fw.Console.Alert.attrib` | agree | 14553851645859233164 | 6055867789368103968 |  |
| `Fw.Console.Alert.title` | agree | 14957312256939327105 | 2853389097361143228 |  |
| `Fw.Console.Alert.act` | agree | 4609870720942665069 | 4546275482535236998 |  |
| `Fw.Gate.unsignedNum` | agree | 450868400 | 9640753599480559311 |  |
| `Fw.Gate.styleValueEq` | agree | 2494698578 | 15247566688675422623 |  |
| `Fw.Gate.ScopeGen.unionJson` | agree | 2092839459 | 2797834986806879267 |  |
| `Fw.Gate.ScopeGen.hypothesisText` | agree | 3265150928 | 3786470143752190081 |  |
| `Fw.Gate.pilotParts` | agree | 13871602926479079190 | 16688107141703883386 |  |
