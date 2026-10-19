// The listeners of the arm origins (task preview-proxy-direct): for each serving preview one HTTP server per arm on the arm's
// public port, on loopback and, in LAN mode, on the LAN address too (the same two bindings as the preview port). Which ports
// exist comes from Lean (`Entry.rp`/`op`, pairwise distinct: `ports_distinct`); every listener answers with the one arm app
// (arm-app.ts), which reads the arm from the local port. A bind that fails (the port is taken) fails the preview start:
// the OS refuses a second listener on a port, so an arm port can never be the console's or another preview's.
// Only I/O: no decisions.
import { serve } from "@hono/node-server";
import type { Entry } from "./manager.ts";

type Srv = { close(cb?: () => void): unknown; on(ev: "error", f: (e: Error) => void): unknown };

export class ArmServers {
  private byId = new Map<string, Srv[]>();
  private readonly fetch: (r: Request, e?: unknown) => unknown;
  private readonly lanAddr: string | null;

  constructor(fetch: (r: Request, e?: unknown) => unknown, lanAddr: string | null) { this.fetch = fetch; this.lanAddr = lanAddr; }

  private listen(port: number, hostname: string): Promise<Srv> {
    return new Promise((resolve, reject) => {
      const srv = serve({ fetch: this.fetch as never, port, hostname }, () => resolve(srv as unknown as Srv));
      (srv as unknown as Srv).on("error", reject);
    });
  }

  /** Listen on both arm ports of a preview; all or nothing. */
  async open(e: Pick<Entry, "id" | "rp" | "op">): Promise<void> {
    const got: Srv[] = [];
    try {
      for (const port of [e.rp, e.op]) {
        got.push(await this.listen(port, "127.0.0.1"));
        if (this.lanAddr) got.push(await this.listen(port, this.lanAddr));
      }
    } catch (err) {
      for (const s of got) s.close();
      throw new Error(`arm ports ${e.rp}/${e.op} could not be bound: ${(err as Error).message}`);
    }
    this.byId.set(e.id, got);
  }

  /** Stop listening for a preview (no-op for an unknown id). */
  close(id: string): void {
    for (const s of this.byId.get(id) ?? []) s.close();
    this.byId.delete(id);
  }

  get open_ids(): string[] { return [...this.byId.keys()]; }
}
