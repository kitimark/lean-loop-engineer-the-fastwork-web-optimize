// Git reconciler: turns git refs into typed facts (actor `git`). It decides nothing:
// the reducer (Lean) accepts, refuses or marks a violation; keys make every fact idempotent.
import { createHash } from "node:crypto";
import { syncCommands, syncFrom, type Command, type WorkGraph } from "@fw/contracts";
import type { Store } from "../store.ts";
import { branches, commitsAhead, fileAt, isAncestor, onMainSet, trailerFacts } from "./git.ts";
import { branchCard } from "./naming.ts";
import { fin, init, req, ticket, type Sched } from "./coalesce.ts";

/** The plan sync content digest, the same as `fw plan sync`'s (apps/runner/src/plan.ts), so both send the same keys. */
const sha10 = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex").slice(0, 10);

export type ReconcileStats ={ submitted: number; duplicate: number; refused: number; skipped: number };

export class Reconciler {
  /** keys already answered in this process; a fresh Reconciler replays and the reducer dedups by key */
  private done = new Set<string>();
  private timer: NodeJS.Timeout | null = null;
  private sched: Sched = init;
  /** the answer of each pass not yet finished, by pass index (Lean `ticket`) */
  private waiting = new Map<number, { promise: Promise<ReconcileStats>; resolve: (s: ReconcileStats) => void; reject: (e: unknown) => void }>();

  private store: Store;
  private repo: string;
  private mainRef: string;
  private graphPath: string;
  /** main's head at the last plan sync (null: none yet in this process, so the first pass syncs; all duplicates) */
  private synced: string | null = null;

  constructor(store: Store, repo: string, mainRef = "main", graphPath = "docs/team/work-graph.json") {
    this.store = store; this.repo = repo; this.mainRef = mainRef; this.graphPath = graphPath;
  }

  get repoDir() { return this.repo; }

  /** Coalesced (Lean `Fw.Console.ReconcileSched`): one pass runs and at most one waits; a request is answered by a pass
   *  that starts after it. */
  reconcile(): Promise<ReconcileStats> {
    const k = ticket(this.sched);
    let w = this.waiting.get(k);
    if (!w) {
      let resolve!: (s: ReconcileStats) => void, reject!: (e: unknown) => void;
      const promise = new Promise<ReconcileStats>((a, b) => { resolve = a; reject = b; });
      w = { promise, resolve, reject };
      this.waiting.set(k, w);
    }
    const before = this.sched.started;
    this.sched = req(this.sched);
    if (this.sched.started > before) this.launch();
    return w.promise;
  }

  private launch() {
    const k = this.sched.started - 1;
    const w = this.waiting.get(k)!;
    this.pass().then(w.resolve, w.reject).finally(() => {
      this.waiting.delete(k);
      const before = this.sched.started;
      this.sched = fin(this.sched);
      if (this.sched.started > before) this.launch();
    });
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
    // 0. main moved -> plan sync from the work graph committed at main's head (never a worktree's copy), before the
    //    task.done facts below so a newly defined task can be finished in the same pass. Which commit (or skip):
    //    Lean `Fw.Plan.syncFrom` (sync_only_main, sync_skip_same); TS stand-in checked against golden/plan/sync.jsonl.
    //    Unchanged defines carry the same keys, so a re-sync is all duplicates (Lean `step_define_idem`).
    const at = syncFrom(this.mainRef, refs.map((r) => [r.ref, r.sha] as const), this.synced);
    if (at) {
      this.synced = at; // a broken file is reported once per commit, not on every poll
      const text = fileAt(this.repo, at, this.graphPath);
      if (text !== null) {
        let cmds: Command[] = [];
        // the ancestry fact of each evidence sha against main (Lean refuses a define whose commit is off main)
        const onMain = onMainSet(this.repo, this.mainRef);
        try { cmds = syncCommands(JSON.parse(text) as WorkGraph, "script", sha10, undefined, onMain); }
        catch (e) { console.error(`plan sync at ${at.slice(0, 7)}: ${(e as Error).message}`); }
        for (const c of cmds) await this.send(c, s);
      }
    }
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
      for (const t of await trailerFacts(this.store.core, this.repo, this.mainRef, board.plan.tasks)) {
        await this.send({ type: "task.done", key: `taskdone:${t.task}`, actor: "git", task: t.task, evidence: t.evidence }, s);
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
