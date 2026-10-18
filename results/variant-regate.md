# variant-regate: per-variant, per-engine gate verdicts against a flags-off baseline of the same commit

Incident inc-variant-gate-flags-off (every variant gate before b27e187 ran the rewrite with flags off). Task variant-regate.
All runs are CI runs of workflow `breakpoint-gate` on commit c558cb4 (full matrix, all 15 parts, both engines, 8 shards per
engine plus sweeps). Engines: Chromium = Chrome Headless Shell 156 on Linux; WebKit = Playwright WebKit on Linux (a
WebKitGTK/WPE port, not Mobile Safari). Status: MEASURED (CI), one run per variant.

## Flags were applied (the regression check)

The harness now (a) records `header.flags = {search, configHash}` in every run file, where configHash is the page's own
`data-fw-config`, read by the browser from the loaded rewrite page, (b) fails the run when that is not the config the flags
name, and (c) prints `Flags: ...` as the first line of every engine's summary. Config hashes seen in the merged summaries:

| run | flags | config hash |
|---|---|---|
| 39071559515, 39073501564, 39073504068 (baselines) | none | 6bb2a28a0d5befeb |
| 39073354068 | morph.mount:shift | c6d18d1068d2cab8 |
| 39071508240 | morph.tween:waapi | 49dbab12c82b72b0 |
| 39071516742 | morph.columns:hidden-pause | e53bd2f9f3571d1f |
| 39071519154 | morph.countdown:hidden-pause | a88766a9586a48b7 |
| 39071562480 | engine.scene:hidden-pause | df37b41ec30125ff |

Run ids are GitHub Actions run ids. Each flagged run is on its own `ci/variant-regate-*` branch (same commit) because the
workflow cancels in-progress runs on the same ref. The baseline is three runs of the same commit (the first is the one in the
table; the other two give the run-to-run spread).

## Verdict

- Chromium: every part passes in the baseline and in all five flagged runs. Delta none for all variants.
- WebKit: three failures exist in the baseline itself (flags off), and they are the same failing items under every variant:
  - hero.countdown (item `face|will-change`), hero.exit (items `copy|will-change`, `copy|filter`, `copy|opacity`, `copy|transform`,
    `cue|filter`, `cue|opacity`, `hero|--exit-opacity`, `hero|--exit-scatter`): WebKit-only, in the base. The failing-probe
    counts vary from run to run even with identical flags (hero.countdown 35/36/38 in the three baselines, 32-37 in the five
    flagged runs; hero.exit 36/39/40 and 36-40), so a count difference between a baseline and a flagged run is noise, not a
    variant effect.
  - platform.stageBg (sweep `desktop-1512-320-1512`, 13/57 stops; items `stage|h`, `stage|height`, `grain|h`, `bg|h`,
    `bg|height`): identical in all 8 runs, so deterministic; it is the base's.
- morph.tween:waapi: its earlier flagged run 39067656223 showed WebKit failing hero.countdown, hero.exit and platform.stageBg.
  Settled: all three fail identically with flags off (baselines above) and under every other variant. They are the base's, not
  the variant's. morph.tween:waapi has no delta on any part, either engine.
- No variant changes any part's verdict, on either engine, against the baseline of the same commit: 0 of 150 rows differ.

## Limits

- The gate loads each page at the top of the document at fixed environments and compares settled computed style and boxes.
  The five variants change scroll-time or visibility-time behaviour (push shift, waapi tween, hidden-pause). A pass here means
  the variant leaves the load-time parity of every part intact; it does not measure the variant's runtime saving (that is the
  counts lanes).
- engine.scene has no visible output: its anchor only checks that the observed section (`.start-selling-platform` /
  `[data-fw="platform"]`) exists once in both arms (animation-* is skipped for every part by the style skipPrefixes). Its
  `hidden-pause` selector in App is the platform section (a stand-in for the original scene scheduler's scene; the original's
  100%-margin scheduler pause is not ported).
- morph.panel:rest: PENDING. `git log main --grep='Task: integrate-ports'` found nothing when checked (after the runs above).
- Harness flake seen once: run 39071505755 (morph.mount:shift, first try) failed in `merge (playwright-webkit)` because two shards'
  headers differed: `header.props["nav.hitTest"].nav.originOnly` listed `opacity` in shard 0 but not shard 2 (the reference
  load's declared-property list of the original's nav is timing-dependent on WebKit). The list is information only, never in a
  verdict. The run was repeated as 39073354068 (success). Not fixed here (merge-gate is outside this task's writes).

## Table

Verdict cell: pass, or FAIL (failing cells, failing probes summed over cells). Baseline = run 39071559515. Delta compares the
failing item set (role|key) and cell set; "base failure" = the same items fail with flags off.

| variant | engine | part | baseline | flagged | delta | baseline run | flagged run |
|---|---|---|---|---|---|---|---|
| morph.mount:shift | Chromium | engine.scroll | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | nav.hitTest | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | morph.mount | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | hero.countdown | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | morph.countdown | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | hero.exit | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | morph.columns | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | morph.tween | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | platform | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | platform.stageBg | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | platform.sweep | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | platform.glint | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | platform.entries | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | platform.marquee | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | Chromium | engine.scene | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | engine.scroll | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | nav.hitTest | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | morph.mount | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | hero.countdown | FAIL (8 cells, 36 probes) | FAIL (7 cells, 36 probes) | base failure: same failing items, cell set differs (probe timing); flagged 36 probes vs 3 baselines 36/38/35 (inside the baseline spread) | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | morph.countdown | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | hero.exit | FAIL (9 cells, 39 probes) | FAIL (8 cells, 40 probes) | base failure: same failing items, cell set differs (probe timing); flagged 40 probes vs 3 baselines 39/40/36 (inside the baseline spread) | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | morph.columns | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | morph.tween | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | platform | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | platform.stageBg | FAIL (1 cells, 13 probes) | FAIL (1 cells, 13 probes) | base failure: same failing items; flagged 13 probes vs 3 baselines 13/13/13 (inside the baseline spread) | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | platform.sweep | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | platform.glint | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | platform.entries | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | platform.marquee | pass | pass | none | 39071559515 | 39073354068 |
| morph.mount:shift | WebKit | engine.scene | pass | pass | none | 39071559515 | 39073354068 |
| morph.tween:waapi | Chromium | engine.scroll | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | nav.hitTest | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | morph.mount | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | hero.countdown | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | morph.countdown | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | hero.exit | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | morph.columns | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | morph.tween | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | platform | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | platform.stageBg | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | platform.sweep | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | platform.glint | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | platform.entries | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | platform.marquee | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | Chromium | engine.scene | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | engine.scroll | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | nav.hitTest | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | morph.mount | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | hero.countdown | FAIL (8 cells, 36 probes) | FAIL (8 cells, 34 probes) | base failure: same failing items; flagged 34 probes vs 3 baselines 36/38/35 (outside the 3 baselines, inside all 8 runs 32-38: run noise) | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | morph.countdown | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | hero.exit | FAIL (9 cells, 39 probes) | FAIL (9 cells, 38 probes) | base failure: same failing items; flagged 38 probes vs 3 baselines 39/40/36 (inside the baseline spread) | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | morph.columns | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | morph.tween | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | platform | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | platform.stageBg | FAIL (1 cells, 13 probes) | FAIL (1 cells, 13 probes) | base failure: same failing items; flagged 13 probes vs 3 baselines 13/13/13 (inside the baseline spread) | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | platform.sweep | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | platform.glint | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | platform.entries | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | platform.marquee | pass | pass | none | 39071559515 | 39071508240 |
| morph.tween:waapi | WebKit | engine.scene | pass | pass | none | 39071559515 | 39071508240 |
| morph.columns:hidden-pause | Chromium | engine.scroll | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | nav.hitTest | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | morph.mount | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | hero.countdown | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | morph.countdown | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | hero.exit | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | morph.columns | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | morph.tween | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | platform | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | platform.stageBg | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | platform.sweep | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | platform.glint | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | platform.entries | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | platform.marquee | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | Chromium | engine.scene | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | engine.scroll | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | nav.hitTest | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | morph.mount | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | hero.countdown | FAIL (8 cells, 36 probes) | FAIL (8 cells, 36 probes) | base failure: same failing items; flagged 36 probes vs 3 baselines 36/38/35 (inside the baseline spread) | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | morph.countdown | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | hero.exit | FAIL (9 cells, 39 probes) | FAIL (9 cells, 40 probes) | base failure: same failing items; flagged 40 probes vs 3 baselines 39/40/36 (inside the baseline spread) | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | morph.columns | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | morph.tween | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | platform | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | platform.stageBg | FAIL (1 cells, 13 probes) | FAIL (1 cells, 13 probes) | base failure: same failing items; flagged 13 probes vs 3 baselines 13/13/13 (inside the baseline spread) | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | platform.sweep | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | platform.glint | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | platform.entries | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | platform.marquee | pass | pass | none | 39071559515 | 39071516742 |
| morph.columns:hidden-pause | WebKit | engine.scene | pass | pass | none | 39071559515 | 39071516742 |
| morph.countdown:hidden-pause | Chromium | engine.scroll | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | nav.hitTest | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | morph.mount | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | hero.countdown | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | morph.countdown | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | hero.exit | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | morph.columns | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | morph.tween | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | platform | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | platform.stageBg | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | platform.sweep | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | platform.glint | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | platform.entries | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | platform.marquee | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | Chromium | engine.scene | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | engine.scroll | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | nav.hitTest | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | morph.mount | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | hero.countdown | FAIL (8 cells, 36 probes) | FAIL (8 cells, 37 probes) | base failure: same failing items; flagged 37 probes vs 3 baselines 36/38/35 (inside the baseline spread) | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | morph.countdown | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | hero.exit | FAIL (9 cells, 39 probes) | FAIL (9 cells, 39 probes) | base failure: same failing items; flagged 39 probes vs 3 baselines 39/40/36 (inside the baseline spread) | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | morph.columns | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | morph.tween | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | platform | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | platform.stageBg | FAIL (1 cells, 13 probes) | FAIL (1 cells, 13 probes) | base failure: same failing items; flagged 13 probes vs 3 baselines 13/13/13 (inside the baseline spread) | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | platform.sweep | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | platform.glint | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | platform.entries | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | platform.marquee | pass | pass | none | 39071559515 | 39071519154 |
| morph.countdown:hidden-pause | WebKit | engine.scene | pass | pass | none | 39071559515 | 39071519154 |
| engine.scene:hidden-pause | Chromium | engine.scroll | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | nav.hitTest | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | morph.mount | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | hero.countdown | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | morph.countdown | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | hero.exit | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | morph.columns | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | morph.tween | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | platform | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | platform.stageBg | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | platform.sweep | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | platform.glint | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | platform.entries | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | platform.marquee | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | Chromium | engine.scene | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | engine.scroll | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | nav.hitTest | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | morph.mount | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | hero.countdown | FAIL (8 cells, 36 probes) | FAIL (8 cells, 32 probes) | base failure: same failing items; flagged 32 probes vs 3 baselines 36/38/35 (outside the 3 baselines, inside all 8 runs 32-38: run noise) | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | morph.countdown | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | hero.exit | FAIL (9 cells, 39 probes) | FAIL (9 cells, 36 probes) | base failure: same failing items; flagged 36 probes vs 3 baselines 39/40/36 (inside the baseline spread) | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | morph.columns | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | morph.tween | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | platform | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | platform.stageBg | FAIL (1 cells, 13 probes) | FAIL (1 cells, 13 probes) | base failure: same failing items; flagged 13 probes vs 3 baselines 13/13/13 (inside the baseline spread) | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | platform.sweep | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | platform.glint | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | platform.entries | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | platform.marquee | pass | pass | none | 39071559515 | 39071562480 |
| engine.scene:hidden-pause | WebKit | engine.scene | pass | pass | none | 39071559515 | 39071562480 |
