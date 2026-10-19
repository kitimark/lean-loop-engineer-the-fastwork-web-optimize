import { test } from 'node:test';
import assert from 'node:assert/strict';
import { overflowExpr, formatOverflow } from '../src/overflow.mjs';

test('formatOverflow lists escaping elements first with part and selector', () => {
  const t = formatOverflow({ vw: 430, total: 2, shown: [
    { sel: 'div.a', part: 'people.deck', right: 443, left: 10, width: 433, pos: 'static', clipped: false },
    { sel: 'span.b', part: null, right: 500, left: 400, width: 100, pos: 'absolute', clipped: true },
  ] });
  assert.match(t, /2 elements end right of the client width 430/);
  assert.match(t, /ESCAPES {2}right 443 .* part people\.deck div\.a/);
  assert.match(t, /clipped {2}right 500 .* part - span\.b/);
});

test('formatOverflow without a listing says so; the page expression is syntactically valid', () => {
  assert.equal(formatOverflow(null), 'overflow: no listing');
  assert.doesNotThrow(() => new Function(`return ${overflowExpr(5)}`));
});
