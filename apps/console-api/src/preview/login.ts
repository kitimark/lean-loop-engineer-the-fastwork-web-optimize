// Owner login: the passphrase from the macOS keychain, the per-address rate limit, the login page.
// The decision "may this attempt be tried, and what follows" is Lean `console.ownerLogin` (`Fw.Console.Preview.Owner.attempt`,
// proved `no_unbounded_tries` per address, `global_bound` across all addresses, `locked_refuses`, `ok_only_if`). This file
// keeps the per-address records and the one global record Lean returns, does the
// constant-time compare (I/O primitive) and reads the keychain. The passphrase is held in memory only: never logged, never
// printed, never stored in a file or event, never part of an error message.
import { createHash, timingSafeEqual } from "node:crypto";
import { execFileSync } from "node:child_process";
import type { Core } from "../core/index.ts";

export const KEYCHAIN_SERVICE = "fw-console-owner";
/** The command the user runs once (prompts for the passphrase without echo). */
export const KEYCHAIN_HINT = `security add-generic-password -U -a "$USER" -s ${KEYCHAIN_SERVICE} -w`;

export type RunSecurity = () => string;
const defaultRun: RunSecurity = () =>
  execFileSync("security", ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 5000 });

/** The owner passphrase from the keychain, or null when there is no item (or the keychain cannot be read). Nothing about
 *  the failure is kept: an error could carry the tool's output. */
export function readPassphrase(run: RunSecurity = defaultRun): string | null {
  try {
    const out = run().replace(/\r?\n$/, "");
    return out.length > 0 ? out : null;
  } catch { return null; }
}

/** Constant-time equality of two strings of any length (both are hashed to 32 bytes first). */
export function sameSecret(a: string, b: string): boolean {
  const ha = createHash("sha256").update(a).digest();
  const hb = createHash("sha256").update(b).digest();
  return timingSafeEqual(ha, hb);
}

type Rec = { fails: number[]; lockUntil: number };
export type Outcome = { verdict: "ok" | "wrong" | "locked" | "disabled"; retryAt: number | null };

export class LoginGuard {
  private recs = new Map<string, Rec>();
  private glob: Rec = { fails: [], lockUntil: 0 }; // the global record: failures across all addresses
  private chain: Promise<unknown> = Promise.resolve();
  private window = 600_000; private lock = 600_000; // overwritten by every Lean reply
  private core: Core; private passphrase: string | null; private clock: () => number; private cap: number;
  constructor(core: Core, passphrase: string | null, clock: () => number = Date.now, cap = 1024) {
    this.core = core; this.passphrase = passphrase; this.clock = clock; this.cap = cap;
  }

  get enabled(): boolean { return this.passphrase !== null; }

  /** One attempt from a client address. Attempts run one at a time: parallel requests cannot share one record. */
  attempt(addr: string, presented: string): Promise<Outcome> {
    const run = () => this.one(addr, presented);
    const p = this.chain.then(run, run);
    this.chain = p.catch(() => undefined);
    return p;
  }

  private async one(addr: string, presented: string): Promise<Outcome> {
    const now = this.clock();
    let rec = this.recs.get(addr);
    if (!rec && this.recs.size >= this.cap) {
      for (const [k, r] of this.recs) if (r.lockUntil <= now && r.fails.every((t) => t + this.window <= now)) this.recs.delete(k);
      if (this.recs.size >= this.cap) return { verdict: "locked", retryAt: now + this.lock }; // full of live records: fail closed
    }
    rec = rec ?? { fails: [], lockUntil: 0 };
    const correct = this.passphrase !== null && sameSecret(presented, this.passphrase); // always computed: timing does not show the lock
    const r = await this.core.ops("console.ownerLogin", { enabled: this.enabled, correct, now, fails: rec.fails, lockUntil: rec.lockUntil, gFails: this.glob.fails, gLockUntil: this.glob.lockUntil });
    this.glob = { fails: (r.gFails as number[]) ?? [], lockUntil: Number(r.gLockUntil) };
    this.window = Number(r.window); this.lock = Number(r.lock);
    const next: Rec = { fails: (r.fails as number[]) ?? [], lockUntil: Number(r.lockUntil) };
    if (r.verdict === "ok" || (next.fails.length === 0 && next.lockUntil === 0)) this.recs.delete(addr);
    else this.recs.set(addr, next);
    return { verdict: r.verdict as Outcome["verdict"], retryAt: (r.retryAt as number | null) ?? null };
  }
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** The localStorage key of the owner token (console origin only; the web reads it for the Authorization header). */
export const TOKEN_KEY = "fw_owner_token";

const loginScript = `const f=document.querySelector("form"),m=document.getElementById("m");f.addEventListener("submit",async(e)=>{e.preventDefault();m.textContent="";try{const r=await fetch("/owner/login",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({passphrase:f.passphrase.value})});const j=await r.json().catch(()=>({}));f.passphrase.value="";if(r.ok&&j.token){localStorage.setItem("${TOKEN_KEY}",j.token);location.replace("/");return}m.textContent=j.reason||"login failed"}catch{m.textContent="login failed: no answer"}})`;

/** The login page: self-contained (inline style and one inline script, no other asset), so the LAN gate has nothing else to
 *  open. The script posts the passphrase as JSON, keeps the returned owner token in localStorage of this origin and goes to
 *  the console. Without script nothing can log in (the token must reach localStorage). */
export function loginPage(o: { enabled: boolean; message?: string }): string {
  const body = o.enabled
    ? `<form method="post" action="/owner/login" onsubmit="return false"><label>Owner passphrase<br><input type="password" name="passphrase" autocomplete="current-password" autofocus required></label><button type="submit">Log in</button></form><p class="m" id="m" role="alert"></p><script>${loginScript}</script>`
    : `<p>Owner login is disabled: this console found no owner passphrase in the keychain.</p><p>On the console's Mac, run once (it prompts for the passphrase, no echo):</p><pre>${esc(KEYCHAIN_HINT)}</pre><p>Then restart the console.</p>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>fw console login</title><style>body{font:16px system-ui;margin:2rem auto;max-width:24rem;padding:0 1rem}input,button{font:inherit;padding:.5rem;margin-top:.5rem}input{width:100%;box-sizing:border-box}pre{background:#eee;padding:.5rem;overflow:auto}.m{color:#a00}</style></head><body><h1>fw console</h1>${o.message ? `<p class="m" role="alert">${esc(o.message)}</p>` : ""}${body}</body></html>`;
}
