import { createRoot, hydrateRoot } from 'react-dom/client';
import { App } from './App';
import { installRootEventsDebug, rootEventsDebugOn } from './debug/root-events';
import { createClientCache } from './emotion';
import { ErrorPage } from './ErrorPage';
import { installFw } from './fw';
import { QUIET_VARIANT, quietContainer } from './parts/engine.events/quiet';
import { resolveSearch } from './registry';
import { installLayerStyle } from './registry/layer-opts';
import { parseOnly } from './registry/only';
import { Root } from './Root';
import { PartStage, pinEnv } from './stage';
import './styles/reset.css';

const rootEl = document.getElementById('root')!;
const ids: string[] = JSON.parse(document.getElementById('fw-emotion-ids')?.textContent ?? '[]');

// Flags resolve once, at load (PLAN 6.3), never per frame.
const resolved = resolveSearch(location.search);
const only = parseOnly(location.search);

if (!resolved.ok || only.kind === 'err') {
  const errors = !resolved.ok ? resolved.errors : [`stage: ${only.kind === 'err' ? only.code : ''}`];
  installFw({ config: { variants: {}, impl: {} }, configHash: 'error', mode: 'client-render' });
  window.__fw.hydrationErrors.push(...errors);
  window.__fw.hydrated = true;
  createRoot(rootEl).render(<ErrorPage errors={errors} />);
} else {
  installLayerStyle(document, resolved.layerOpts);
  // The static HTML was prerendered for one config. Same hash: hydrate. Different: render on the client
  // (hydrating other markup would mismatch). `mode` is recorded so a run can refuse client-render builds.
  // A stage page (`?only=`) is never hydrated: the static shell is the home page, so it renders on the client.
  const same = only.kind === 'none' && rootEl.dataset.fwConfig === resolved.configHash;
  const fw = installFw({
    config: resolved.config,
    configHash: resolved.configHash,
    mode: same ? 'hydrate' : 'client-render',
  });
  // The stage environment is pinned before the first render, so mount-time reads (layout effects of children) see it.
  const pinned = only.kind === 'ok' ? pinEnv(window, only.stage.env) : null;
  // Before the root exists: React registers its listeners on the container when it is created.
  if (rootEventsDebugOn(location.search)) installRootEventsDebug({ proto: EventTarget.prototype, win: window, store: window as unknown as Record<string, unknown> });
  if (resolved.config.variants['engine.events'] === QUIET_VARIANT) quietContainer(rootEl);
  const cache = createClientCache(__FW_ENGINE__, ids);
  const tree = (
    
      <Root cache={cache}>
        {only.kind === 'ok' ? <PartStage stage={only.stage} config={resolved.config} pinned={pinned!} /> : <App config={resolved.config} />}
      </Root>
    
  );
  if (same) {
    hydrateRoot(rootEl, tree, {
      onRecoverableError: (e) => fw.hydrationErrors.push(String((e as Error)?.message ?? e)),
    });
  } else {
    createRoot(rootEl).render(tree);
  }
}
