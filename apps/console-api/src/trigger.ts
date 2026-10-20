// Event-driven sweeps with a safety tick. TS STAND-IN of Lean `Fw.Console.ReconcileSched` (answered_after_*, wait_le_two,
// dropped_event_drained): a poke is answered by a pass that starts after it, and the safety tick is a poke that never depends
// on a file event (events can be coalesced or dropped, so every sweep looks at everything).
import { fin, init, req, type Sched } from "./reconcile/coalesce.ts";

export type TriggerOpts = {
  /** one full sweep */
  run: () => Promise<unknown>;
  /** a request every `safetyMs` whether or not an event came */
  safetyMs: number;
  /** pokes within `settleMs` of the first share one request (default 50) */
  settleMs?: number;
  onError?: (e: unknown) => void;
};

export class Trigger {
  private sched: Sched = init;
  private settle: NodeJS.Timeout | null = null;
  private tick: NodeJS.Timeout | null = null;
  private opts: TriggerOpts;
  /** passes started and pokes received (local debug counters) */
  passes = 0;
  pokes = 0;

  constructor(opts: TriggerOpts) { this.opts = opts; }

  /** An event happened: request a pass after the settle window. */
  poke(): void {
    this.pokes++;
    if (this.settle) return;
    this.settle = setTimeout(() => { this.settle = null; this.request(); }, this.opts.settleMs ?? 50);
    this.settle.unref();
  }

  /** Request a pass now (Lean `req`). */
  request(): void {
    const before = this.sched.started;
    this.sched = req(this.sched);
    if (this.sched.started > before) this.launch();
  }

  private launch(): void {
    this.passes++;
    this.opts.run().catch((e) => this.opts.onError?.(e)).finally(() => {
      const before = this.sched.started;
      this.sched = fin(this.sched);
      if (this.sched.started > before) this.launch();
    });
  }

  /** Start the safety tick. */
  start(): void {
    this.tick = setInterval(() => this.request(), this.opts.safetyMs);
    this.tick.unref();
  }

  stop(): void {
    if (this.tick) clearInterval(this.tick);
    if (this.settle) clearTimeout(this.settle);
    this.tick = this.settle = null;
  }
}
