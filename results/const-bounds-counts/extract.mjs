// Copies the per-step series and the census out of webkit-sim session files into cells.json, the input of
// Fw.Parts.ConstBoundsCounts (no decision is made here).
//   node extract.mjs <out.json> baseRun=<id> flagRun=<id> sha=<sha> flag=<part:variant> \
//        base=<vm>:<session.json> ... arm=<vm>:<session.json> ... \
//        crBaseRun=<id> crFlagRun=<id> crSha=<sha> crbase=<run>:<counts.json> ... crarm=<run>:<counts.json> ...
// A session file holds `passes[]`; each pass has scroll.ys, scroll.reduced.{countTypes,perStep,perStepPaintArea}
// and census[]. Every number must be an integer, else the script stops.
import fs from 'node:fs'

const METRICS = ['Layout', 'RecalculateStyles', 'Paint', 'Composite', 'FunctionCall', 'EventDispatch', 'paintArea']
const [out, ...specs] = process.argv.slice(2)
const meta = {}
const sides = { base: [], arm: [], crbase: [], crarm: [] }
for (const s of specs) {
  const [k, v] = [s.slice(0, s.indexOf('=')), s.slice(s.indexOf('=') + 1)]
  if (k in sides) sides[k].push(v)
  else meta[k] = v
}
const int = (x, what) => {
  if (!Number.isInteger(x)) throw new Error(`${what}: ${x} is not an integer`)
  return x
}
const passesOf = (list) =>
  list.flatMap((spec) => {
    const [vm, file] = [Number(spec.slice(0, spec.indexOf(':'))), spec.slice(spec.indexOf(':') + 1)]
    const j = JSON.parse(fs.readFileSync(file, 'utf8'))
    return j.passes.map((p, i) => {
      const r = p.scroll.reduced
      const steps = {}
      for (const m of METRICS) {
        steps[m] = m === 'paintArea' ? r.perStepPaintArea.map((v) => int(v, m)) : r.perStep.map((row) => int(row[r.countTypes.indexOf(m)], m))
      }
      return {
        vm,
        pass: i + 1,
        ys: p.scroll.ys.map((v) => int(v, 'y')),
        steps,
        census: p.census.map((c) => ({ y: int(c.requestedY, 'census y'), layers: int(c.layerCount, 'layers'), mem: int(c.memoryBytes, 'mem') })),
      }
    })
  })
// A Chromium counts file holds frames[]: scrollY and counts{type: n} per 60 Hz frame; a run plays the part of a VM.
const CR = [
  'trace.Layout', 'metric.LayoutCount', 'trace.Layout.dirtyObjects', 'trace.InvalidateLayout', 'trace.UpdateLayoutTree',
  'metric.RecalcStyleCount', 'trace.Paint', 'trace.PrePaint', 'trace.cc.Commit', 'trace.FunctionCall', 'trace.EventDispatch',
  'raster.invalidationAreaPx', 'census.layers', 'census.drawingAreaPx',
]
const framesOf = (list) =>
  list.map((spec) => {
    const [run, file] = [Number(spec.slice(0, spec.indexOf(':'))), spec.slice(spec.indexOf(':') + 1)]
    const j = JSON.parse(fs.readFileSync(file, 'utf8'))
    const steps = {}
    for (const m of CR) steps[m] = j.frames.map((f) => int(f.counts[m] ?? 0, m))
    return { vm: run, pass: 1, ys: j.frames.map((f) => int(f.scrollY, 'scrollY')), steps, census: [] }
  })
const cells = { ...meta, base: passesOf(sides.base), arm: passesOf(sides.arm), crBase: framesOf(sides.crbase), crArm: framesOf(sides.crarm) }
fs.writeFileSync(out, JSON.stringify(cells) + '\n')
console.log(`${out}: base ${cells.base.length} passes, arm ${cells.arm.length} passes, chromium ${cells.crBase.length}/${cells.crArm.length} runs`)
