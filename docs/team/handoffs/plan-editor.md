# Handoff: plan-editor

State at c04c8ef (plan rev 5 with review fixes). Read this, then only the PLAN sections your delta touches.

- `docs/plan/PLAN.md` is rev 5, about 1,445 lines. There is no hard line limit; clarity first.
- Every change gets a row in Appendix D (the review log). The last row is 16.
- §10 is a dependency graph: workstreams in §10.1 with blocked-by and outputs, a Mermaid graph, and gates M0–M6 in
  §10.2. Never use days or dates. Never hand-write "running"; landed items show their commit.
- Frontmatter `status` enum (§7.2): draft | review | accepted | superseded. Cited notes go in `links.notes`.
- Claims carry CONFIRMED / INFERRED / MEASURED. The 1/70 false-better rate is a planned M0 bound,
  ≤ 1/C(8,4) with equality iff no ties (L1-cond), not proved yet.
- Lean first (§3.3): code reaches Lean by running in fwcore, by being generated, or by passing golden vectors (level L2).
- `docs/plan/rev5-delta.md` is accepted and partly superseded; don't edit it further.
- Edit only PLAN.md unless told otherwise. Don't commit (the lead commits). Report ≤300 chars.
