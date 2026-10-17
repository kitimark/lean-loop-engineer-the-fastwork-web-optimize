# Handoff: meas-webkit (WebKit counts lane, iOS Simulator)

State at 1d6c88c (written by the lead from meas-webkit's report). Read packages/measure-webkit/README.md first: commands,
protocol facts and full class tables.

- Mobile Safari on `fw-iphone-27` (iOS 27.0) over the raw Web Inspector protocol via ios_webkit_debug_proxy. Ports
  9341/9342. Attached physical phones are written to the proxy config with port -1, so a real phone is never attached.
  Every command boots headless and shuts the Simulator down (`--keep` leaves it booted).
- Bootstrap script (clock pinned, seeded Math.random, native rAF): works only on the connection that then calls
  `Page.reload`.
- Determinism over 4 passes: `Composite` and `EventDispatch` are deterministic at every grain. Most other totals are
  stable (about 1–3 %). Per-zone and per-step counts are mostly quarantined, because the scroll is wall-clock-driven
  and the original runs rAF all the time (about 105 per 3 s idle). Layer census is deterministic at y ≥ 3000.
- `RenderingFrame` records are absent on iOS 27.0 over this proxy, so `Composite` stands in for rendering updates.
- Seek fixture: seeking N accelerated animations costs 122 style records + paint growing with N; free-running costs 0.
- Pure TS: `src/reduce.mjs` needs a Lean spec + goldens. 15 unit tests run without the Simulator.
- Open: per-step determinism (no virtual time in WebKit); run the lane on the rewrite's pilot configs; WKTR/internals
  path (needs a WebKit build) not tried.
