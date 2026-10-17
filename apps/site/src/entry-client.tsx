import { createRoot, hydrateRoot } from 'react-dom/client';
import { App } from './App';
import { createClientCache } from './emotion';
import { ErrorPage } from './ErrorPage';
import { installFw } from './fw';
import { resolveSearch } from './registry';
import { Root } from './Root';
import './styles/reset.css';

const rootEl = document.getElementById('root')!;
const ids: string[] = JSON.parse(document.getElementById('fw-emotion-ids')?.textContent ?? '[]');

// Flags resolve once, at load (PLAN 6.3), never per frame.
const resolved = resolveSearch(location.search);

if (!resolved.ok) {
  installFw({ config: { variants: {}, impl: {} }, configHash: 'error', mode: 'client-render' });
  window.__fw.hydrationErrors.push(...resolved.errors);
  window.__fw.hydrated = true;
  createRoot(rootEl).render(<ErrorPage errors={resolved.errors} />);
} else {
  // The static HTML was prerendered for one config. Same hash: hydrate. Different: render on the client
  // (hydrating other markup would mismatch). `mode` is recorded so a run can refuse client-render builds.
  const same = rootEl.dataset.fwConfig === resolved.configHash;
  const fw = installFw({
    config: resolved.config,
    configHash: resolved.configHash,
    mode: same ? 'hydrate' : 'client-render',
  });
  const cache = createClientCache(__FW_ENGINE__, ids);
  const tree = (
    
      <Root cache={cache}>
        <App config={resolved.config} />
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
