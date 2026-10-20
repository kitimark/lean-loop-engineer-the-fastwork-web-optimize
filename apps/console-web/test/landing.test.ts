// The Builds-tab landing after a login whose preview has stopped (Lean console.loginReturn, `next` = /?tab=builds&note=stopped).
import { describe, expect, it } from "vitest";
import { landingOf } from "../src/App";

describe("landingOf", () => {
  it("the stopped-preview landing opens the Builds tab with the note", () => {
    expect(landingOf("?tab=builds&note=stopped")).toEqual({ tab: "builds", note: "That preview has stopped; press Open." });
  });
  it("anything else is the console tab without a note", () => {
    expect(landingOf("")).toEqual({ tab: "console", note: null });
    expect(landingOf("?tab=builds&note=x")).toEqual({ tab: "builds", note: null });
    expect(landingOf("?tab=plan")).toEqual({ tab: "console", note: null });
  });
});
