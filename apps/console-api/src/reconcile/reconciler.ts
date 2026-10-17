// Git reconciler: turns git refs into typed facts (actor `git`). It decides nothing:
// the reducer (Lean) accepts, refuses or marks a violation; keys make every fact idempotent.
import type { Command } from "@fw/contracts";
import type { Store } from "../store.ts";
import { branches, commitsAhead, isAncestor, taskTrailers } from "./git.ts";
import { branchCard } from "./naming.ts";

export type ReconcileStats = { submitted: number; duplicate: number; refused: number; skipped: number };

export class Reconciler {
  /** keys already answered in this process; a fresh Reconciler replays and the reducer dedups by key */
  private done = new Set<string>();
  private timer: NodeJS.Timeout | null = null;
  private last: Promise<unknown> = Promise.resolve();

  private store: Store;
  private repo: string;
  private mainRef: string;

  constructor(store: Store, repo: string, mainRef = "main") {
    this.store = store; this.repo = repo; this.mainRef = mainRef;
  }

  get repoDir() { return this.repo; }

  /** Serialized: passes never overlap. */
  reconcile(): Promise<ReconcileStats> {
    const next = this.last.catch(() => undefined).then(() => this.pass());
    this.last = next;
    return next;
  }

  private async send(cmd: Command, s: ReconcileStats) {
    if (this.done.has(cmd.key)) { s.skipped++; return; }
    const r = await this.store.submit(cmd);
    this.done.add(cmd.key); // a refusal is logged once in refused.jsonl, not on every poll
    if (!r.ok) s.refused++;
    else if (r.duplicate) s.duplicate++;
    else s.submitted++;
  }

  private async pass(): Promise<ReconcileStats> {
    const s: ReconcileStats = { submitted: 0, duplicate: 0, refused: 0, skipped: 0 };
    const refs = branches(this.repo);
    if (!refs.some((r) => r.ref === this.mainRef)) return s;
    // card facts come from the Lean board projection (console.query); there is no TS copy of the state
    const open = new Map((await this.store.board()).cards.map((c) => [c.id, c.owner]));
    // 1. new commits on card branches -> card.build (oldest first, so the last one is the head)
    for (const r of refs) {
      const bc = branchCard(r.ref);
      if (!bc) continue;
      const owner = open.get(bc.card);
      if (owner === undefined) continue; // glue: card not opened yet; retried on the next pass (not memoized)
      for (const sha of commitsAhead(this.repo, this.mainRef, r.ref)) {
        await this.send({ type: "card.build", key: `build:${r.ref}:${sha}`, actor: "git", card: bc.card, sha, agent: bc.agent ?? owner }, s);
      }
    }
    // 2. main advanced over a card's head -> card.landed (the reducer marks a violation if no request preceded it)
    for (const c of (await this.store.board()).cards) { // re-read: step 1 moved heads
      if (c.landed || !c.head || !isAncestor(this.repo, c.head, this.mainRef)) continue;
      await this.send({ type: "card.landed", key: `landed:${this.mainRef}:${c.head}`, actor: "git", card: c.id, sha: c.head }, s);
    }
    // 3. work graph: a landed card whose id (or whose branch's agent) equals an undone task id -> task.done(evidence = head)
    const board = await this.store.board();
    const undone = new Set(board.plan.tasks.filter((t) => t.state !== "done").map((t) => t.id));
    if (undone.size > 0) {
      // 3a. explicit: a `Task: <id>` trailer on a main commit (merge done with plain git or by `fw land --task`); oldest first
      for (const t of taskTrailers(this.repo, this.mainRef).reverse()) {
        if (undone.has(t.task)) await this.send({ type: "task.done", key: `taskdone:${t.task}`, actor: "git", task: t.task, evidence: t.sha }, s);
      }
      // 3b. inferred: card id or branch agent
      for (const c of board.cards) {
        if (!c.landed || !c.head) continue;
        const names = new Set([c.id]);
        for (const r of refs) { const bc = branchCard(r.ref); if (bc?.card === c.id && bc.agent) names.add(bc.agent); }
        for (const n of names) {
          if (undone.has(n)) await this.send({ type: "task.done", key: `taskdone:${n}`, actor: "git", task: n, evidence: c.head }, s);
        }
      }
    }
    return s;
  }

  start(everyMs = 2000) {
    this.timer = setInterval(() => { this.reconcile().catch((e) => console.error("reconcile:", e.message)); }, everyMs);
    this.timer.unref();
  }
  stop() { if (this.timer) clearInterval(this.timer); }
}
