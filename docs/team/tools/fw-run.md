# fw run: dispatching measurement lanes

`pnpm -s fw run ...` dispatches a CI measurement workflow with its inputs, waits on the shared poller, and (count lanes)
files the artifacts in `.fw-console/store/`. A `ci/*` push carries no workflow inputs and `gh workflow run` is refused in
the agent sandbox, so this is the agent's way to run a lane with a preset, flags, a target or an engine choice.
Every decision (jobs, inputs, blocked) is Lean's (`store.plan`, `store.gate`; `lean/Fw/Store/Layout.lean`).

## Lanes and inputs

| lane | workflow | `fw run` | inputs sent | blocked |
|---|---|---|---|---|
| chromium counts | chromium-counts.yml | `--engines chromium` | profile, runs, target, preset, fw | never |
| webkit sim | webkit-sim.yml | `--engines webkit` | vms (= `--runs`), target, preset, fw | `--profile` other than `swipe-v1` (no profile input); `--runs` above 3 is a problem (vms is 1 to 3) |
| breakpoint gate | breakpoint-gate.yml | `--gate` | engines, preset, fw | never (`parts`, `runs`, `free`, `times` keep defaults) |

The Lean table `Fw.Store.Lane.inputs` equals the `workflow_dispatch` inputs of the three files; the check.sh stage
"lane inputs check" (`lean/scripts/LaneInputs.lean`) fails when a workflow gains or loses an input without the table.
A job is blocked iff a needed input is missing from its lane's table (`blocked_eq_none_iff`, `gateBlocked_eq_none_iff`).

## Flags

- `--target original|rewrite` (required for count lanes; the original takes no preset or flags), `--preset`, `--fw a:x,b:y`
  (repeat or commas), `--engines chromium,webkit` (gate: one of `both|chromium|playwright-webkit`; preset and fw are exclusive).
- `--ref <branch>`: dispatch on that pushed branch and measure it at its own commit (`origin/<branch>`, else the local
  branch); the store key and the headSha check use that sha. Without `--ref` the current branch and HEAD are used.
  `--sha` overrides the sha; `--from-run engine=<id>` (gate: `gate=<id>`) takes an existing run instead of dispatching.
- `--dry` prints the plan (inputs, cache hit or miss, BLOCKED) and makes no gh call. Exit 0 ok, 2 refused (problems or blocked).
- The branch must be pushed first (`git branch -f ci/<name> HEAD`, then `git push origin ci/<name>`).

## Recipes

Counts on both profiles x3, candidate rewrite against base rewrite. Push the candidate as `ci/cand` and the base as `ci/base`, then:

    for p in swipe-v1 swipe-wheel-v1; do
      pnpm -s fw run --target rewrite --engines chromium --profile $p --runs 3 --ref ci/base
      pnpm -s fw run --target rewrite  --engines chromium --profile $p --runs 3 --ref ci/cand --preset <preset>
    done

(`--runs 3` is also the default; a repeated key is a cache hit and is not dispatched again. The run count is part of
the key since key version 3, so a 2-run and a 3-run request never share a stored run, and no key from before version 3,
when every WebKit dispatch ran 1 VM, is a hit.) Add `--fw part:variant` instead
of `--preset` for single flags.

Gate for a flag: `pnpm -s fw run --gate --engines both --fw morph.tween:waapi --ref ci/cand`. It prints
`gate: run <id> succeeded`; read the tables with `gh run download <id>` (the gate files nothing in the store).

Webkit-sim on both refs (default profile only; `--runs` 2 or 3 is the VM count, default 3, `sessions` stays 1 per VM):

    pnpm -s fw run --target rewrite  --engines webkit --ref ci/base
    pnpm -s fw run --target rewrite  --engines webkit --ref ci/cand --fw part:variant

Always try `--dry` first. Allow rule the user adds: `Bash(pnpm fw run *)` (the lead hands over the `!` command).
