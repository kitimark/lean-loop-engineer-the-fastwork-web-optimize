# css-apply handoff
State: Q34 = c and Q35 = a applied (user, 2026-10-18).
- `apps/site/src/theme.ts`: `cssVariables: false`, `colorSchemes` removed, `themeVariablesCss` serialiser deleted.
- `Root.tsx`: `disableStyleSheetGeneration` / `defaultMode` props removed. `entry-server.tsx` and `scripts/build.mjs`: `themeCss` removed.
- No `var(--mui` reader existed; no dead-CSS sheet or flag exists in `apps/site`. No Lean rule or constant encodes S8, so nothing was regenerated.
- PLAN S8, Q34 and Q35 text updated to the decisions.
- Checks: typecheck, 688 vitest tests, `pnpm build` (aot gates) pass.
- Open: the N4 root-custom-property count was not measured here (CI census). The runtime-engine build was not run.
