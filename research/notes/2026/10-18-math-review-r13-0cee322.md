---
title: Math review round 13 at 0cee322 (math-final pass 1: engine models, part proofs, platform port, plan lint, land scope)
date: 2026-10-18
status: CONFIRMED
round: 13
---

# Math review round 13 at 0cee322

Four math-reviewer agents (workflow `review-r13`, read-only) back-translated the 936 pending or stale declarations at
0cee322, listed reproducibly by `node scripts/math-pending.mjs --batches 4` (task math-pending-tool): the engine models
(Chromium, WebKit, EngineCheck), the part proofs of waves 1 and 2, the platform port, Plan.Lint and Console.Land.
Method as in rounds 3 to 11; ShadowLint and WhereLint are build errors. The lead wrote this record from the agents' structured verdicts; `stmtHash` and
`mathHash` come from `lake exe mathview` at 0cee322.

## Counts

| Batch | Reviewed | Agree | Disagree |
|---|---|---|---|
| A | 234 | 226 | 8 |
| B | 236 | 188 | 48 |
| C | 233 | 228 | 5 |
| D | 233 | 222 | 11 |
| **Total** | 936 | 864 | 72 |

Batches are module-balanced by the script; each module sits in exactly one batch (see the tsv files named in the handoff docs/team/handoffs/math-final.md).

## Rows

| Declaration | Verdict | stmtHash | mathHash | Note |
|---|---|---|---|---|
| `Fw.Ci.Budget.statusOf` | agree | 4186552515 | 14719122184741539660 |  |
| `Fw.Gate.pilotParts` | disagree | 13871602926479079190 | 539306716148607846 | Math lists 6 parts; Lean has 14: adds morph.mount (after hero.exit; O=[morph.mount], C=[], D=[js.morph-arm]), morph.tween, platform, platform.sweep, platform.stageBg, platform.glint, platform.entries, platform.marquee. Fix: list all 14 entries in source order with their C_orig, C_rw, Kn, D. |
| `Fw.Gate.pilot_conds_known` | agree | 16610297153154524803 | 7526050284835420810 |  |
| `Fw.Gate.scope_covers` | agree | 13056712425987396169 | 17128440888733101845 |  |
| `Fw.Gate.scope_sweeps_covered` | agree | 945521708704454246 | 6346691640250470344 |  |
| `Fw.Gate.scope_observes_edges` | agree | 15167964310697366834 | 16622346301872691559 |  |
| `Fw.Gate.scope_sound` | agree | 17485920647293165452 | 8618996965993508778 |  |
| `Fw.Gate.scope_union_sound` | agree | 15549911455980981079 | 3169694580590222245 |  |
| `Fw.Measure.Freeze.RunTable` | agree | 3931117990 | 7568588942517639099 |  |
| `Fw.Parts.HeroCountdownOpt.DigitGeo` | agree | 3931117990 | 4092450301158871651 |  |
| `Fw.Parts.HeroCountdownOpt.glyph` | agree | 1095758614284817164 | 6563283053011333684 |  |
| `Fw.Parts.HeroCountdownOpt.glyphId` | agree | 17101314598916428630 | 13282606125027319084 |  |
| `Fw.Parts.HeroCountdownOpt.facesDigit` | agree | 1495848687830500940 | 4137510251054639584 |  |
| `Fw.Parts.HeroCountdownOpt.stripEntries` | agree | 94281387 | 2048107762130777036 |  |
| `Fw.Parts.HeroCountdownOpt.mem_stripEntries` | agree | 15471543893951261682 | 8567172830922775306 |  |
| `Fw.Parts.HeroCountdownOpt.stripDigit` | agree | 1495848687830500940 | 9491335928496658458 |  |
| `Fw.Parts.HeroCountdownOpt.facesClock` | agree | 8082971128054792893 | 17283524018565437742 |  |
| `Fw.Parts.HeroCountdownOpt.stripClock` | agree | 8082971128054792893 | 130369151274242574 |  |
| `Fw.Parts.HeroCountdownOpt.glyph_kept_window` | agree | 10727834713374244364 | 1896990623093090163 |  |
| `Fw.Parts.HeroCountdownOpt.filter_map_unique` | agree | 1698745521 | 17684925695014138075 |  |
| `Fw.Parts.HeroCountdownOpt.strip_glyph_same` | agree | 8403993468918997727 | 14502477278998057231 |  |
| `Fw.Parts.HeroCountdownOpt.flatMap_congr'` | agree | 3397308229 | 2387656768674045530 |  |
| `Fw.Parts.HeroCountdownOpt.strip_digit_same` | agree | 18382259277415568644 | 4759360711672912240 |  |
| `Fw.Parts.HeroCountdownOpt.strip_visSame` | agree | 7568816997523300239 | 15885283987513192884 |  |
| `Fw.Parts.HeroCountdownOpt.faceWrites` | agree | 8521999773025639467 | 8955992006893986242 |  |
| `Fw.Parts.HeroCountdownOpt.stripWrites` | agree | 8521999773025639467 | 2915760791628098825 |  |
| `Fw.Parts.HeroCountdownOpt.withWrites` | agree | 8238079875145044081 | 3395406378569705056 |  |
| `Fw.Parts.HeroCountdownOpt.faceWrites_stages` | agree | 3077227441187042105 | 13720764373441511228 |  |
| `Fw.Parts.HeroCountdownOpt.stripWrites_stages` | agree | 9617247757916896171 | 793188086796365161 |  |
| `Fw.Parts.HeroCountdownOpt.faceWrites_isEmpty` | agree | 4272601806396727130 | 16838806916272461510 |  |
| `Fw.Parts.HeroCountdownOpt.stripWrites_isEmpty` | agree | 9451168164852628165 | 18402554461800272109 |  |
| `Fw.Parts.HeroCountdownOpt.faceWrites_count` | agree | 11155839510831340696 | 231971887681831143 |  |
| `Fw.Parts.HeroCountdownOpt.stripWrites_count` | agree | 16508650528920204534 | 6981204431391031973 |  |
| `Fw.Parts.HeroCountdownOpt.touched_congr` | agree | 8425284775392855510 | 304089427072369078 |  |
| `Fw.Parts.HeroCountdownOpt.strip_passes_eq` | agree | 15210480751016418976 | 13145672784720606233 |  |
| `Fw.Parts.HeroCountdownOpt.strip_units` | agree | 18268984947084393927 | 8420928209748334006 |  |
| `Fw.Parts.HeroCountdownOpt.strip_frame_le` | agree | 18278868392039435818 | 14511165906661575154 |  |
| `Fw.Parts.HeroCountdownOpt.strip_frame_lt` | agree | 16989944603900755933 | 3711658548215374113 |  |
| `Fw.Parts.HeroCountdownOpt.facesRun` | agree | 12976123221728664764 | 9339022000415378056 |  |
| `Fw.Parts.HeroCountdownOpt.stripRun` | agree | 12976123221728664764 | 1018277893200068049 |  |
| `Fw.Parts.HeroCountdownOpt.rolls` | agree | 16522316529147643950 | 8109266790749033998 |  |
| `Fw.Parts.HeroCountdownOpt.strip_leAll` | agree | 11378881539823681388 | 11966318720898688160 |  |
| `Fw.Parts.HeroCountdownOpt.strip_someLt` | agree | 11842237358370174476 | 12315986173230449597 |  |
| `Fw.Parts.HeroCountdownOpt.strip_run_eq_of_still` | agree | 14640870508648115688 | 796914930282865384 |  |
| `Fw.Parts.HeroCountdownOpt.strip_claim` | agree | 12172460647909983199 | 11120600827100257741 |  |
| `Fw.Parts.HeroCountdownOpt.cr_strip` | agree | 14250592483280110807 | 9924890173674930565 |  |
| `Fw.Parts.HeroCountdownOpt.wk_strip` | agree | 6434038798646931744 | 885211145641952841 |  |
| `Fw.Parts.HeroCountdownOpt.Host` | agree | 3931117990 | 17165117281260071720 |  |
| `Fw.Parts.HeroCountdownOpt.owns` | agree | 18253191163862223734 | 9171949684702181258 |  |
| `Fw.Parts.HeroCountdownOpt.wk_owns` | agree | 17039434343309589955 | 8115578459746602127 |  |
| `Fw.Parts.HeroCountdownOpt.facesResident` | agree | 13006517187122969297 | 7002434813961127043 |  |
| `Fw.Parts.HeroCountdownOpt.stripResident` | agree | 13006517187122969297 | 12856289917327289475 |  |
| `Fw.Parts.HeroCountdownOpt.clockDigits` | agree | 2546708756 | 1593753116592889322 |  |
| `Fw.Parts.HeroCountdownOpt.strip_layers_lt` | agree | 2735815091438832290 | 13266479018972128104 |  |
| `Fw.Parts.HeroCountdownOpt.hero_layers` | agree | 8879589157254364938 | 14618970819878177580 |  |
| `Fw.Parts.HeroCountdownOpt.strip_backing_gt` | agree | 4250367500823443699 | 16350772162777138180 |  |
| `Fw.Parts.HeroCountdownOpt.strip_label_fullLayer` | agree | 8367777481124107166 | 2272011097477698356 |  |
| `Fw.Parts.HeroCountdownOpt.uncomposited_same` | agree | 4805476722105137737 | 5262173815552553103 |  |
| `Fw.Parts.HeroCountdownOpt.wk_conservative_same` | agree | 4173681234953358762 | 1704964487219441092 |  |
| `Fw.Parts.HeroCountdownOpt.paused_same` | agree | 10723366768031024794 | 11421339755345277394 |  |
| `Fw.Parts.HeroCountdownOpt.wk_normal_layers` | agree | 6795309172127691454 | 733903487446848308 |  |
| `Fw.Parts.HeroCountdownOpt.layersPred` | agree | 1249826691 | 8715452784899860212 |  |
| `Fw.Parts.HeroCountdownOpt.variantName` | agree | 3265150928 | 6760195447662673786 |  |
| `Fw.Parts.HeroCountdownOpt.goldenRow` | agree | 3438944622 | 10529205223951928754 |  |
| `Fw.Parts.HeroCountdownOpt.goldenJsonl` | agree | 3265150928 | 14790159297621262074 |  |
| `Fw.Parts.MorphMount.Action.after` | agree | 11714304022762680895 | 12200996989552923043 |  |
| `Fw.Parts.MorphMountGolden.rin` | agree | 893280584 | 12687645030207746003 |  |
| `Fw.Parts.MorphMountGolden.rects` | agree | 2453996840 | 2332230705970153559 |  |
| `Fw.Parts.MorphMountGolden.lines` | agree | 4017531403 | 14438101962430281740 |  |
| `Fw.Parts.MorphMountOpt.Tick` | agree | 3931117990 | 14746091565848073116 |  |
| `Fw.Parts.MorphMountOpt.mountO` | agree | 18033310738836025617 | 13171869557597336112 |  |
| `Fw.Parts.MorphMountOpt.mountV` | agree | 18033310738836025617 | 501956930368949317 |  |
| `Fw.Parts.MorphMountOpt.mountO_stays` | agree | 8616743005770971356 | 13015555639569696945 |  |
| `Fw.Parts.MorphMountOpt.mountV_of_mountO` | agree | 5148369473797396777 | 2770016700018424049 |  |
| `Fw.Parts.MorphMountOpt.sceneOf` | agree | 1662452840781647516 | 12798123287550468204 |  |
| `Fw.Parts.MorphMountOpt.armO` | agree | 458828559400219659 | 4923501572405391197 |  |
| `Fw.Parts.MorphMountOpt.armV` | agree | 458828559400219659 | 8609224257096663761 |  |
| `Fw.Parts.MorphMountOpt.PhaseFree` | agree | 14866642561593574490 | 13387085427258189015 |  |
| `Fw.Parts.MorphMountOpt.HiddenBefore` | agree | 5001713318930125596 | 6408597881120274712 |  |
| `Fw.Parts.MorphMountOpt.visible_append` | agree | 14521702014709282445 | 17545452837417887744 |  |
| `Fw.Parts.MorphMountOpt.E_after_mount` | agree | 1169076626541809764 | 7546658353272745150 |  |
| `Fw.Parts.MorphMountOpt.visSame_mount` | agree | 14426745635971797740 | 15855337263252191655 |  |
| `Fw.Parts.MorphMountOpt.merge` | agree | 6768640875653155234 | 4825661470562808028 |  |
| `Fw.Parts.MorphMountOpt.arm` | agree | 2342671129046661516 | 12534036708189898956 |  |
| `Fw.Parts.MorphMountOpt.mem_touched` | agree | 16795602433329946933 | 16744046500884775814 |  |
| `Fw.Parts.MorphMountOpt.mem_touched_merge` | agree | 8370125727436043299 | 11254126927842243054 |  |
| `Fw.Parts.MorphMountOpt.units_merge` | agree | 8297062969132643946 | 15957794039349726405 |  |
| `Fw.Parts.MorphMountOpt.forced_merge` | agree | 4092937625375906739 | 15551850927442161943 |  |
| `Fw.Parts.MorphMountOpt.extra` | agree | 6748605792814343796 | 4683841512680699251 |  |
| `Fw.Parts.MorphMountOpt.passes_merge` | agree | 18073026740316219724 | 12292604096392710720 |  |
| `Fw.Parts.MorphMountOpt.le_merge` | agree | 15543528217510208314 | 14607690409227240477 |  |
| `Fw.Parts.MorphMountOpt.frameAt_arm` | agree | 2021723914993436358 | 4947387893003107097 |  |
| `Fw.Parts.MorphMountOpt.total_units` | agree | 11942696547959646380 | 12319502819618086842 |  |
| `Fw.Parts.MorphMountOpt.total_passes` | agree | 4427199121710655808 | 7764373870920708141 |  |
| `Fw.Parts.MorphMountOpt.total_hits` | agree | 1992924532644036914 | 14416918823250507107 |  |
| `Fw.Parts.MorphMountOpt.sum_bump` | agree | 3581301750 | 4173877718505234865 |  |
| `Fw.Parts.MorphMountOpt.Work.max_le_max` | agree | 1478687795950690441 | 15572896425880301037 |  |
| `Fw.Parts.MorphMountOpt.peak_mono` | agree | 17831943856273571713 | 1151245457392712306 |  |
| `Fw.Parts.MorphMountOpt.peak_units_lt` | agree | 643382775972785241 | 12714932150088499133 |  |
| `Fw.Parts.MorphMountOpt.ShiftLt` | agree | 9256173328535474475 | 2998665930001924517 |  |
| `Fw.Parts.MorphMountOpt.shift_units` | agree | 12829546930806118924 | 6716074436586587275 |  |
| `Fw.Parts.MorphMountOpt.shift_hits` | agree | 16435731725199782285 | 7474292519718572441 |  |
| `Fw.Parts.MorphMountOpt.shift_passes` | agree | 13259056367532963826 | 625471117064434039 |  |
| `Fw.Parts.MorphMountOpt.shift_passes_eq` | agree | 7281990642621391847 | 15580653814440321252 |  |
| `Fw.Parts.MorphMountOpt.shift_passes_succ` | agree | 6989401282515701455 | 9867700151936232858 |  |
| `Fw.Parts.MorphMountOpt.shift_peak_lt` | agree | 15550758482731629265 | 9262628449363585734 |  |
| `Fw.Parts.MorphMountOpt.mount_shift` | agree | 9549036822149623058 | 9847342136541614347 |  |
| `Fw.Parts.MorphMountOpt.shift_mainUs` | agree | 9309590881011322918 | 3406637114716325222 |  |
| `Fw.Parts.MorphMountOpt.shift_of_passes` | agree | 694818144012014585 | 1333115670214311083 |  |
| `Fw.Parts.MorphMountOpt.leVec_refl` | agree | 4412365625844625814 | 17891219814780506886 |  |
| `Fw.Parts.MorphMountOpt.leRun_refl` | agree | 5234648737521893483 | 3749510394457044442 |  |
| `Fw.Parts.MorphMountOpt.units_of_leVec` | agree | 4845195213907369882 | 1165293035260448497 |  |
| `Fw.Parts.MorphMountOpt.units_of_leRun` | agree | 3987088630361553051 | 18142452553242596223 |  |
| `Fw.Parts.MorphMountOpt.arm_length` | agree | 7512788815652260368 | 10748458499309673482 |  |
| `Fw.Parts.MorphMountOpt.shift_screen_mixed` | agree | 7972294983928649672 | 5053871285315768637 |  |
| `Fw.Parts.MorphMountOpt.mountCr` | agree | 1759703767827629274 | 3372205567164679749 |  |
| `Fw.Parts.MorphMountOpt.mountWk` | agree | 16991382746948856284 | 11535806103750897531 |  |
| `Fw.Parts.MorphMountOpt.scrollCr` | agree | 17946780828110619414 | 10717500921122830942 |  |
| `Fw.Parts.MorphMountOpt.scrollWk` | agree | 13735895882983308574 | 14883062931683755461 |  |
| `Fw.Parts.MorphMountOpt.mountCr_layout` | agree | 2820408985788103866 | 1579211939520326949 |  |
| `Fw.Parts.MorphMountOpt.mountWk_layout` | agree | 9570875174598877839 | 5880540393188455167 |  |
| `Fw.Parts.MorphMountOpt.scrollCr_layout` | agree | 17509590520564124839 | 5881664889231670052 |  |
| `Fw.Parts.MorphMountOpt.scrollWk_layout` | agree | 907784445959643967 | 1044153352968166746 |  |
| `Fw.Parts.MorphMountOpt.chromium_shift` | agree | 11365209205955388479 | 10276393185366582583 |  |
| `Fw.Parts.MorphMountOpt.webkit_shift` | agree | 13130831857060462271 | 8042997512267060904 |  |
| `Fw.Parts.MorphMountOpt.chromium_mixed` | agree | 15041225423471257353 | 13331182233777736003 |  |
| `Fw.Parts.MorphMountOpt.webkit_mixed` | agree | 12135590463586935523 | 1364878474213893028 |  |
| `Fw.Parts.MorphMountOpt.idle` | agree | 18427575540590717088 | 11946913985720334277 |  |
| `Fw.Parts.MorphMountOpt.swipeCr` | agree | 1759703767827629274 | 6626008690027101850 |  |
| `Fw.Parts.MorphMountOpt.swipeWk` | agree | 16991382746948856284 | 16318705608270013240 |  |
| `Fw.Parts.MorphMountOpt.motion` | agree | 403126073 | 2306739917665414805 |  |
| `Fw.Parts.MorphMountOpt.crO` | agree | 9670317657891034104 | 16727525401157106245 |  |
| `Fw.Parts.MorphMountOpt.crV` | agree | 9670317657891034104 | 17005008777069670916 |  |
| `Fw.Parts.MorphMountOpt.wkO` | agree | 9670317657891034104 | 18350224059032163201 |  |
| `Fw.Parts.MorphMountOpt.wkV` | agree | 9670317657891034104 | 11450182287065219175 |  |
| `Fw.Parts.MorphMountOpt.cr_swipe_shift` | agree | 12047954727145012250 | 2386229682034586631 |  |
| `Fw.Parts.MorphMountOpt.wk_swipe_shift` | agree | 18066861623442273604 | 7955158608329821154 |  |
| `Fw.Parts.MorphMountOpt.cr_swipe_mixed` | agree | 14283144658199478640 | 5761978665181017168 |  |
| `Fw.Parts.MorphMountOpt.wk_swipe_mixed` | agree | 14181660596646686995 | 11376397351499530808 |  |
| `Fw.Parts.MorphMountOpt.chromium_not_shift` | agree | 8849856220332289187 | 1159778968121732883 |  |
| `Fw.Parts.MorphMountOpt.webkit_not_shift` | agree | 13772533823043978103 | 652261364104622619 |  |
| `Fw.Parts.MorphMountOpt.CountType` | agree | 3931117990 | 8726310551053859952 |  |
| `Fw.Parts.MorphMountOpt.stageName` | agree | 13237354143774927416 | 5018164951693487975 |  |
| `Fw.Parts.MorphMountOpt.series` | agree | 2861599138941898419 | 7256318397167537554 |  |
| `Fw.Parts.MorphMountOpt.predict` | agree | 2340511515 | 14935060714063386997 |  |
| `Fw.Parts.MorphMountOpt.crTypes` | disagree | 13733811795767940606 | 2513869422180326138 | Math only states \|crTypes\|=8; definition lists 8 (name, stage, units, exact) entries. Fix: list them: (trace.FunctionCall,script,T,T),(trace.UpdateLayoutTree,style,F,T),(trace.Layout,layout,F,F),(trace.Layout.dirtyObjects,layout,T,F),(metric.LayoutCount,layout,F,F),(trace.PrePaint,props,F,F),(raster.invalidationAreaPx,paint,T,F),(trace.cc.Commit,commit,F,T). |
| `Fw.Parts.MorphMountOpt.wkTypes` | disagree | 13733811795767940606 | 6771344442657314112 | Math only states \|wkTypes\|=4. Fix: wkTypes = [(RecalculateStyles,style,F,F),(Layout,layout,F,F),(Paint,paint,F,F),(Composite,commit,F,F)] as (name, stage, units, exact). |
| `Fw.Parts.MorphMountOpt.row` | agree | 10594729171394810334 | 3278965477312053878 |  |
| `Fw.Parts.MorphMountOpt.goldenLines` | disagree | 4017531403 | 5755997058793103302 | Math only states the length 20. Fix: goldenLines = [row(chromium, sc, t, crV, crO) \| sc in [swipe-v1, swipe-touch-v1], t in crTypes] ++ [row(webkit, swipe-v1, t, wkV, wkO) \| t in wkTypes], length 20. |
| `Fw.Parts.MorphMountOpt.goldenText` | agree | 3265150928 | 14843777165650652409 |  |
| `Fw.Parts.NavHitTestOpt.navEe` | agree | 18349000911985273043 | 15104978555079919392 |  |
| `Fw.Parts.NavHitTestOpt.probeFaithful` | agree | 18349000911985273043 | 15430532254890579266 |  |
| `Fw.Parts.NavHitTestOpt.probeElements` | agree | 18349000911985273043 | 6825405629286943425 |  |
| `Fw.Parts.NavHitTestOpt.navTrack` | agree | 18349000911985273043 | 1160551957863428047 |  |
| `Fw.Parts.NavHitTestOpt.navAccesses_eq` | agree | 1375711433381803629 | 5316913081799273715 |  |
| `Fw.Parts.NavHitTestOpt.fin` | agree | 2307969892939550200 | 16148719665900907800 |  |
| `Fw.Parts.NavHitTestOpt.forced_append` | agree | 6572128712267649 | 6616784142844951209 |  |
| `Fw.Parts.NavHitTestOpt.forced_true_le` | agree | 4404451145935907766 | 11030866127210569090 |  |
| `Fw.Parts.NavHitTestOpt.fin_append` | agree | 16178909083115273450 | 9307615996232665274 |  |
| `Fw.Parts.NavHitTestOpt.probeFaithful_style` | agree | 3339178035440350633 | 15668395686897708284 |  |
| `Fw.Parts.NavHitTestOpt.probeElements_style` | agree | 11508171803177375341 | 15557844431906949099 |  |
| `Fw.Parts.NavHitTestOpt.probes_layout` | agree | 5149814186500636114 | 17775568487910989280 |  |
| `Fw.Parts.NavHitTestOpt.skip_style_lt` | agree | 5080515037564348110 | 4001632060956145516 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_style_two` | agree | 7267459250540384592 | 703624147967719651 |  |
| `Fw.Parts.NavHitTestOpt.elements_style_lt` | agree | 4144464868563608266 | 12569735054001002317 |  |
| `Fw.Parts.NavHitTestOpt.elements_style_two` | agree | 7671269585071032709 | 13493202742133535870 |  |
| `Fw.Parts.NavHitTestOpt.skip_layout_le` | agree | 12233774373416710363 | 7220002262132021086 |  |
| `Fw.Parts.NavHitTestOpt.elements_layout_eq` | agree | 5896160868482495446 | 11115302677532392737 |  |
| `Fw.Parts.NavHitTestOpt.NavCtx` | agree | 2330190150 | 9415211446892880445 |  |
| `Fw.Parts.NavHitTestOpt.probeFrame` | agree | 7398066046301045042 | 14446684769832677271 |  |
| `Fw.Parts.NavHitTestOpt.origFrame` | agree | 9159379339778358231 | 11469869705885809050 |  |
| `Fw.Parts.NavHitTestOpt.skipHitTest` | agree | 3512254526 | 4086643933514444645 |  |
| `Fw.Parts.NavHitTestOpt.hitSkipFrame` | agree | 10328993244616631402 | 15394612060299458935 |  |
| `Fw.Parts.NavHitTestOpt.elementsFrame` | agree | 16843550634453126121 | 7343439964391669527 |  |
| `Fw.Parts.NavHitTestOpt.coverB_refl` | agree | 1353142358293265524 | 1298202476875601275 |  |
| `Fw.Parts.NavHitTestOpt.orig_perm` | agree | 1293010436187582612 | 3458382767249985710 |  |
| `Fw.Parts.NavHitTestOpt.frame_lt_of_style` | agree | 9324873660295090727 | 6611091400025366634 |  |
| `Fw.Parts.NavHitTestOpt.frame_lt_of_hits` | agree | 9250105846574269876 | 3759705363038406175 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_le_any` | agree | 12573614660839961575 | 15564898946794012500 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_lt_any` | agree | 8012153562344948725 | 8045214289999054522 |  |
| `Fw.Parts.NavHitTestOpt.elementsSkip_lt_any` | agree | 1409968715215431977 | 16481012518611995800 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_work_lt` | agree | 10981411267101271296 | 16788062866680187929 |  |
| `Fw.Parts.NavHitTestOpt.elementsSkip_work_lt` | agree | 14716191325223639959 | 7421222302531369936 |  |
| `Fw.Parts.NavHitTestOpt.leAll_map` | agree | 5228057407343679114 | 2873012130148572521 |  |
| `Fw.Parts.NavHitTestOpt.someLt_map` | agree | 9845322418206861036 | 6895988201904023212 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_run_dominates_any` | agree | 16491256995925340117 | 3528337445980204641 |  |
| `Fw.Parts.NavHitTestOpt.elementsSkip_run_dominates_any` | agree | 18189321402082461116 | 12887580244317637096 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_run_dominates` | agree | 13490657512042991813 | 2139139768834850908 |  |
| `Fw.Parts.NavHitTestOpt.elementsSkip_run_dominates` | agree | 5464149657872392314 | 15066106205731392059 |  |
| `Fw.Parts.NavHitTestOpt.withWrite` | agree | 12812387439206691266 | 16427248365946721282 |  |
| `Fw.Parts.NavHitTestOpt.writeOnChange_le` | agree | 17503304245818978625 | 15318859577119853862 |  |
| `Fw.Parts.NavHitTestOpt.hitSkipAnswer` | agree | 3445224877 | 333142101087207576 |  |
| `Fw.Parts.NavHitTestOpt.hitSkipAnswer_onDark` | agree | 1835723298669001759 | 7157333743063515908 |  |
| `Fw.Parts.NavHitTestOpt.hitSkip_visSame` | agree | 3612691953522192506 | 3432560023017712476 |  |
| `Fw.Parts.NavHitTestOpt.elementsSkip_visSame` | agree | 18256496681217824495 | 10934118269085038005 |  |
| `Fw.Parts.NavHitTestOpt.elementsSkip_visSame_port` | agree | 15733912851834157409 | 11782577458890423252 |  |
| `Fw.Parts.NavHitTestOpt.Row` | agree | 3931117990 | 11922069066994308354 |  |
| `Fw.Parts.NavHitTestOpt.crTypes` | agree | 839686457 | 1344047359757526896 |  |
| `Fw.Parts.NavHitTestOpt.wkTypes` | agree | 839686457 | 15747448310266007001 |  |
| `Fw.Parts.NavHitTestOpt.variantKey` | agree | 3438944622 | 9346642614218110968 |  |
| `Fw.Parts.NavHitTestOpt.goldenRows` | agree | 13355197313428223640 | 7150344308761773797 |  |
| `Fw.Parts.NavHitTestOpt.Row.json` | agree | 7301994037384090816 | 10265422948961754320 |  |
| `Fw.Parts.NavHitTestOpt.goldenJsonl` | agree | 3265150928 | 13477655913003878127 |  |
| `Fw.Parts.NavHitTestOpt.readStage` | agree | 14582035148696871019 | 14389087957104754579 |  |
| `Fw.Parts.NavHitTestOpt.holds` | agree | 2144725198 | 17530362134033703020 |  |
| `Fw.Parts.NavHitTestOpt.sampleCtx` | agree | 9454998678513282904 | 13214567030496010502 |  |
| `Fw.Parts.NavHitTestOpt.rowsHold` | agree | 5565976426804750665 | 2153822589141654186 |  |
| `Fw.Plan.cpf` | agree | 3820173399935414584 | 1825777708845471348 |  |
| `Fw.Plan.Lint.EvKind` | agree | 3931117990 | 490323718224617186 |  |
| `Fw.Plan.Lint.isHex` | agree | 3068939364 | 9475325071297664243 |  |
| `Fw.Plan.Lint.isCommit` | agree | 1526413716 | 12325126318867793683 |  |
| `Fw.Plan.Lint.isRun` | agree | 1526413716 | 15818533246185319175 |  |
| `Fw.Plan.Lint.hasCommitToken` | agree | 1526413716 | 4168437508701800951 |  |
| `Fw.Plan.Lint.evKind` | agree | 2844698297841156680 | 1683392441391690257 |  |
| `Fw.Plan.Lint.Code` | agree | 3931117990 | 17598014499928021682 |  |
| `Fw.Plan.Lint.Code.all` | agree | 1355927278195484830 | 6744964782997482393 |  |
| `Fw.Plan.Lint.Code.name` | agree | 16592236020132419898 | 6471344117739140874 |  |
| `Fw.Plan.Lint.Code.severity` | agree | 16592236020132419898 | 3681746500123669412 |  |
| `Fw.Plan.Lint.Ctx` | agree | 3931117990 | 13754932790587137801 |  |
| `Fw.Plan.Lint.holds` | agree | 16899037310602076580 | 1946691680053545917 |  |
| `Fw.Plan.Lint.codes` | agree | 9080897928730423010 | 8396233180039178901 |  |
| `Fw.Plan.Lint.mem_codes` | agree | 3896799806242631721 | 455840406381065747 |  |
| `Fw.Plan.Lint.unknownDep_iff` | agree | 9703278842337102280 | 9490073524557371060 |  |
| `Fw.Plan.Lint.evLong_iff` | agree | 15425255012727875533 | 6699376847034286117 |  |
| `Fw.Plan.Lint.longTitle_iff` | agree | 6750627424366960705 | 1262658645221154828 |  |
| `Fw.Plan.Lint.trailerNoEvidence_iff` | agree | 6579965738633243147 | 5412142665919299209 |  |
| `Fw.Plan.Lint.evidenceNoTrailer_iff` | agree | 8814627517397666816 | 15504782699234050170 |  |
| `Fw.Plan.Lint.Finding` | agree | 3931117990 | 10678709311172947208 |  |
| `Fw.Plan.Lint.stuck` | disagree | 10400717583269997718 | 2677659469556986485 | Math omits the fuel f and the length test. Lean: stuck(0,R)=R; stuck(f+1,R)= R if \|R'\|=\|R\| else stuck(f,R'), with R'=[t in R \| exists d in t.deps, exists r in R: r.id=d]. |
| `Fw.Plan.Lint.namedIds` | disagree | 13752034602789477822 | 1446501625719476702 | Math uses a set union; Lean concatenates lists in commit order and keeps repeats. Fix: named(C) = concatenation over c in C of trailers(c.body) (++, order kept, repeats kept). |
| `Fw.Plan.Lint.detailOf` | disagree | 18007639185139703369 | 15084343020732634107 | Math is vague. Lean: unknownDep gives join(', ', [d in t.deps \| d not in ids]); evOther, evLong, evUser, evProse give evidence or empty string if none; trailerNoEvidence, evidenceNoTrailer, longTitle give empty string. |
| `Fw.Plan.Lint.lint` | disagree | 17448983655105510606 | 14351773480438181987 | Math gives pairs (t,k); Lean findings are (t.id, name(k), sev(k), detail(ctx,t,k)) with ctx=(ids(T), named(C)), plus ('*', cycle, error, join(', ', ids(stuck(\|T\|,T)))) when not acyclicB(T). Fix the LaTeX to show these fields. |
| `Fw.Plan.Lint.ok` | agree | 5627046307924942074 | 10689757536276751984 |  |
| `Fw.Plan.Lint.ok_sound` | agree | 2993966156423616563 | 13532104533446149761 |  |
| `Fw.Parts.HiddenPause.Tmpl` | agree | 2330190150 | 3968782317093685775 |  |
| `Fw.Parts.HiddenPause.Still` | agree | 773173516643918604 | 18440645919313708317 |  |
| `Fw.Parts.HiddenPause.Hidden` | agree | 2543540316057877642 | 3409521167923603586 |  |
| `Fw.Parts.HiddenPause.HiddenOrStill` | agree | 6455800590708934155 | 11411446392354135995 |  |
| `Fw.Parts.HiddenPause.hidden_pause_eq` | agree | 4153818942726709144 | 4861946511762103109 |  |
| `Fw.Parts.HiddenPause.hiddenPause_visSame` | agree | 11729549665730941110 | 5433391636942088794 |  |
| `Fw.Parts.HiddenPause.panelOpacity` | agree | 3498294262 | 15248933249934897354 |  |
| `Fw.Parts.HiddenPause.panelOpacity_eq_zero_iff` | agree | 11908205027502210930 | 215680508194617104 |  |
| `Fw.Parts.HiddenPause.hiddenPause` | agree | 3512254526 | 16288234607487129691 |  |
| `Fw.Parts.HiddenPause.scenePaused` | agree | 3512254526 | 2569013209028700375 |  |
| `Fw.Parts.HiddenPause.scenePaused_imp_hiddenPause` | agree | 14185279206807721629 | 9010530770391159918 |  |
| `Fw.Parts.HiddenPause.UnderPanel` | agree | 6064188572964241407 | 15084508042646337341 |  |
| `Fw.Parts.HiddenPause.underPanel_hidden` | agree | 2679399979818006048 | 981608872086918867 |  |
| `Fw.Parts.HiddenPause.panel_visSame` | agree | 2377560562598947436 | 5808240523024752905 |  |
| `Fw.Parts.HiddenPause.inside` | agree | 15104314254767822967 | 15532763276544117391 |  |
| `Fw.Parts.HiddenPause.meets_of_inside` | agree | 7233362859871982972 | 9417962001476629032 |  |
| `Fw.Parts.HiddenPause.offscreen_hidden` | agree | 8391751735244292796 | 12015559491117673148 |  |
| `Fw.Parts.HiddenPause.sceneHidden` | agree | 10441105183908726464 | 11776428455792872611 |  |
| `Fw.Parts.HiddenPause.clockStep` | agree | 3624215101 | 15666835455059474121 |  |
| `Fw.Parts.HiddenPause.origClock` | agree | 2749908076 | 8464035069939456159 |  |
| `Fw.Parts.HiddenPause.naiveClock` | agree | 2749908076 | 17702193941294905604 |  |
| `Fw.Parts.HiddenPause.naive_pause_shifts` | agree | 15209935961264022464 | 399753387430473545 |  |
| `Fw.Parts.HiddenPause.paused` | agree | 3498503231861209482 | 11358041034048401394 |  |
| `Fw.Parts.HiddenPause.skipWrites` | agree | 3498503231861209482 | 4635951750133613656 |  |
| `Fw.Parts.HiddenPause.pause_le` | agree | 3455191819252023203 | 947401932902597045 |  |
| `Fw.Parts.HiddenPause.skipWrites_le` | agree | 8327976088819014333 | 5167169323914220844 |  |
| `Fw.Parts.HiddenPause.cr_pause_style_units` | agree | 9482799602765457980 | 8949662639829504318 |  |
| `Fw.Parts.HiddenPause.cr_realChrome_pause_eq` | agree | 13922573780861116797 | 18422381041542204731 |  |
| `Fw.Parts.HiddenPause.crMarquee` | agree | 8745148923930300803 | 12156160332061552410 |  |
| `Fw.Parts.HiddenPause.marquees` | agree | 1645242211 | 1777640263115343304 |  |
| `Fw.Parts.HiddenPause.crMarqueeFrame` | agree | 1759703767827629274 | 6064121744838739563 |  |
| `Fw.Parts.HiddenPause.cr_marquee_bands` | agree | 10863853019303023874 | 1371272617982861368 |  |
| `Fw.Parts.HiddenPause.wk_pause_eq` | agree | 1068028370097722094 | 4424456284154954445 |  |
| `Fw.Parts.HiddenPause.wkMarquee` | agree | 2579111148985320997 | 671517249725762812 |  |
| `Fw.Parts.HiddenPause.wk_marquee_bands` | agree | 14274837429986515673 | 16268390522440993711 |  |
| `Fw.Parts.HiddenPause.cdFrame` | agree | 619123872042438874 | 7031006868969779147 |  |
| `Fw.Parts.HiddenPause.cr_countdown_style` | agree | 3371736625305833231 | 7801509139068647315 |  |
| `Fw.Parts.HiddenPause.wk_countdown_style` | agree | 13669808323227506592 | 2608907183675212556 |  |
| `Fw.Parts.HiddenPause.relPred` | agree | 346868352876978179 | 10368294953197409090 |  |
| `Fw.Parts.HiddenPause.crPairs` | agree | 17842768775439924501 | 8972840186279236836 |  |
| `Fw.Parts.HiddenPause.wkPairs` | agree | 17842768775439924501 | 9129206549460459562 |  |
| `Fw.Parts.HiddenPause.target` | agree | 3518942148 | 5383619614684219800 |  |
| `Fw.Parts.HiddenPause.row` | agree | 2062259744 | 10948479427043663640 |  |
| `Fw.Parts.HiddenPause.goldenRows` | agree | 1789995637 | 17331921228155668805 |  |
| `Fw.Parts.HiddenPause.goldenJsonl` | agree | 3265150928 | 1071407202563335058 |  |
| `Fw.Parts.MorphPanelOpt.fade` | agree | 3498294262 | 4920129659368001193 |  |
| `Fw.Parts.MorphPanelOpt.radius` | agree | 3498294262 | 16598964567381651219 |  |
| `Fw.Parts.MorphPanelOpt.blurOp` | agree | 6888073081228331751 | 11277775393312590844 |  |
| `Fw.Parts.MorphPanelOpt.filterO` | agree | 1219855461727825579 | 1031268072506616945 |  |
| `Fw.Parts.MorphPanelOpt.filterV` | agree | 1219855461727825579 | 16873776690902002947 |  |
| `Fw.Parts.MorphPanelOpt.radius_eq_zero_iff` | agree | 14303403059195220378 | 3571216626802421052 |  |
| `Fw.Parts.MorphPanelOpt.fade_ge_one_iff` | agree | 18335384600805160761 | 92220708022606048 |  |
| `Fw.Parts.MorphPanelOpt.rest_iff` | agree | 13628181540737269242 | 5010209679965744735 |  |
| `Fw.Parts.MorphPanelOpt.filterO_rest` | agree | 8987934086714440417 | 4185883108756906717 |  |
| `Fw.Parts.MorphPanelOpt.filterV_rest` | agree | 16811993499381439609 | 6119836243961296899 |  |
| `Fw.Parts.MorphPanelOpt.filterV_fade` | agree | 2377389170346112184 | 1390251546105063712 |  |
| `Fw.Parts.MorphPanelOpt.identityOp` | agree | 6268716985004296219 | 12473075666092915607 |  |
| `Fw.Parts.MorphPanelOpt.render` | agree | 7843075348480648806 | 4761837771593835138 |  |
| `Fw.Parts.MorphPanelOpt.groups` | agree | 14564861969901743718 | 8494939017838293892 |  |
| `Fw.Parts.MorphPanelOpt.sceneO` | agree | 5274500915668701281 | 13200148360962794449 |  |
| `Fw.Parts.MorphPanelOpt.sceneV` | agree | 5274500915668701281 | 15978327476924347130 |  |
| `Fw.Parts.MorphPanelOpt.RG10` | agree | 4068219403291824647 | 4308656842619989656 |  |
| `Fw.Parts.MorphPanelOpt.rest_groups_differ` | agree | 9688979408302562264 | 10202388162738548858 |  |
| `Fw.Parts.MorphPanelOpt.fade_scene_eq` | agree | 12784532276788378144 | 10231592973366693509 |  |
| `Fw.Parts.MorphPanelOpt.rest_visSame_E` | agree | 16876444664752831959 | 17412053924775223840 |  |
| `Fw.Parts.MorphPanelOpt.fade_visSame_Q` | agree | 14764145176057869740 | 10050108191613170669 |  |
| `Fw.Parts.MorphPanelOpt.bump` | agree | 14717512765419159897 | 17158772984781903586 |  |
| `Fw.Parts.MorphPanelOpt.le_bump` | agree | 15364936688656714053 | 5322291500724471302 |  |
| `Fw.Parts.MorphPanelOpt.lt_bump` | agree | 7649318758559352958 | 16414531733504720101 |  |
| `Fw.Parts.MorphPanelOpt.RestIn` | agree | 2330190150 | 2570842932359965675 |  |
| `Fw.Parts.MorphPanelOpt.crEffectStages` | agree | 14673355470449990949 | 16464253164638060596 |  |
| `Fw.Parts.MorphPanelOpt.wkEffectStages` | agree | 14673355470449990949 | 4003963535791822321 |  |
| `Fw.Parts.MorphPanelOpt.crRestW` | agree | 6503666549835392448 | 16557807789693858803 |  |
| `Fw.Parts.MorphPanelOpt.wkRestW` | agree | 15833664313740546864 | 9631079356884277822 |  |
| `Fw.Parts.MorphPanelOpt.cr_rest_le` | agree | 534058075251018363 | 7517055245691464843 |  |
| `Fw.Parts.MorphPanelOpt.cr_rest_lt` | agree | 16138420573590525270 | 10183310913022528274 |  |
| `Fw.Parts.MorphPanelOpt.wk_rest_le` | agree | 6920623536873780723 | 14959101329890854680 |  |
| `Fw.Parts.MorphPanelOpt.wk_rest_lt` | agree | 8492721347321312486 | 529065217004532654 |  |
| `Fw.Parts.MorphPanelOpt.leAll_map` | agree | 7422151756615759270 | 13417603898811372853 |  |
| `Fw.Parts.MorphPanelOpt.someLt_map` | agree | 9845322418206861036 | 13008406920424851856 |  |
| `Fw.Parts.MorphPanelOpt.cr_rest_claim` | agree | 3377479486327552212 | 7503412107723362998 |  |
| `Fw.Parts.MorphPanelOpt.wkResident` | agree | 10013828597216323415 | 10235946331697838151 |  |
| `Fw.Parts.MorphPanelOpt.wk_rest_layers` | agree | 6561808923939186496 | 4444697308910637088 |  |
| `Fw.Parts.MorphPanelOpt.wk_rest_claim` | agree | 7989640841994650038 | 1436371093008721367 |  |
| `Fw.Parts.MorphPanelOpt.panel` | agree | 421340980 | 14987821467470160561 |  |
| `Fw.Parts.MorphPanelOpt.wk_rest_panel_not_mono` | agree | 16012185928416357326 | 10477291976547371021 |  |
| `Fw.Parts.MorphPanelOpt.cr_toggle_not_le` | agree | 8380382998070310847 | 13777041449592686728 |  |
| `Fw.Parts.MorphPanelOpt.fadeVar` | agree | 421340980 | 15085634034577474530 |  |
| `Fw.Parts.MorphPanelOpt.fadeProp` | agree | 17074632489159419994 | 2768004415355655309 |  |
| `Fw.Parts.MorphPanelOpt.crFade` | agree | 17975449620656047584 | 15163766314893916031 |  |
| `Fw.Parts.MorphPanelOpt.cr_enter_layout_zero` | agree | 7891332450751567705 | 12674010412029072949 |  |
| `Fw.Parts.MorphPanelOpt.wkEdgeO` | agree | 13667132523475151971 | 2952939032500470150 |  |
| `Fw.Parts.MorphPanelOpt.wkEdgeV` | agree | 13667132523475151971 | 274937985014948634 |  |
| `Fw.Parts.MorphPanelOpt.wk_toggle_layout_units` | agree | 18428502169768062468 | 12228317853922655745 |  |
| `Fw.Parts.MorphPanelOpt.wk_toggle_passes` | agree | 12497414609608063233 | 9422450647929825083 |  |
| `Fw.Parts.MorphPanelOpt.wk_toggle_not_le` | agree | 188876796224143430 | 1449180555168428297 |  |
| `Fw.Parts.MorphPanelOpt.coverB_self` | agree | 1353142358293265524 | 13030436388527047947 |  |
| `Fw.Parts.MorphPanelOpt.cr_fade_le` | agree | 13518565127409641767 | 14888497971405181447 |  |
| `Fw.Parts.MorphPanelOpt.cr_fade_raster_drop` | agree | 14587815268153473289 | 11698309351191160769 |  |
| `Fw.Parts.MorphPanelOpt.ownResident` | agree | 17092776356684267260 | 8445775281735020283 |  |
| `Fw.Parts.MorphPanelOpt.fade_layers_up` | agree | 6552276863765433481 | 9433554336433211579 |  |
| `Fw.Parts.MorphPanelOpt.cr_fade_trade` | agree | 14433181938337894203 | 15183776908114933547 |  |
| `Fw.Parts.MorphPanelOpt.wkFadeO` | agree | 4985023659763822871 | 12204742810965930647 |  |
| `Fw.Parts.MorphPanelOpt.wkFadeV` | agree | 4985023659763822871 | 6195015045089136683 |  |
| `Fw.Parts.MorphPanelOpt.wk_fade_paint_drop` | agree | 12728990664149260370 | 4890275435770981411 |  |
| `Fw.Parts.MorphPanelOpt.wk_fade_props_up` | agree | 2626887332223764530 | 9001633490778726380 |  |
| `Fw.Parts.MorphPanelOpt.wk_fade_not_le` | agree | 14593201984057119314 | 16929807702385249639 |  |
| `Fw.Parts.MorphPanelOpt.restCr` | agree | 1001990075746202326 | 17936698601733575592 |  |
| `Fw.Parts.MorphPanelOpt.restWk` | agree | 1670281972909956944 | 1115886653627627907 |  |
| `Fw.Parts.MorphPanelOpt.fadeCr` | agree | 16780244879864052101 | 12156880672432265323 |  |
| `Fw.Parts.MorphPanelOpt.crO` | agree | 9670317657891034104 | 10284327578100297050 |  |
| `Fw.Parts.MorphPanelOpt.crV` | agree | 9670317657891034104 | 255694222094308486 |  |
| `Fw.Parts.MorphPanelOpt.fadeWk` | agree | 16780244879864052101 | 14141735106469517959 |  |
| `Fw.Parts.MorphPanelOpt.wkO` | agree | 9670317657891034104 | 14571103001015553218 |  |
| `Fw.Parts.MorphPanelOpt.wkV` | agree | 9670317657891034104 | 14982231184541662534 |  |
| `Fw.Parts.MorphPanelOpt.CountType` | agree | 3931117990 | 8726310551053859952 |  |
| `Fw.Parts.MorphPanelOpt.stageName` | agree | 13237354143774927416 | 5018164951693487975 |  |
| `Fw.Parts.MorphPanelOpt.series` | agree | 13343470789444078649 | 7256318397167537554 |  |
| `Fw.Parts.MorphPanelOpt.predict` | agree | 2340511515 | 14935060714063386997 |  |
| `Fw.Parts.MorphPanelOpt.crTypes` | disagree | 12673250420853743963 | 15987153494447296797 | Math states only \|crTypes\|=8, not the list. Fix: crTypes=[(trace.FunctionCall,script,T,T),(trace.UpdateLayoutTree,style,F,T),(trace.Layout,layout,F,F),(trace.Layout.dirtyObjects,layout,T,F),(metric.LayoutCount,layout,F,F),(trace.PrePaint,props,F,F),(raster.invalidationAreaPx,paint,T,F),(trace.cc.Commit,commit,F,T)] as (name,stage,units,exact). |
| `Fw.Parts.MorphPanelOpt.wkTypes` | disagree | 12673250420853743963 | 4173844351217871996 | Math states only \|wkTypes\|=4, not the list. Fix: wkTypes=[(RecalculateStyles,style,F,F),(Layout,layout,F,F),(Paint,paint,F,F),(Composite,commit,F,F)] as (name,stage,units,exact). |
| `Fw.Parts.MorphPanelOpt.row` | agree | 6008635756756057675 | 3043540524103707490 |  |
| `Fw.Parts.MorphPanelOpt.goldenLines` | disagree | 4017531403 | 9602931550666849871 | Math states only the length 20, not the lines. Fix: goldenLines=[row(chromium,sc,t,crV,crO) \| sc∈[swipe-v1,swipe-touch-v1], t∈crTypes] ++ [row(webkit,swipe-v1,t,wkV,wkO) \| t∈wkTypes]. |
| `Fw.Parts.MorphPanelOpt.goldenText` | agree | 3265150928 | 14843777165650652409 |  |
| `Fw.Parts.PlatformEntries.Bez` | agree | 3931117990 | 9132055937945937508 |  |
| `Fw.Parts.PlatformEntries.spring` | agree | 1814349348215763701 | 18172705389407670674 |  |
| `Fw.Parts.PlatformEntries.bx` | agree | 3620388040975548728 | 1135457844791844953 |  |
| `Fw.Parts.PlatformEntries.by'` | agree | 3620388040975548728 | 10780023775851228841 |  |
| `Fw.Parts.PlatformEntries.bis` | disagree | 7299736616687225882 | 9839820116864169318 | Math gives one halving step only, not the n-fold recursion. Fix: bis_{b,x}(0,p)=p; bis_{b,x}(n+1,(lo,hi)) = bis_{b,x}(n, B_x(m)<x ? (m,hi) : (lo,m)), m=(lo+hi)/2. |
| `Fw.Parts.PlatformEntries.steps` | agree | 421340980 | 15008607135317004295 |  |
| `Fw.Parts.PlatformEntries.solve` | disagree | 3620388040975548728 | 11862808625119000465 | Math omits where lo_N, hi_N come from (start interval [0,1], N=24 halvings). Fix: u_b(x)=(lo_N+hi_N)/2 where (lo_N,hi_N)=bis_{b,x}(24,(0,1)). |
| `Fw.Parts.PlatformEntries.ease` | agree | 3620388040975548728 | 7296640869944505881 |  |
| `Fw.Parts.PlatformEntries.bis_inv` | agree | 12393256957264156497 | 14872313967730163536 |  |
| `Fw.Parts.PlatformEntries.solve_mem` | agree | 17209356074747048241 | 2598927329567576592 |  |
| `Fw.Parts.PlatformEntries.spring_by` | disagree | 14020498640649239627 | 4899021221826587654 | Lean is about b = spring only; math B_y(u) reads as any curve (false in general). Fix: ∀u∈Q: B_y^{spring}(u) = 1-(1-u)^3. |
| `Fw.Parts.PlatformEntries.ease_mem` | disagree | 15590708238193238016 | 1099789356400908105 | Lean fixes b = spring; math ease(x) leaves the curve open (false for overshooting curves) and the domain unstated. Fix: ∀x∈Q: 0 ≤ ease_{spring}(x) ≤ 1. |
| `Fw.Parts.PlatformEntries.ease_ends` | disagree | 17198584449496924147 | 10601355034672807594 | Lean proves it for b = spring only; math reads as every curve (stronger). Fix: ease_{spring}(0)=0 ∧ ease_{spring}(1)=1. |
| `Fw.Parts.PlatformEntries.div_nonpos'` | agree | 1035743858 | 7569319907595654328 |  |
| `Fw.Parts.PlatformEntries.one_le_div'` | agree | 2679575213 | 10797720827389354225 |  |
| `Fw.Parts.PlatformEntries.Tr` | agree | 3931117990 | 9639691984946715121 |  |
| `Fw.Parts.PlatformEntries.Entry` | agree | 3931117990 | 122883603189257794 |  |
| `Fw.Parts.PlatformEntries.liftBlur` | agree | 250304300630605491 | 408375331657681749 |  |
| `Fw.Parts.PlatformEntries.credCard` | disagree | 13922638264708200624 | 13764617783808626042 | Math gives only D and d; omits keyframe name and props. Fix: ∀i∈N: credCard(i) = (cred-card-in, 420, 70i, liftBlur). |
| `Fw.Parts.PlatformEntries.profilePhone` | disagree | 4737607177018484825 | 6143415974954553185 | Math gives only D and d; omits name and props. Fix: profilePhone = (profile-phone-in, 620, 0, liftBlur). |
| `Fw.Parts.PlatformEntries.rings` | disagree | 4737607177018484825 | 4707081344921467993 | $$ math gives only D, d; name and props are missing (props only in prose). Fix: rings = (secure-network-rings-in, 480, 0, [(opacity,0,1),(scale,1.04,1)]). |
| `Fw.Parts.PlatformEntries.faceLeft` | disagree | 4737607177018484825 | 15658307506669666677 | Math gives only D, d; name and props missing, and prose omits the opacity track. Fix: faceLeft = (secure-network-face-left-in, 320, 0, [(opacity,0,1),(translateX,-8,0)]). |
| `Fw.Parts.PlatformEntries.faceRight` | disagree | 4737607177018484825 | 4623194912701186691 | Math gives only D, d; name and props missing, prose omits opacity. Fix: faceRight = (secure-network-face-right-in, 320, 0, [(opacity,0,1),(translateX,8,0)]). |
| `Fw.Parts.PlatformEntries.dash` | disagree | 4737607177018484825 | 10630354380327115389 | Math gives only D, d; name and props missing, prose omits opacity. Fix: dash = (secure-network-dash-in, 260, 60, [(opacity,0,1),(scaleX,0,1)]). |
| `Fw.Parts.PlatformEntries.shield` | disagree | 4737607177018484825 | 11923942699451152354 | Math gives only D, d; name and props missing, prose omits opacity. Fix: shield = (secure-network-shield-in, 420, 180, [(opacity,0,1),(scale,0.88,1)]). |
| `Fw.Parts.PlatformEntries.logo` | disagree | 4737607177018484825 | 15347677517548135301 | Math gives only D, d; name and props missing, prose omits opacity. Fix: logo = (secure-network-logo-in, 280, 680, [(opacity,0,1),(scale,0.7,1)]). |
| `Fw.Parts.PlatformEntries.flagDelay` | disagree | 4293550323 | 18292189991764342795 | Domain is N: math omits k = 0, which Lean's wildcard maps to 600. Fix: d(k) = 560 if k∈{2,5}; 520 if k∈{3,4}; 600 otherwise (k=0, k=1, k≥6). |
| `Fw.Parts.PlatformEntries.flag` | disagree | 13922638264708200624 | 8209278818558035314 | Math gives only D, d; name and props missing, prose omits opacity. Fix: ∀k∈N: flag(k) = (secure-network-flag-in, 280, flagDelay(k), [(opacity,0,1),(scale,0.82,1)]). |
| `Fw.Parts.PlatformEntries.invoiceCard` | disagree | 4737607177018484825 | 15040805301674324822 | Math gives only D, d; name and props missing, prose omits opacity. Fix: invoiceCard = (invoice-card-in, 560, 620, [(opacity,0,1),(translateY,22,0),(scale,0.94,1)]). |
| `Fw.Parts.PlatformEntries.orderRow` | disagree | 13922638264708200624 | 2599408953079276419 | Math gives only D, d; name and props missing, prose omits opacity. Fix: ∀i∈N: orderRow(i) = (invoice-i-row-in, 620, 140i, [(opacity,0,1),(translateX,20,0)]). |
| `Fw.Parts.PlatformEntries.askIn` | disagree | 13922638264708200624 | 14627166028074650785 | Math gives only D, d; name and props missing, prose omits opacity. Fix: ∀i∈N: askIn(i) = (agents-ask-in, 560, 140i, [(opacity,0,1),(translateY,10,0)]). |
| `Fw.Parts.PlatformEntries.askOut` | disagree | 13922638264708200624 | 13210959409424456826 | $$ math gives only D, d; name and props missing. Fix: ∀i∈N: askOut(i) = (agents-ask-out, 560, 140i, [(opacity,1,0),(translateY,0,10)]). |
| `Fw.Parts.PlatformEntries.lin` | agree | 12087864225032396793 | 1854031824539371441 |  |
| `Fw.Parts.PlatformEntries.progress` | disagree | 12087864225032396793 | 9592169491227185692 | Lean uses the spring curve; math ease(x(t)) leaves the curve open. Fix: p_e(t) = ease_{spring}(x_e(t)) = ease_{spring}((t-d)/D). |
| `Fw.Parts.PlatformEntries.value` | agree | 8086731582808365754 | 1963391121693134491 |  |
| `Fw.Parts.PlatformEntries.progress_before` | disagree | 8674865027601344013 | 13171871460216129408 | Math omits Lean hypothesis hD: D > 0. Fix: ∀e,∀t∈Q: D > 0 ∧ t ≤ d ⇒ p_e(t) = 0. |
| `Fw.Parts.PlatformEntries.progress_after` | disagree | 5216118646825992238 | 8154692650707062415 | Math omits hypothesis D > 0, without which it is false (D=0 gives x=0, p=0). Fix: ∀e,∀t∈Q: D > 0 ∧ t ≥ d + D ⇒ p_e(t) = 1. |
| `Fw.Parts.PlatformEntries.progress_mem` | agree | 17527153747580748230 | 16615446958920590826 |  |
| `Fw.Parts.PlatformEntries.value_between` | agree | 3038387225109438189 | 8261969664501159303 |  |
| `Fw.Parts.PlatformEntries.play` | agree | 603921427 | 12195960086512389838 |  |
| `Fw.Parts.PlatformEntries.countDelay` | agree | 1901972866 | 1522190557291216355 |  |
| `Fw.Parts.PlatformEntries.countDur` | agree | 1901972866 | 3937513324718766403 |  |
| `Fw.Parts.PlatformEntries.easeOut` | agree | 3498294262 | 8875080450819594862 |  |
| `Fw.Parts.PlatformEntries.jsRound` | agree | 2426920303 | 4754259223339693123 |  |
| `Fw.Parts.PlatformEntries.countAt` | agree | 3801780552 | 16763884525662082738 |  |
| `Fw.Parts.PlatformEntries.count_done` | agree | 9732834101333712386 | 11117026771176453543 |  |
| `Fw.Parts.PlatformEntries.askLead` | agree | 1901972866 | 15801684887534662038 |  |
| `Fw.Parts.PlatformEntries.typeStep` | agree | 1901972866 | 16869164853332896179 |  |
| `Fw.Parts.PlatformEntries.eraseStep` | agree | 1901972866 | 10157693378277018681 |  |
| `Fw.Parts.PlatformEntries.holdMs` | agree | 1901972866 | 7788660480814246459 |  |
| `Fw.Parts.PlatformEntries.firstReveal` | agree | 1901972866 | 7794566174103234047 |  |
| `Fw.Parts.PlatformEntries.swapMs` | agree | 1901972866 | 6372258832392729444 |  |
| `Fw.Parts.PlatformEntries.topicDur` | agree | 544046110 | 11115988068726158358 |  |
| `Fw.Parts.PlatformEntries.View` | agree | 3931117990 | 7536249141786746155 |  |
| `Fw.Parts.PlatformEntries.fl` | agree | 957469855 | 9367968540651115116 |  |
| `Fw.Parts.PlatformEntries.lenAt` | disagree | 1649852746 | 6275026075027216693 | Lean's first case is min(L, ⌊τ/32⌋_N + 1) (differs for τ<0, e.g. L=0); math has ⌊τ/32⌋+1. Fix: first case min(L, ⌊τ/32⌋_N+1) if τ<32L; other cases unchanged (third = L ∸ (⌊…/18⌋+1)). |
| `Fw.Parts.PlatformEntries.topicView` | disagree | 1077030870265570336 | 1184334885124886779 | Math elides leaving, results, caret with '…'. Fix: topicView(i,p,L,f,τ) = (ℓ_{L,r}(τ), i, 32L≤τ ? i : p, ¬f ∧ 32L≤τ<32L+700, ¬f ∨ 32L+280≤τ, true), r = f ? 280 : 700. |
| `Fw.Parts.PlatformEntries.locate` | disagree | 3244207601 | 18188156250333229785 | Math omits the empty-list case and the Option. Fix: locate([],r)=none; locate((i,L)::R,r) = some(i,L,r) if r < 50L+3700, else locate(R, r−50L−3700). |
| `Fw.Parts.PlatformEntries.cycleLen` | agree | 1067225169 | 14798267768502971682 |  |
| `Fw.Parts.PlatformEntries.wrap` | agree | 4035929107 | 9879114345209993993 |  |
| `Fw.Parts.PlatformEntries.rotation` | disagree | 946758936 | 10118718982367724893 | Math omits the empty list. Fix: rot([]) = []; rot([L_0,…,L_{n−1}]) = [(1,L_1),…,(n−1,L_{n−1}),(0,L_0)]. |
| `Fw.Parts.PlatformEntries.cycView` | disagree | 3978470733644657455 | 15361163890342538925 | Math omits prev topic, first=false and the none case. Fix: cyc(r) = topicView(i, i=0 ? n−1 : i−1, L, false, τ) if locate(rot, wrap_P(r)) = some(i,L,τ), P=cycleLen(rot); else (0,0,0,⊥,⊥,⊥). |
| `Fw.Parts.PlatformEntries.askView` | disagree | 3978470733644657455 | 14023312041584827113 | Math elides topicView arguments and omits lens=[]. Fix: ask(t) = (0,0,0,⊥,⊥,⊥) if t<700 or lens=[]; topicView(0,0,L_0,true,t−700) if t−700 < D_0=50L_0+3280; else cyc(t−700−D_0). |
| `Fw.Parts.PlatformEntries.wrap_periodic` | agree | 17664193799438082568 | 3763776779321195002 |  |
| `Fw.Parts.PlatformEntries.cycView_periodic` | agree | 413659875092256752 | 8743958292086104578 |  |
| `Fw.Parts.PlatformEntries.lenAt_le` | agree | 10313930786988733298 | 5306982011563587828 |  |
| `Fw.Parts.PlatformEntries.before_lead` | agree | 12886339144144598973 | 7973278390319762459 |  |
| `Fw.Parts.PlatformGlint.dur` | agree | 1901972866 | 1955269340670341284 |  |
| `Fw.Parts.PlatformGlint.startDelay` | agree | 1901972866 | 15102147478847543548 |  |
| `Fw.Parts.PlatformGlint.minRatio` | agree | 1901972866 | 2176223489456922585 |  |
| `Fw.Parts.PlatformGlint.lerp` | agree | 1069553462 | 17187970250651900789 |  |
| `Fw.Parts.PlatformGlint.interp` | disagree | 2402884068 | 11795878410274764416 | Math defines f only on [0,1]; Lean is total on Q: u<1/5 (incl. u<0) uses k=0, u≥4/5 (incl. u>1) uses k=4. Fix: f(u) = lerp(a_k, a_{k+1}, 5u−k), k = min(4, max(0, ⌊5u⌋)). |
| `Fw.Parts.PlatformGlint.Side` | agree | 3931117990 | 10159707575256267188 |  |
| `Fw.Parts.PlatformGlint.x1At` | disagree | 6028429764805610256 | 13910808696690353848 | $$ math leaves a_0..a_5 unspecified (values only in prose). Fix: x_1(left,u) = interp(−200,200,200,200,−200,−200; u), x_1(right,u) = interp(−200,−200,200,−200,−200,−200; u). |
| `Fw.Parts.PlatformGlint.x2At` | disagree | 6028429764805610256 | 5297583677061150750 | $$ math leaves b_0..b_5 unspecified (values only in prose). Fix: x_2(left,u) = interp(−80,320,320,320,−80,−80; u), x_2(right,u) = interp(−80,−80,320,−80,−80,−80; u). |
| `Fw.Parts.PlatformGlint.cycle` | agree | 3498294262 | 16239806556549210965 |  |
| `Fw.Parts.PlatformGlint.sample` | agree | 5071698757036344098 | 7598762330505670453 |  |
| `Fw.Parts.PlatformGlint.rest` | agree | 9472925059620789904 | 17917100428432912265 |  |
| `Fw.Parts.PlatformGlint.interp_between` | agree | 16087736805366907730 | 11054534529530464214 |  |
| `Fw.Parts.PlatformGlint.cycle_mem` | agree | 5818439773400925854 | 657492628530646449 |  |
| `Fw.Parts.PlatformGlint.sample_periodic` | agree | 17798009524212834451 | 7543396413984951590 |  |
| `Fw.Parts.PlatformGlint.sample_range` | agree | 15185444358078389307 | 16182457341529589040 |  |
| `Fw.Parts.PlatformGlint.St` | agree | 3931117990 | 6666741544730859556 |  |
| `Fw.Parts.PlatformGlint.init` | agree | 16214098169923692097 | 13669526402382336587 |  |
| `Fw.Parts.PlatformGlint.reset` | agree | 8721933728777508746 | 14122449462935488495 |  |
| `Fw.Parts.PlatformGlint.Ev` | agree | 3931117990 | 15338620449651367757 |  |
| `Fw.Parts.PlatformGlint.step` | agree | 17164323004691170744 | 5675460889762854604 |  |
| `Fw.Parts.PlatformGlint.Inv` | agree | 16943197065715243192 | 6004071036441924087 |  |
| `Fw.Parts.PlatformGlint.inv_init` | agree | 17612037825612972769 | 18272352031460368956 |  |
| `Fw.Parts.PlatformGlint.inv_step` | agree | 10223308074675117182 | 5490048828936546834 |  |
| `Fw.Parts.PlatformGlint.reduced_never_plays` | agree | 17521384766154729147 | 5037050951180061480 |  |
| `Fw.Parts.PlatformGlint.visible_arms` | agree | 15086024901211085453 | 229645945302937899 |  |
| `Fw.Parts.PlatformGlint.fire_plays` | agree | 15659862698389892290 | 10882745850350737948 |  |
| `Fw.Parts.PlatformGlint.view` | agree | 17956055321681209187 | 15813298614777736560 |  |
| `Fw.Parts.PlatformGolden.rin` | disagree | 893280584 | 1659150252371112010 | Math q·10^6·10^{-6} is vacuous and omits the fallback. Fix: rin(q) = JSON decimal num·(10^6/den)·10^{-6} if den \| 10^6, else {num: str(num), den: str(den)}. |
| `Fw.Parts.PlatformGolden.ratWire` | disagree | 893280584 | 8271059587640101315 | Math omits that fields are decimal strings of the reduced fraction. Fix: ratWire(q) = {num: toString(q.num), den: toString(q.den)}. |
| `Fw.Parts.PlatformGolden.line` | disagree | 477717292 | 13602363943829079377 | Math 'JSON line' states no content. Fix: line(fn, in, out) = compress({fn: fn, in: obj(in), out: out}). |
| `Fw.Parts.PlatformGolden.jn` | agree | 1534267800 | 9418899831807884546 |  |
| `Fw.Parts.PlatformGolden.times` | agree | 3599122630 | 5620562364666871203 |  |
| `Fw.Parts.PlatformGolden.rgbWire` | agree | 2764293545 | 10174345255565791811 |  |
| `Fw.Parts.PlatformGolden.platformLines` | disagree | 4017531403 | 11678642638589977980 | Math 'lines' states nothing. Fix: raw/shrinking/shrink(rm∈{F,T}) over vh∈[600,800,900] × 15 bottoms; scale over 5 s; stageHeight/artboardScale over 6 widths; one const line (bgBlur, bgOpacity…, grainTile). |
| `Fw.Parts.PlatformGolden.sweepLines` | disagree | 4017531403 | 18372110341997127044 | Math 'lines' states nothing. Fix: pos/phase over T(period); color at imageU(v,p) for 7 v × 5 p; active for reduce∈[F,T]; const {periodMs, stops}. |
| `Fw.Parts.PlatformGolden.marqueeLines` | disagree | 4017531403 | 3236003664478318408 | Math 'lines' states nothing. Fix: offsetLeft/offsetRight over T(period) × w∈[1000,2192,4048]; running for reduce∈[F,T]; const {periodMs}. |
| `Fw.Parts.PlatformGolden.sideName` | agree | 6224927389044829326 | 13071908942666464173 |  |
| `Fw.Parts.PlatformGolden.stJson` | disagree | 13730681569056081640 | 845334758108563 | Math omits key names and encodings. Fix: stJson(s) = {h, g, v, timer: τ=some d ? ratWire(d) : null, t0: t_0=some d ? ratWire(d) : null}. |
| `Fw.Parts.PlatformGolden.stIn` | disagree | 13730681569056081640 | 9939796997167616281 | Math omits key names and encodings. Fix: stIn(s) = {h, g, v, timer: τ=some d ? rin(d) : null, t0: t_0=some d ? rin(d) : null}. |
| `Fw.Parts.PlatformGolden.evIn` | disagree | 7713840813040354687 | 2781806774447947082 | Math elides fields with '…'. Fix: ratio(r) ↦ {kind: ratio, ratio: rin(r)}; reduced(b) ↦ {kind: reduced, value: b}; fire ↦ {kind: fire}. |
| `Fw.Parts.PlatformGolden.glintLines` | disagree | 4017531403 | 9159642870513518861 | Math 'lines' states nothing. Fix: sample over 2 sides × 17 elapsed; step over 6 states × now∈[0,600,1000,2500] × 7 events; view over 2 states × 2 sides × 4 nows; const {durMs, startDelayMs, minRatio}. |
| `Fw.Parts.PlatformGolden.viewJson` | disagree | 18273315195726722264 | 2343425330344711140 | Math omits key names. Fix: viewJson(v) = {len: ℓ, topic: i, shown: s, leaving: a, results: r, caret: c}. |
| `Fw.Parts.PlatformGolden.entryTable` | disagree | 14182609729687948041 | 704099687024549191 | Math [(name,e)] lists no entries. Fix: the 18 pairs credCard0/3, profilePhone, rings, faceLeft, faceRight, dash, shield, logo, flag1/3/6, invoiceCard, orderRow0/3, askIn0/2, askOut1 with their entries, in that order. |
| `Fw.Parts.PlatformGolden.entriesLines` | disagree | 4017531403 | 2730994584670886570 | Math 'lines' states nothing. Fix: ease_spring over 10 x; progress over entryTable × 11 t; countAt over 8 (t,n); askView over 23 t with lens [23,25,22,20]; one const line (spring, timings, entries). |
| `Fw.Parts.PlatformGolden.files` | disagree | 203758760 | 11259703588022677745 | Math omits the five pairs. Fix: files = [(platform.jsonl, platformLines), (platform.sweep.jsonl, sweepLines), (platform.glint.jsonl, glintLines), (platform.marquee.jsonl, marqueeLines), (platform.entries.jsonl, entriesLines)]. |
| `Fw.Console.Land.protectedGlobs` | disagree | 4017531403 | 11187214555794217429 | The Lean list holds exclusion globs, each with a leading !. The math drops the ! and writes a set. Fix: P = [\texttt{!.fw-console/}, \texttt{!.git/}, \texttt{!.claude/settings*}, \texttt{!lean/.lake/}]. |
| `Fw.Console.Land.generated` | agree | 4017531403 | 8011565960059480654 |  |
| `Fw.Console.Land.registrations` | agree | 4017531403 | 4724976232379642705 |  |
| `Fw.Console.Land.safeName` | agree | 1526413716 | 11282064138303825240 |  |
| `Fw.Console.Land.handoffs` | agree | 1429689486 | 10412329204117237888 |  |
| `Fw.Console.Land.testGlob` | disagree | 1380837422 | 888147237958831701 | Lean matches splitOn(w,"/") = p::n::src::rest, so w = p/n/src with nothing after it also gives some. The math w = p/n/src/... reads as needing a further segment. Fix: case \mathrm{split}_/(w) = p :: n :: \texttt{src} :: r. |
| `Fw.Console.Land.testGlobs` | agree | 1429689486 | 752866481614739015 |  |
| `Fw.Console.Land.testGlob_eq_some` | disagree | 15947393189663587164 | 839899308062523289 | Lean has splitOn(w,"/") = p::n::src::rest, where rest may be []. The math \exists r: w = p/n/src/r is false for w = apps/x/src. Fix: \exists p,n,r:\ \mathrm{split}_/(w) = p :: n :: \texttt{src} :: r \land ... |
| `Fw.Console.Land.landScope` | agree | 1362163309 | 15504154356317254716 |  |
| `Fw.Console.Land.landScope_mem_tests` | agree | 15303880934632971077 | 9875970451621604990 |  |
| `Fw.Console.Land.landScope_protected_suffix` | agree | 18409279525631987974 | 6608997749259789536 |  |
| `Fw.Console.Land.Verdict` | agree | 3931117990 | 3370443023873608446 |  |
| `Fw.Console.Land.landVerdict` | agree | 3433660845722047311 | 10507293811485585172 |  |
| `Fw.Console.Land.matchesPath_dir_prefix` | agree | 9096310917897509265 | 7118192876734727153 |  |
| `Fw.Console.Land.outside_every_glob_refused` | agree | 10503584499909897468 | 8789203269906374405 |  |
| `Fw.Console.Land.excluded_refused` | agree | 290998573834969213 | 2344525670293958383 |  |
| `Fw.Console.Land.noWrites_refused` | agree | 5113960544852516882 | 6886810130505051612 |  |
| `Fw.Console.Land.landVerdict_ok_iff` | agree | 6661821125539110672 | 11029481811376644315 |  |
| `Fw.Engine.Chromium.CrKey` | agree | 3931117990 | 15065509979335395389 |  |
| `Fw.Engine.Chromium.CrKey.all` | agree | 14569251103777489020 | 5662872001910255784 |  |
| `Fw.Engine.Chromium.CrKey.name` | agree | 16672801923981271308 | 8105483122798586690 |  |
| `Fw.Engine.Chromium.CrProp` | agree | 3931117990 | 9993038153923168253 |  |
| `Fw.Engine.Chromium.CrLevel` | agree | 3931117990 | 2864685013388508346 |  |
| `Fw.Engine.Chromium.CrLevel.all` | agree | 11351820828782037020 | 6775780219665546213 |  |
| `Fw.Engine.Chromium.CrLevel.rank` | agree | 15828158119949249545 | 14415200406445486478 |  |
| `Fw.Engine.Chromium.CrLevel.max` | agree | 15210652871644917195 | 15759745881485172988 |  |
| `Fw.Engine.Chromium.CrLevel.stages` | agree | 14073908359279525753 | 4370479234387206997 |  |
| `Fw.Engine.Chromium.keyLevel` | agree | 9603044366951409999 | 8495434214204887042 |  |
| `Fw.Engine.Chromium.crLevel` | agree | 7731699277016782186 | 2732962241293629759 |  |
| `Fw.Engine.Chromium.scrollStages` | agree | 8182590125755894458 | 3880217429605614412 |  |
| `Fw.Engine.Chromium.CrProp.extra` | agree | 10492233755634900758 | 6278923309855754558 |  |
| `Fw.Engine.Chromium.crStagesOf` | agree | 10468992181359111860 | 306819913081897376 |  |
| `Fw.Engine.Chromium.CrMode` | agree | 3931117990 | 1902502812537476929 |  |
| `Fw.Engine.Chromium.lane` | agree | 2610004033009516459 | 15585087731236551795 |  |
| `Fw.Engine.Chromium.realChrome` | agree | 2610004033009516459 | 13025739833673841014 |  |
| `Fw.Engine.Chromium.crCompStages` | agree | 8200998662656035199 | 8821962268108272671 |  |
| `Fw.Engine.Chromium.chromiumAt` | agree | 2791640211103836858 | 17652472465690710077 |  |
| `Fw.Engine.Chromium.chromium` | agree | 4693264901122188913 | 6960751501850239015 |  |
| `Fw.Engine.Chromium.crStages_mono` | agree | 12071223130544463112 | 11896171091386284675 |  |
| `Fw.Engine.Chromium.CrLevel.le_max_left` | agree | 6816998504158758303 | 1448451672983565113 |  |
| `Fw.Engine.Chromium.CrLevel.le_max_right` | agree | 16690957281001429296 | 4277218294750357097 |  |
| `Fw.Engine.Chromium.CrLevel.le_trans` | agree | 17987981302547395662 | 7666022630928103414 |  |
| `Fw.Engine.Chromium.foldl_max_ge` | agree | 9625567192238691342 | 7624466033173416856 |  |
| `Fw.Engine.Chromium.custom_ge_reader` | agree | 12454093716560935305 | 8444493244066617918 |  |
| `Fw.Engine.Chromium.custom_ge_styleOnly` | agree | 5203480457745500675 | 7326383428850942061 |  |
| `Fw.Engine.Chromium.levelCover` | agree | 10393476899138390839 | 2417488580694720574 |  |
| `Fw.Engine.Chromium.levelCover_coverB` | agree | 15699780599966021328 | 9923687835671476340 |  |
| `Fw.Engine.Chromium.CrTimeline` | agree | 3931117990 | 2644781204299930907 |  |
| `Fw.Engine.Chromium.CrAnim` | agree | 3931117990 | 223717366032059724 |  |
| `Fw.Engine.Chromium.CrProp.eligible` | agree | 11457817186523426498 | 1366446037687285407 |  |
| `Fw.Engine.Chromium.CrProp.movesPixels` | agree | 11457817186523426498 | 13653721210159637092 |  |
| `Fw.Engine.Chromium.failBits` | agree | 14779144091327817288 | 15235113213091951732 |  |
| `Fw.Engine.Chromium.crThread` | agree | 7366911532982655039 | 18008182146064291185 |  |
| `Fw.Engine.Chromium.crThread_comp_iff` | agree | 3757402143243368018 | 12815739009217143574 |  |
| `Fw.Engine.Chromium.failBits_lane_no0` | agree | 1453406423249943907 | 7594747339073910730 |  |
| `Fw.Engine.Chromium.CrAnim.changes` | agree | 12512521205235917717 | 3846986316892921192 |  |
| `Fw.Engine.Chromium.animFrame` | agree | 10791734368085493487 | 17706934648406812140 |  |
| `Fw.Engine.Chromium.jsWrite` | agree | 1477655491305963266 | 3492565606669743043 |  |
| `Fw.Engine.Chromium.compAnim_no_layout_paint` | agree | 802874418664681921 | 1944902220792091817 |  |
| `Fw.Engine.Chromium.transformAnim_comp` | agree | 7605100422154726073 | 9952522972667638269 |  |
| `Fw.Engine.Chromium.compTransform_no_layout_paint` | agree | 2615865978924120247 | 8879538356668492837 |  |
| `Fw.Engine.Chromium.jsTransform_le_topLeft` | agree | 2892182863086349443 | 12118810829562177024 |  |
| `Fw.Engine.Chromium.jsTransform_lt_topLeft` | agree | 12211217512437623521 | 4636073306064725123 |  |
| `Fw.Engine.Chromium.cullPeriod` | agree | 2546708756 | 15598013030511263208 |  |
| `Fw.Engine.Chromium.scrollPaints` | agree | 454481631 | 696108055991650898 |  |
| `Fw.Engine.Chromium.scrollPaints_moved` | agree | 9749731951981349817 | 1834448816975136600 |  |
| `Fw.Engine.Chromium.scrollChange` | agree | 13752119209759853678 | 248601067705857516 |  |
| `Fw.Engine.Chromium.scroll_stages` | agree | 7961052819783729650 | 18265783656645236534 |  |
| `Fw.Engine.Chromium.Pred` | agree | 3931117990 | 11268299786347388392 |  |
| `Fw.Engine.Chromium.Pred.str` | agree | 3997042335715859750 | 9376361761910096243 |  |
| `Fw.Engine.Chromium.predOf` | agree | 13950701030804248567 | 5035171446861577932 |  |
| `Fw.Engine.Chromium.stageCounts` | agree | 1424393777815108805 | 7095161496490713512 |  |
| `Fw.Engine.Chromium.stageName` | agree | 13237354143774927416 | 2703954888501818249 |  |
| `Fw.Engine.Chromium.levelName` | agree | 3799874488409752002 | 12380622307193323436 |  |
| `Fw.Engine.Chromium.layerName` | agree | 2918275682134471121 | 6650128148809716468 |  |
| `Fw.Engine.Chromium.fxRest` | agree | 4039410157403949536 | 6764560437412920497 |  |
| `Fw.Engine.Chromium.fxAnimComp` | agree | 4039410157403949536 | 8923917931996615993 |  |
| `Fw.Engine.Chromium.fxAnimLayout` | agree | 4039410157403949536 | 3564181335688634100 |  |
| `Fw.Engine.Chromium.stageRow` | agree | 15044185091677193306 | 18028651110482358421 |  |
| `Fw.Engine.Chromium.bitCount` | agree | 11605754492705853356 | 16479956603806672348 |  |
| `Fw.Engine.Chromium.f0Row` | disagree | 5174617436275224003 | 8219413044264327856 | In Lean, pred is =0 if bitCount(0,A)=0 and any otherwise. The math states pred: =0 with no condition, which holds only because of failBits_lane_no0. Fix: \mathrm{pred}{:}\,(=\!0 \text{ if } \operatorname{bitCount}(0,A)=0 \text{ else any}). |
| `Fw.Engine.Chromium.signatureRow` | agree | 2334200896690598204 | 18011974705977293704 |  |
| `Fw.Engine.Chromium.modeRow` | agree | 14175473028015287419 | 10543183514450482480 |  |
| `Fw.Engine.Chromium.goldenRows` | agree | 1789995637 | 6296979087880510471 |  |
| `Fw.Engine.Chromium.goldenText` | agree | 3265150928 | 2500430238034089871 |  |
| `Fw.Engine.Chromium.goldenPath` | agree | 4277623442 | 9938964274700795614 |  |
| `Fw.Engine.Chromium.goldenRun` | agree | 2311388699 | 6835330147681316779 |  |
| `Fw.Measure.EngineCheck.Pred` | agree | 3931117990 | 8840667089120084281 |  |
| `Fw.Measure.EngineCheck.Pred.ofName` | agree | 6040505673203702954 | 8589943139200282383 |  |
| `Fw.Measure.EngineCheck.exact` | agree | 17323568078924736632 | 10810331413947111924 |  |
| `Fw.Measure.EngineCheck.slack` | agree | 12649141545779846115 | 3156425067256231692 |  |
| `Fw.Measure.EngineCheck.Claim` | agree | 14046067587221957365 | 9167824566646397959 |  |
| `Fw.Measure.EngineCheck.passes` | agree | 3245899609597757416 | 4709867431151215432 |  |
| `Fw.Measure.EngineCheck.fails` | agree | 3245899609597757416 | 13996456703034534897 |  |
| `Fw.Measure.EngineCheck.Why` | agree | 3931117990 | 834008984110026221 |  |
| `Fw.Measure.EngineCheck.Res` | agree | 3931117990 | 2481821818898923819 |  |
| `Fw.Measure.EngineCheck.verdict` | agree | 10471608665009151516 | 13115588514277987822 |  |
| `Fw.Measure.EngineCheck.exact_frames` | agree | 2689169521491044898 | 4033705634041129526 |  |
| `Fw.Measure.EngineCheck.totals_gap` | agree | 7466189121757657853 | 3932976703042689131 |  |
| `Fw.Measure.EngineCheck.claim_exact_iff` | agree | 14731494680190623602 | 11931715052855590205 |  |
| `Fw.Measure.EngineCheck.exact_pass_iff` | agree | 5271322605242317040 | 467993533262162563 |  |
| `Fw.Measure.EngineCheck.quarantined_unusable` | agree | 970212183114538093 | 3077368356346474244 |  |
| `Fw.Measure.EngineCheck.ltO_stable_unusable` | agree | 17274129775061970168 | 15240154937479795772 |  |
| `Fw.Measure.EngineCheck.verdict_pass` | agree | 14878480917408698973 | 15652083971816286954 |  |
| `Fw.Measure.EngineCheck.verdict_bug` | agree | 7852845861798332234 | 13489619856936496104 |  |
| `Fw.Measure.EngineCheck.pass_sound` | agree | 7286059343406600772 | 12873901723021329873 |  |
| `Fw.Measure.EngineCheck.bug_sound` | agree | 2511122705367085126 | 7527737244004888846 |  |
| `Fw.Measure.EngineCheck.leO_pass_margin` | agree | 10963959309669341268 | 1811733012559046502 |  |
| `Fw.Measure.EngineCheck.total_nonneg` | agree | 18415867759607590108 | 1857604556349535164 |  |
| `Fw.Measure.EngineCheck.total_zero_frames` | agree | 12115724500355140470 | 3367894130970134043 |  |
| `Fw.Measure.EngineCheck.judgeClass` | agree | 8651559340865467274 | 3593269934122356141 |  |
| `Fw.Measure.EngineCheck.within_judge` | agree | 10672988255246411362 | 10409032760463786002 |  |
| `Fw.Measure.EngineCheck.pairs` | agree | 3412871159656930734 | 10015774789914139952 |  |
| `Fw.Measure.EngineCheck.combine` | agree | 7290206520246401589 | 2156072571465326676 |  |
| `Fw.Measure.EngineCheck.combine_pass` | agree | 3756419291225592701 | 3884021413462358996 |  |
| `Fw.Measure.EngineCheck.combine_bug` | agree | 14520110941445081539 | 14233642023324905605 |  |
| `Fw.Measure.EngineCheck.rowRes` | agree | 18149861437978527308 | 12361135032076949113 |  |
| `Fw.Measure.EngineCheck.rowRes_pass_sound` | agree | 14343428456293153505 | 3722188227123668640 |  |
| `Fw.Measure.EngineCheck.rowRes_bug_sound` | agree | 9775486215020631766 | 5391807424249592722 |  |
| `Fw.Measure.EngineCheck.laneRes` | agree | 17368602389073089182 | 6275441884168368417 |  |
| `Fw.Measure.EngineCheck.laneRes_webkit` | agree | 13199344088902146463 | 4646527852337350864 |  |
| `Fw.Measure.EngineCheck.laneRes_chromium` | agree | 3052072384618280132 | 1715673099561008361 |  |
| `Fw.Measure.Quiet.Verdict` | agree | 3931117990 | 6894234376455306396 |  |
| `Fw.Parts.MorphTween.pointerNone_iff` | agree | 14299847474152279287 | 6399772484125840200 |  |
| `Fw.Parts.MorphTweenOpt.interpWk` | agree | 1069553462 | 6553989694144720069 |  |
| `Fw.Parts.MorphTweenOpt.interpBlink` | agree | 1069553462 | 10131001648465728497 |  |
| `Fw.Parts.MorphTweenOpt.interpBlink_eq_wk` | agree | 18305058245743069444 | 13638179684356555199 |  |
| `Fw.Parts.MorphTweenOpt.interpDiscrete` | agree | 1069553462 | 8885000171719193511 |  |
| `Fw.Parts.MorphTweenOpt.discrete_not_linear` | agree | 2584500844105526968 | 3927852346090962415 |  |
| `Fw.Parts.MorphTweenOpt.WaapiPremises` | agree | 3931117990 | 13588097497038681974 |  |
| `Fw.Parts.MorphTweenOpt.premisesWk` | agree | 15802101433843222745 | 647274531777910030 |  |
| `Fw.Parts.MorphTweenOpt.premisesBlink` | agree | 15802101433843222745 | 4859587449625956944 |  |
| `Fw.Parts.MorphTweenOpt.Anim` | agree | 3931117990 | 11711193575808397407 |  |
| `Fw.Parts.MorphTweenOpt.progress` | agree | 4035929107 | 17420930349939544158 |  |
| `Fw.Parts.MorphTweenOpt.valA` | agree | 2539664505171756799 | 8769514572282616591 |  |
| `Fw.Parts.MorphTweenOpt.clamp01_idem` | agree | 9608599820604204849 | 16746179812797979112 |  |
| `Fw.Parts.MorphTweenOpt.ease_clamp` | agree | 1715525649843473365 | 1303360158871780846 |  |
| `Fw.Parts.MorphTweenOpt.tween_value_eq` | agree | 6533856352889406899 | 15366413963782822222 |  |
| `Fw.Parts.MorphTweenOpt.timing_progress` | agree | 2180597355831926822 | 1494703089193152979 |  |
| `Fw.Parts.MorphTweenOpt.valA_eq` | agree | 13592019123758280966 | 10062416829644628459 |  |
| `Fw.Parts.MorphTweenOpt.Ev` | agree | 3931117990 | 15536974697300459661 |  |
| `Fw.Parts.MorphTweenOpt.stepO` | agree | 11472577204271419017 | 16794682444891307770 |  |
| `Fw.Parts.MorphTweenOpt.runO` | agree | 1280343029437954413 | 18214274685911374778 |  |
| `Fw.Parts.MorphTweenOpt.VSt` | agree | 3931117990 | 12839902780316486634 |  |
| `Fw.Parts.MorphTweenOpt.initV` | agree | 17204246170951118442 | 3541931257030032315 |  |
| `Fw.Parts.MorphTweenOpt.valV` | agree | 7003623924677204293 | 13168587149011505355 |  |
| `Fw.Parts.MorphTweenOpt.stepV` | agree | 18395000770891111762 | 14121915308046259735 |  |
| `Fw.Parts.MorphTweenOpt.runV` | agree | 16000154103083152977 | 15641885677840190987 |  |
| `Fw.Parts.MorphTweenOpt.monoB` | agree | 8585243984255881995 | 7245870255235102366 |  |
| `Fw.Parts.MorphTweenOpt.Inv` | agree | 624860334945455482 | 6312922122336897182 |  |
| `Fw.Parts.MorphTweenOpt.inv_init` | agree | 3367737125555890857 | 7941674693788950985 |  |
| `Fw.Parts.MorphTweenOpt.inv_push` | agree | 7313696779190641185 | 12406731268808117900 |  |
| `Fw.Parts.MorphTweenOpt.inv_tick` | agree | 10190768068240436521 | 8399022437282828572 |  |
| `Fw.Parts.MorphTweenOpt.inv_run` | agree | 16278356374078436388 | 12321427700275050411 |  |
| `Fw.Parts.MorphTweenOpt.waapi_eq_tween` | agree | 17443280923577930092 | 3971868942156195797 |  |
| `Fw.Parts.MorphTweenOpt.waapi_frame_eq` | agree | 10068317782209449572 | 8609095723505509832 |  |
| `Fw.Parts.MorphTweenOpt.flipAt` | agree | 3320891813 | 14015365068717484752 |  |
| `Fw.Parts.MorphTweenOpt.kfOffset` | agree | 1069553462 | 10501184373031394502 |  |
| `Fw.Parts.MorphTweenOpt.flagV` | agree | 1370077378 | 12706646744297921968 |  |
| `Fw.Parts.MorphTweenOpt.flagO` | agree | 1370077378 | 1617788991352451273 |  |
| `Fw.Parts.MorphTweenOpt.up_iff` | agree | 14324682363413773099 | 13867695071385885351 |  |
| `Fw.Parts.MorphTweenOpt.down_iff` | agree | 10856713619913451477 | 8699674515043219422 |  |
| `Fw.Parts.MorphTweenOpt.kfOffset_flat` | agree | 9541861092902556108 | 5047111906232522680 |  |
| `Fw.Parts.MorphTweenOpt.kfOffset_mem` | agree | 3134519808066693704 | 9539783606427551443 |  |
| `Fw.Parts.MorphTweenOpt.flag_below_tie` | agree | 9568059201975066796 | 14206677718878777326 |  |
| `Fw.Parts.MorphTweenOpt.flag_tie` | agree | 18315626261793398475 | 4697254113989905064 |  |
| `Fw.Parts.MorphTweenOpt.flag_above_tie` | agree | 4176582905957274730 | 1202125632622002083 |  |
| `Fw.Parts.MorphTweenOpt.flags_same_frame` | agree | 13897033065450898852 | 5438025382774218178 |  |
| `Fw.Parts.MorphTweenOpt.flagV_one` | agree | 5671333971709348032 | 3001689080043451811 |  |
| `Fw.Parts.MorphTweenOpt.ease_gt_iff` | agree | 3503655901739194264 | 6154623689799733289 |  |
| `Fw.Parts.MorphTweenOpt.thresholds` | agree | 1704485823 | 4628386192289192377 |  |
| `Fw.Parts.MorphTweenOpt.pointerNone_eq` | agree | 14377818908889913071 | 5317828472057207389 |  |
| `Fw.Parts.MorphTweenOpt.fade_css` | agree | 18374259303928879416 | 7830894507026246763 |  |
| `Fw.Parts.MorphTweenOpt.flagW` | agree | 3213752308833392361 | 2189507240674920449 |  |
| `Fw.Parts.MorphTweenOpt.tieB` | agree | 3647519985914901254 | 7328202247208571548 |  |
| `Fw.Parts.MorphTweenOpt.flags_same_run` | agree | 6116406792635990889 | 4539984931908175703 |  |
| `Fw.Parts.MorphTweenOpt.View` | agree | 3931117990 | 18228890498042433371 |  |
| `Fw.Parts.MorphTweenOpt.viewO` | agree | 10201115770764718814 | 15950681997731426598 |  |
| `Fw.Parts.MorphTweenOpt.viewV` | agree | 13871279647720831894 | 18353015217434945881 |  |
| `Fw.Parts.MorphTweenOpt.Hist` | agree | 3931117990 | 9867111436052139802 |  |
| `Fw.Parts.MorphTweenOpt.view_eq` | agree | 5673716279590123110 | 2991355496690621666 |  |
| `Fw.Parts.MorphTweenOpt.waapi_vis` | agree | 6434179657708926138 | 14993949920469299199 |  |
| `Fw.Parts.MorphTweenOpt.dropsScript` | agree | 18201648147187768253 | 5200196076855314998 |  |
| `Fw.Parts.MorphTweenOpt.script_drop` | agree | 6013995650070401887 | 1501458067712911828 |  |
| `Fw.Parts.MorphTweenOpt.cr_custom_main` | agree | 18227276537819174562 | 4998061376748205665 |  |
| `Fw.Parts.MorphTweenOpt.cr_no_script` | agree | 4247377124496625479 | 6821895423570619884 |  |
| `Fw.Parts.MorphTweenOpt.waapi_work_le_chromium` | agree | 8614447474464884078 | 11677204389295438974 |  |
| `Fw.Parts.MorphTweenOpt.wk_no_script` | agree | 14822874612865365561 | 3793771069928258725 |  |
| `Fw.Parts.MorphTweenOpt.waapi_work_le_webkit` | agree | 8610265424882501252 | 2193191417349131899 |  |
| `Fw.Parts.MorphTweenOpt.waapi_work_le` | agree | 263058349219186788 | 4364712478673373374 |  |
| `Fw.Parts.MorphTweenOpt.drop_run_dominates` | agree | 13271975792237412104 | 7891126223787725912 |  |
| `Fw.Parts.MorphTweenOpt.crMorph` | agree | 1037570828942945348 | 5651384157179210984 |  |
| `Fw.Parts.MorphTweenOpt.wkMorph` | agree | 2579111148985320997 | 13190115263380759931 |  |
| `Fw.Parts.MorphTweenOpt.predW` | agree | 927257721002872234 | 12481642389898244964 |  |
| `Fw.Parts.MorphTweenOpt.predStage` | agree | 13237354143774927416 | 1862032594712338419 |  |
| `Fw.Parts.MorphTweenOpt.pred_sound` | agree | 3663521292716021237 | 9508978405881115161 |  |
| `Fw.Parts.MorphTweenOpt.PredRow` | agree | 3931117990 | 3927830408130641016 |  |
| `Fw.Parts.MorphTweenOpt.armV` | agree | 3265150928 | 2294609069276412327 |  |
| `Fw.Parts.MorphTweenOpt.countsOf` | agree | 6142760560302376045 | 7130437146686993865 |  |
| `Fw.Parts.MorphTweenOpt.goldenRows` | agree | 14902286675933474485 | 3092244280049598880 |  |
| `Fw.Parts.MorphTweenOpt.PredRow.json` | agree | 96175375969513023 | 6645908373818946286 |  |
| `Fw.Parts.MorphTweenOpt.goldenJsonl` | agree | 3265150928 | 14997386187219371071 |  |
| `Fw.Parts.PlatformSection.clamp01` | agree | 3498294262 | 11117017471824840705 |  |
| `Fw.Parts.PlatformSection.smooth` | agree | 3498294262 | 549525092894584425 |  |
| `Fw.Parts.PlatformSection.raw` | agree | 4035929107 | 18270313422672232910 |  |
| `Fw.Parts.PlatformSection.shrink` | agree | 3166571776 | 17679911533384650982 |  |
| `Fw.Parts.PlatformSection.shrinking` | agree | 2621932306 | 5758723229825311895 |  |
| `Fw.Parts.PlatformSection.scale` | agree | 3498294262 | 16392122664457325378 |  |
| `Fw.Parts.PlatformSection.radius` | agree | 4035929107 | 9381486230084220526 |  |
| `Fw.Parts.PlatformSection.clamp01_mem` | agree | 6724117951197758742 | 9540711019198229325 |  |
| `Fw.Parts.PlatformSection.smooth_mem` | agree | 16155532137209402450 | 9655858314538360961 |  |
| `Fw.Parts.PlatformSection.smooth_symm` | agree | 15530339819377133012 | 8876173746281252946 |  |
| `Fw.Parts.PlatformSection.raw_mem` | agree | 4830307102424403387 | 3308974140146675452 |  |
| `Fw.Parts.PlatformSection.shrink_ends` | agree | 881677036790803101 | 17841078656876633781 |  |
| `Fw.Parts.PlatformSection.shrink_reduced_two` | disagree | 14026517128746742122 | 11409455976935737191 | The Lean is only about shrink true b h (reduced motion). The math s \in \{0,1\} leaves out reduced motion and is false in general. Fix: \forall b,h \in \mathbb{Q}:\ \operatorname{shrink}(\top, b, h) \in \{0, 1\}. |
| `Fw.Parts.PlatformSection.shrink_mem` | agree | 15235462756176100144 | 15123244478918411411 |  |
| `Fw.Parts.PlatformSection.scale_mem` | agree | 9635895670275232116 | 10117109199432480347 |  |
| `Fw.Parts.PlatformSection.stageHeight` | agree | 3498294262 | 4989755306273056 |  |
| `Fw.Parts.PlatformSection.artboardScale` | agree | 3498294262 | 7865170947555732820 |  |
| `Fw.Parts.PlatformSection.artboard_fills` | agree | 8277707833737722448 | 17274417839568005358 |  |
| `Fw.Parts.PlatformSection.artboard_width` | agree | 17442976113195468748 | 9796364161983080042 |  |
| `Fw.Parts.PlatformSection.bgOpacity` | agree | 2155457422 | 13180417977925064538 |  |
| `Fw.Parts.PlatformSection.bgBlur` | agree | 1901972866 | 6656947586336909521 |  |
| `Fw.Parts.PlatformSection.grainOpacity` | agree | 2155457422 | 17027319401820011750 |  |
| `Fw.Parts.PlatformSection.grainTile` | agree | 1901972866 | 5014107353718525511 |  |
| `Fw.Parts.PlatformSection.Row` | agree | 3931117990 | 11743752108895704869 |  |
| `Fw.Parts.PlatformSection.Bg` | agree | 3931117990 | 1279274136355096665 |  |
| `Fw.Parts.PlatformSection.bgOf` | agree | 17482399383673219105 | 10671841504441927046 |  |
| `Fw.Parts.PlatformSection.flip` | agree | 14414519395252894450 | 17439553438690287470 |  |
| `Fw.Parts.PlatformSection.quote_fainter` | agree | 13673365974159701984 | 5461747372929522152 |  |
| `Fw.Parts.PlatformSection.secure_grain_fainter` | agree | 15933775373002358538 | 6525041426129890324 |  |
| `Fw.Null.pNull` | agree | 860301984 | 3627452787602067488 |  |
| `Fw.Null.winsAt_le_one` | agree | 13636951606155557958 | 351250758126195679 |  |
| `Fw.Engine.WebKit.Diff` | agree | 3931117990 | 6294546879929897898 |  |
| `Fw.Engine.WebKit.Diff.rank` | agree | 16267985858435497287 | 10632764850639393628 |  |
| `Fw.Engine.WebKit.Diff.max` | agree | 7813731228368357029 | 13775711883101047440 |  |
| `Fw.Engine.WebKit.diffStages` | agree | 180526507988448686 | 14630110439469552121 |  |
| `Fw.Engine.WebKit.Ctx` | agree | 3931117990 | 6828196259653883130 |  |
| `Fw.Engine.WebKit.WkProp` | agree | 3931117990 | 7464558633870126631 |  |
| `Fw.Engine.WebKit.rawDiff` | agree | 8259363017613316167 | 9269908138526550374 |  |
| `Fw.Engine.WebKit.adjTransform` | agree | 14701031307368789300 | 408331168898769314 |  |
| `Fw.Engine.WebKit.adjust` | agree | 9285675802686498217 | 16635176074543475179 |  |
| `Fw.Engine.WebKit.wkDiff` | agree | 11061204636161794040 | 9002696918453685721 |  |
| `Fw.Engine.WebKit.Policy` | agree | 3931117990 | 17433099886794534533 |  |
| `Fw.Engine.WebKit.WkMode` | agree | 3931117990 | 2065113781791672173 |  |
| `Fw.Engine.WebKit.WkMode.safari` | agree | 4896611385188254884 | 13871702798761622092 |  |
| `Fw.Engine.WebKit.webkitAt` | agree | 9587901923604966714 | 16830886960380550812 |  |
| `Fw.Engine.WebKit.webkit` | agree | 15744378093111098160 | 7422733930682624788 |  |
| `Fw.Engine.WebKit.transform_diff` | agree | 510735686265728513 | 9142685317524252503 |  |
| `Fw.Engine.WebKit.opacityCross1_layout` | agree | 3362860946366563374 | 10830959624422374522 |  |
| `Fw.Engine.WebKit.strokeDashoffset_layout` | agree | 1263515033939282477 | 8218910840058822215 |  |
| `Fw.Engine.WebKit.scrollPos_stages` | agree | 5970706720673454977 | 10112890747316601013 |  |
| `Fw.Engine.WebKit.wk_not_mono` | agree | 2351244967537726629 | 2750389458486698902 |  |
| `Fw.Engine.WebKit.CompReason` | agree | 3931117990 | 891088252741533817 |  |
| `Fw.Engine.WebKit.composites` | agree | 11541606771207965521 | 17552992178918065219 |  |
| `Fw.Engine.WebKit.robust` | agree | 6509207667745209596 | 11733830031077198177 |  |
| `Fw.Engine.WebKit.static2D_not_own` | agree | 15974201781050877023 | 7102736825605694771 |  |
| `Fw.Engine.WebKit.willChange_dropped` | agree | 11050961949093631521 | 6023980824920410900 |  |
| `Fw.Engine.WebKit.own_robust` | agree | 11614540036645246313 | 6281922371487332670 |  |
| `Fw.Engine.WebKit.base_commit` | agree | 16152953312332583300 | 3806065402466102522 |  |
| `Fw.Engine.WebKit.scrollStep` | agree | 2295350488405320386 | 14407675026441897550 |  |
| `Fw.Engine.WebKit.scroll_commit` | agree | 1565976781677712645 | 16609373034203968217 |  |
| `Fw.Engine.WebKit.scroll_baseline` | agree | 11816627746676506636 | 8429394689966409475 |  |
| `Fw.Engine.WebKit.CssProp` | agree | 3931117990 | 3788096635921114237 |  |
| `Fw.Engine.WebKit.Path` | agree | 3931117990 | 2527389248019446715 |  |
| `Fw.Engine.WebKit.accelerated` | agree | 12208537986102173238 | 15723605012824217837 |  |
| `Fw.Engine.WebKit.Timeline` | agree | 3931117990 | 12361630470913779037 |  |
| `Fw.Engine.WebKit.Easing` | agree | 3931117990 | 1185462589675210412 |  |
| `Fw.Engine.WebKit.Blocker` | agree | 3931117990 | 9117438391959309164 |  |
| `Fw.Engine.WebKit.WkAnim` | agree | 3931117990 | 11819746830186456571 |  |
| `Fw.Engine.WebKit.pathOf` | agree | 2675317957789654 | 7132226314457464833 |  |
| `Fw.Engine.WebKit.canBeAccelerated` | agree | 14962322472291328788 | 16939147631577649303 |  |
| `Fw.Engine.WebKit.isFilter` | agree | 9355655373554767175 | 14926570303656355459 |  |
| `Fw.Engine.WebKit.caAccepts` | agree | 18138582357883844644 | 8506523998378492199 |  |
| `Fw.Engine.WebKit.wkThread` | agree | 11874406061561310918 | 1834990301367838631 |  |
| `Fw.Engine.WebKit.WkAnim.clean` | agree | 13511654557799042207 | 13107502390979987789 |  |
| `Fw.Engine.WebKit.path_default` | agree | 4988520526875975628 | 10936302669156446775 |  |
| `Fw.Engine.WebKit.legacy_rejects` | agree | 1069490714188718296 | 9903353333914642431 |  |
| `Fw.Engine.WebKit.custom_main` | agree | 14344518905425971817 | 15463587941159120957 |  |
| `Fw.Engine.WebKit.comp_accelerated` | agree | 16790595063044683274 | 12179075509413462146 |  |
| `Fw.Engine.WebKit.compFrame` | agree | 16991382746948856284 | 4863861814094155231 |  |
| `Fw.Engine.WebKit.animFrame` | agree | 13162752002208331800 | 18059795311485558894 |  |
| `Fw.Engine.WebKit.compFrame_zero` | agree | 16012678500149826700 | 12349941469235416328 |  |
| `Fw.Engine.WebKit.anim_comp_zero` | agree | 3502821528809421982 | 4200410468762884606 |  |
| `Fw.Engine.WebKit.jsFrame` | agree | 4985023659763822871 | 3502237046582045330 |  |
| `Fw.Engine.WebKit.trade_accepted` | agree | 8086516009340126079 | 14437695893707245273 |  |
| `Fw.Engine.WebKit.blurAnim` | agree | 2579111148985320997 | 3913386257746791924 |  |
| `Fw.Engine.WebKit.blur_comp` | agree | 16234600813629742242 | 15596272152523683269 |  |
| `Fw.Engine.WebKit.blur_zero` | agree | 3728434228436002722 | 5794093436830066973 |  |
| `Fw.Engine.WebKit.Pred` | agree | 3931117990 | 12270539046510209353 |  |
| `Fw.Engine.WebKit.Pred.str` | agree | 8173726216513224844 | 5041308527755017777 |  |
| `Fw.Engine.WebKit.predictOrig` | agree | 8090162057960462019 | 4239970153109741951 |  |
| `Fw.Engine.WebKit.predictVar` | agree | 10942595151348050040 | 11549748170131443467 |  |
| `Fw.Engine.WebKit.Lane` | agree | 3931117990 | 11657256671778487311 |  |
| `Fw.Engine.WebKit.Lane.counts` | agree | 7961540717507714628 | 526397752041400628 |  |
| `Fw.Engine.WebKit.stageName` | agree | 13237354143774927416 | 11676243100482230771 |  |
| `Fw.Engine.WebKit.Scenario` | agree | 3931117990 | 11734543658945868389 |  |
| `Fw.Engine.WebKit.scenarios` | disagree | 8900147676106821374 | 18233300571834212338 | Math gives only ids, lanes and \|variants_i\|=1; it omits every frame. Fix: list each, e.g. P1=(sim, scrollStep(js[(1,transform,layer)]), [(scrollDriven, scrollStep(animFrame(safari, clean([transform],scroll), [(1,transform,layer)])))]), likewise P2..P5 per source. |
| `Fw.Engine.WebKit.Row` | agree | 3931117990 | 4862330784743770524 |  |
| `Fw.Engine.WebKit.rowsOf` | disagree | 7989985682188099606 | 11028466529086581976 | Lean stores the strings stageName(s) and (predictOrig o s).str / (predictVar w o s).str; math puts the Stage s and the Pred value. Fix: write \operatorname{name}(s) and \operatorname{str}(\operatorname{predO}(W_o,s)), \operatorname{str}(\operatorname{predV}(W_v,W_o,s)). |
| `Fw.Engine.WebKit.goldenRows` | agree | 13349458273485063496 | 8221119841353165265 |  |
| `Fw.Engine.WebKit.Row.json` | agree | 17981706437347346499 | 7672234322694222688 |  |
| `Fw.Engine.WebKit.goldenJsonl` | disagree | 3265150928 | 7075766214768890675 | Math ranges over 'rows', which in this module is the per-scenario function rows(σ); Lean joins goldenRows. Fix: \mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{goldenRows}} (\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}) |
| `Fw.Engine.WebKit.predOf` | agree | 1776253279 | 7500607085171646416 |  |
| `Fw.Parts.Golden.tweenLines` | disagree | 4017531403 | 10879555087430801979 | Math is the placeholder \text{lines}; it says nothing about the body. Fix: state the concatenation: ease over xs ++ tween over ends×els ++ dir ++ armed ++ taken ++ active ++ fade/pointerNone ++ push ++ frame rows. |
| `Fw.Parts.HeroExitOpt.clamp01` | agree | 3498294262 | 8057053330469666002 |  |
| `Fw.Parts.HeroExitOpt.timelineProgress` | agree | 1069553462 | 4051005729760178602 |  |
| `Fw.Parts.HeroExitOpt.RG11` | agree | 3270613368 | 4472764071612965043 |  |
| `Fw.Parts.HeroExitOpt.div_eq_of_eq_mul` | agree | 3967941661 | 15657095016101343315 |  |
| `Fw.Parts.HeroExitOpt.progress_eq_js` | agree | 16258199260335357919 | 10247318457321750462 |  |
| `Fw.Parts.HeroExitOpt.lerp` | agree | 1069553462 | 7761581782371047299 |  |
| `Fw.Parts.HeroExitOpt.Consumer` | agree | 3931117990 | 12479088966035211578 |  |
| `Fw.Parts.HeroExitOpt.Consumer.val` | agree | 12196986773337444603 | 14070180050583577310 |  |
| `Fw.Parts.HeroExitOpt.Consumer.anim` | agree | 12196986773337444603 | 15055048767840769625 |  |
| `Fw.Parts.HeroExitOpt.val_affine` | agree | 884939615313394647 | 7762566848405438710 |  |
| `Fw.Parts.HeroExitOpt.anim_eq` | agree | 48551156926559259 | 9322400901496899277 |  |
| `Fw.Parts.HeroExitOpt.consumer_eq_s` | agree | 7149025707288943974 | 7304910780164925536 |  |
| `Fw.Parts.HeroExitOpt.reduced_eq` | agree | 14549185819856280991 | 14935215900247822796 |  |
| `Fw.Parts.HeroExitOpt.sentinelAbove` | agree | 1370077378 | 7962727475364568663 |  |
| `Fw.Parts.HeroExitOpt.sentinel_iff_pointerOff` | agree | 17674324124030989128 | 928514139257248556 |  |
| `Fw.Parts.HeroExitOpt.mainLe` | agree | 8958368436691900475 | 12681211434639614684 |  |
| `Fw.Parts.HeroExitOpt.mainLt` | agree | 8958368436691900475 | 6441219829992426873 |  |
| `Fw.Parts.HeroExitOpt.mainLe_mainUs` | agree | 13600781551146669194 | 7482355220182351965 |  |
| `Fw.Parts.HeroExitOpt.exitVar` | agree | 421340980 | 2526800179328434569 |  |
| `Fw.Parts.HeroExitOpt.copyReaders` | agree | 10128862532335155053 | 18062009400567636074 |  |
| `Fw.Parts.HeroExitOpt.cueReaders` | agree | 10128862532335155053 | 10697632733291353277 |  |
| `Fw.Parts.HeroExitOpt.scrollC` | agree | 10681139031546518500 | 3353487706919486448 |  |
| `Fw.Parts.HeroExitOpt.crOrigChanges` | agree | 10398411763457663950 | 149257802082169931 |  |
| `Fw.Parts.HeroExitOpt.crOrig` | agree | 17827461384335117029 | 17082921865748767016 |  |
| `Fw.Parts.HeroExitOpt.sAnim` | agree | 16833151810748077665 | 5375137578445737048 |  |
| `Fw.Parts.HeroExitOpt.crAnims` | agree | 17580899822088297535 | 15956947444344534025 |  |
| `Fw.Parts.HeroExitOpt.crVar` | agree | 10769784407478635902 | 9612803756016933768 |  |
| `Fw.Parts.HeroExitOpt.blur_main` | agree | 17290673206931818771 | 5057521038544875395 |  |
| `Fw.Parts.HeroExitOpt.opTr_comp` | agree | 1641167363740316334 | 6679045863464366518 |  |
| `Fw.Parts.HeroExitOpt.merged_main` | agree | 8837306771275905682 | 9961135252774269696 |  |
| `Fw.Parts.HeroExitOpt.crVar_eq` | agree | 15521630955402362233 | 3674369620557687422 |  |
| `Fw.Parts.HeroExitOpt.crOrigPasses` | agree | 13861085218002525744 | 3049476032713966184 |  |
| `Fw.Parts.HeroExitOpt.crOrigUnits` | agree | 1004086198962786762 | 12917777221537681072 |  |
| `Fw.Parts.HeroExitOpt.readerStages` | agree | 10274630676297502790 | 12109475459816072228 |  |
| `Fw.Parts.HeroExitOpt.reader_stages` | agree | 7590044816530225161 | 3857027579589855680 |  |
| `Fw.Parts.HeroExitOpt.cr_orig_exact` | agree | 16604787496806112870 | 15568871211975382862 |  |
| `Fw.Parts.HeroExitOpt.crVarPasses` | agree | 17681647860612934066 | 1584912003960297519 |  |
| `Fw.Parts.HeroExitOpt.crVarUnits` | agree | 10681274534712827629 | 2289851318725371763 |  |
| `Fw.Parts.HeroExitOpt.cr_var_exact` | agree | 8630509551868637980 | 9785207850417151034 |  |
| `Fw.Parts.HeroExitOpt.cr_real_trade` | agree | 17991487937684668647 | 1621726511039027097 |  |
| `Fw.Parts.HeroExitOpt.cr_lane_mixed` | agree | 11394883144998271620 | 3015395163328828602 |  |
| `Fw.Parts.HeroExitOpt.wkAnim` | agree | 17507941298490766211 | 2394639320352283149 |  |
| `Fw.Parts.HeroExitOpt.wkAnims` | agree | 15090577973165646573 | 18420076771000723038 |  |
| `Fw.Parts.HeroExitOpt.wkAnims_length` | agree | 3626320323834416769 | 10740709498960904966 |  |
| `Fw.Parts.HeroExitOpt.wkAnims_mem` | agree | 3418349937279319626 | 2863776505633261046 |  |
| `Fw.Parts.HeroExitOpt.wk_anim_comp` | agree | 7404519553423234636 | 7002744016241376428 |  |
| `Fw.Parts.HeroExitOpt.wk_all_comp` | agree | 6904359217199339294 | 326893464276592621 |  |
| `Fw.Parts.HeroExitOpt.wk_legacy_main` | agree | 14077627565420756761 | 11264123378374087329 |  |
| `Fw.Parts.HeroExitOpt.wkAnimsFrame` | agree | 16034978456355811566 | 7447069096000156370 |  |
| `Fw.Parts.HeroExitOpt.wkVar` | agree | 8665224791586344345 | 17128493242688751450 |  |
| `Fw.Parts.HeroExitOpt.wkVar_eq` | agree | 15555574776523254425 | 9245203723017841500 |  |
| `Fw.Parts.HeroExitOpt.wk_var_exact` | agree | 1222884030036789398 | 1426246852349323927 |  |
| `Fw.Parts.HeroExitOpt.comp_not_diff` | agree | 4230247687222026051 | 3046922853160154453 |  |
| `Fw.Parts.HeroExitOpt.wk_trade` | agree | 14814718216383741584 | 7725086907723798357 |  |
| `Fw.Parts.HeroExitOpt.wkOrigChanges` | agree | 4952710957675238004 | 4404540318157279771 |  |
| `Fw.Parts.HeroExitOpt.GRow` | agree | 3931117990 | 9745310299418338764 |  |
| `Fw.Parts.HeroExitOpt.GRow.json` | agree | 7702898188069679708 | 3612458501933961372 |  |
| `Fw.Parts.HeroExitOpt.framePred` | agree | 346868352876978179 | 3212282904085274111 |  |
| `Fw.Parts.HeroExitOpt.zeroWork` | agree | 16780244879864052101 | 15086074913257007432 |  |
| `Fw.Parts.HeroExitOpt.scriptWork` | agree | 16780244879864052101 | 6322909336151540509 |  |
| `Fw.Parts.HeroExitOpt.gScenario` | agree | 3265150928 | 16184132674072895965 |  |
| `Fw.Parts.HeroExitOpt.gVariant` | agree | 3265150928 | 1801021612257942120 |  |
| `Fw.Parts.HeroExitOpt.gBand` | agree | 183048209 | 14264084565647640691 |  |
| `Fw.Parts.HeroExitOpt.gN` | agree | 421340980 | 10719946589578712454 |  |
| `Fw.Parts.HeroExitOpt.crFrames` | agree | 17842768775439924501 | 14639624277668816825 |  |
| `Fw.Parts.HeroExitOpt.wkFrames` | agree | 17842768775439924501 | 6606575704367697051 |  |
| `Fw.Parts.HeroExitOpt.crCounts` | agree | 1424393777815108805 | 700149284274599470 |  |
| `Fw.Parts.HeroExitOpt.goldenRows` | disagree | 3564223488100649134 | 18197832472375786569 | Rows are 6-field GRow ⟨engine, gScenario, gVariant, stageName s, pred, κ⟩; math writes 4-tuples (engine, s, κ, p), dropping scenario/variant and the stage name. Fix: (\texttt{chromium}, \mathrm{gScenario}, \mathrm{gVariant}, \operatorname{name}(s), p_{cr}(s), \kappa), same for webkit. |
| `Fw.Parts.HeroExitOpt.goldenJsonl` | agree | 3265150928 | 7158430777620829797 |  |
| `Fw.Parts.HeroExitOpt.gPred` | agree | 355955788 | 7732313577446517887 |  |
| `Fw.Parts.PainNotes.St` | agree | 2330190150 | 3046086656237104436 |  |
| `Fw.Parts.PainNotes.Ctx` | agree | 3931117990 | 17419512819594956904 |  |
| `Fw.Parts.PainNotes.maxExtras` | agree | 421340980 | 14657823784199221178 |  |
| `Fw.Parts.PainNotes.blocked` | agree | 10175890244424193191 | 15058954807794200933 |  |
| `Fw.Parts.PainNotes.tickO` | agree | 5307737279306789848 | 8726460191430660889 |  |
| `Fw.Parts.PainNotes.armed` | agree | 15155696184629336260 | 6603584007763230505 |  |
| `Fw.Parts.PainNotes.tickV` | agree | 5307737279306789848 | 17298682059887274279 |  |
| `Fw.Parts.PainNotes.clears` | agree | 15155696184629336260 | 14740332018679177981 |  |
| `Fw.Parts.PainNotes.tickO_idle` | agree | 1344909747688612560 | 10125963627177826569 |  |
| `Fw.Parts.PainNotes.tickV_eq` | agree | 5218568321699144973 | 55872233130069846 |  |
| `Fw.Parts.PainNotes.Ev` | agree | 2301245127 | 2665602195695780534 |  |
| `Fw.Parts.PainNotes.stepO` | agree | 16550510711117734137 | 6385024970231634279 |  |
| `Fw.Parts.PainNotes.stepV` | agree | 16550510711117734137 | 13004344141572979369 |  |
| `Fw.Parts.PainNotes.runO` | agree | 7294748665668496478 | 6753660847413826958 |  |
| `Fw.Parts.PainNotes.runV` | agree | 7294748665668496478 | 6080040352712070136 |  |
| `Fw.Parts.PainNotes.CovOk` | agree | 4205677791693075227 | 10740069403582529175 |  |
| `Fw.Parts.PainNotes.pain_run_eq` | agree | 4194724609606070153 | 3268889259615663686 |  |
| `Fw.Parts.PainNotes.pain_prefix_eq` | agree | 14724323078590448760 | 958629961983475538 |  |
| `Fw.Parts.PainNotes.pain_visSame` | agree | 8459622651513925567 | 3911661576311884235 |  |
| `Fw.Parts.PainNotes.ctxAt` | agree | 18342271427656193802 | 13153708532533631473 |  |
| `Fw.Parts.PainNotes.narrow_tick_id` | agree | 3770883409802901587 | 7948122857054017291 |  |
| `Fw.Parts.PainNotes.narrow_run_eq` | agree | 13611289147076816365 | 3694586224014409007 |  |
| `Fw.Parts.PainNotes.wide_armed_iff` | agree | 5390564626686095069 | 5126650082466473374 |  |
| `Fw.Parts.PainNotes.period` | agree | 421340980 | 4210933011689136788 |  |
| `Fw.Parts.PainNotes.tickAt` | agree | 9906956 | 12231457210014567297 |  |
| `Fw.Parts.PainNotes.resumeAt` | agree | 9906956 | 6619967882855043183 |  |
| `Fw.Parts.PainNotes.resumeAt_on_grid` | agree | 14811126801395485293 | 833118802936615615 |  |
| `Fw.Parts.PainNotes.resumeAt_ge` | agree | 7175844595852412435 | 11358749314871457474 |  |
| `Fw.Parts.PainNotes.resumeAt_least` | agree | 11901887925083937112 | 17541761767172137317 |  |
| `Fw.Parts.PainNotes.resume_grid` | agree | 14829219138236977396 | 7575207277505632399 |  |
| `Fw.Parts.PainNotes.ticksIn` | agree | 3512939730 | 13470388945668957622 |  |
| `Fw.Parts.PainNotes.naive_rearm_shifts` | agree | 16769568064881461486 | 4732209321904054208 |  |
| `Fw.Parts.PainNotes.withTick` | agree | 5157873258033269635 | 17743136804228186443 |  |
| `Fw.Parts.PainNotes.hiddenTick_le` | agree | 10514943336840378652 | 18347933749212419182 |  |
| `Fw.Parts.PainNotes.hiddenTick_lt` | agree | 12116994583647083993 | 13365283007984421747 |  |
| `Fw.Parts.PainNotes.frames_le` | agree | 11209337876620698454 | 8483796622925842178 |  |
| `Fw.Parts.PainNotes.idle` | agree | 18427575540590717088 | 7310907634223584195 |  |
| `Fw.Parts.PainNotes.idle_zero` | agree | 1309219927152511671 | 9152699466798898999 |  |
| `Fw.Parts.PainNotes.cr_idle_tick` | agree | 8347991719754263493 | 12700340200992545045 |  |
| `Fw.Parts.PainNotes.wk_idle_tick` | agree | 15351042104732608164 | 3471676048361727333 |  |
| `Fw.Parts.PainNotes.ticksPerMinute` | agree | 421340980 | 3330708272227278102 |  |
| `Fw.Parts.PainNotes.CountType` | agree | 3931117990 | 4131100289762928762 |  |
| `Fw.Parts.PainNotes.stageName` | agree | 13237354143774927416 | 5018164951693487975 |  |
| `Fw.Parts.PainNotes.relPred` | agree | 14144071420719870757 | 12992923333695048075 |  |
| `Fw.Parts.PainNotes.pairsOf` | agree | 11464295219850515988 | 12455712319751637939 |  |
| `Fw.Parts.PainNotes.crTypes` | disagree | 1505524162569433535 | 7101011325138976892 | Math gives only the length 8; body is a fixed list. Fix: [(FunctionCall,script,⊤),(UpdateLayoutTree,style,⊥),(Layout,layout,⊥),(Layout.dirtyObjects,layout,⊤),(metric.LayoutCount,layout,⊥),(PrePaint,props,⊥),(raster.invalidationAreaPx,paint,⊤),(cc.Commit,commit,⊥)], names trace.-prefixed except metric/raster. |
| `Fw.Parts.PainNotes.wkTypes` | disagree | 1505524162569433535 | 3569338099807407157 | Math gives only the length 4; body is a fixed list. Fix: \mathrm{wkTypes} = [(\texttt{RecalculateStyles}, \mathrm{style}, \bot), (\texttt{Layout}, \mathrm{layout}, \bot), (\texttt{Paint}, \mathrm{paint}, \bot), (\texttt{Composite}, \mathrm{commit}, \bot)] |
| `Fw.Parts.PainNotes.row` | agree | 13128411222146329442 | 6955091590247725856 |  |
| `Fw.Parts.PainNotes.goldenLines` | disagree | 4017531403 | 7039685568166329999 | Math gives only the length 20, not the rows. Fix: [row(chromium, sc, t, relPred(pairsOf(cr, css(transform)), t)) \| sc ∈ [swipe-v1, swipe-touch-v1], t ∈ crTypes] ++ [row(webkit, swipe-v1, t, relPred(pairsOf(wk, transform), t)) \| t ∈ wkTypes]. |
| `Fw.Parts.PainNotes.goldenText` | agree | 3265150928 | 14843777165650652409 |  |
| `Fw.Parts.PlatformMarquee.period` | agree | 1901972866 | 11729321481339729971 |  |
| `Fw.Parts.PlatformMarquee.phase` | agree | 3498294262 | 8430419393860710587 |  |
| `Fw.Parts.PlatformMarquee.offsetLeft` | agree | 4035929107 | 12448258381382971599 |  |
| `Fw.Parts.PlatformMarquee.offsetRight` | agree | 4035929107 | 759313713023121901 |  |
| `Fw.Parts.PlatformMarquee.phase_mem` | agree | 5409429103879050373 | 13024047991814292914 |  |
| `Fw.Parts.PlatformMarquee.phase_periodic` | agree | 765723695648080263 | 671345731044784735 |  |
| `Fw.Parts.PlatformMarquee.left_range` | disagree | 3942788959915404807 | 9654591785879353413 | Math says the strict -w/2 < x_L; Lean proves -(w/2) ≤ offsetLeft w t (the strict form fails at w = 0). Fix: w \ge 0 \Rightarrow -\tfrac w2 \le x_L(w, t) \le 0 |
| `Fw.Parts.PlatformMarquee.right_range` | agree | 10473259310748078418 | 9246716805725022247 |  |
| `Fw.Parts.PlatformMarquee.left_add_right` | agree | 368301224678754918 | 8506614090817129065 |  |
| `Fw.Parts.PlatformMarquee.seam` | agree | 1268359360 | 1643308968869457975 |  |
| `Fw.Parts.PlatformMarquee.speed` | agree | 3498294262 | 3933229615937401974 |  |
| `Fw.Parts.PlatformMarquee.speed_pass` | agree | 10850299146960758357 | 14713609154241291687 |  |
| `Fw.Parts.PlatformMarquee.running` | agree | 3551570259 | 1439272835894485116 |  |
| `Fw.Parts.PlatformSweep.period` | agree | 1901972866 | 2413981959156754520 |  |
| `Fw.Parts.PlatformSweep.frac` | agree | 3498294262 | 6984707424700846548 |  |
| `Fw.Parts.PlatformSweep.frac_mem` | agree | 2707941715319259442 | 3046078595970470668 |  |
| `Fw.Parts.PlatformSweep.frac_add_one` | agree | 9573144310377068331 | 451540632751538630 |  |
| `Fw.Parts.PlatformSweep.phase` | agree | 3498294262 | 7852026473785389758 |  |
| `Fw.Parts.PlatformSweep.phase_periodic` | agree | 17847892300399778118 | 15942526545436431358 |  |
| `Fw.Parts.PlatformSweep.pos` | disagree | 3498294262 | 12870583640542503257 | Minor: the body is only 1 - phase t; the added claim p(t) ∈ (0,1] is the theorem pos_mem, not part of the definition. Fix: p(t) = 1 - \varphi(t) |
| `Fw.Parts.PlatformSweep.pos_mem` | agree | 5573491890225525579 | 17322983444217188833 |  |
| `Fw.Parts.PlatformSweep.pos_zero` | agree | 7670988649059268628 | 13279335790096203697 |  |
| `Fw.Parts.PlatformSweep.pos_half` | agree | 123007796291806962 | 11795075113597537586 |  |
| `Fw.Parts.PlatformSweep.pos_periodic` | agree | 11258510708739104273 | 17304710306737030258 |  |
| `Fw.Parts.PlatformSweep.Rgb` | agree | 3931117990 | 9005501473672957700 |  |
| `Fw.Parts.PlatformSweep.white` | agree | 8250704365544455845 | 13559293650743741555 |  |
| `Fw.Parts.PlatformSweep.c1` | disagree | 8250704365544455845 | 8156505425564836936 | Math defines c_1..c_5 in hex, but c1's body is only (130,188,255); c2..c5 are separate defs. The prose also says 'six' stops where there are five. Fix: c_1 = \#82bcff = (130, 188, 255) |
| `Fw.Parts.PlatformSweep.c2` | agree | 8250704365544455845 | 12492731057983054215 |  |
| `Fw.Parts.PlatformSweep.c3` | agree | 8250704365544455845 | 11759954966606485700 |  |
| `Fw.Parts.PlatformSweep.c4` | agree | 8250704365544455845 | 15100240974064410263 |  |
| `Fw.Parts.PlatformSweep.c5` | agree | 8250704365544455845 | 399690376138796877 |  |
| `Fw.Parts.PlatformSweep.stops` | agree | 1704485823 | 5505834028152874759 |  |
| `Fw.Parts.PlatformSweep.mix` | agree | 7769520000765199062 | 12903859472237600810 |  |
| `Fw.Parts.PlatformSweep.seg` | agree | 16894770701460736518 | 942739756056643709 |  |
| `Fw.Parts.PlatformSweep.color` | agree | 17180898988950772432 | 17019505898574618962 |  |
| `Fw.Parts.PlatformSweep.imageU` | agree | 4035929107 | 15580741842091101778 |  |
| `Fw.Parts.PlatformSweep.shown` | agree | 6245959448555993749 | 5867234614933517078 |  |
| `Fw.Parts.PlatformSweep.end_nearly_white` | agree | 13616712457311847211 | 308956257444608924 |  |
| `Fw.Parts.PlatformSweep.start_nearly_white` | agree | 11273411328657201851 | 6284238663006903033 |  |
| `Fw.Parts.PlatformSweep.active` | agree | 3551570259 | 4308986889291262668 |  |
| `Fw.Plan.mk` | agree | 10837882321712380008 | 761795629769026237 |  |
