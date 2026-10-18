import AppBar from '@mui/material/AppBar';
import Avatar from '@mui/material/Avatar';
import Backdrop from '@mui/material/Backdrop';
import Box from '@mui/material/Box';
import ButtonBase from '@mui/material/ButtonBase';
import Button from '@mui/material/Button';
import Card from '@mui/material/Card';
import CardActions from '@mui/material/CardActions';
import CardContent from '@mui/material/CardContent';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import Divider from '@mui/material/Divider';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import Link from '@mui/material/Link';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import { HeroCountdown } from './parts/hero.countdown';
import { HeroExit } from './parts/hero.exit';
import { MorphColumns } from './parts/morph.columns';
import { MorphPanel } from './parts/morph.panel';
import { parts } from './registry';

/**
 * Build-only census route (never shipped as a page). It renders every MUI component the site uses, in every
 * state the site can reach, so the styles Emotion generates for them can be extracted to static CSS.
 *
 * Overlays render with `disablePortal` (MUI `Portal` renders nothing on the server), both open and closed
 * (`keepMounted`). Emotion class names depend only on the serialized styles, not on where the node is mounted,
 * so the portal at runtime reuses the same ids.
 *
 * Add a component or a state here whenever a part starts to use it; `muiStates` in `part.json` lists the
 * ownerState values a part needs (S2).
 */
const COLORS = ['inherit', 'primary', 'secondary', 'error', 'success', 'info', 'warning'] as const;
const VARIANTS = ['text', 'outlined', 'contained'] as const;
const SIZES = ['small', 'medium', 'large'] as const;
const TYPO = [
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'subtitle1', 'subtitle2', 'body1', 'body2', 'caption', 'overline', 'button',
] as const;
const ANCHORS = ['left', 'right', 'top', 'bottom'] as const;

function Buttons() {
  return (
    <Stack>
      {COLORS.flatMap((c) =>
        VARIANTS.flatMap((v) =>
          SIZES.flatMap((s) => [
            <Button key={`${c}${v}${s}`} color={c} variant={v} size={s}>
              b
            </Button>,
            <Button key={`${c}${v}${s}d`} color={c} variant={v} size={s} disabled>
              b
            </Button>,
          ]),
        ),
      )}
      <Button fullWidth>full</Button>
      <Button href="#x">link</Button>
      <Button disableElevation variant="contained">
        flat
      </Button>
      <IconButton aria-label="i">i</IconButton>
      <IconButton aria-label="i" disabled color="primary" size="small">
        i
      </IconButton>
      <Link href="#x">link</Link>
      <Link href="#x" underline="hover" color="inherit">
        link
      </Link>
    </Stack>
  );
}

function Surfaces() {
  return (
    <Box>
      <AppBar position="static">
        <Toolbar>
          <Typography variant="h6">bar</Typography>
        </Toolbar>
      </AppBar>
      <AppBar position="sticky" color="transparent" elevation={0}>
        <Toolbar />
      </AppBar>
      <AppBar position="fixed" color="primary">
        <Toolbar />
      </AppBar>
      {[0, 1, 2, 3, 4, 6, 8, 12, 16, 24].map((e) => (
        <Paper key={e} elevation={e}>
          p
        </Paper>
      ))}
      <Paper variant="outlined" square>
        p
      </Paper>
      <Card>
        <CardContent>
          <Typography>c</Typography>
        </CardContent>
        <CardActions>
          <Button>a</Button>
        </CardActions>
      </Card>
      <Card variant="outlined" elevation={0} />
      <Divider />
      <Divider orientation="vertical" flexItem />
      <Backdrop open>
        <span />
      </Backdrop>
      <Backdrop open={false} invisible>
        <span />
      </Backdrop>
    </Box>
  );
}

function People() {
  return (
    <Stack direction="row">
      <Avatar>A</Avatar>
      <Avatar variant="rounded">B</Avatar>
      <Avatar variant="square">
        <img alt="" width="1" height="1" />
      </Avatar>
      <Avatar />
    </Stack>
  );
}

function TypographyAll() {
  return (
    <Box>
      {TYPO.map((v) => (
        <Typography key={v} variant={v}>
          t
        </Typography>
      ))}
      <Typography noWrap>t</Typography>
      <Typography gutterBottom align="center" color="text.secondary">
        t
      </Typography>
      <Typography color="primary">
        t
      </Typography>
    </Box>
  );
}

function TabsAll() {
  return (
    <Box>
      {[0, 1].map((value) => (
        <Tabs key={value} value={value} aria-label="t" slotProps={{ indicator: { style: { display: 'none' } } }}>
          <Tab label="a" />
          <Tab label="b" />
          <Tab label="c" disabled />
        </Tabs>
      ))}
      <Tabs value={0} variant="fullWidth" centered>
        <Tab label="a" />
        <Tab label="b" />
      </Tabs>
      <Tabs value={0} textColor="secondary" indicatorColor="secondary" orientation="vertical">
        <Tab label="a" />
        <Tab label="b" />
      </Tabs>
      {/* S7: MUI 9.5.0 Tab needs Tabs' roving-tabindex context, so the home page's measuring-free tablist uses ButtonBase */}
      <div role="tablist">
        <ButtonBase role="tab" aria-selected>a</ButtonBase>
        <ButtonBase role="tab" aria-selected={false} disabled>b</ButtonBase>
      </div>
    </Box>
  );
}

function Overlays() {
  return (
    <Box>
      {/* closed: keepMounted so the hidden markup (and its closed-state styles) exists */}
      <Dialog open={false} keepMounted disablePortal>
        <DialogTitle>d</DialogTitle>
        <DialogContent>c</DialogContent>
        <DialogActions>
          <Button>x</Button>
        </DialogActions>
      </Dialog>
      <Dialog open disablePortal>
        <DialogTitle>d</DialogTitle>
        <DialogContent dividers>c</DialogContent>
        <DialogActions>
          <Button>x</Button>
        </DialogActions>
      </Dialog>
      <Dialog open disablePortal fullWidth scroll="body">
        <DialogContent>c</DialogContent>
      </Dialog>
      <Dialog open disablePortal fullScreen>
        <DialogContent>c</DialogContent>
      </Dialog>
      {ANCHORS.map((a) => (
        <Drawer key={`${a}o`} anchor={a} open disablePortal>
          <Box>d</Box>
        </Drawer>
      ))}
      {ANCHORS.map((a) => (
        <Drawer key={`${a}c`} anchor={a} open={false} keepMounted disablePortal>
          <Box>d</Box>
        </Drawer>
      ))}
      <Drawer variant="persistent" open anchor="left">
        <Box>d</Box>
      </Drawer>
      <Drawer variant="permanent" anchor="right">
        <Box>d</Box>
      </Drawer>
      {/* Popover without an anchor element: positions are inline styles, not Emotion */}
      <Menu open disablePortal anchorReference="anchorPosition" anchorPosition={{ top: 0, left: 0 }}>
        <MenuItem>a</MenuItem>
        <MenuItem selected>b</MenuItem>
        <MenuItem disabled>c</MenuItem>
        <Divider />
        <MenuItem dense>d</MenuItem>
      </Menu>
      <Menu open={false} keepMounted disablePortal anchorReference="anchorPosition" anchorPosition={{ top: 0, left: 0 }}>
        <MenuItem>a</MenuItem>
      </Menu>
    </Box>
  );
}

function PartsAll() {
  // Every variant of every registered part, so a variant swap by flag never needs a new style.
  return (
    <Box>
      {parts.flatMap((p) =>
        Object.keys(p.variants).map((variant) =>
          p.id === 'hero.countdown' ? (
            <HeroCountdown key={`${p.id}:${variant}`} variant={variant} />
          ) : p.id === 'hero.exit' ? (
            <HeroExit key={`${p.id}:${variant}`} variant={variant} />
          ) : p.id === 'morph.columns' ? (
            <MorphColumns key={`${p.id}:${variant}`} variant={variant} />
          ) : p.id === 'morph.panel' ? (
            <MorphPanel key={`${p.id}:${variant}`} variant={variant} />
          ) : null,
        ),
      )}
    </Box>
  );
}

export function Census() {
  return (
    <>
      <Buttons />
      <Surfaces />
      <People />
      <TypographyAll />
      <TabsAll />
      <Overlays />
      <PartsAll />
    </>
  );
}
