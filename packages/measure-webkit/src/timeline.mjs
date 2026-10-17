// Timeline capture over the raw protocol (I/O only; reduction lives in reduce.mjs).
//
// Order matters (CONFIRMED in source, InspectorPageAgent::enable starts the stopwatch; P16 in v1): `Page.enable`
// must be sent BEFORE `Timeline.start`, or every record time is 0. `maxCallStackDepth: 1` is the cheapest stack.
// Only the `Timeline` instrument is enabled (never Screenshot, never paint flashing: they change what is measured).
// A page-side `performance.mark(name)` arrives as a `TimeStamp` record {data: {message: name}} on the same clock,
// and is how steps are joined to records.
import { sleep } from './sim.mjs';
import { flattenRecords } from './reduce.mjs';

/** Start recording on a connected tab. `stop()` returns the raw rows (reduce.mjs schema `fw.webkit.records/1`). */
export async function startTimeline(c) {
  const protocolRecords = [];
  let stopped = false;
  const off = c.on((m) => {
    if (m.method === 'Timeline.eventRecorded') protocolRecords.push(m.params.record);
    else if (m.method === 'Timeline.recordingStopped') stopped = true;
  });
  await c.enable('Page');
  await c.enable('Timeline');
  await c.send('Timeline.setInstruments', { instruments: ['Timeline'] });
  await c.send('Timeline.start', { maxCallStackDepth: 1 });
  return {
    async stop() {
      await c.send('Timeline.stop');
      for (let i = 0; i < 100 && !stopped; i++) await sleep(50);
      await sleep(200); // late eventRecorded messages
      off();
      return flattenRecords(protocolRecords);
    },
  };
}
