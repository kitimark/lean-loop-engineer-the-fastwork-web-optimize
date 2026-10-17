// Identity -> actor: apps/runner/hooks/cap.mjs `identity` and apps/console-api/src/cap/cap.ts `actorFor` against fwcore `ops.actor`
// (Fw.Ops.Identity). Fields are absent, null, strings of near-"review" shapes (ASCII case folding, non-ASCII look-alikes, empty)
// or non-strings (a refusal, whose message must match).
import { test, before, after } from 'node:test';
import fc from 'fast-check';
import { FwCore } from '../src/fwcore.mjs';
import { differential } from '../src/diff.mjs';
import { identity } from '../../../apps/runner/hooks/cap.mjs';
import { actorFor } from '../../../apps/console-api/src/cap/cap.ts';

let core;
before(() => { core = new FwCore(); });
after(() => core.close());

const unit = fc.constantFrom(...'reviewREVIEW-_x'.split(''), 'K', 'İ', 'ſ', ' ', 'é');
const str = fc.oneof(
  fc.constantFrom('', 'main', 'reviewer', 'Math-REVIEWER', 'revie-w', 'lean-prover', 'review', 'REVIEW'),
  fc.string({ unit, maxLength: 12 }));
const field = fc.oneof({ weight: 5, arbitrary: str }, { weight: 2, arbitrary: fc.constant(null) }, { weight: 1, arbitrary: fc.constant(undefined) },
  { weight: 1, arbitrary: fc.oneof(fc.integer(), fc.boolean()) });
const arb = fc.record({ agent_id: field, agent_type: field }, { requiredKeys: [] });

test('ops.actor vs hooks/cap.mjs identity', () => differential(core, {
  op: 'ops.actor', arb, compareErrors: true, minAccepted: 0.3,
  ts: ({ agent_id, agent_type }) => {
    const r = identity(agent_id, agent_type);
    return r.error ? { error: r.error } : { actor: r.actor, role: r.role, who: r.who };
  },
}));

test('ops.actor vs cap.ts actorFor (string/null fields)', () => differential(core, {
  op: 'ops.actor',
  arb: fc.record({ agent_id: fc.oneof(str, fc.constant(null), fc.constant(undefined)), agent_type: fc.oneof(str, fc.constant(null), fc.constant(undefined)) }, { requiredKeys: [] }),
  ts: ({ agent_id, agent_type }) => ({ actor: actorFor(agent_id, agent_type) }),
  project: (r) => ({ actor: r.actor }),
}));
