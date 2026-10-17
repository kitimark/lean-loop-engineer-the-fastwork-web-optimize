# Handoff: spk-records (W1-D, SPK decision-record drafts)

State: drafts written, nothing committed. Evidence read up to HEAD `30e3264`. Reading only: no measurements, builds
or installs were run. Every cited sha resolves (`git cat-file -e`); no home paths, emails or device ids in the drafts.

Read first: `research/notes/2026/10-17-spk-drafts/README.md` (table of 13 spikes, blockers, findings).

Files (all untracked, under `research/notes/2026/10-17-spk-drafts/`): `README.md`, `class-policy.md` (DRAFT),
`spk-{a,b,c,d,e,i,j,k,l,o,p,q,t}.md`. They are drafts: the lead moves them to `research/decisions/` and sets
`status: signed` on signing.

Counts: 4 answered (a, b, e, k), 8 partial (c, d, i, j, l, o, p, t), 1 open (q).

Conventions followed: each record has question, answer, status, evidence table (file:line@commit or note path, marked
CONFIRMED / MEASURED / INFERRED), evidence commit, missing, next step with owner role, "What this changes in the plan".

Open items for the lead:
- Sign or change `class-policy.md` (Chromium kMax 4, tMax 24, min 3 runs; WebKit tolerance table). The tMax tighten-to-4
  option is unverified; check with `node src/classify.mjs <3 runs> --tMax 4`.
- SPK-i: "two byte-identical vectors" is not met (14 stable, 8 quarantined types); the V-i re-scope in `spk-i.md` needs
  a decision.
- SPK-l: `lean_hammer_premise` is remote and missing from `--disable-tools` in `.mcp.json`.
- SPK-c / SPK-t: `cap.mjs:47` maps a missing `agent_type` to `main` (the lead); decide after the SPK-c hook payload is seen.
- SPK-q is listed in both the M0 and M1 rows of PLAN §10.2; decide which.
- SPK-t, SPK-c, SPK-p, SPK-o all wait on one planned `.claude/settings.json` sitting (sandbox + hooks) and on `fw gate`.

Owners of the non-answered spikes: console-builder (c, d, o, p, t), lead (c, d, i, l, t), measure-engineer (i, j, q),
env-ops (l), lean-prover (k, e follow-ups).

Not read: the uncommitted worktree changes of `meas-chromium-2` (not evidence until committed).
