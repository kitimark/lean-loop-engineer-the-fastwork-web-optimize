---
title: Math review round 5 at c4ca5ad (Fw/Sched, Fw/Serve, Fw/Ops, round-4 fixes)
date: 2026-10-17
status: CONFIRMED
round: 5
---

# Math review round 5 at c4ca5ad

Four math-reviewer agents (workflow `math-review-r5`, read-only) back-translated the 490 declarations that were stale
or pending in the Math view at c4ca5ad: all of `Fw/Sched` (Admit, ParMetrics), `Fw/Serve`, `Fw/Ops`, and the 84 rows
whose Lean or docstring changed after round 4. Method as in rounds 3 and 4: write the math from the Lean first, then
compare clause by clause. The lead wrote this record from the agents' structured verdicts; `stmtHash` and `mathHash`
come from `lake exe mathview` at c4ca5ad (cache key 2ee52f0aa882e041). Coverage was checked: every listed declaration
has exactly one row.

## Counts

| Group | Reviewed | Agree | Disagree |
|---|---|---|---|
| Fw.Sched.Admit | 142 | 130 | 12 |
| Fw.Sched.ParMetrics, Fw.Serve | 132 | 105 | 27 |
| Fw.Ops (Meter, PathCheck, SpawnGuard, Usage) | 132 | 110 | 22 |
| Stale since round 4 (Measure, Null, Site) | 84 | 83 | 1 |
| **Total** | 490 | 428 | 62 |

## Recurring problems

- **Fw.Sched.Admit:** 12 of 142 disagree. (1) Nodup of a mapped list written as 'f injective on l' (Inv, eq_of_nodup_map, nodup_map_sublist, nodup_admit); fix: 'the list [f(a) | a ∈ l] has no repeats'. (2) |{..}| set-builder where the Lean is a list-filter length (psi). (3) 'the first (p, y)' with no scan order, where the Lean scans Run first (writeAt, devAt). (4) Quantifier/⇒ scope in Base. (5) Example defs: landed flag left out of finish, State fields left out, English units clash with Vec units. Inductive rule schemata (Reachable, Steps, Trace) accepted with schematic variables.
- **Fw.Sched.ParMetrics, Fw.Serve:** 27 of 132 disagree. (1) Free variables: all 9 Tbl theorems in Serve leave key, T, k, f free, because they come from `variable`; ok_unique also drops i, j < |rows|. (2) Set-builder counts (busyAt, runIdx, runIdx_get) merge repeats where Lean counts list entries. (3) ℚ division with ℕ inputs not marked ∈ ℚ (speedup, serialShare, stretch, div_le_of_le_mul). (4) Undefined edge cases: max over empty D (cp), out-of-range index (Tbl.modify, modify_eq), absent map key → 0 (fastRow). (5) segSum uses − for ℕ ∸. Plus unbound or misindexed symbols (sortS_sorted, mergeGo_ok, merge_disjoint_sorted, query_after_run) and a ⇒/⇔ precedence issue (mergeGo_cover).
- **Fw.Ops (Meter, PathCheck, SpawnGuard, Usage):** 22/132 disagree. (1) Free variables in theorem math that the Lean quantifies (σ/now/O, S/x, R/A, i, ρ, r/t): write the ∀. (2) Set-builder |{…}| for list-filter lengths (countKind/Sub/Role, recentCount): use |[…]|. (3) Overlapping cases where the Lean is first-match (capFail, roleCheck, check). (4) ⌊now/ω⌋ with ω = 0 (Lean gives 0). (5) A list result with no order given (lastWins), and English that contradicts the list order (exLines).
- **Stale since round 4 (Measure, Null, Site):** The round-4 fixes are correct in 83 of 84 rows: the ∀s are now written, list-filter counts are used instead of set-builder notation, truncated subtraction is marked with ∸, first-match cases no longer overlap, and the English claims are narrowed (null exactness, gap1000, inv_stats). One fix broke something: in reduceSteps (lean/Fw/Measure/WebKit.lean:178) the corrected last component replaced the whole $$, so the math now defines only rowsBeforeFirstStep. In the earlier fixes, check that an edit meant for one component did not replace the whole formula.

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Sched.Admit.Res.mem_all` | agree | 8309613196865852480 | 17344666865386792915 |  |
| `Fw.Sched.Admit.neverFitsAt_none` | agree | 6397612890738468358 | 11190864267720228663 |  |
| `Fw.Sched.Admit.depAt_none` | agree | 2461503071226894806 | 7105012957808420373 |  |
| `Fw.Sched.Admit.writeAt_none` | agree | 12025490939761363852 | 13199326646180309764 |  |
| `Fw.Sched.Admit.devAt_none` | agree | 10212905285394606132 | 14291722996086458557 |  |
| `Fw.Sched.Admit.budgetAt_none` | agree | 16567357524239378464 | 6660752048583706885 |  |
| `Fw.Sched.Admit.heldAt_none` | agree | 10507691291290751409 | 883657471293050738 |  |
| `Fw.Sched.Admit.free_iff` | agree | 10774529841240228245 | 17663402764216479314 |  |
| `Fw.Sched.Admit.admit_eq_admit` | agree | 17248254681928652393 | 14283187688180457253 |  |
| `Fw.Sched.Admit.fits_not_unfit` | agree | 12987265508850748771 | 10354393976827794837 |  |
| `Fw.Sched.Admit.admit_iff` | agree | 5974993741112378 | 13416481825190822839 |  |
| `Fw.Sched.Admit.unfit_reported` | agree | 16833765798489277050 | 7274155375897427637 |  |
| `Fw.Sched.Admit.pickFrom_mem` | agree | 1584535433982563823 | 4874692494750231912 |  |
| `Fw.Sched.Admit.pick_mem` | agree | 15948017401552886650 | 10649561125639450532 |  |
| `Fw.Sched.Admit.eq_of_nodup_map` | disagree | 436139848 | 9815542624243598298 | The hypothesis 'f injective on l', read on the set of members, makes the statement a tautology. The Lean assumes Nodup(map f l). Fix: $$\forall f,l,a,b:\ [f(c)\mid c\in l] \text{ has no repeats} \land a,b\in l \land f(a)=f(b) \Rightarrow a=b$$ |
| `Fw.Sched.Admit.wconf_comm` | agree | 17234805471511561116 | 8974180611098520787 |  |
| `Fw.Sched.Admit.devShare_comm` | agree | 3029452058003280422 | 1776912535495811822 |  |
| `Fw.Sched.Admit.related_comm` | agree | 1945152684630604032 | 1127450118462653874 |  |
| `Fw.Sched.Admit.used_filter_le` | agree | 10802005870616959816 | 10984513606738646807 |  |
| `Fw.Sched.Admit.chosen_sound` | agree | 8617055282317609385 | 18049699540593097055 |  |
| `Fw.Sched.Admit.admit_conserving` | agree | 4732845319054816024 | 14619706812956908485 |  |
| `Fw.Sched.Admit.nodup_map_sublist` | disagree | 645536096 | 937837048314306357 | 'f injective on l' (set reading) is weaker than Nodup(map f l), and the conclusion is Nodup too. Fix: $$\forall f,l',l:\ l' \text{ a sublist of } l \land [f(a)\mid a\in l] \text{ has no repeats} \Rightarrow [f(a)\mid a\in l'] \text{ has no repeats}$$ |
| `Fw.Sched.Admit.nodup_admit` | disagree | 9158011613192942020 | 18174575097616286541 | Both 'injective on' clauses are Nodup of mapped lists in the Lean (no repeats, so x' is also not repeated). Fix: $$\ldots,\ [f(y)\mid y\in R \mathbin{+\!\!+} Q] \text{ has no repeats} \Rightarrow [f(y)\mid y\in x' :: R \mathbin{+\!\!+} [y\in Q\mid \mathit{id}(y)\ne\mathit{id}(x)]] \text{ has no repeats}$$ |
| `Fw.Sched.Admit.inv_step` | agree | 18040813206526255862 | 18118032704463692908 |  |
| `Fw.Sched.Admit.inv_init` | agree | 3585255329293021560 | 12972361604443241106 |  |
| `Fw.Sched.Admit.inv_reachable` | agree | 18322029304465573126 | 12926546881682771370 |  |
| `Fw.Sched.Admit.writes_disjoint` | agree | 5274115601932934934 | 17555870758334073330 |  |
| `Fw.Sched.Admit.devices_exclusive` | agree | 12548453422902289558 | 17332083816831033250 |  |
| `Fw.Sched.Admit.deps_respected` | agree | 6723764067908859637 | 1578288403195754620 |  |
| `Fw.Sched.Admit.done_grows` | agree | 12072609090176660526 | 15480084052711420486 |  |
| `Fw.Sched.Admit.within_budget` | agree | 4218495734644945871 | 1690354377884460628 |  |
| `Fw.Sched.Admit.aged_not_overtaken` | agree | 6896207941210067659 | 2671986688933332341 |  |
| `Fw.Sched.Admit.Steps.trans` | agree | 10624381302463236641 | 906981882994920762 |  |
| `Fw.Sched.Admit.steps_admitN` | agree | 10900739977710284308 | 1993466619459579117 |  |
| `Fw.Sched.Admit.steps_event` | agree | 18359500273610813519 | 17893940750815420135 |  |
| `Fw.Sched.Admit.admitStep_shrinks` | agree | 12775074014367100735 | 15167395837245924536 |  |
| `Fw.Sched.Admit.chosen_admitN` | agree | 4369010709542820146 | 6002440424693017816 |  |
| `Fw.Sched.Admit.chosen_event` | agree | 11854112237101454496 | 8330813914742120629 |  |
| `Fw.Sched.Admit.len_filter_mono` | agree | 2948991022 | 5794800540172362432 |  |
| `Fw.Sched.Admit.len_filter_lt` | agree | 2597184965 | 8633733034140361401 |  |
| `Fw.Sched.Admit.used_sublist` | agree | 11221863411809713513 | 17547235983331375259 |  |
| `Fw.Sched.Admit.le_of_not_unfit` | agree | 12979321794946854255 | 7083529639447065416 |  |
| `Fw.Sched.Admit.eff_aged` | agree | 12110182922143564772 | 14063305487866279302 |  |
| `Fw.Sched.Admit.before_of_aged` | agree | 10505556938977931130 | 12640890640844751269 |  |
| `Fw.Sched.Admit.seq_le_of_before` | agree | 3483005794297689612 | 15681213515507466563 |  |
| `Fw.Sched.Admit.aged_mono` | agree | 16226736397164625450 | 15630922275079395364 |  |
| `Fw.Sched.Admit.ready_mono` | agree | 17217072170735383163 | 9721392255122427906 |  |
| `Fw.Sched.Admit.elig_mono` | agree | 14692250429165222867 | 2292066530410677963 |  |
| `Fw.Sched.Admit.t_step` | agree | 18102499807090345471 | 10321861359339403898 |  |
| `Fw.Sched.Admit.next_step` | agree | 13567494453043145706 | 14608741568236482407 |  |
| `Fw.Sched.Admit.queue_step` | agree | 12546107328134627208 | 1042570095020879085 |  |
| `Fw.Sched.Admit.gone_steps` | agree | 1099985954798347888 | 18010896442608798003 |  |
| `Fw.Sched.Admit.gone_trace` | agree | 14621067125237518519 | 4929154128174582339 |  |
| `Fw.Sched.Admit.eq_of_seq` | agree | 7057884673040318594 | 7482262940188753049 |  |
| `Fw.Sched.Admit.eq_of_id` | agree | 9925372389823515907 | 12442347384530925500 |  |
| `Fw.Sched.Admit.elig_of_seq_eq` | agree | 3668935317186628248 | 7587277973514247471 |  |
| `Fw.Sched.Admit.base_step` | agree | 14772205452930030319 | 1671660015353442804 |  |
| `Fw.Sched.Admit.base_steps` | agree | 8026674580768611586 | 16838867463023433982 |  |
| `Fw.Sched.Admit.psi_elig` | agree | 8526272051708360770 | 4408726971688325514 |  |
| `Fw.Sched.Admit.psi_admit` | agree | 10795936826802922252 | 5729743572880567739 |  |
| `Fw.Sched.Admit.psi_step` | agree | 8713338521113125698 | 13501966649916144622 |  |
| `Fw.Sched.Admit.ghost_step` | agree | 10703466978803380736 | 3656220523541183060 |  |
| `Fw.Sched.Admit.ghost_steps` | agree | 11175319705667002679 | 16453071278045908775 |  |
| `Fw.Sched.Admit.stuck_false` | agree | 12614930006451672535 | 12118189111325440242 |  |
| `Fw.Sched.Admit.phase` | agree | 8775876658664873685 | 17910221825308216729 |  |
| `Fw.Sched.Admit.aged_admitted_by` | agree | 2101429365128891231 | 7835631042110629924 |  |
| `Fw.Sched.Admit.okTrace_sound` | agree | 18028496710737974414 | 16580097451391387766 |  |
| `Fw.Sched.Admit.Res` | agree | 3931117990 | 13509733962961059256 |  |
| `Fw.Sched.Admit.Res.all` | agree | 12457518191784205200 | 3702153906029803554 |  |
| `Fw.Sched.Admit.Vec` | agree | 3931117990 | 9314664786399152851 |  |
| `Fw.Sched.Admit.Vec.get` | agree | 11409194679213925499 | 9461831770211211937 |  |
| `Fw.Sched.Admit.Dev` | agree | 3931117990 | 6291000641749703782 |  |
| `Fw.Sched.Admit.Item` | agree | 3931117990 | 7476775807021109768 |  |
| `Fw.Sched.Admit.Item.job` | agree | 2498424393327566940 | 10321270018322375029 |  |
| `Fw.Sched.Admit.pconf` | agree | 2423821251 | 3286672389400710377 |  |
| `Fw.Sched.Admit.wconf` | agree | 13512379346175720554 | 14392357159895214270 |  |
| `Fw.Sched.Admit.devShare` | agree | 13512379346175720554 | 6387003710249177997 |  |
| `Fw.Sched.Admit.related` | agree | 13512379346175720554 | 15169394368208242115 |  |
| `Fw.Sched.Admit.used` | agree | 6243340923167482381 | 2720382099652889877 |  |
| `Fw.Sched.Admit.State` | agree | 3931117990 | 14283951850473426791 |  |
| `Fw.Sched.Admit.ready` | agree | 17151823911198711123 | 16450918100771967921 |  |
| `Fw.Sched.Admit.free` | agree | 17151823911198711123 | 11500578612515800593 |  |
| `Fw.Sched.Admit.fits` | agree | 9131380758644327908 | 14742348492151692030 |  |
| `Fw.Sched.Admit.unfit` | agree | 2329628843098153039 | 1957220971705021896 |  |
| `Fw.Sched.Admit.comp` | agree | 12133169314277374141 | 2205672210298572051 |  |
| `Fw.Sched.Admit.aged` | agree | 4282766856239973060 | 12529324201925166663 |  |
| `Fw.Sched.Admit.before` | agree | 2208164910266870246 | 3449929613047614493 |  |
| `Fw.Sched.Admit.heldBy` | agree | 12133169314277374141 | 9451929073724642558 |  |
| `Fw.Sched.Admit.held` | agree | 9131380758644327908 | 12450426460319253457 |  |
| `Fw.Sched.Admit.Reason` | agree | 3931117990 | 10083613749994275496 |  |
| `Fw.Sched.Admit.Decision` | agree | 3931117990 | 4923033437688974266 |  |
| `Fw.Sched.Admit.neverFitsAt` | agree | 10542890285090972744 | 893869759064646141 |  |
| `Fw.Sched.Admit.depAt` | agree | 4589519709518025226 | 11988344909596765797 |  |
| `Fw.Sched.Admit.writeAt` | disagree | 221296761862308444 | 18127155621229429159 | 'the first (p, id(y))' leaves the scan order open. The Lean scans Run first (findSome?), then W(x). Fix: $$\operatorname{wAt}(\sigma,x)=(p,\mathit{id}(y))$$ with y the first y∈Run where ¬(x∼y) ∧ ∃p'∈W(x), q∈W(y): p'⋈q, and p the first such p'∈W(x) for that y; else ⊥. |
| `Fw.Sched.Admit.devAt` | disagree | 11968143927411640709 | 10408710865187452631 | 'the first (v, id(y))' leaves the scan order open. The Lean scans Run first (findSome?), then V(x). Fix: $$\operatorname{vAt}(\sigma,x)=(v,\mathit{id}(y))$$ with y the first y∈Run where ¬(x∼y) ∧ V(x)∩V(y)≠∅, and v the first v∈V(x) with v∈V(y); else ⊥. |
| `Fw.Sched.Admit.budgetAt` | agree | 16116011147469297905 | 13746726471778194628 |  |
| `Fw.Sched.Admit.heldAt` | agree | 8277928083547560797 | 7617114239087988769 |  |
| `Fw.Sched.Admit.admit` | agree | 814940866720591146 | 313480153215712145 |  |
| `Fw.Sched.Admit.pickFrom` | agree | 689508151682935970 | 8538024126708378419 |  |
| `Fw.Sched.Admit.pick` | agree | 14251773847256376051 | 3557922610454547832 |  |
| `Fw.Sched.Admit.chosen` | agree | 791996293808599180 | 9838473762456173188 |  |
| `Fw.Sched.Admit.admitStep` | agree | 14839612362739072554 | 842328359134695617 |  |
| `Fw.Sched.Admit.finish` | agree | 17460923291055426916 | 5427347272425932532 |  |
| `Fw.Sched.Admit.enqueue` | agree | 18294198363155408024 | 10666121682846668090 |  |
| `Fw.Sched.Admit.setTime` | agree | 9262195255900444059 | 9959402362246328998 |  |
| `Fw.Sched.Admit.Cmd` | agree | 3931117990 | 9615563097377923983 |  |
| `Fw.Sched.Admit.step` | agree | 17246750176188782297 | 8917082923105997724 |  |
| `Fw.Sched.Admit.Reachable` | agree | 15317366621955740554 | 332481669081151612 |  |
| `Fw.Sched.Admit.Inv` | disagree | 15317366621955740554 | 35920495045026071 | 'id and seq injective on Run++Q' (set reading) allows the same item twice; the Lean fields ids/seqs are Nodup of the mapped lists. Fix the first clause: $$[\mathit{id}(x)\mid x\in \mathit{Run} \mathbin{+\!\!+} Q] \text{ and } [\mathit{seq}(x)\mid x\in \mathit{Run} \mathbin{+\!\!+} Q] \text{ have no repeats}$$ |
| `Fw.Sched.Admit.admitN` | agree | 15153917511004356588 | 6726858710041392248 |  |
| `Fw.Sched.Admit.admitAll` | agree | 14839612362739072554 | 15557566104113117574 |  |
| `Fw.Sched.Admit.event` | agree | 17246750176188782297 | 13225243079908640799 |  |
| `Fw.Sched.Admit.Trace` | agree | 13698802710366285121 | 15054771753120140213 |  |
| `Fw.Sched.Admit.Steps` | agree | 6527587913770358195 | 2559921156487681614 |  |
| `Fw.Sched.Admit.oldOk` | agree | 1555833134945955230 | 7832186763476919427 |  |
| `Fw.Sched.Admit.elig` | agree | 17151823911198711123 | 6285988363179365431 |  |
| `Fw.Sched.Admit.psi` | disagree | 17279220915337067317 | 6898923640359763896 | Set-builder \|{o∈Q \| …}\| merges duplicates, but the Lean takes the length of a list filter (psi is defined for any σ, not only under Inv). Fix: $$\Psi_{B,z}(\sigma)=\big\|[o\in Q\mid \operatorname{oldOk}(B,z,o)]\big\|+\big\|[o\in Q\mid \operatorname{oldOk}(B,z,o)\land\lnot\operatorname{elig}(\sigma,o)]\big\|$$ |
| `Fw.Sched.Admit.qual` | agree | 14999402882802710101 | 4120536108975114174 |  |
| `Fw.Sched.Admit.Gone` | agree | 3965722802369144747 | 13277766519777888621 |  |
| `Fw.Sched.Admit.Base` | disagree | 16197377537675326756 | 8817542067228339572 | Scope: in '∀y∈Q: seq(y)∉G ∧ ∀y∈Run: seq(y)∈G ⇒ start(y)≤t_0 ∧ (z∈Q ∨ …)', the ∀ and ⇒ swallow the last clause and make it conditional. Fix by bracketing: (∀y∈Q: seq(y)∉G) ∧ (∀y∈Run: seq(y)∈G ⇒ start(y)≤t_0) ∧ (z∈Q ∨ ∀y∈Q: seq(y)≠seq(z)). |
| `Fw.Sched.Admit.Ghost` | agree | 8105670768146603629 | 14179165604958862280 |  |
| `Fw.Sched.Admit.runTrace` | agree | 4742269330745819445 | 10984316307979571871 |  |
| `Fw.Sched.Admit.okTrace` | agree | 11799488269404929992 | 9632127038683496408 |  |
| `Fw.Sched.Admit.Ex.B4` | disagree | 11142282837834494097 | 12657870653205082314 | English '4 cores, 8 GB' contradicts the Vec units (cores in tenths, RAM in MB): (4,8,0,0) means 0.4 cores and 8 MB. The math is fine. Fix English: 'Budget for the examples: cores 4, RAM 8 (small abstract numbers, not the tenths/MB scale).' |
| `Fw.Sched.Admit.Ex.a` | agree | 8463832041641151135 | 12644467709067853677 |  |
| `Fw.Sched.Admit.Ex.b` | agree | 8463832041641151135 | 17858257744708412703 |  |
| `Fw.Sched.Admit.Ex.c` | agree | 8463832041641151135 | 8372194410604315720 |  |
| `Fw.Sched.Admit.Ex.big` | agree | 8463832041641151135 | 1387568021367966295 |  |
| `Fw.Sched.Admit.Ex.dep` | agree | 8463832041641151135 | 8812627462162821133 |  |
| `Fw.Sched.Admit.Ex.s1` | agree | 8463832041641151135 | 14042210671010179201 |  |
| `Fw.Sched.Admit.Ex.s2` | agree | 8463832041641151135 | 3684734504327192651 |  |
| `Fw.Sched.Admit.Ex.kid` | agree | 8463832041641151135 | 3374253871894015550 |  |
| `Fw.Sched.Admit.Ex.o` | agree | 8463832041641151135 | 3015918733927076230 |  |
| `Fw.Sched.Admit.Ex.x` | agree | 8463832041641151135 | 81735824942783588 |  |
| `Fw.Sched.Admit.Cex.r1` | agree | 8463832041641151135 | 16382989511838779557 |  |
| `Fw.Sched.Admit.Cex.e` | agree | 8463832041641151135 | 6037971358820874281 |  |
| `Fw.Sched.Admit.Cex.o` | agree | 8463832041641151135 | 13087776586757860548 |  |
| `Fw.Sched.Admit.Cex.z` | agree | 8463832041641151135 | 17918855874250417565 |  |
| `Fw.Sched.Admit.Cex.y` | agree | 8463832041641151135 | 4657552393479700660 |  |
| `Fw.Sched.Admit.Cex.σi` | disagree | 17639440263550986050 | 13337010493855343833 | The math gives only Run and Q. The definition also sets next = 7, which fixes y's arrival number, plus t = 0 and Done = []. Fix: $$\sigma_i = (\mathit{Run}=[r_1,e],\ \mathit{Done}=[\,],\ Q=[o,z],\ t=0,\ \mathit{next}=7)$$ |
| `Fw.Sched.Admit.Cex.cmds` | disagree | 13592552919542134372 | 15095778454860261740 | Cmd.finish takes (i, ℓ) and the landed flag decides whether Done grows; the Lean passes true. Fix: $$\mathrm{tick}(8), \mathrm{enqueue}(y), \mathrm{tick}(9), \mathrm{finish}(e,\mathrm{true}), \mathrm{finish}(r_1,\mathrm{true}), \mathrm{tick}(17), \mathrm{finish}(y,\mathrm{true}), \mathrm{tick}(25)$$ |
| `Fw.Sched.Admit.Cex.rest` | disagree | 13592552919542134372 | 15828432991634110536 | The landed flag is missing: the Lean is .finish "o" true. Fix: $$\mathrm{tick}(26), \mathrm{finish}(o,\mathrm{true})$$ |
| `Fw.Sched.ParMetrics.sortS_sorted` | disagree | 9847209347818384789 | 15707803794104637658 | Math indexes the input l, not sortS(l): 's_{l_i} ≤ s_{l_j}' says l itself is sorted. Fix: $$\forall l,\ \forall i < j < \|\operatorname{sortS}(l)\|:\ s_{\operatorname{sortS}(l)_i} \le s_{\operatorname{sortS}(l)_j}$$ |
| `Fw.Sched.ParMetrics.mergeGo_start` | agree | 14747971408555102972 | 17490050604655850377 |  |
| `Fw.Sched.ParMetrics.mergeGo_ok` | disagree | 13357520133464333054 | 12803428630123795995 | In the last clause 's_o < e_o', o is free (Lean: ∀ o ∈ mergeGo c ys). Fix the conclusion: $$(\forall i<j<\|g\|:\ e_{g_i} < s_{g_j}) \land \forall o \in g:\ s_o < e_o,\quad g = \operatorname{go}(c, ys)$$ |
| `Fw.Sched.ParMetrics.mergeGo_within` | agree | 13793051268880907184 | 11371052480895830607 |  |
| `Fw.Sched.ParMetrics.mergeGo_cover` | disagree | 1894653855042681847 | 2710321106608034437 | With usual precedence 'A ⇒ B ⇔ C' reads as (A ⇒ B) ⇔ C. Lean is A → (B ↔ C). Fix: $$\dots \Rightarrow \big[(p \in c \lor \exists y \in ys:\ p \in y) \iff \exists o \in \operatorname{go}(c, ys):\ p \in o\big]$$ |
| `Fw.Sched.ParMetrics.merge_disjoint_sorted` | disagree | 15879058867578421040 | 11978222616158471549 | m is never bound. English 'consecutive' understates: Pairwise covers all pairs i<j. Fix: '∀ l, with m = merge(l): ∀ i<j<\|m\|: e_{m_i} < s_{m_j} ∧ ∀ o ∈ m: s_o < e_o'. English: 'every merged interval ends before any later one starts'. |
| `Fw.Sched.ParMetrics.merge_cover` | agree | 7063507963564079900 | 2761731098986906151 |  |
| `Fw.Sched.ParMetrics.merge_within` | agree | 8320152279507678785 | 16429158535616981245 |  |
| `Fw.Sched.ParMetrics.sum_len_le` | agree | 3630241594402413185 | 2915294620390309857 |  |
| `Fw.Sched.ParMetrics.busy_le_alive` | agree | 12318169487410466523 | 17424837070346983531 |  |
| `Fw.Sched.ParMetrics.div_le_of_le_mul` | disagree | 653433142 | 3129480873909677126 | Lean divides in ℚ: (x:ℚ)/(y:ℚ) ≤ (k:ℚ). Over ℕ, 'x/y' reads as floor division (Nat x/0 = 0 too), so the math does not say which. Fix: $$\forall x, y, k \in \mathbb N:\ x \le k y \Rightarrow x / y \le k \text{ in } \mathbb{Q}\ (x/0 = 0)$$ |
| `Fw.Sched.ParMetrics.busy_sum_le` | agree | 12716419805379298601 | 2452337620647383384 |  |
| `Fw.Sched.ParMetrics.speedup_le_agents` | agree | 17843069391757099886 | 13082769177376073047 |  |
| `Fw.Sched.ParMetrics.segSum_le` | agree | 11203096915388337020 | 9476417001072411566 |  |
| `Fw.Sched.ParMetrics.serial_share_le_one` | agree | 1384160378299931007 | 10855805342983771639 |  |
| `Fw.Sched.ParMetrics.mem_preds` | agree | 4641652947053630720 | 13652068856582959763 |  |
| `Fw.Sched.ParMetrics.le_maxl` | agree | 10322346278458957619 | 10098987527069901404 |  |
| `Fw.Sched.ParMetrics.maxl_mem` | agree | 12764678728839241042 | 8604189021775977580 |  |
| `Fw.Sched.ParMetrics.look_eq` | agree | 9684207171319124770 | 1289107892251708655 |  |
| `Fw.Sched.ParMetrics.weight_snoc` | agree | 11471772657675340605 | 16007490315926001802 |  |
| `Fw.Sched.ParMetrics.PathTo.lt` | agree | 14141141774281237360 | 3437183778440686725 |  |
| `Fw.Sched.ParMetrics.Plus.lt` | agree | 13048653841185260670 | 15713356325465175675 |  |
| `Fw.Sched.ParMetrics.Plus.cons` | agree | 1438305205004623074 | 7152685004331252287 |  |
| `Fw.Sched.ParMetrics.kinv_init` | agree | 8616875629625685821 | 15222195224040833064 |  |
| `Fw.Sched.ParMetrics.kinv_step` | agree | 7796459987008256768 | 801807161451540462 |  |
| `Fw.Sched.ParMetrics.kahn_some` | agree | 6198418946459191282 | 4615517633910828095 |  |
| `Fw.Sched.ParMetrics.cycle_of_closed` | agree | 8511789408800965666 | 10162929035957130118 |  |
| `Fw.Sched.ParMetrics.kahn_none` | agree | 13494502858008776629 | 1341316196817492593 |  |
| `Fw.Sched.ParMetrics.topo_closed` | agree | 7866582850046424032 | 6197642996493867421 |  |
| `Fw.Sched.ParMetrics.cp_ge_path` | agree | 8575877660944712969 | 8162538543683866428 |  |
| `Fw.Sched.ParMetrics.cp_attained` | agree | 6104563748460520722 | 13227217782390446874 |  |
| `Fw.Sched.ParMetrics.cp_acyclic_or_error` | agree | 6907433120242043498 | 11537263938744643590 |  |
| `Fw.Sched.ParMetrics.bench_wins_le_one` | agree | 3100659722341731525 | 254316008628498145 |  |
| `Fw.Sched.ParMetrics.Iv` | agree | 3931117990 | 2492706031563716960 |  |
| `Fw.Sched.ParMetrics.Iv.len` | agree | 9255844592782565516 | 1953701697354950625 |  |
| `Fw.Sched.ParMetrics.covers` | agree | 1920156447134460442 | 6983973401127732274 |  |
| `Fw.Sched.ParMetrics.mergeGo` | agree | 6735798785661018601 | 17203324619220890840 |  |
| `Fw.Sched.ParMetrics.sortS` | agree | 1544987099655766943 | 17492352380977452938 |  |
| `Fw.Sched.ParMetrics.merge` | agree | 1544987099655766943 | 13939117334430439534 |  |
| `Fw.Sched.ParMetrics.clip` | agree | 4762919801392471560 | 14013700239276862969 |  |
| `Fw.Sched.ParMetrics.busy` | agree | 1378521427834616038 | 3606698726624010263 |  |
| `Fw.Sched.ParMetrics.speedup` | disagree | 15651464537387123000 | 13218882717654571690 | The Lean value is in ℚ (Nat sum cast, then divided). With ℕ inputs the fraction can be read as floor division. Fix: append '\in \mathbb{Q}' to the math, as in Null.falseBetterProb: $$S_{a,b}(ag) = \frac{\sum_{l} \operatorname{busy}_{a,b}(l)}{b \mathbin{\dot-} a} \in \mathbb{Q}\ (x/0=0)$$ |
| `Fw.Sched.ParMetrics.busyAt` | disagree | 6618854042646415590 | 15079416254728065234 | Lean takes the length of a list filter, so two agents with identical interval lists count twice. A set-builder \|{l ∈ ag \| …}\| merges them. Fix: $$\operatorname{busyAt}(ag, p) = \big\|[\, l \in ag \mid \exists i \in l:\ s_i \le p < e_i \,]\big\|$$ (list filter, repeats counted). |
| `Fw.Sched.ParMetrics.points` | disagree | 16012442667506301285 | 16242723725277645927 | '[a,b] ∪ {…}' reads as the closed interval (every point) united with a set, and ∪ drops repeats. Lean filters the list a::b::(every s_i,e_i) and keeps repeats. Fix: $$\operatorname{sort}([\,p \in a :: b :: [s_i, e_i \mid l \in ag,\ i \in l] \mid a \le p \le b\,])$$ English: 'every interval start and end'. |
| `Fw.Sched.ParMetrics.segSum` | disagree | 1457435609 | 1204696106439183968 | q − p is truncated ℕ subtraction in Lean (0 when q < p, e.g. on an unsorted list). Fix: $$\operatorname{segSum}_f(p :: q :: r) = [f(p)] \cdot (q \mathbin{\dot-} p) + \operatorname{segSum}_f(q :: r)$$ |
| `Fw.Sched.ParMetrics.serial` | agree | 16916687045280984344 | 10403726558617828316 |  |
| `Fw.Sched.ParMetrics.serialShare` | disagree | 15651464537387123000 | 4074299351164974373 | The Lean value is in ℚ. With ℕ serial and b ∸ a, '/' reads as floor division. Fix: $$\operatorname{serialShare}_{a,b}(ag) = \operatorname{serial}_{a,b}(ag) / (b \mathbin{\dot-} a) \in \mathbb{Q}\quad (x/0 = 0)$$ |
| `Fw.Sched.ParMetrics.stretch` | disagree | 860301984 | 2968845251363774448 | d, d_solo ∈ ℕ but Lean divides in ℚ (stretch 13 10 = 13/10). The math reads as floor division. Fix: $$\operatorname{stretch}(d, d_{solo}) = d / d_{solo} \in \mathbb{Q}\quad (x/0 = 0)$$ |
| `Fw.Sched.ParMetrics.Edge` | agree | 97089768 | 16844701036615279178 |  |
| `Fw.Sched.ParMetrics.Plus` | agree | 97089768 | 6839058147609081831 |  |
| `Fw.Sched.ParMetrics.PathTo` | agree | 483116935 | 2701717000899834334 |  |
| `Fw.Sched.ParMetrics.weight` | agree | 4142788134 | 3218022254763723447 |  |
| `Fw.Sched.ParMetrics.maxl` | agree | 434822048 | 12985060820351420563 |  |
| `Fw.Sched.ParMetrics.preds` | agree | 3491814348 | 17606229289709482395 |  |
| `Fw.Sched.ParMetrics.look` | agree | 3286129178 | 14711220282593475169 |  |
| `Fw.Sched.ParMetrics.kahn` | agree | 3060975003 | 8738721619558467577 |  |
| `Fw.Sched.ParMetrics.CP` | agree | 3931117990 | 8935747306126617625 |  |
| `Fw.Sched.ParMetrics.cp` | disagree | 11534204576069871869 | 17980132448042945320 | max_{(v,d)∈D} d is undefined for D = [] (n = 0). Lean uses maxl, so cp(0, w, E) = ok(0) (#guard). Fix: $$\mathrm{ok}(\operatorname{maxl}([\, d \mid (v, d) \in D \,]))$$ with maxl([]) = 0. |
| `Fw.Sched.ParMetrics.TopoOk` | agree | 664897157 | 4806038355667817760 |  |
| `Fw.Sched.ParMetrics.KInv` | agree | 14077940 | 3133354710276575137 |  |
| `Fw.Sched.ParMetrics.benchVerdict` | agree | 10376018007185218553 | 5194722878720995711 |  |
| `Fw.Sched.ParMetrics.labeling` | agree | 3826915952 | 7860946251689981886 |  |
| `Fw.Serve.Tbl.empty_ok` | disagree | 15666290570809750230 | 10372738369242109592 | key (and α) are free; Lean quantifies them. Fix: $$\forall \alpha,\ \mathit{key} : \alpha \to \mathrm{String}:\ \operatorname{Ok}_{\mathit{key}}(T_0)$$ |
| `Fw.Serve.Tbl.ok_unique` | disagree | 4756260597300652464 | 7088522381699801840 | key, T, i, j are free, and the hypotheses i, j < \|rows\| are missing. Fix: $$\forall \mathit{key}, T, i, j:\ \operatorname{Ok}_{\mathit{key}}(T) \land i, j < \|\mathit{rows}\| \land \mathit{key}(\mathit{rows}_i) = \mathit{key}(\mathit{rows}_j) \Rightarrow i = j$$ |
| `Fw.Serve.Tbl.has_eq` | disagree | 8829925721849814737 | 13477725039060137814 | key, T, k are free. Fix: $$\forall \mathit{key}, T, k:\ \operatorname{Ok}_{\mathit{key}}(T) \Rightarrow \big(\operatorname{has}(T, k) \iff \exists x \in \mathit{rows}:\ \mathit{key}(x) = k\big)$$ |
| `Fw.Serve.Tbl.get?_eq` | disagree | 15890265255252164933 | 11524133208367705462 | key, T, k are free. Fix: prefix $$\forall \mathit{key}, T, k:$$ to the existing statement. |
| `Fw.Serve.Tbl.push_rows` | disagree | 8915394780415350774 | 6387717122898410212 | key, T, a are free. Fix: $$\forall \mathit{key}, T, a:\ \operatorname{push}_{\mathit{key}}(T, a).\mathit{rows} = \mathit{rows} \mathbin{+\!\!+} [a]$$ |
| `Fw.Serve.Tbl.push_eq` | disagree | 10904644283189860795 | 6361728412151766937 | key, T, a are free. Fix: prefix $$\forall \mathit{key}, T, a:$$ to the existing equation. |
| `Fw.Serve.Tbl.modify_eq` | disagree | 11530726228494533973 | 1782529666597630276 | T, k, f are free, and rows_i is undefined when I(k) = i ≥ \|rows\| (Array.modify then leaves rows unchanged). Fix: prefix ∀ T, k, f, and in the first case add '(rows unchanged if i ≥ \|rows\|)'. |
| `Fw.Serve.Tbl.push_ok` | disagree | 16992309065471658143 | 9145248880581811577 | key, T, a are free. Fix: $$\forall \mathit{key}, T, a:\ \operatorname{Ok}_{\mathit{key}}(T) \land \neg\operatorname{has}(T, \mathit{key}(a)) \Rightarrow \operatorname{Ok}_{\mathit{key}}(\operatorname{push}_{\mathit{key}}(T, a))$$ |
| `Fw.Serve.Tbl.modify_rows` | disagree | 2094035929265395706 | 14430848119380157186 | key, T, k, f are free. Fix: prefix $$\forall \mathit{key}, T, k, f:$$ to the existing statement. |
| `Fw.Serve.Tbl.modify_ok` | disagree | 11815221007861748621 | 10984709756813529017 | key, T, k, f are free. Fix: $$\forall \mathit{key}, T, k, f:\ \operatorname{Ok}_{\mathit{key}}(T) \land (\forall x:\ \mathit{key}(f(x)) = \mathit{key}(x)) \Rightarrow \operatorname{Ok}_{\mathit{key}}(\operatorname{modify}(T, k, f))$$ |
| `Fw.Serve.init_spec` | agree | 8667224817692782203 | 7082305759742569166 |  |
| `Fw.Serve.faccept_seen` | agree | 2130116373964102689 | 2116788689693732311 |  |
| `Fw.Serve.cardStep_id` | agree | 5306531806080204789 | 10974517679077012715 |  |
| `Fw.Serve.fcheck_eq` | agree | 4953775948515773551 | 4035686465556723096 |  |
| `Fw.Serve.faccept_st` | agree | 11163159642241286996 | 4844003924305239176 |  |
| `Fw.Serve.faccept_indexed` | agree | 4829494930155870599 | 8352489468848017892 |  |
| `Fw.Serve.fstep_spec` | agree | 13612523515750259237 | 16835225644668822296 |  |
| `Fw.Serve.fstep_indexed` | agree | 15814977684965599388 | 4839089890313865576 |  |
| `Fw.Serve.fstep_refused` | agree | 14369636723197922194 | 13787110220594294242 |  |
| `Fw.Serve.ftouched_eq` | agree | 2979758777168101404 | 15759978142321812630 |  |
| `Fw.Serve.openIdx_get` | agree | 7221094997660354525 | 17951570803342087060 |  |
| `Fw.Serve.runIdx_get` | disagree | 6661357699925464799 | 6290123984744910305 | Lean: (runIdx rs).getD c 0 = length of a list filter, so repeated equal runs count each time; #{r ∈ rs : …} merges them. getD 0 is also missing. Fix: $$\forall rs, c:\ \operatorname{runIdx}(rs)(c) = \big\|[\, r \in rs \mid r.\mathit{card} = c \land r.\mathit{status} = \mathrm{running} \,]\big\|\ (\text{absent} = 0)$$ |
| `Fw.Serve.fastBoard_eq` | agree | 15098346083994552874 | 4111427817086426268 |  |
| `Fw.Serve.replayFrom_spec` | agree | 8974667838111260243 | 273691569754938160 |  |
| `Fw.Serve.replayFrom_total` | agree | 4060209225386673917 | 7776587946554096011 |  |
| `Fw.Serve.exec_spec` | agree | 4603677423808386358 | 7633774116985326077 |  |
| `Fw.Serve.run_eq_fold` | agree | 9732731179691859771 | 13741300882403909799 |  |
| `Fw.Serve.run_init_eq_project` | agree | 16335224124008482609 | 7542406596116145952 |  |
| `Fw.Serve.apply_each_eq_replay` | agree | 2157702475719106233 | 14106752709589254440 |  |
| `Fw.Serve.run_reset` | agree | 17604175051763858174 | 11889014821283368162 |  |
| `Fw.Serve.refused_unchanged` | agree | 814271196875875393 | 10306024924386529466 |  |
| `Fw.Serve.accepted_changed` | agree | 17413597126318576588 | 14602862819886395788 |  |
| `Fw.Serve.query_keeps` | agree | 4676018755146920640 | 3470355665996898756 |  |
| `Fw.Serve.query_eq_of_st` | agree | 2602241928833209889 | 14438531044217312851 |  |
| `Fw.Serve.query_after_run` | disagree | 17872371203539605148 | 11824348914182331059 | c_1..c_n are not tied to cs, so ev(c_1)++…++ev(c_n) is free. Fix: quantify '∀ cs = [c_1, …, c_n], now, seq', or write ev(cs) = flatMap(ev, cs). |
| `Fw.Serve.Tbl` | agree | 2330190150 | 1516989809364557269 |  |
| `Fw.Serve.Tbl.empty` | agree | 14253053291303610423 | 11110513508888844944 |  |
| `Fw.Serve.Tbl.Ok` | agree | 5577176014194378949 | 1839682172799864829 |  |
| `Fw.Serve.Tbl.has` | agree | 4883561087458788343 | 17226002518937904572 |  |
| `Fw.Serve.Tbl.get?` | agree | 1078366208087814493 | 15826361218376468324 |  |
| `Fw.Serve.Tbl.push` | agree | 14993745518330818836 | 10565338669968289844 |  |
| `Fw.Serve.Tbl.modify` | disagree | 2758336468504801195 | 13949157405125189490 | rows_i and rows[i := …] are undefined when I(k) = i ≥ \|rows\|. Lean's Array.modify then leaves rows unchanged, so modify gives (rows, I). Fix: in the first case add '(rows unchanged if i ≥ \|rows\|)'. |
| `Fw.Serve.Srv` | agree | 3931117990 | 12976513671509071012 |  |
| `Fw.Serve.Srv.st` | agree | 5268116756505246773 | 15459377114826476687 |  |
| `Fw.Serve.init` | agree | 9799685696640054773 | 403406730968821727 |  |
| `Fw.Serve.Indexed` | agree | 1538822114317956051 | 8516050734137762004 |  |
| `Fw.Serve.fcheck` | agree | 9646227764584174646 | 4972352180086439342 |  |
| `Fw.Serve.stepUpd` | agree | 3046642208697140844 | 6755687166918796220 |  |
| `Fw.Serve.runFin` | agree | 2095648672588434901 | 13607215377010077188 |  |
| `Fw.Serve.faccept` | agree | 1395361211614604709 | 10309997589892695057 |  |
| `Fw.Serve.fstep` | agree | 2024321720681594084 | 6931493198413633488 |  |
| `Fw.Serve.fapply` | agree | 1395361211614604709 | 7304377166926185626 |  |
| `Fw.Serve.Delta` | agree | 3931117990 | 10570089205599951968 |  |
| `Fw.Serve.touched` | agree | 14070664391015131680 | 8770640504296050025 |  |
| `Fw.Serve.ftouched` | agree | 2243280147170074315 | 5879114950682146556 |  |
| `Fw.Serve.changed` | agree | 7259886938200936912 | 5414764620606563873 |  |
| `Fw.Serve.openIdx` | agree | 8994815855999336118 | 13484712848984818910 |  |
| `Fw.Serve.runIdx` | disagree | 3149088961631741452 | 11155544571084346974 | #{r ∈ rs : …} merges equal runs, but the Lean fold adds 1 per list entry. Cards with no running run get no entry. Fix: $$\operatorname{runIdx}(rs)(c) = \big\|[\, r \in rs \mid r.\mathit{card} = c \land r.\mathit{status} = \mathrm{running} \,]\big\|$$ (no entry when this is 0). |
| `Fw.Serve.fastRow` | disagree | 17560804047737547872 | 14191643856612305197 | σ is unbound, and R(c.id) is undefined for ids R lacks (Lean: getD 0). Fix: 'frow(O,R,now,c) = row(σ,now,c) for any σ, with m = O(c.id) (⊥ if absent) and ρ = R(c.id) (0 if absent); σ enters row only through m and ρ'. |
| `Fw.Serve.fastBoard` | agree | 18164736976520485792 | 6717979092961881992 |  |
| `Fw.Serve.Cmd` | agree | 3931117990 | 15795175353331166411 |  |
| `Fw.Serve.Cmd.events` | agree | 6804598819987950192 | 12837126141232926744 |  |
| `Fw.Serve.Cmd.isReset` | agree | 5652423615392617053 | 13625177212711308790 |  |
| `Fw.Serve.Tally` | agree | 3931117990 | 502096751923315986 |  |
| `Fw.Serve.Tally.count` | agree | 16674665197411996652 | 1022515375008260901 |  |
| `Fw.Serve.Tally.total` | agree | 10015253176077431210 | 5480404118331454203 |  |
| `Fw.Serve.replayFrom` | agree | 8551501319886340641 | 6987299973281896009 |  |
| `Fw.Serve.Resp` | agree | 3931117990 | 5263163983258842734 |  |
| `Fw.Serve.exec` | agree | 15422401754975484058 | 2825204290825245147 |  |
| `Fw.Serve.run` | agree | 2138018788742317102 | 11441946930924023413 |  |
| `Fw.Ops.Meter.holds_mono` | agree | 13755746736428344074 | 14111238254776271288 |  |
| `Fw.Ops.Meter.verdict_mono` | agree | 18363845018149161362 | 2351333334610486885 |  |
| `Fw.Ops.Meter.mem_fresh` | agree | 16451345316059984595 | 12005197497582269954 |  |
| `Fw.Ops.Meter.fresh_nodup` | agree | 14927412884186281424 | 3490109290407187720 |  |
| `Fw.Ops.Meter.step_complete` | disagree | 11251114897714883634 | 17701819570932181348 | σ, now, O (and p) are free, and w, F_0 are not defined in this formula. Fix: $$\forall p, \sigma, \mathit{now}, O,\ o \in O,\ r:\ r(o) \land (o.\mathit{agent}, r) \notin F_0 \Rightarrow (o.\mathit{agent}, r, w) \in \mathrm{step}(\sigma, \mathit{now}, O).2$$ with w, F_0 as in step. |
| `Fw.Ops.Meter.step_sound` | disagree | 8388803732366841906 | 16693414099387703943 | σ, now and O are free; the Lean quantifies them. Fix: $$\forall p, \sigma, \mathit{now}, O,\ (a, r, w) \in \mathrm{step}(\sigma, \mathit{now}, O).2:\ \exists o \in O:\ o.\mathit{agent} = a \land r(o)$$ |
| `Fw.Ops.Meter.run_inv` | disagree | 16279058002545642417 | 14599621735633770953 | σ and T are free, and the ∀(t,O)∈T scope swallows the ⇒. Fix: $$\forall p, \sigma, T:\ \big(\mathrm{times}(T) \text{ non-decr.} \land \forall (t, O) \in T:\ \sigma.w \le \lfloor t/\omega \rfloor\big) \Rightarrow \big(\text{no repeats} \land \forall (a,r,w) \in \ldots\big)$$ |
| `Fw.Ops.Meter.once_per_window` | agree | 1129875062815222887 | 6532142593372993236 |  |
| `Fw.Ops.Meter.Rule` | agree | 3931117990 | 8021180402488066447 |  |
| `Fw.Ops.Meter.Rule.all` | agree | 15895761131065305935 | 5213083235554443616 |  |
| `Fw.Ops.Meter.Params` | agree | 3931117990 | 13639053612126939293 |  |
| `Fw.Ops.Meter.Obs` | agree | 3931117990 | 3623673564702797934 |  |
| `Fw.Ops.Meter.ttlOf` | agree | 9906956 | 1500471962239534640 |  |
| `Fw.Ops.Meter.holds` | agree | 2836664803629978160 | 7267120829809442457 |  |
| `Fw.Ops.Meter.Obs.le` | agree | 1194510417390499309 | 12000770777096797675 |  |
| `Fw.Ops.Meter.Verdict` | agree | 3931117990 | 14304409302132050125 |  |
| `Fw.Ops.Meter.Verdict.rank` | agree | 2326143106391630979 | 13640392235136228866 |  |
| `Fw.Ops.Meter.verdict` | agree | 14759649746363408326 | 17948654587050596386 |  |
| `Fw.Ops.Meter.Key` | agree | 3931117990 | 7459012839808686186 |  |
| `Fw.Ops.Meter.Alert` | agree | 3931117990 | 302952820006664476 |  |
| `Fw.Ops.Meter.State` | agree | 3931117990 | 6504797316832496705 |  |
| `Fw.Ops.Meter.candidates` | agree | 1021432004006217243 | 7238154574690501894 |  |
| `Fw.Ops.Meter.fresh` | agree | 9004853884327066743 | 14606501436856942241 |  |
| `Fw.Ops.Meter.step` | disagree | 16777480458224403722 | 2779532270715882488 | w = ⌊now/ω⌋ is undefined for ω = 0, which Params allows (windowSec : ℕ); the Lean gives now/0 = 0. Fix: add "w = ⌊now/ω⌋ (w = 0 when ω = 0)". |
| `Fw.Ops.Meter.run` | agree | 2440424061349861473 | 4631733630513432857 |  |
| `Fw.Ops.Meter.exObs` | agree | 8014763603228885922 | 1432083998606666314 |  |
| `Fw.Ops.PathCheck.mem_violations` | agree | 12935302253643871622 | 6941749810752766111 |  |
| `Fw.Ops.PathCheck.violations_nil_iff` | agree | 4381129402091784469 | 14938175599723275089 |  |
| `Fw.Ops.PathCheck.inScope_iff` | disagree | 369270830513400740 | 4487164428022628003 | S and x are free in the theorem math (the Lean quantifies sc, x). Fix: prefix $$\forall S = (I, E),\ x:\quad \mathrm{in}(S, x) \iff \ldots$$ |
| `Fw.Ops.PathCheck.excl_wins` | agree | 7961258246390325305 | 4766604453544750900 |  |
| `Fw.Ops.PathCheck.segMatch_star` | agree | 12812142394897758678 | 5338095094733013986 |  |
| `Fw.Ops.PathCheck.segMatch_lit` | agree | 2870552773482159367 | 6622039994411257602 |  |
| `Fw.Ops.PathCheck.globMatch_dstar` | agree | 9748344683406370836 | 9437524695570610471 |  |
| `Fw.Ops.PathCheck.globMatch_dstar_append` | agree | 11683833588002961729 | 1591148411560251001 |  |
| `Fw.Ops.PathCheck.globMatch_lit` | agree | 85413991701033747 | 16291534366341512570 |  |
| `Fw.Ops.PathCheck.matchesPath_append` | agree | 9215334816138790348 | 11730284304208874187 |  |
| `Fw.Ops.PathCheck.matchesPath_lit` | agree | 17800860954156654056 | 12553570307471685165 |  |
| `Fw.Ops.PathCheck.matchesPath_dstar` | agree | 3388021225791242992 | 7951267620270775910 |  |
| `Fw.Ops.PathCheck.matchesPath_nil` | agree | 3731274587964434789 | 9694604761398256707 |  |
| `Fw.Ops.PathCheck.segs` | agree | 1961493383 | 16676699527280307650 |  |
| `Fw.Ops.PathCheck.segMatch` | agree | 1344957889 | 3686073738783464186 |  |
| `Fw.Ops.PathCheck.globMatch` | agree | 2820148121 | 13996673968795125536 |  |
| `Fw.Ops.PathCheck.matchesPath` | agree | 2820148121 | 5765968696327949114 |  |
| `Fw.Ops.PathCheck.Scope` | agree | 3931117990 | 1749954660464897084 |  |
| `Fw.Ops.PathCheck.parseScope` | agree | 1707559777136268397 | 1293610963587984366 |  |
| `Fw.Ops.PathCheck.inScope` | agree | 5731083005437319666 | 648127145673839519 |  |
| `Fw.Ops.PathCheck.violations` | agree | 2247060916 | 7619128149430425093 |  |
| `Fw.Ops.PathCheck.leanScope` | agree | 4017531403 | 14358802856998491887 |  |
| `Fw.Ops.SpawnGuard.accepted_iff` | agree | 9486929448167159914 | 3607421652723401092 |  |
| `Fw.Ops.SpawnGuard.overRole_none` | disagree | 14251551752926029052 | 6784742783311752021 | R and A are free; the Lean quantifies rs, as. Fix: $$\forall R, A:\quad \mathrm{overRole}(R, A) = \bot \iff \forall (r, c) \in R:\ \#^{r}(A) \le c$$ |
| `Fw.Ops.SpawnGuard.capFail_none` | agree | 6546486869931837363 | 161577892346293453 |  |
| `Fw.Ops.SpawnGuard.check_none` | disagree | 805829739956165195 | 9588412209233931447 | i is free (no ∀ i), though the Lean quantifies it. Fix: prefix $$\forall i:\quad \mathrm{check}(i) = \bot \iff \ldots$$ (the rest is right). |
| `Fw.Ops.SpawnGuard.accepted_within` | agree | 5491372947503127752 | 544275693868153094 |  |
| `Fw.Ops.SpawnGuard.accepted_rate` | agree | 1509530291629105601 | 14340089397001660360 |  |
| `Fw.Ops.SpawnGuard.accepted_names_nodup` | agree | 11241868573068236620 | 9877497307709419710 |  |
| `Fw.Ops.SpawnGuard.name_in_use_denied` | agree | 1514009168576436598 | 4202083485558465721 |  |
| `Fw.Ops.SpawnGuard.trap_worktree_role_as_teammate` | disagree | 12434383979578912908 | 4006789490542732442 | ρ is free; the Lean quantifies r. Fix: $$\forall i, \rho:\quad \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{worktree} \land \lnot q.\mathit{iso} \Rightarrow \lnot\,\mathrm{accepted}(\mathrm{decide}(i))$$ |
| `Fw.Ops.SpawnGuard.trap_exact` | disagree | 5964047166111521356 | 4621153434985813543 | i and ρ are free (no quantifier at all). Fix: $$\forall i, \rho:\quad q.\mathit{name} \ne \texttt{""} \land \lnot\mathrm{taken}(i) \land q.d = 0 \land \lnot q.\mathit{iso} \land \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{worktree} \Rightarrow \ldots$$ |
| `Fw.Ops.SpawnGuard.teammate_with_isolation_denied` | disagree | 12394437821273403957 | 16390383860351113762 | ρ is free; the Lean quantifies r. Fix: $$\forall i, \rho:\quad \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{teammate} \land q.\mathit{iso} \Rightarrow \lnot\,\mathrm{accepted}(\mathrm{decide}(i))$$ |
| `Fw.Ops.SpawnGuard.ask_never_allow` | agree | 15461061302205128765 | 2857940744475394809 |  |
| `Fw.Ops.SpawnGuard.ask_needs_approval` | agree | 8157277889147255540 | 17090176739700827113 |  |
| `Fw.Ops.SpawnGuard.accepted_nested_read_only` | disagree | 8004628514037443770 | 17825521540562202590 | ρ is free; the Lean quantifies r. Fix: $$\forall i, \rho:\quad \mathrm{role}(i) = \rho \land \mathrm{accepted}(\mathrm{decide}(i)) \land q.d \ge 1 \Rightarrow \lnot \rho.\mathit{edits}$$ |
| `Fw.Ops.SpawnGuard.Kind` | agree | 3931117990 | 1056379272161041553 |  |
| `Fw.Ops.SpawnGuard.Role` | agree | 3931117990 | 3531463499221133289 |  |
| `Fw.Ops.SpawnGuard.Agent` | agree | 3931117990 | 3915300355274824474 |  |
| `Fw.Ops.SpawnGuard.Caps` | agree | 3931117990 | 5761652703488716404 |  |
| `Fw.Ops.SpawnGuard.Req` | agree | 3931117990 | 6649203855693138876 |  |
| `Fw.Ops.SpawnGuard.Input` | agree | 3931117990 | 16873158748553313829 |  |
| `Fw.Ops.SpawnGuard.Reason` | agree | 3931117990 | 14539531662458281427 |  |
| `Fw.Ops.SpawnGuard.Decision` | agree | 3931117990 | 816227471741709510 |  |
| `Fw.Ops.SpawnGuard.Decision.accepted` | agree | 17294761278006602248 | 5934414114695333479 |  |
| `Fw.Ops.SpawnGuard.effKind` | agree | 11512716392295839592 | 10483821653242707849 |  |
| `Fw.Ops.SpawnGuard.newAgent` | agree | 88210393069123090 | 10949212561206516294 |  |
| `Fw.Ops.SpawnGuard.countKind` | disagree | 15318421747809857204 | 8908089636973682840 | Lean is the length of a list filter (repeated agents count each time); set-builder \|{…}\| merges equal entries. Fix: $$\#_k(A) = \big\|[\, a \in A : a.\mathit{kind} = k \,]\big\|$$ |
| `Fw.Ops.SpawnGuard.countSub` | disagree | 14414273047122486095 | 4030438151018873322 | List-filter length, not a set cardinality (repeats count). Fix: $$\#_{sub}(A) = \big\|[\, a \in A : a.\mathit{kind} \ne \mathrm{teammate} \,]\big\|$$ |
| `Fw.Ops.SpawnGuard.countRole` | disagree | 10931890675436000845 | 8715773789255364800 | List-filter length, not a set cardinality (repeats count). Fix: $$\#^{r}(A) = \big\|[\, a \in A : a.\mathit{role} = r \,]\big\|$$ |
| `Fw.Ops.SpawnGuard.Within` | agree | 13795276225359352614 | 16641846895341336570 |  |
| `Fw.Ops.SpawnGuard.overRole` | agree | 7763363298659597750 | 10552127053564894553 |  |
| `Fw.Ops.SpawnGuard.recentCount` | disagree | 5236941062931335848 | 41944059156605769 | H is a list and equal (spawner, time) pairs each count (the guards use 10 equal ('lead', 500) entries); set-builder merges them. Fix: $$\mathrm{recent}(i) = \big\|[\, (s, t) \in H : s = q.\mathit{spawner} \land \mathit{now} < t + \Delta \,]\big\|$$ |
| `Fw.Ops.SpawnGuard.hasInfix` | agree | 2423821251 | 10772684093695067539 |  |
| `Fw.Ops.SpawnGuard.isAsk` | agree | 15360677023635179474 | 4795451646708248800 |  |
| `Fw.Ops.SpawnGuard.capFail` | disagree | 7249119862315467034 | 2254350899177039297 | The case conditions overlap (e.g. both teammates > T and worktrees > W), and the Lean is first-match. Fix: mark the cases as "first matching row" or add the negated earlier conditions, e.g. capWorktrees when #_teammate(A') ≤ T ∧ #_worktree(A') > W. |
| `Fw.Ops.SpawnGuard.roleCheck` | disagree | 2061137161209727187 | 4498984334403983960 | The cases overlap (a kind mismatch with a nested editor, rate limit, …), and the Lean is first-match. Fix: state "first matching row" or add the negations: nestedEditor when κ(q) = ρ.runsAs ∧ q.d ≥ 1 ∧ ρ.edits, and so on. |
| `Fw.Ops.SpawnGuard.roleOf` | agree | 2978394618717368621 | 3148416066578270474 |  |
| `Fw.Ops.SpawnGuard.excused` | disagree | 13620722946369271513 | 3445054740057043412 | ρ is free in the formula; the Lean matches on role(i). Fix: $$\mathrm{excused}(i) \iff u \land \exists \rho:\ \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{subagent} \land \lnot \rho.\mathit{edits}$$ |
| `Fw.Ops.SpawnGuard.taken` | agree | 13620722946369271513 | 7657856909984975261 |  |
| `Fw.Ops.SpawnGuard.check` | disagree | 17876292504302604772 | 10192130987720595572 | The cases overlap: unnamed or nameInUse together with role(i) = ⊥. The Lean is first-match (unnamed, then nameInUse, then role). Fix: say "first matching row", or add ¬taken(i) ∧ ¬(name = "" ∧ ¬excused) to the unknownRole and roleCheck rows. |
| `Fw.Ops.SpawnGuard.decide` | agree | 6504251171835932270 | 3752238150641178567 |  |
| `Fw.Ops.SpawnGuard.exRoles` | agree | 10581312192331807162 | 10240479220063274555 |  |
| `Fw.Ops.SpawnGuard.exInput` | agree | 11864956868114791857 | 15491654229926385116 |  |
| `Fw.Ops.Usage.join_comm` | agree | 4710253849232354395 | 1241775256309188611 |  |
| `Fw.Ops.Usage.join_assoc` | agree | 4048976775264969325 | 6607520925227379605 |  |
| `Fw.Ops.Usage.join_idem` | agree | 4221600861633168635 | 12172860703745916837 |  |
| `Fw.Ops.Usage.join_zero` | agree | 7287594748152551673 | 11937028425278815873 |  |
| `Fw.Ops.Usage.ojoin_comm` | agree | 716981653271936440 | 5375689124039924250 |  |
| `Fw.Ops.Usage.ojoin_assoc` | agree | 16529361408401253125 | 9473472317860395834 |  |
| `Fw.Ops.Usage.ojoin_idem` | agree | 8892076202209886250 | 2172531583915031957 |  |
| `Fw.Ops.Usage.ojoin_none` | agree | 14911815835932787808 | 13933575626071157698 |  |
| `Fw.Ops.Usage.get_of_lt` | agree | 5716209964840526793 | 5155206744565568091 |  |
| `Fw.Ops.Usage.ins_keys` | disagree | 10574807479032757668 | 15571405935075992710 | r and t are free; only x is quantified. Fix: $$\forall r, t,\ x \in \mathrm{ins}(r, t):\quad x.\mathit{id} = r.\mathit{id} \lor \exists y \in t:\ x.\mathit{id} = y.\mathit{id}$$ |
| `Fw.Ops.Usage.str_lt_or_gt` | agree | 2341504549 | 15798308650824873288 |  |
| `Fw.Ops.Usage.ins_sorted` | agree | 471065702879465617 | 11087260221399564206 |  |
| `Fw.Ops.Usage.get_ins` | agree | 9041688921865695083 | 593005465490005362 |  |
| `Fw.Ops.Usage.get_merge_gather` | agree | 6654048292885454936 | 18184835053746623243 |  |
| `Fw.Ops.Usage.merge_sorted` | agree | 14249211998329670432 | 11602607659280392966 |  |
| `Fw.Ops.Usage.gather_sorted` | agree | 5629284683422851945 | 11544494259644679435 |  |
| `Fw.Ops.Usage.get_merge` | agree | 11048713451106170660 | 1671951401283290062 |  |
| `Fw.Ops.Usage.ext` | agree | 12331756832910544884 | 14971801288477049218 |  |
| `Fw.Ops.Usage.merge_comm` | agree | 1962970039389670335 | 17009534124332386766 |  |
| `Fw.Ops.Usage.merge_assoc` | agree | 1446143016071662339 | 17470735430878727287 |  |
| `Fw.Ops.Usage.merge_idem` | agree | 10162126040559736775 | 10661639153934263370 |  |
| `Fw.Ops.Usage.ingest_sorted` | agree | 17117570956000424081 | 9927565284537171072 |  |
| `Fw.Ops.Usage.get_ingest` | agree | 3563074357799136866 | 4038236794390082353 |  |
| `Fw.Ops.Usage.gather_perm` | agree | 13544987434475137123 | 13969529311088762078 |  |
| `Fw.Ops.Usage.ingest_perm` | agree | 3548141514884912225 | 9858640627655754475 |  |
| `Fw.Ops.Usage.gather_append` | agree | 15698447193530188162 | 493255672496046729 |  |
| `Fw.Ops.Usage.ingest_append` | agree | 4072403404565378653 | 13519066904809321635 |  |
| `Fw.Ops.Usage.ingest_dup` | agree | 2558811448890086203 | 5905070797205792022 |  |
| `Fw.Ops.Usage.Usage` | agree | 3931117990 | 1033447189710563430 |  |
| `Fw.Ops.Usage.Usage.join` | agree | 9480543259895828246 | 12096454451482309901 |  |
| `Fw.Ops.Usage.Usage.add` | agree | 9480543259895828246 | 10748743560773506524 |  |
| `Fw.Ops.Usage.ojoin` | agree | 218098713881059253 | 9269981049357735906 |  |
| `Fw.Ops.Usage.Table` | agree | 3931117990 | 5262615951793324526 |  |
| `Fw.Ops.Usage.Sorted` | agree | 4385555627205615141 | 2944260032980640453 |  |
| `Fw.Ops.Usage.get` | agree | 2653976321571166146 | 6451566629908379824 |  |
| `Fw.Ops.Usage.ins` | agree | 10146744403083757326 | 6148337235163597742 |  |
| `Fw.Ops.Usage.merge` | agree | 16065352755871361623 | 16300476361966562957 |  |
| `Fw.Ops.Usage.ingest` | agree | 443133856313385135 | 15460993060111779305 |  |
| `Fw.Ops.Usage.gather` | agree | 9886868903336287809 | 15230319815222901091 |  |
| `Fw.Ops.Usage.total` | agree | 104267338255300954 | 18343115976371405232 |  |
| `Fw.Ops.Usage.lastWins` | disagree | 443133856313385135 | 6946244636749996088 | The result is a list, but its order is not given (Lean: survivors in line order). Fix: $$\mathrm{lastWins}(l) = [\, l_i : i < \|l\|,\ \forall i' > i:\ l_{i'}.\mathit{id} \ne l_i.\mathit{id} \,]$$ (in index order). |
| `Fw.Ops.Usage.exLines` | disagree | 12153952940135557592 | 6917057207019584242 | English has the wrong order: it says output 5, then output 3, but the list (and the math) is output 3, then output 5. Fix the English: 'output 3, then output 5'. Optionally add 'all other fields 0' to the math. |
| `Fw.Null.null_prob_5v5` | agree | 18075036907877158627 | 12573529771365051628 |  |
| `Fw.Null.null_prob_3v3` | agree | 6489614198802959727 | 4421992263835721552 |  |
| `Fw.Measure.mem_pairVals` | agree | 6636699135471761656 | 10675334945891378513 |  |
| `Fw.Measure.of_mem_pairVals` | agree | 8757058033327226236 | 18091552892266055309 |  |
| `Fw.Measure.le_maxOf` | agree | 402788507859230878 | 5534286400301955520 |  |
| `Fw.Measure.maxOf_le` | agree | 4325398493808774828 | 7940197986245551815 |  |
| `Fw.Measure.le_obs` | agree | 13451303423807748807 | 8711427673228823302 |  |
| `Fw.Measure.obs_le` | agree | 2468621134342217711 | 16334769664397668953 |  |
| `Fw.Measure.Class.le` | agree | 10815727072737250461 | 5897436628453810589 |  |
| `Fw.Measure.classify` | agree | 4365503056447931362 | 11535106609120756113 |  |
| `Fw.Measure.Admissible` | agree | 16612968250247939391 | 10632572989657668579 |  |
| `Fw.Measure.valAt_cons_zero` | agree | 15777937534269648769 | 6959879314703521243 |  |
| `Fw.Measure.valAt_cons_succ` | agree | 5530680968361843191 | 5995191532211697534 |  |
| `Fw.Measure.valAt_nil` | agree | 6897084323336475097 | 12710509091312152648 |  |
| `Fw.Measure.forall_nat_split` | agree | 1857868817 | 16323069418182441256 |  |
| `Fw.Measure.stable_frames_unsound` | agree | 18233019987136091141 | 7338074299054840781 |  |
| `Fw.Measure.margin_sound` | agree | 8168097739944979335 | 7755871971305281693 |  |
| `Fw.Measure.typeOk_sound` | agree | 7133921010868635016 | 5163218261629835335 |  |
| `Fw.Measure.noMoreWork_sound` | agree | 9997276766248713760 | 13458020259461893400 |  |
| `Fw.Measure.promise_total` | agree | 5128735658350405641 | 15529712221862770171 |  |
| `Fw.Measure.noMoreWork_cost` | agree | 7157085185538849944 | 1462208285325040357 |  |
| `Fw.Measure.WebKit.place_step_lt` | agree | 14129300563033836998 | 15370230011727238996 |  |
| `Fw.Measure.WebKit.sum_partition_range` | agree | 10114943881604380211 | 9366749446801444520 |  |
| `Fw.Measure.WebKit.steps_partition` | agree | 973303652374035453 | 11803607179929098489 |  |
| `Fw.Measure.WebKit.rows_conserved` | agree | 14502404216174526813 | 5370172468736145849 |  |
| `Fw.Measure.WebKit.zoneIx_lt` | agree | 5521191523064346135 | 9638114191730092873 |  |
| `Fw.Measure.WebKit.inv_step` | agree | 13438233413361943372 | 5121953004760036385 |  |
| `Fw.Measure.WebKit.inv_foldl` | agree | 15576517556166428745 | 1521500178892192379 |  |
| `Fw.Measure.WebKit.inv_stats` | agree | 2975618593375659832 | 33009355220247475 |  |
| `Fw.Measure.WebKit.stats_snoc` | agree | 16122121228540269532 | 10199894975123214722 |  |
| `Fw.Measure.WebKit.spread_step` | agree | 1951591541450519475 | 8258075487910706963 |  |
| `Fw.Measure.WebKit.cellStatus_snoc` | agree | 2041925030879651644 | 5494901158267466211 |  |
| `Fw.Measure.WebKit.maxOf_map_le` | agree | 4129911459868968161 | 12708315316840607636 |  |
| `Fw.Measure.WebKit.classifyCells_snoc` | agree | 7429653682100254942 | 16118663749918945103 |  |
| `Fw.Measure.WebKit.const_of_spread_zero` | agree | 1196543588850179280 | 4347411443429738449 |  |
| `Fw.Measure.WebKit.classifyCells_det_holds` | agree | 1868862034747537152 | 15626600522133814778 |  |
| `Fw.Measure.WebKit.classifyCells_det_iff` | agree | 10142406327214317105 | 1295907290467122686 |  |
| `Fw.Measure.WebKit.keysOf_singletons` | agree | 6918812425755989884 | 14259154844687056799 |  |
| `Fw.Measure.WebKit.symDiff_terms_comm` | agree | 3593551289043951633 | 14535779480324395140 |  |
| `Fw.Measure.WebKit.summarize_worst` | agree | 7403079843117610682 | 7474042525945396254 |  |
| `Fw.Measure.WebKit.Tally` | agree | 3931117990 | 3490857730437147818 |  |
| `Fw.Measure.WebKit.countType` | agree | 587461394105216975 | 18222334133082062310 |  |
| `Fw.Measure.WebKit.stepOf` | agree | 1413513732 | 1949915561559937098 |  |
| `Fw.Measure.WebKit.Place` | agree | 3931117990 | 6867157602273858546 |  |
| `Fw.Measure.WebKit.place` | agree | 7936059542731249505 | 13439616639508780614 |  |
| `Fw.Measure.WebKit.Reduced` | agree | 3931117990 | 606122356937355674 |  |
| `Fw.Measure.WebKit.reduceSteps` | disagree | 7182257889439989746 | 1523849080201891022 | The r4 fix (b63572c) replaced the whole $$ with only the last field \|[r∈R \| place=before]\|, so it no longer defines reduceSteps. Restore: reduceSteps(R,M,e) = ([tally(R_k).counts]_{k<\|M\|}, [tally(R_k).paintArea]_{k<\|M\|}, tally(W(R)), \|[r∈R \| place(M,e,r)=before]\|) |
| `Fw.Measure.WebKit.WZone` | agree | 3931117990 | 12932779634792765606 |  |
| `Fw.Measure.WebKit.stats` | agree | 2988002467 | 15652179841233071729 |  |
| `Fw.Measure.WebKit.classifyCells` | agree | 11158056407918044845 | 11850290406503799888 |  |
| `Fw.Measure.WebKit.CRow` | agree | 3931117990 | 602422254429756193 |  |
| `Fw.Measure.WebKit.summarize` | agree | 17346974674929751393 | 7735695950121976814 |  |
| `Fw.Measure.sumBy_append` | agree | 15647582540199657352 | 11992310841170849912 |  |
| `Fw.Measure.sumBy_congr` | agree | 14406787293401102937 | 6613135710248964584 |  |
| `Fw.Measure.sumBy_mono` | agree | 281945892509906224 | 3913962314188812487 |  |
| `Fw.Measure.sumBy_nonneg` | agree | 8970722563538727727 | 3658656643356135807 |  |
| `Fw.Measure.sumBy_map` | agree | 432525635984642504 | 2472349041428449674 |  |
| `Fw.Measure.sumBy_one` | agree | 15911232535078067984 | 991646210773245214 |  |
| `Fw.Measure.tag_append` | agree | 13391686364065910876 | 5496170999603967714 |  |
| `Fw.Measure.tag_ids` | agree | 9452240659416139499 | 5715277465553695711 |  |
| `Fw.Measure.sumBy_rows_tag` | agree | 7499317909518203148 | 8226313316315334322 |  |
| `Fw.Measure.length_rows_tag` | agree | 2995601724491961856 | 2263720597809411415 |  |
| `Fw.Measure.mem_insKey` | agree | 9340818374163425608 | 14968327545388015095 |  |
| `Fw.Measure.countIn_eq_zero_of_not_mem_foldr` | agree | 15522053012292330328 | 1959579851205999580 |  |
| `Fw.Measure.sumBy_eq_zero_of_not_mem_keys` | agree | 3745710538136767383 | 13385737077666235269 |  |
| `Fw.Measure.lookup_map_keys` | agree | 876736841 | 3134872777470114396 |  |
| `Fw.Measure.zoneOf_sum` | agree | 15830398160613585906 | 12291541475186119603 |  |
| `Fw.Measure.find_map_zoneOf` | agree | 6978991901957499161 | 13195464415593432988 |  |
| `Fw.Measure.firstSeen_aux` | agree | 1992975206 | 18191008620052248971 |  |
| `Fw.Measure.firstSeen_nodup` | agree | 25374702463417174 | 12087604077364677568 |  |
| `Fw.Measure.mem_firstSeen` | agree | 3226367232712550972 | 4313922584096885455 |  |
| `Fw.Measure.sum_partition` | agree | 16698476959894021456 | 10434737275375453926 |  |
| `Fw.Measure.rowsOf_eq_nil_of_not_mem` | agree | 18413942491248102189 | 16921168018615418849 |  |
| `Fw.Measure.framesAt_spec` | agree | 8933016369799741017 | 16824882291210128999 |  |
| `Fw.Measure.sumBy_filter_below` | agree | 11156018339986313942 | 4918784052006984961 |  |
| `Fw.Measure.zoneIds_zoneSumsFrom` | agree | 3067824238693863970 | 12077419137428557352 |  |
| `Fw.Measure.sumBy_zones` | agree | 3535941583735736722 | 12635002621279578700 |  |
| `Fw.Measure.cover_tag` | agree | 1343907616655754875 | 9362745937475583536 |  |
| `Fw.Measure.sumBy_tag_counts` | agree | 8071384096479203838 | 13453242854072217696 |  |
| `Fw.Measure.sumBy_tag_dy` | agree | 16969251380269620173 | 4046916362960181396 |  |
| `Fw.Measure.length_tag` | agree | 16755015601265272645 | 6537187011278463933 |  |
| `Fw.Measure.zoneId` | agree | 7442719906477834373 | 7918689239946854518 |  |
| `Fw.Measure.insKey` | agree | 1154949025 | 3952989683885008921 |  |
| `Fw.Site.Breakpoints.gap1000` | agree | 10826935179828543176 | 3356751727707973050 |  |
