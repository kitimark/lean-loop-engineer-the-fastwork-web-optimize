import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import Typography from '@mui/material/Typography';
import { useEffect, useState } from 'react';
import { Hero } from './parts/hero';
import { EngineScroll } from './parts/engine.scroll';
import { MorphTween } from './parts/morph.tween';
import { MorphCountdown } from './parts/morph.countdown';
import { NavHitTest } from './parts/nav.hitTest';
import { Nav } from './parts/nav';
import { MorphMount } from './parts/morph.mount';
import { MorphColumns } from './parts/morph.columns';
import { People } from './parts/people';
import { Pain } from './parts/pain';
import { Commission } from './parts/commission';
import { Platform } from './parts/platform';
import { MorphPanel } from './parts/morph.panel';
import { OverlayDrawer, openDrawer } from './parts/overlays.drawer';
import { OverlaySignup, openSignup } from './parts/overlays.signup';
import type { FwConfig } from './registry/types';
import { setHydrated } from './fw';

/** Placeholder home page. Overlays are mounted closed (no keepMounted: they portal in on open, like the real ones). */
export function App({ config }: { config: FwConfig }) {
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);

  useEffect(() => setHydrated(), []); // root effects run after hydration has committed

  return (
    <>
      <EngineScroll variant={config.variants['engine.scroll'] ?? 'faithful'} />
      <NavHitTest variant={config.variants['nav.hitTest'] ?? 'faithful'} />
      <MorphMount variant={config.variants['morph.mount'] ?? 'faithful'} />
      <MorphTween variant={config.variants['morph.tween'] ?? 'faithful'} />
      <Nav variant={config.variants['nav'] ?? 'faithful'} />
      {/* Overlay triggers of the placeholder page (the MUI census clicks them); the nav is the port above. */}
      <Box data-fw="overlay-triggers" style={{ position: 'fixed', left: 0, bottom: 0, zIndex: 50, display: 'flex', gap: 4 }}>
        <Button size="small" id="open-menu" onClick={(e) => setAnchor(e.currentTarget)}>
          Menu
        </Button>
        <Button size="small" id="open-drawer" onClick={openDrawer}>
          Drawer
        </Button>
        <Button size="small" id="open-dialog" onClick={openSignup}>
          Sign up
        </Button>
      </Box>

      <MorphPanel variant={config.variants['morph.panel'] ?? 'faithful'} impl={config.impl['morph.panel']} />

      <main>
        <Hero variants={config.variants} />
        {/* stand-in for the morph panel at rest (scene paused); morph.panel replaces this host */}
        <div data-start-selling-scene="paused">
          <MorphCountdown variant={config.variants['morph.countdown'] ?? 'faithful'} impl={config.impl['morph.countdown']} />
        </div>

        <People variants={config.variants} />
        <Pain variant={config.variants['pain'] ?? 'shell'} />
        <Commission variant={config.variants['commission'] ?? 'faithful'} typingVariant={config.variants['commission.typing'] ?? 'faithful'} />
        <Platform variant={config.variants['platform'] ?? 'shell'} />
        <MorphColumns variant={config.variants['morph.columns'] ?? 'faithful'} />
      </main>

      <Menu open={anchor !== null} anchorEl={anchor} onClose={() => setAnchor(null)}>
        <MenuItem onClick={() => setAnchor(null)}>Item one</MenuItem>
        <MenuItem selected onClick={() => setAnchor(null)}>
          Item two
        </MenuItem>
      </Menu>
      <OverlayDrawer variant={config.variants['overlays.drawer'] ?? 'faithful'} onGetStarted={openSignup} />
      <OverlaySignup variant={config.variants['overlays.signup'] ?? 'faithful'} />
    </>
  );
}
