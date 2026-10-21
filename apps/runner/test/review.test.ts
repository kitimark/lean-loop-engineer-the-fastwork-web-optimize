import { describe, expect, it } from "vitest";
import { UsageError } from "../src/lib.ts";
import { renderFeedback, reviewCommand } from "../src/review.ts";

describe("fw review reply (the lead answers a comment)", () => {
  it("is the review.feedback.reply command, lead by default, with a key derived from the comment id", () => {
    expect(reviewCommand(["reply", "--flag", "nav:a", "--to", "fb-1", "--text", "done"], {})).toEqual({
      type: "review.feedback.reply", key: "review-feedback-reply:fb-1", actor: "lead", flag: "nav:a", to: "fb-1", text: "done" });
  });
  it("takes the actor from FW_ACTOR or --as (the capability door stamps the real one)", () => {
    expect(reviewCommand(["reply", "--flag", "nav:a", "--to", "fb-1", "--text", "x"], { FW_ACTOR: "user" })).toMatchObject({ actor: "user" });
    expect(reviewCommand(["reply", "--flag", "nav:a", "--to", "fb-1", "--text", "x", "--as", "lead"], { FW_ACTOR: "user" })).toMatchObject({ actor: "lead" });
  });
  it("refuses a missing part or another verb", () => {
    expect(() => reviewCommand(["reply", "--flag", "nav:a", "--text", "x"], {})).toThrow(UsageError);
    expect(() => reviewCommand(["reply", "--to", "fb-1", "--text", "x"], {})).toThrow(UsageError);
    expect(() => reviewCommand(["reply", "--flag", "nav:a", "--to", "fb-1"], {})).toThrow(UsageError);
    expect(() => reviewCommand(["nope"], {})).toThrow(UsageError);
  });
});

describe("fw review feedback (print the threads)", () => {
  const t = [{ flag: "nav:a", comments: [
    { id: "fb-1", text: "one", at: 0, status: "answered", reply: { text: "ok", at: 1000 } },
    { id: "fb-2", text: "two\nlines", at: 2000, status: "open", reply: null }] }];
  it("prints the open comments only, and all of them with --all", () => {
    const open = renderFeedback(t, false);
    expect(open).toContain("fb-2");
    expect(open).not.toContain("fb-1");
    const all = renderFeedback(t, true);
    expect(all).toContain("fb-1");
    expect(all).toContain("reply (1970-01-01T00:00:01.000Z): ok");
  });
  it("says so when nothing is open", () => { expect(renderFeedback([], false)).toBe("no open feedback"); });
});
