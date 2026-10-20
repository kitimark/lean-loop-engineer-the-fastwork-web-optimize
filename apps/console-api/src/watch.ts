// fs.watch glue: one watcher per wanted path. A watcher only says "something changed here", never what, so the sweep
// behind it looks at everything (FSEvents coalesces events and can drop names).
import { existsSync, watch, type FSWatcher } from "node:fs";

export type Target = { path: string; recursive: boolean; accept: (name: string) => boolean; discover?: boolean };

export class Watches {
  private open = new Map<string, FSWatcher>();
  private targets: () => Target[];
  private onEvent: (t: Target) => void;

  /** `targets` is asked again by every `sync` (new session dirs appear over time); `onEvent` runs for an accepted name. */
  constructor(targets: () => Target[], onEvent: (t: Target) => void) { this.targets = targets; this.onEvent = onEvent; }

  /** Open a watcher for each wanted path that has none; close those no longer wanted. A missing path is retried next sync.
   *  Returns how many watchers it opened (a closed one that is replaced counts: the size alone would hide it). */
  sync(): number {
    let opened = 0;
    const want = new Map(this.targets().map((t) => [t.path, t] as const));
    for (const [p, w] of this.open) if (!want.has(p)) { w.close(); this.open.delete(p); }
    for (const [p, t] of want) {
      if (this.open.has(p)) continue;
      // Node 24.21.0 on Linux does not throw for a recursive watch of a missing path (lib/internal/fs/recursive_watch.js:236-241: the
      // ENOENT is swallowed unless throwIfNoEntry is false), it returns a watcher that never fires; 24.14.0 and 24.22.0 throw. A
      // watcher counted as open would never be retried, so a missing path is skipped here, on every Node.
      if (!existsSync(p)) continue;
      try {
        const w = watch(p, { recursive: t.recursive, persistent: false }, (_ev, name) => {
          if (name === null || t.accept(String(name).split("/").pop()!)) this.onEvent(t);
        });
        w.on("error", () => { w.close(); if (this.open.get(p) === w) this.open.delete(p); });
        this.open.set(p, w);
        opened++;
      } catch { /* the path does not exist yet */ }
    }
    return opened;
  }

  get size(): number { return this.open.size; }

  close(): void { for (const w of this.open.values()) w.close(); this.open.clear(); }
}
