import { useEffect, useRef, useState } from 'react';
import { Hero } from './parts/hero';
import { EngineScroll } from './parts/engine.scroll';
import { MorphTween } from './parts/morph.tween';
import { nobounceProps } from './parts/morph.end.nobounce';
import { MorphCountdown } from './parts/morph.countdown';
import { NavHitTest } from './parts/nav.hitTest';
import { Nav } from './parts/nav';
import { MorphMount } from './parts/morph.mount';
import { dormant, isDormantVariant } from './parts/morph.mount/logic';
import { MorphColumns } from './parts/morph.columns';
import { EngineScene } from './parts/engine.scene';
import { People } from './parts/people';
import { Pain } from './parts/pain';
import { Commission } from './parts/commission';
import { Platform } from './parts/platform';
import { FADE_THREADED } from './parts/platform/fade.logic';
import { MorphPanel, type PanelWriter } from './parts/morph.panel';
import { OverlayDrawer, openDrawer } from './parts/overlays.drawer';
import { OverlaySignup, openSignup } from './parts/overlays.signup';
import type { FwConfig } from './registry/types';
import { setHydrated } from './fw';

/** Hero "Join list" and the commission "why" link are other parts' buttons; the page opens the overlays from them (click delegation, discrete). */
const OPEN_SIGNUP = '[data-fw="hero"] button, [data-selenium="start-selling.people.button.message"]';
const OPEN_DRAWER = '[data-selenium="start-selling.commission.button.why"]';

/** Placeholder home page. Overlays are mounted closed (no keepMounted: they portal in on open, like the real ones). */
export function App({ config }: { config: FwConfig }) {
  const [panel, setPanel] = useState(false); // morph.mount: the panel's DOM insertion (once, never unmounted)
  const [woken, setWoken] = useState(false);
  const mountVariant = config.variants['morph.mount'] ?? 'faithful';
  const asleep = isDormantVariant(mountVariant) && dormant(panel, woken);
  const writerRef = useRef<PanelWriter | null>(null); // the nav hands each --morph value to the panel's attribute writer

  useEffect(() => setHydrated(), []); // root effects run after hydration has committed

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const t = e.target instanceof Element ? e.target : null;
      if (t?.closest(OPEN_SIGNUP)) openSignup();
      else if (t?.closest(OPEN_DRAWER)) openDrawer();
    };
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, []);

  return (
    <>
      <EngineScroll variant={config.variants['engine.scroll'] ?? 'faithful'} />
      <NavHitTest variant={config.variants['nav.hitTest'] ?? 'faithful'} />
      <MorphMount variant={mountVariant} targetSelector='[data-fw="platform"]' onMount={() => setPanel(true)} onWake={() => setWoken(true)} />
      <MorphTween variant={config.variants['morph.tween'] ?? 'faithful'} platformFade={config.variants['platform'] === FADE_THREADED} />
      {/* engine.scene: the platform section is the scene it pauses while it paints nothing (hidden-pause) */}
      <EngineScene variant={config.variants['engine.scene'] ?? 'faithful'} selector='[data-fw="platform"]' />
      {/* The nav hosts the morph panel (as the original does): `--morph` reaches it by inheritance, columns sit in its backdrop. */}
      <Nav variant={config.variants['nav'] ?? 'faithful'} onJoin={openSignup} panelWriterRef={writerRef}>
        {panel && (
          <MorphPanel
            variant={config.variants['morph.panel'] ?? 'faithful'}
            impl={config.impl['morph.panel']}
            writerRef={writerRef}
            onAction={openSignup}
            backdrop={<MorphColumns variant={config.variants['morph.columns'] ?? 'faithful'} dormant={asleep} />}
            countdown={<MorphCountdown variant={config.variants['morph.countdown'] ?? 'faithful'} impl={config.impl['morph.countdown']} dormant={asleep} />}
          />
        )}
      </Nav>

      <div data-fw="page-root" {...nobounceProps(config.variants['morph.end.nobounce'] ?? 'faithful')}>
      <main>
        <Hero variants={config.variants} />
        <People variants={config.variants} />
        <Pain variant={config.variants['pain'] ?? 'faithful'} notesVariant={config.variants['pain.notes'] ?? 'faithful'} />
        <Commission variant={config.variants['commission'] ?? 'faithful'} typingVariant={config.variants['commission.typing'] ?? 'faithful'} />
        <Platform
          variant={config.variants['platform'] ?? 'faithful'}
          sub={{
            sweep: config.variants['platform.sweep'],
            glint: config.variants['platform.glint'],
            entries: config.variants['platform.entries'],
            stageBg: config.variants['platform.stageBg'],
            marquee: config.variants['platform.marquee'],
          }}
        />
      </main>
      </div>

      <OverlayDrawer variant={config.variants['overlays.drawer'] ?? 'faithful'} onGetStarted={openSignup} />
      <OverlaySignup variant={config.variants['overlays.signup'] ?? 'faithful'} />
    </>
  );
}
