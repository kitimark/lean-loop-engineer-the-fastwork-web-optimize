# plan-evidence-link handoff
- Plan.tsx `Evidence` fetches GET /api/repo once (module-cached promise) and links `${commit}${sha}`; null/failed -> plain short sha.
- Assumes `commit` is a URL prefix ending where the sha goes (per fw-land-log handoff). Not browser-tested; build passes.
