import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { CiCard, type CiView } from "../src/Health";

const base: CiView = {
  readAt: 1_000_000, now: 1_060_000, fresh: true, error: null, url: "https://status.circleci.com",
  states: { docker: "operational", machine: "operational", pipelines: "operational", api: "operational", macos: "degraded_performance" },
  arm: { verdict: "healthy", usable: true }, macos: { verdict: "degraded", usable: false },
  incidents: [{ name: "Increased wait times for macOS jobs", status: "monitoring", impact: "minor", createdAt: 900_000, updatedAt: 950_000, components: ["macOS Jobs"] }],
};

describe("CircleCI card (rendering of the Lean verdict)", () => {
  it("shows both lane verdicts, the router input, the components and the open incident", () => {
    const html = renderToStaticMarkup(<CiCard ci={base} />);
    expect(html).toContain("Linux Arm healthy, usable");
    expect(html).toContain("macOS degraded");
    expect(html).not.toContain("macOS degraded, usable");
    expect(html).toContain("Docker Jobs");
    expect(html).toContain("Increased wait times for macOS jobs");
    expect(html).toContain("status.circleci.com");
  });
  it("says stale and the failure when the reading is old", () => {
    const html = renderToStaticMarkup(<CiCard ci={{ ...base, fresh: false, error: "HTTP 429", incidents: [], arm: { verdict: "unknown", usable: false } }} />);
    expect(html).toContain("(stale)");
    expect(html).toContain("HTTP 429");
    expect(html).toContain("No open incident");
  });
  it("before the first read", () => {
    expect(renderToStaticMarkup(<CiCard ci={{ ...base, readAt: null, fresh: false }} />)).toContain("Not read yet.");
  });
});
