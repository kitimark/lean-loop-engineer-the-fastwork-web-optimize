// The owner token lives in localStorage and travels in the Authorization header only (console-lan-owner r3).
import { afterEach, describe, expect, it, vi } from "vitest";
import { adoptHashToken, apiFetch, clearToken, getToken, setToken, TOKEN_KEY } from "../src/lib/auth";

const mem = () => {
  const m = new Map<string, string>();
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) };
};
afterEach(() => vi.unstubAllGlobals());

describe("owner token", () => {
  it("is sent as a bearer header and never as a cookie; no token, no header", async () => {
    vi.stubGlobal("localStorage", mem());
    const seen: Headers[] = [];
    vi.stubGlobal("fetch", async (_u: string, init: RequestInit) => { seen.push(new Headers(init.headers)); return new Response("{}"); });
    await apiFetch("/api/x");
    setToken("t".repeat(43));
    await apiFetch("/api/x", { method: "POST", headers: { "content-type": "application/json" } });
    expect(seen[0]!.get("authorization")).toBeNull();
    expect(seen[1]!.get("authorization")).toBe(`Bearer ${"t".repeat(43)}`);
    expect(seen[1]!.get("content-type")).toBe("application/json");
    expect(seen[1]!.get("cookie")).toBeNull();
    clearToken();
    expect(getToken()).toBeNull();
  });
  it("the owner link fragment is adopted and removed from the address bar; anything else is ignored", () => {
    vi.stubGlobal("localStorage", mem());
    const replaced: string[] = [];
    vi.stubGlobal("window", { history: { replaceState: (_a: unknown, _b: string, u: string) => replaced.push(u) } });
    const tok = "a".repeat(43);
    expect(adoptHashToken({ hash: `#owner=${tok}`, pathname: "/", search: "" })).toBe(true);
    expect(localStorage.getItem(TOKEN_KEY)).toBe(tok);
    expect(replaced).toEqual(["/"]);
    expect(adoptHashToken({ hash: "#owner=short", pathname: "/", search: "" })).toBe(false);
    expect(adoptHashToken({ hash: "#other=" + tok, pathname: "/", search: "" })).toBe(false);
  });
});
