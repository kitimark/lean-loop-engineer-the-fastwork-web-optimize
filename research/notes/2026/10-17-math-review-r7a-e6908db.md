---
title: Math review round 7a at e6908db (Fw/Plan, Fw/Measure SelfCheck and Snapshot, stale Serve and Board, Admit.Inv, Ops.Identity)
date: 2026-10-17
status: CONFIRMED
round: 7
---

# Math review round 7a at e6908db

Two math-reviewer agents (workflow `math-review-r7a`, read-only) back-translated the 234 pending or stale declarations
in modules that no running task was changing. Fw.Obs, Fw.Gate and Fw.Console rows wait for watch-fix,
gate-unreachable and lean-console-gaps (round 7b). Method as in rounds 3 to 6. The lead wrote this record from the
agents' structured verdicts; `stmtHash` and `mathHash` come from `lake exe mathview` at e6908db (cache key ff5b9f9cb0611ae7).

## Counts

| Batch | Reviewed | Agree | Disagree |
|---|---|---|---|
| A | 119 | 114 | 5 |
| B | 115 | 100 | 15 |
| **Total** | 234 | 214 | 20 |

Batch A: Fw.Plan.Core and Fw.Plan.Graph. Batch B: Fw.Measure.SelfCheck and Snapshot, stale Fw.Serve and Fw.Board,
Fw.Sched.Admit.Inv (round-6 disagree, now agree), Fw.Ops.Identity. Patterns: arguments left out where the Lean fixes
them (ts, pi.tasks), free variables the Lean quantifies, set-builder counts for list-filter lengths, undefined symbols.
Fixes: Plan and Console rows in lean-console-gaps, Measure rows in pixel-tolerance.

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Plan.Def` | agree | 3931117990 | 3460815774983122456 |  |
| `Fw.Plan.Cmd` | agree | 3931117990 | 10042843844827538590 |  |
| `Fw.Plan.CmdType` | agree | 3931117990 | 16871724651368308215 |  |
| `Fw.Plan.CmdType.name` | agree | 3618243253790239463 | 6871682899799139886 |  |
| `Fw.Plan.Cmd.type` | agree | 13281550437315500015 | 17755278074212884326 |  |
| `Fw.Plan.Milestone` | agree | 3931117990 | 5647673992546215691 |  |
| `Fw.Plan.State` | agree | 3931117990 | 17211272150953038473 |  |
| `Fw.Plan.Def.row` | agree | 17962901670393362340 | 3512257505870864995 |  |
| `Fw.Plan.setRow` | agree | 1257654101191615203 | 13829061356259054965 |  |
| `Fw.Plan.upsert` | agree | 4595697726034664302 | 3663773288411081731 |  |
| `Fw.Plan.isDone` | agree | 9294840217181749092 | 6065355511412186149 |  |
| `Fw.Plan.check` | disagree | 594116433317874102 | 12432011450203152640 | drop/claim/done rows use 'x \notin \operatorname{ids}', '\operatorname{isDone}(x)' and 'the first undone t' with no list. Lean uses π.tasks. Fix: x \notin \operatorname{ids}(\pi.\mathit{tasks}), \operatorname{isDone}(\pi.\mathit{tasks}, x), 'the first t \in \pi.\mathit{tasks} with t.\mathit{evidence}=\bot \land x \in t.\mathit{deps}'. |
| `Fw.Plan.exec` | agree | 14213102090100649495 | 10390197625985480750 |  |
| `Fw.Plan.step` | agree | 14213102090100649495 | 6842435670753017754 |  |
| `Fw.Plan.run` | agree | 16270088217053026563 | 2127767599999522173 |  |
| `Fw.Plan.TState` | agree | 3931117990 | 6895059093220267822 |  |
| `Fw.Plan.TState.name` | agree | 14018970435036265245 | 15258883709531425327 |  |
| `Fw.Plan.blockers` | agree | 803562344829617287 | 8299014187350000785 |  |
| `Fw.Plan.tstate` | agree | 15481984326847501693 | 12655532922282393971 |  |
| `Fw.Plan.isDone_iff` | agree | 14019427333556245700 | 14216831944118584808 |  |
| `Fw.Plan.mem_blockers` | agree | 6877004790457152280 | 18163570994789396257 |  |
| `Fw.Plan.tstate_ready_iff` | agree | 17980142580395382324 | 12353791463842010112 |  |
| `Fw.Plan.tstate_blocked` | agree | 14573683710110302047 | 9549000542077606974 |  |
| `Fw.Plan.tstate_done_iff` | agree | 18261168972740496691 | 15445646326707305969 |  |
| `Fw.Plan.tstate_running_iff` | agree | 12780298478804618356 | 2673348148486416438 |  |
| `Fw.Plan.row_unique` | agree | 1200499574124786276 | 11325543686716239944 |  |
| `Fw.Plan.ready_indep` | agree | 17462263828915014548 | 6396968944972953432 |  |
| `Fw.Plan.Inv` | agree | 4453979846798335996 | 616154249138935346 |  |
| `Fw.Plan.ids_setRow` | agree | 6123388880629306667 | 15693514251008254164 |  |
| `Fw.Plan.dep_setRow` | agree | 10708327722324437248 | 10303769782074036632 |  |
| `Fw.Plan.upsert_nodup` | agree | 2271158574770869443 | 769709839245212400 |  |
| `Fw.Plan.define_acyclic` | agree | 4241750209036292680 | 695322795310541659 |  |
| `Fw.Plan.define_cycle_refused` | agree | 1999874450295106926 | 10131630626422507113 |  |
| `Fw.Plan.exec_inv` | agree | 3500453041833756073 | 10556293965022534872 |  |
| `Fw.Plan.inv_init` | agree | 2260259849017163001 | 12233699516604917247 |  |
| `Fw.Plan.step_inv` | agree | 13919589364643472207 | 8314507183400226487 |  |
| `Fw.Plan.foldl_inv` | agree | 4601359386097851946 | 9028711255468991867 |  |
| `Fw.Plan.run_inv` | agree | 14048837206352897675 | 4875649053188821896 |  |
| `Fw.Plan.isDone_setRow` | agree | 14271090276098038256 | 14992017113664696261 |  |
| `Fw.Plan.exec_isDone` | agree | 4603963723118972989 | 18325737675098073405 |  |
| `Fw.Plan.step_isDone` | agree | 10241176956679880430 | 10564947597880255517 |  |
| `Fw.Plan.ok` | agree | 17148301413588112250 | 13928535934804899225 |  |
| `Fw.Plan.fits` | agree | 4003850771630345855 | 9936397260051314454 |  |
| `Fw.Plan.place` | agree | 2165834526198355559 | 11634387155126042636 |  |
| `Fw.Plan.readyRows` | agree | 6059138189471357247 | 13658038763366670377 |  |
| `Fw.Plan.groups` | agree | 4814894817033107558 | 5447479398735925392 |  |
| `Fw.Plan.fits_iff` | agree | 6245925856490521057 | 2891713481440068918 |  |
| `Fw.Plan.place_pairwise` | agree | 10861931799458815063 | 2631476343031086124 |  |
| `Fw.Plan.place_perm` | agree | 16393288913591435716 | 7847851030267220199 |  |
| `Fw.Plan.foldl_place` | agree | 7905045566739431708 | 7537334081021455416 |  |
| `Fw.Plan.groups_pairwise` | agree | 1552851911435490059 | 14831202420501564556 |  |
| `Fw.Plan.groups_perm` | agree | 17175071114941877796 | 3977301655602064221 |  |
| `Fw.Plan.TaskView` | agree | 3931117990 | 14767951854537099376 |  |
| `Fw.Plan.MilestoneView` | agree | 3931117990 | 9202187004141460102 |  |
| `Fw.Plan.View` | agree | 3931117990 | 7829535079319351158 |  |
| `Fw.Plan.taskView` | agree | 8172441234583205985 | 2769814911915118433 |  |
| `Fw.Plan.msView` | disagree | 3665224364769316189 | 13116106887302350707 | The counts are written \|\{t \in ts : ...\}\| (a set), but the Lean takes the length of a list filter, so repeated rows are counted each time. Fix: \|[\, t \in ts : t.\mathit{milestone} = m.\mathit{id} \land t.\mathit{evidence} \ne \bot \,]\| and \|[\, t \in ts : t.\mathit{milestone} = m.\mathit{id} \,]\|. |
| `Fw.Plan.view` | disagree | 8606534878737370153 | 4998745115463088429 | '[\operatorname{taskView}(t)]_{t}' and '[\operatorname{msView}(m)]_{m}' give no domain and drop the ts argument. Fix: [\operatorname{taskView}(\pi.\mathit{tasks}, t) : t \in \pi.\mathit{tasks}], [\operatorname{msView}(\pi.\mathit{tasks}, m) : m \in \pi.\mathit{milestones}]. |
| `Fw.Plan.msView_done_le` | agree | 15548010537964974634 | 12049059075851704448 |  |
| `Fw.Plan.view_criticalPath` | disagree | 4674057372163889314 | 8500382851388501289 | UChain is used with no graph, but it is defined as UChain_{ts}, and the Lean uses π.tasks. Fix: \operatorname{UChain}_{\pi.\mathit{tasks}}(\operatorname{view}(\pi).\mathit{criticalPath}) \land \forall l:\ \operatorname{UChain}_{\pi.\mathit{tasks}}(l) \Rightarrow \|l\| \le \|\operatorname{view}(\pi).\mathit{criticalPath}\|. |
| `Fw.Plan.mk` | agree | 11650877355630277991 | 11620394579320208683 |  |
| `Fw.Plan.Task` | agree | 3931117990 | 15996057861111387920 |  |
| `Fw.Plan.ids` | agree | 16286443710977984750 | 17007958738790584485 |  |
| `Fw.Plan.Dep` | agree | 8818866048216191506 | 13102291966663791179 |  |
| `Fw.Plan.Acyclic` | agree | 12837587544921677794 | 17112914266463920932 |  |
| `Fw.Plan.tg_first` | agree | 47659031 | 14425746117546734839 |  |
| `Fw.Plan.tg_mono` | agree | 1136207832 | 8503707544094577914 |  |
| `Fw.Plan.tg_flip` | agree | 178187014 | 16478245962982631094 |  |
| `Fw.Plan.Chain` | agree | 3909927719 | 16995976317147719274 |  |
| `Fw.Plan.chain_tg` | agree | 621992330702169352 | 13404408746436549208 |  |
| `Fw.Plan.chain_nodup` | agree | 17971190296131991055 | 586129817827703027 |  |
| `Fw.Plan.stuck_chain` | agree | 7726274480375023066 | 12026938350418436405 |  |
| `Fw.Plan.stuck_cycle` | agree | 73556588 | 16138428741962338443 |  |
| `Fw.Plan.succ` | agree | 10942027998628807112 | 2212501180651920715 |  |
| `Fw.Plan.mem_succ` | agree | 856209785513027908 | 5754992580361856547 |  |
| `Fw.Plan.free` | agree | 9294840217181749092 | 4113356972945738122 |  |
| `Fw.Plan.kahn` | agree | 3713993939575875982 | 6679761122662896108 |  |
| `Fw.Plan.acyclicB` | agree | 12660393424833114677 | 13263456903362928677 |  |
| `Fw.Plan.dep_src` | agree | 8055824708624102504 | 7121799231157225834 |  |
| `Fw.Plan.dep_filter` | agree | 13400556110514094915 | 4603908970191706368 |  |
| `Fw.Plan.dep_keep` | agree | 1858083190252919417 | 2318561579369206735 |  |
| `Fw.Plan.free_no_edge` | agree | 2470562166036377431 | 16071857115912335412 |  |
| `Fw.Plan.cycle_survives` | agree | 5129427456177417101 | 9752847374284077195 |  |
| `Fw.Plan.kahn_sound` | agree | 8963957767763130207 | 11096552551474017104 |  |
| `Fw.Plan.kahn_complete` | agree | 10084707084366114515 | 6515770091615495471 |  |
| `Fw.Plan.acyclicB_iff` | agree | 2659934962005025333 | 11571509173871319250 |  |
| `Fw.Plan.undone` | agree | 6059138189471357247 | 2168326551992956458 |  |
| `Fw.Plan.uids` | agree | 16286443710977984750 | 16828877150317620057 |  |
| `Fw.Plan.Next` | agree | 8818866048216191506 | 7425249098017985129 |  |
| `Fw.Plan.UChain` | agree | 16700541711297375655 | 1772397739827542206 |  |
| `Fw.Plan.dependents` | agree | 10942027998628807112 | 10395049601097556874 |  |
| `Fw.Plan.mem_dependents` | agree | 5241395742552081579 | 6053763249363726786 |  |
| `Fw.Plan.next_uid` | agree | 12929237184954646311 | 14945522867991850669 |  |
| `Fw.Plan.best` | agree | 2152285327 | 10921830637927507726 |  |
| `Fw.Plan.best_cases` | agree | 5811489044241737121 | 17555739066382893573 |  |
| `Fw.Plan.le_best` | agree | 8478115714940701543 | 12105489818516147928 |  |
| `Fw.Plan.look` | agree | 367951578 | 10312313601355884024 |  |
| `Fw.Plan.look_map` | agree | 3248029354243637122 | 7570140160938846098 |  |
| `Fw.Plan.tab` | disagree | 10056531092951660662 | 10792023262924991894 | ts never appears: T_k, 'uids' and 'dependents(x)' have no argument, but the Lean is tab ts k over uids(ts) and dependents_{ts}(x). Fix: T^{ts}_0 = [(x,[x]) : x \in \operatorname{uids}(ts)], T^{ts}_{k+1} = [(x, x :: \operatorname{best}([\operatorname{look}(T^{ts}_k, y) : y \in \operatorname{dependents}_{ts}(x)])) : x \in \operatorname{uids}(ts)]. |
| `Fw.Plan.cpf` | agree | 18349627095398630629 | 1875578296616469223 |  |
| `Fw.Plan.criticalPath` | agree | 16286443710977984750 | 15880472212093362821 |  |
| `Fw.Plan.cpf_zero` | agree | 3345780061248996598 | 5038927989812489339 |  |
| `Fw.Plan.cpf_succ` | agree | 8870776279697327459 | 5027569231515975800 |  |
| `Fw.Plan.cpf_chain` | agree | 3607950455674057310 | 9555194504368458199 |  |
| `Fw.Plan.cpf_long` | agree | 13488018766326311962 | 3778022177012674813 |  |
| `Fw.Plan.criticalPath_chain` | agree | 15422038572599728967 | 3426866277653834932 |  |
| `Fw.Plan.next_acyclic` | agree | 5122866217983121122 | 14470217793511832688 |  |
| `Fw.Plan.criticalPath_longest` | agree | 9450851796581591839 | 12825390292058226170 |  |
| `Fw.Plan.segs` | agree | 1961493383 | 15795469220787388396 |  |
| `Fw.Plan.wild` | agree | 1526413716 | 6966379087178623654 |  |
| `Fw.Plan.segOv` | agree | 2423821251 | 14543477393123606606 |  |
| `Fw.Plan.globOv` | agree | 2820148121 | 11616872048634907502 |  |
| `Fw.Plan.gm` | agree | 1762791200 | 17969223778635204007 |  |
| `Fw.Plan.globOv_sound` | agree | 16469204427636240300 | 3418825621863640355 |  |
| `Fw.Plan.globOv_literal` | agree | 4874634883000571415 | 14478475582881008364 |  |
| `Fw.Plan.wconf` | agree | 15155811874404257103 | 584813443704038372 |  |
| `Fw.Plan.dconf` | agree | 15155811874404257103 | 4012717194110817021 |  |
| `Fw.Plan.conflict` | agree | 15155811874404257103 | 4449713241740775665 |  |
| `Fw.Plan.conflict_false_iff` | agree | 8834190627562181883 | 17744482823709373095 |  |
| `Fw.Measure.SelfCheck.SClass` | agree | 3931117990 | 21343920048600327 |  |
| `Fw.Measure.SelfCheck.SClass.rank` | agree | 14530072776010481536 | 4842641183946059553 |  |
| `Fw.Measure.SelfCheck.SClass.name` | disagree | 13127854298390031049 | 10421662760905240350 | 'name(c) ∈ {...}' says only that the name is in the set, not which class gets which name. Fix: $$\operatorname{name}(\mathrm{det})=\texttt{deterministic},\ \operatorname{name}(\mathrm{stable})=\texttt{stable},\ \operatorname{name}(\mathrm{shifting})=\texttt{shifting},\ \operatorname{name}(\mathrm{quar})=\texttt{quarantined}$$ |
| `Fw.Measure.SelfCheck.Thresholds` | agree | 3931117990 | 2812325546362838400 |  |
| `Fw.Measure.SelfCheck.harness` | agree | 2703450546457548773 | 237035915299894177 |  |
| `Fw.Measure.SelfCheck.spreadOk` | agree | 866056308 | 13315332438593172389 |  |
| `Fw.Measure.SelfCheck.Obs` | agree | 3931117990 | 3436206983019373913 |  |
| `Fw.Measure.SelfCheck.classOf` | agree | 8894278015917102899 | 13840312969610392975 |  |
| `Fw.Measure.SelfCheck.diffVs` | agree | 7935768620491261356 | 9112000732797157523 |  |
| `Fw.Measure.SelfCheck.maxDiff` | agree | 988627104220465608 | 11228417307274587690 |  |
| `Fw.Measure.SelfCheck.hi` | agree | 370980283 | 295333646190752245 |  |
| `Fw.Measure.SelfCheck.lo` | agree | 370980283 | 9152729456348664266 |  |
| `Fw.Measure.SelfCheck.spreadOf` | agree | 2527983506 | 2139545987091348666 |  |
| `Fw.Measure.SelfCheck.obs` | disagree | 13764121343766628012 | 2039394815385841660 | The first component \|r_0\| is undefined when there are no runs (m = 0). The Lean uses (rs.headD []).length = 0, so obs([]) = (0,0,0,0,0). Fix: append ',\quad \operatorname{obs}(\,) = (0, 0, 0, 0, 0)' or define \|r_0\| := 0 when m = 0. |
| `Fw.Measure.SelfCheck.SRow` | agree | 3931117990 | 4721448281546425299 |  |
| `Fw.Measure.SelfCheck.check` | agree | 9268589004445787576 | 5252815303091789441 |  |
| `Fw.Measure.SelfCheck.aligned` | agree | 2436421905 | 1441262422051144147 |  |
| `Fw.Measure.SelfCheck.classOf_det_iff` | agree | 4477740583047789430 | 10220855296187345406 |  |
| `Fw.Measure.SelfCheck.classOf_gc` | disagree | 18318202972652009784 | 5878987879699714008 | θ and o are free, but the Lean quantifies both. Fix: $$\forall \theta,\ o \in \mathrm{Obs}:\ \operatorname{cls}_\theta(\top, o) \in \{\mathrm{det}, \mathrm{quar}\}$$ |
| `Fw.Measure.SelfCheck.classOf_stable_iff` | agree | 17662785949528506817 | 665596293717285065 |  |
| `Fw.Measure.SelfCheck.classOf_shifting_iff` | agree | 3950227843883869696 | 4797351580878901005 |  |
| `Fw.Measure.SelfCheck.spreadOk_den` | agree | 9585496058136358306 | 9769341002402114827 |  |
| `Fw.Measure.SelfCheck.spreadOk_anti` | agree | 10198920662004338360 | 1782597738578435846 |  |
| `Fw.Measure.SelfCheck.stable_spread_shift` | agree | 12216078693035544267 | 12319058583438761418 |  |
| `Fw.Measure.SelfCheck.rank_pos` | agree | 953070977410238838 | 639277434449884097 |  |
| `Fw.Measure.SelfCheck.classOf_mono_maxDiff` | agree | 9898106378669327650 | 16631548065409437870 |  |
| `Fw.Measure.SelfCheck.classOf_mono_spread` | agree | 5084522964366698409 | 5751622817935716439 |  |
| `Fw.Measure.SelfCheck.diffVs_zero_iff` | agree | 16727694663063347661 | 14440943736446452859 |  |
| `Fw.Measure.SelfCheck.diffVs_le_maxDiff` | disagree | 16807322748350060472 | 751359221393535020 | r_0, r and R are free, but the Lean binds them (implicit args). Fix: $$\forall r_0, r \in \mathbb{Z}^{*},\ R \in (\mathbb{Z}^{*})^{*}:\ r \in r_0 :: R \implies \operatorname{diff}_{\|r_0\|}(r_0, r) \le \delta(r_0 :: R)$$ |
| `Fw.Measure.SelfCheck.maxDiff_zero_iff` | disagree | 14290114658272089634 | 10609946062214502090 | r_0 and R are free. Fix: prefix '\forall r_0 \in \mathbb{Z}^{*},\ R \in (\mathbb{Z}^{*})^{*}:\ ' to the iff (r[i] padded with 0 as in diffVs). |
| `Fw.Measure.SelfCheck.valAt_of_le` | agree | 10355442003966583874 | 13442046799148616273 |  |
| `Fw.Measure.SelfCheck.diffFrames_zero_iff` | agree | 16317357657340798212 | 15663635903372307230 |  |
| `Fw.Measure.SelfCheck.maxDiff_zero_iff_holds` | disagree | 14702442132771712696 | 13260994720190904468 | r_0 and R are free. Fix: $$\forall r_0, R:\ (\forall r \in r_0 :: R:\ \|r\| \le \|r_0\|) \implies \big(\delta(r_0 :: R) = 0 \iff \operatorname{Holds}(\mathrm{det}, r_0 :: R)\big)$$ |
| `Fw.Measure.SelfCheck.le_hi` | agree | 17004788980339814533 | 1902968484842184691 |  |
| `Fw.Measure.SelfCheck.lo_le` | agree | 12392517410931360193 | 5084356284293517891 |  |
| `Fw.Measure.SelfCheck.gap_le_spread` | agree | 5329824452828313645 | 11725171307292821623 |  |
| `Fw.Measure.SelfCheck.check_sound` | disagree | 9696374925345326298 | 5774582450788105157 | θ and 𝓡 are free, and o_k is used but not defined in this formula (it is defined only in check). Fix: begin with '\forall \theta, \mathcal{R}, (k, c, \delta, s, T) \in \operatorname{check}_\theta(\mathcal{R}):' and end with ', o_k = \operatorname{obs}(R_k)'. |
| `Fw.Measure.SelfCheck.aligned_iff` | disagree | 4142485415083933725 | 105502232027921682 | K is free. Fix: $$\forall K \in (\alpha^{*})^{*}:\ \operatorname{aligned}(K) \iff \forall a, b \in K:\ a = b$$ |
| `Fw.Measure.Snapshot.Layer` | agree | 3931117990 | 9074495719091987461 |  |
| `Fw.Measure.Snapshot.Tile` | agree | 3931117990 | 2402786319938252997 |  |
| `Fw.Measure.Snapshot.Snap` | agree | 3931117990 | 9948530455138982440 |  |
| `Fw.Measure.Snapshot.rects` | agree | 2555458049 | 13152958860580826448 |  |
| `Fw.Measure.Snapshot.rectArea` | agree | 3351561212 | 14042766684362953060 |  |
| `Fw.Measure.Snapshot.natSum` | agree | 434822048 | 4403256100447126262 |  |
| `Fw.Measure.Snapshot.census` | disagree | 17835941456747689167 | 17590384195357666909 | (1) The three counts use set-builder \|{l ∈ L \| …}\|, which merges equal layers or tiles, but the Lean takes list-filter lengths. Use \|[l ∈ L \| l.draws]\|, \|[t ∈ T \| t.solid]\| and \|[l ∈ L \| l.inv ≠ []]\|. (2) The Lean result is a list of (name, value) pairs, but the math gives only the values. Pair each value with its name, e.g. (census.snapshots, 1), … |
| `Fw.Measure.Snapshot.at?` | agree | 6034383128513556817 | 4120887280610100556 |  |
| `Fw.Measure.Snapshot.rects_length` | agree | 9774460515172773021 | 17522520584416903917 |  |
| `Fw.Measure.Snapshot.census_names` | disagree | 8121439739817002489 | 17904013845713369634 | The '…' hides 10 of the 12 names, and the census math does not name them either, so the math alone does not say what the list is. Fix: write all 12 in order: [census.snapshots, census.layers, census.drawingLayers, census.drawingAreaPx, census.tilings, census.tiles, census.activeTiles, census.solidTiles, census.activeTileAreaPx, raster.invalidatedLayers, raster.invalidationRects, raster.invalidationAreaPx]. |
| `Fw.Measure.Snapshot.subsets_le` | disagree | 7465810611349501855 | 18337744727059156344 | The set-builder counts \|{l ∈ L \| …}\| should be list-filter lengths (r5 pattern). Fix: \|[l ∈ L \| l.draws]\| ≤ \|L\| ∧ \|[l ∈ L \| l.inv ≠ []]\| ≤ \|L\| ∧ \|[t ∈ T \| t.solid]\| ≤ \|T\|. |
| `Fw.Measure.Snapshot.invalidated_of_rects` | disagree | 1778365682846686269 | 12691765853576914044 | L is free, but the Lean has ∀ ls. Fix: $$\forall L \in \mathrm{Layer}^{*}:\ \sum_{l \in L} \|\operatorname{rects}(l.\mathrm{inv})\| > 0 \implies \|[\,l \in L \mid l.\mathrm{inv} \ne [\,]\,]\| > 0$$ |
| `Fw.Measure.Snapshot.sumBy_nonneg` | agree | 8970722563538727727 | 3985089866101426153 |  |
| `Fw.Measure.Snapshot.rectArea_nonneg` | disagree | 9498472848102837070 | 5265282156549747968 | L is free, but the Lean has ∀ l. Fix: $$\forall L \in \mathbb{Z}^{*}:\ (\forall x \in L:\ x \ge 0) \implies \operatorname{area}(L) \ge 0$$ |
| `Fw.Measure.Snapshot.layers_additive` | disagree | 18198750520460587736 | 8287170644553375347 | Σ^draw, Σ^area and Σ^rects are never defined, so a reader must guess which sums they are. Fix: add 'where Σ^draw(L)=Σ_{l∈L, l.draws} l.w·l.h, Σ^area(L)=Σ_{l∈L} area(l.inv), Σ^rects(L)=Σ_{l∈L} \|rects(l.inv)\|'. |
| `Fw.Serve.Srv` | agree | 3931117990 | 3958887519701678366 |  |
| `Fw.Serve.Srv.st` | agree | 12650794700729926449 | 13400488030152232255 |  |
| `Fw.Serve.init` | agree | 4183589070269397029 | 6907425075465386074 |  |
| `Fw.Serve.Indexed` | agree | 333091397302457987 | 8516050734137762004 |  |
| `Fw.Serve.init_spec` | agree | 12377993493798116623 | 7082305759742569166 |  |
| `Fw.Serve.fcheck` | agree | 16365588633156882981 | 4972352180086439342 |  |
| `Fw.Serve.faccept` | agree | 16571546375171564522 | 12497664624139159875 |  |
| `Fw.Serve.faccept_seen` | agree | 13321901848260507412 | 2116788689693732311 |  |
| `Fw.Serve.fstep` | agree | 15161502382785291659 | 6931493198413633488 |  |
| `Fw.Serve.fapply` | agree | 16571546375171564522 | 7304377166926185626 |  |
| `Fw.Serve.cardStep_id` | agree | 2077601944898909474 | 10974517679077012715 |  |
| `Fw.Serve.fcheck_eq` | agree | 4760164048746664477 | 4035686465556723096 |  |
| `Fw.Serve.faccept_st` | agree | 39920724866852923 | 4844003924305239176 |  |
| `Fw.Serve.faccept_indexed` | agree | 10909151758191132173 | 8352489468848017892 |  |
| `Fw.Serve.fstep_spec` | agree | 1041951612167346199 | 16835225644668822296 |  |
| `Fw.Serve.fstep_indexed` | agree | 16579623756478502431 | 4839089890313865576 |  |
| `Fw.Serve.fstep_refused` | agree | 18350682003768014513 | 13787110220594294242 |  |
| `Fw.Serve.touched` | agree | 11227471014940213338 | 8770640504296050025 |  |
| `Fw.Serve.ftouched` | agree | 6106890019441188200 | 5879114950682146556 |  |
| `Fw.Serve.ftouched_eq` | agree | 1885546531690276952 | 15759978142321812630 |  |
| `Fw.Serve.changed` | agree | 2775392396673574907 | 5414764620606563873 |  |
| `Fw.Serve.fastBoard` | agree | 54855381088658253 | 6717979092961881992 |  |
| `Fw.Serve.fastBoard_eq` | agree | 12124382430293692435 | 4111427817086426268 |  |
| `Fw.Serve.Cmd.events` | agree | 14751393250934457687 | 12837126141232926744 |  |
| `Fw.Serve.Cmd.isReset` | agree | 7538764709716809286 | 13625177212711308790 |  |
| `Fw.Serve.replayFrom` | agree | 6707285282723545298 | 6987299973281896009 |  |
| `Fw.Serve.Resp` | agree | 3931117990 | 9732172185540171377 |  |
| `Fw.Serve.exec` | agree | 2179779174274812663 | 994231162652416565 |  |
| `Fw.Serve.run` | agree | 4557295377581222361 | 11441946930924023413 |  |
| `Fw.Serve.replayFrom_spec` | agree | 14016002831674674685 | 273691569754938160 |  |
| `Fw.Serve.replayFrom_total` | agree | 8738964815380439026 | 7776587946554096011 |  |
| `Fw.Serve.exec_spec` | agree | 1961643581170563137 | 7633774116985326077 |  |
| `Fw.Serve.run_eq_fold` | agree | 16808781533046495488 | 13741300882403909799 |  |
| `Fw.Serve.run_init_eq_project` | agree | 15678536602132593077 | 7542406596116145952 |  |
| `Fw.Serve.apply_each_eq_replay` | agree | 9731804074449132521 | 14106752709589254440 |  |
| `Fw.Serve.run_reset` | agree | 7040621138404535161 | 11889014821283368162 |  |
| `Fw.Serve.refused_unchanged` | agree | 5827876586837275842 | 10306024924386529466 |  |
| `Fw.Serve.accepted_changed` | agree | 6467918810216605251 | 14602862819886395788 |  |
| `Fw.Serve.query_keeps` | agree | 9431028343713711235 | 8369952621995470586 |  |
| `Fw.Serve.query_eq_of_st` | agree | 998474929482636258 | 14438531044217312851 |  |
| `Fw.Console.boardCard` | disagree | 5498730827532609432 | 3049044365302310876 | ρ = #{r ∈ runs : …} merges equal runs, but the Lean is a list-filter length. The r5 runIdx fix already says the count boardCard does is \|[…]\|. Fix: ρ = \|[ r ∈ σ.runs \| r.card = c.id ∧ r.status = running ]\|, and say that STALE = staleMs. |
| `Fw.Console.board` | agree | 54855381088658253 | 9377535437969557175 |  |
| `Fw.Console.landed_not_stale` | agree | 8679932407917334885 | 17614862804858788002 |  |
| `Fw.Console.running_not_stale` | agree | 3431714646197031367 | 10765127944274944300 |  |
| `Fw.Console.row_land_iff` | agree | 17203310027920732597 | 18397925734428084636 |  |
| `Fw.Console.needsYou_open` | agree | 12380582029402214694 | 12002383940004787762 |  |
| `Fw.Sched.Admit.Inv` | agree | 15317366621955740554 | 4482591055472719912 |  |
| `Fw.Ops.Identity.Who` | agree | 3931117990 | 15527178002168863957 |  |
| `Fw.Ops.Identity.who` | agree | 8672972181153401003 | 11530777831421141581 |  |
| `Fw.Ops.Identity.infixOf` | agree | 1344957889 | 3456484710699348931 |  |
| `Fw.Ops.Identity.isReviewRole` | agree | 1526413716 | 10761618222701793458 |  |
| `Fw.Ops.Identity.actorOf` | agree | 9101080822709140586 | 10430450450218138151 |  |
| `Fw.Ops.Identity.capActor` | agree | 11774593405490383543 | 17077164435179484791 |  |
| `Fw.Ops.Identity.who_lead_iff` | agree | 9746952204522863845 | 12817654815159252464 |  |
| `Fw.Ops.Identity.who_some_ne_lead` | agree | 10318294560975988738 | 8321301652908637399 |  |
| `Fw.Ops.Identity.who_agent_iff` | agree | 11047289686892352992 | 17353192172803441518 |  |
| `Fw.Ops.Identity.who_unknown_iff` | agree | 16727984665843627515 | 11106655625356782586 |  |
| `Fw.Ops.Identity.who_forked` | agree | 10421667978956875459 | 5196469166894522076 |  |
| `Fw.Ops.Identity.who_total` | agree | 16614870183942668730 | 16741931815928386933 |  |
| `Fw.Ops.Identity.capActor_lead_iff` | agree | 557465277284064924 | 5505974582331132636 |  |
| `Fw.Ops.Identity.capActor_none_iff` | agree | 14432149982509552871 | 6008912686593752974 |  |
| `Fw.Ops.Identity.capActor_range` | agree | 9409672560594852336 | 7162139453988864089 |  |
