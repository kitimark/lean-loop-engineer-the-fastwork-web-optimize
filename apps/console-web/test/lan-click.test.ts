// The LAN page is plain http, so the browser gives it no secure-context APIs; a click there threw before sending
// (crypto.randomUUID undefined) and the error was swallowed. Incident inc-lan-click-silent.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { clickError, sendAsUser } from "../src/lib/api";

afterEach(() => vi.unstubAllGlobals());

/** Only `getRandomValues` survives outside a secure context (https, localhost). */
const insecureCrypto = () => {
  const c = globalThis.crypto;
  return { getRandomValues: c.getRandomValues.bind(c) };
};

describe("a click on the plain-http LAN page", () => {
  it("sends step.start with a fresh key when crypto.randomUUID is missing", async () => {
    vi.stubGlobal("crypto", insecureCrypto());
    const sent: Record<string, unknown>[] = [];
    vi.stubGlobal("fetch", async (_u: string, init: RequestInit) => {
      sent.push(JSON.parse(String(init.body)));
      return new Response(JSON.stringify({ ok: true, seq: 1, duplicate: false }), { headers: { "content-type": "application/json" } });
    });
    expect(await clickError(() => sendAsUser({ type: "step.start", step: "ask-x" }))).toBeNull();
    await sendAsUser({ type: "step.start", step: "ask-x" });
    expect(sent).toHaveLength(2);
    expect(sent[0]).toMatchObject({ type: "step.start", step: "ask-x", actor: "user" });
    expect(String(sent[0]!.key)).toMatch(/^web:[0-9a-f]{32}$/);
    expect(sent[0]!.key).not.toBe(sent[1]!.key);
  });
  it("shows why a click was not sent, and the refusal of one that was", async () => {
    expect(await clickError(async () => { throw new TypeError("crypto.randomUUID is not a function"); }))
      .toBe("Not sent: crypto.randomUUID is not a function");
    vi.stubGlobal("fetch", async () => { throw new TypeError("Failed to fetch"); });
    expect(await clickError(() => sendAsUser({ type: "step.start", step: "ask-x" }))).toBe("Not sent: Failed to fetch");
    expect(await clickError(async () => ({ ok: false, reason: "step is started, not waiting" })))
      .toBe("Refused: step is started, not waiting");
  });
});

/** APIs a browser offers only in a secure context (MDN "Features restricted to secure contexts"). The console is also
 *  served over plain http on the LAN, so its source uses one only on a line that checks `isSecureContext` (with a
 *  fallback, like `copyText`). */
const SECURE_ONLY = [/\brandomUUID\b/, /\bcrypto\.subtle\b/, /\bnavigator\.clipboard\b/, /\bserviceWorker\b/, /\bnavigator\.share\b/,
  /\bnavigator\.credentials\b/, /\bnavigator\.storage\b/, /\bgetUserMedia\b/, /\bNotification\b/, /\bPaymentRequest\b/,
  /\bnavigator\.wakeLock\b/, /\bnavigator\.usb\b/, /\bnavigator\.bluetooth\b/, /\bnavigator\.geolocation\b/];

const files = (d: string): string[] => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? files(p) : /\.(ts|tsx)$/.test(f) ? [p] : [];
});

describe("console-web source", () => {
  it("uses a secure-context-only browser API only behind an isSecureContext check (comments excluded)", () => {
    const src = join(import.meta.dirname, "..", "src");
    const hits = files(src).flatMap((f) => readFileSync(f, "utf8").split("\n").flatMap((l, i) => {
      const code = l.replace(/\/\/.*$/, "").replace(/^\s*(\/\*\*|\*).*$/, "").replace(/\/\*.*?\*\//g, "");
      if (code.includes("isSecureContext")) return [];
      return SECURE_ONLY.filter((re) => re.test(code)).map((re) => `${f.slice(src.length + 1)}:${i + 1} ${re}`);
    }));
    expect(hits).toEqual([]);
  });
});
