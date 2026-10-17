// 100k synthetic console events (post, start, note, answer per step): node gen-events.mjs > events100k.jsonl
const L = []; let e = 0;
for (let k = 0; k < 25000; k++) {
  L.push({ eid: ++e, body: { post: { step: k } } }); L.push({ eid: ++e, body: { start: { step: k } } });
  L.push({ eid: ++e, body: { note: { row: 'r' + k, text: 'x' } } }); L.push({ eid: ++e, body: { answer: { step: k, text: 'ok' } } });
}
console.log(L.map((x) => JSON.stringify(x)).join('\n'));
