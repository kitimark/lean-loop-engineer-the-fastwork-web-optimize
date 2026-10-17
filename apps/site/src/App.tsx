import AppBar from '@mui/material/AppBar';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import Drawer from '@mui/material/Drawer';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import { useEffect, useState } from 'react';
import { HeroCountdown } from './parts/hero.countdown';
import { HeroExit } from './parts/hero.exit';
import { EngineScroll } from './parts/engine.scroll';
import { NavHitTest } from './parts/nav.hitTest';
import { MorphMount } from './parts/morph.mount';
import { MorphColumns } from './parts/morph.columns';
import { People } from './parts/people';
import { Pain } from './parts/pain';
import { Commission } from './parts/commission';
import { Platform } from './parts/platform';
import type { FwConfig } from './registry/types';
import { setHydrated } from './fw';

/** Placeholder home page. Overlays are mounted closed (no keepMounted: they portal in on open, like the real ones). */
export function App({ config }: { config: FwConfig }) {
  const [dialog, setDialog] = useState(false);
  const [drawer, setDrawer] = useState(false);
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);

  useEffect(() => setHydrated(), []); // root effects run after hydration has committed

  return (
    <>
      <EngineScroll variant={config.variants['engine.scroll'] ?? 'faithful'} />
      <NavHitTest variant={config.variants['nav.hitTest'] ?? 'faithful'} />
      <MorphMount variant={config.variants['morph.mount'] ?? 'faithful'} />
      <AppBar position="sticky" data-fw="nav">
        <Toolbar>
          <Typography variant="h6" component="div" style={{ flexGrow: 1 }}>
            Placeholder site
          </Typography>
          <Button color="inherit" id="open-menu" onClick={(e) => setAnchor(e.currentTarget)}>
            Menu
          </Button>
          <Button color="inherit" id="open-drawer" onClick={() => setDrawer(true)}>
            Drawer
          </Button>
          <Button color="inherit" variant="outlined" id="open-dialog" onClick={() => setDialog(true)}>
            Sign up
          </Button>
        </Toolbar>
      </AppBar>

      <main>
        <HeroCountdown variant={config.variants['hero.countdown'] ?? 'faithful'} />
        <HeroExit variant={config.variants['hero.exit'] ?? 'faithful'} />

        <People variant={config.variants['people'] ?? 'shell'} />
        <Pain variant={config.variants['pain'] ?? 'shell'} />
        <Commission variant={config.variants['commission'] ?? 'shell'} />
        <Platform variant={config.variants['platform'] ?? 'shell'} />
        <MorphColumns variant={config.variants['morph.columns'] ?? 'faithful'} />
      </main>

      <Menu open={anchor !== null} anchorEl={anchor} onClose={() => setAnchor(null)}>
        <MenuItem onClick={() => setAnchor(null)}>Item one</MenuItem>
        <MenuItem selected onClick={() => setAnchor(null)}>
          Item two
        </MenuItem>
      </Menu>
      <Drawer anchor="right" open={drawer} onClose={() => setDrawer(false)}>
        <Box style={{ width: 240, padding: 16 }}>
          <Typography>Drawer content</Typography>
        </Box>
      </Drawer>
      <Dialog open={dialog} onClose={() => setDialog(false)}>
        <DialogTitle>Sign up</DialogTitle>
        <DialogContent>
          <Typography>Placeholder dialog.</Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialog(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </>
  );
}
