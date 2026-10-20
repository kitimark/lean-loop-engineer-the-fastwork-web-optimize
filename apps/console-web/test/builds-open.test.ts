import { describe, expect, it } from "vitest";
import { RECENT_KEY, RECENT_MAX, addRecent, readRecent } from "../src/buildsOpen";

/** Recent searches are browser-local glue: newest first, no duplicates, capped, and a broken store reads as empty. */
const fake = (init?: string) => {
  const m = new Map<string, string>(init === undefined ? [] : [[RECENT_KEY, init]]);
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v) };
};

describe("recent searches (localStorage only)", () => {
  it("newest first, no duplicates, capped", () => {
    const s = fake();
    addRecent("?a=1", s); addRecent("?b=1", s); addRecent("?a=1", s);
    expect(readRecent(s)).toEqual(["?a=1", "?b=1"]);
    for (let i = 0; i < 20; i++) addRecent(`?p=${i}`, s);
    expect(readRecent(s).length).toBe(RECENT_MAX);
    expect(readRecent(s)[0]).toBe("?p=19");
  });
  it("a broken or foreign value reads as empty", () => {
    expect(readRecent(fake("not json"))).toEqual([]);
    expect(readRecent(fake('{"a":1}'))).toEqual([]);
    expect(readRecent(fake('["?ok",3,null]'))).toEqual(["?ok"]);
  });
});
