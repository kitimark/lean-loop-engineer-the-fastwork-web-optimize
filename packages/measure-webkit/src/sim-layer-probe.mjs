// RenderLayerCompositor.cpp:3842-3860@862f17d sets the `animation` reason also for an effect stack that merely affects transform
export async function layerProbe(c) {
  try {
    await c.enable('Page').catch(() => {});
    await c.enable('DOM').catch(() => {});
    await c.enable('LayerTree');
    const doc = (await c.send('DOM.getDocument', { depth: 0 })).root.nodeId;
    const found = await c.send('DOM.querySelectorAll', { nodeId: doc, selector: '[class*="layerBg"]' });
    const nodes = found.nodeIds ?? [];
    let layers = 0;
    let animation = 0;
    let willChange = 0;
    let noRenderer = 0;
    let noReasons = 0;
    for (const nodeId of nodes) {
      const own = await c.send('LayerTree.layersForNode', { nodeId }).catch(() => null);
      if (own === null) { noRenderer++; continue; }
      for (const l of own.layers ?? []) {
        const got = await c.send('LayerTree.reasonsForCompositingLayer', { layerId: l.layerId }).catch(() => null);
        if (got === null) { noReasons++; continue; }
        layers++;
        const r = got.compositingReasons ?? {};
        if (r.animation) animation++;
        if (r.willChange) willChange++;
      }
    }
    return { nodes: nodes.length, noRenderer, noReasons, layers, animation, willChange };
  } catch (e) {
    return { error: String(e.message ?? e).slice(0, 160) };
  } finally {
    await c.disable('LayerTree').catch(() => {});
    await c.disable('DOM').catch(() => {});
  }
}
