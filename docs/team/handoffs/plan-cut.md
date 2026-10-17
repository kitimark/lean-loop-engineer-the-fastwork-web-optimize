# Handoff: plan-cut (PLAN revision 8, length cut)

**State.** Committed on `worktree-agent-a8d5e82657e31108b` with the trailer `Task: plan-cut` (parent 6109ec0).
PLAN.md: 1,698 → 1,537 lines. Plan state is unchanged at 7d564e2; only the length changed.

**What moved** (verbatim, to `research/notes/2026/10-17-plan-evidence.md`, cited as `[EV §n]`):
- history: the intro history and §0 "Since revision 6/7" (EV §1); the rev 7 and 7.1 item tables (EV §12);
- evidence: §2.1/§2.2 v1 columns (EV §2); §4.1/§4.2 CI figures, harness flags, all findings, WKTR (EV §3);
  §5.1 built modules (EV §4); §5.3 review rounds and the long example (EV §5); §6.5 S7 and census (EV §6);
  §6.6 matrix, gate status, unreachable cells (EV §7); §8.1/§8.2 wording and the §8.5 v1 tails (EV §8);
- lists: the §10.1 workstream table (EV §9; live tasks are in `docs/team/work-graph.json`), the §10.2
  contradiction paragraph (EV §10), the answered spikes and full SPK-r/SPK-t details (EV §11).

**Conventions.**
- `[EV]` is a citation key, defined in the plan intro like `[CU]`; it is not a label prefix.
- The note copies the rev 7.1 (cdcb907) lines unchanged, demoting only the headings, and names each source range.
- Explainer: only the meta label, the footer and one `#findings` pointer changed. The math view was not touched.

**Self-check** (MEASURED, a regex over plan + note):
- 100 of 100 commit hashes found (68 still in the plan); 96 of 96 Q/R/A ids found (all in the plan);
- 88 of 88 other labels (SPK, PL, N, S, V, M, K, G, L) are in the plan;
- 84 of 84 backticked task ids are in the plan or the note.

**Open.** The ~1,300-line target is missed by about 237 lines. The rest is design content (§0, architecture,
method, gates, roster, settings, App A, risks, Qs). Cutting further means moving whole design sections (e.g. the
§7.1 tree, §8.3) into their own documents; that is a lead or user call (App D, revision 8, "Which way the plan goes").

**Read first.** PLAN App D "Revision 8", then the note's intro paragraph.
