// How a run switches the images-at-drawn-size arm on (task image-audit). This is an API only: no caller exists yet (webkit-lag-probe is
// not wired), and the arm premise is closed as a MEASURED negative finding (task image-arm-v2 re-plans it). The arm is a request rewrite
// on the static server, not a build: `serveTree(root, { rewrite })` answers an image URL of the table with the resized copy for
// the probe's CSS width and DPR, and leaves every other request to `base` (the config-hash rewrite) or to the file tree.
// The page, its CSS and its scripts are byte for byte the same in both arms, so a run differs in image bytes only.
//   const arm = armFromEnv(process.env);                    // FW_IMAGES_ARM=drawn | unset
//   serveTree(dist, { rewrite: drawnRewrite({ arm, width: 430, dpr: 3, base: configRewrite }) });
// The copies must be under the served root: arm build writes them into the gitignored apps/site/dist/aot/images-drawn (never committed).
import { composeRewrite, loadDrawn } from './arm.mjs';

/** 'drawn' when FW_IMAGES_ARM=drawn, 'default' when it is unset or 'default'; anything else throws (a typo must not read as the default arm). */
export function armFromEnv(env) {
  const v = env.FW_IMAGES_ARM;
  if (v === undefined || v === '' || v === 'default') return 'default';
  if (v === 'drawn') return 'drawn';
  throw new Error(`FW_IMAGES_ARM=${v}: expected drawn or default`);
}

/** The rewrite for `serveTree`: `base` itself for the default arm, the arm's copies on top of `base` for 'drawn'. */
export function drawnRewrite({ arm, width, dpr, base = null, manifest = null }) {
  if (arm === 'default') return base;
  if (arm !== 'drawn') throw new Error(`arm ${arm}: expected drawn or default`);
  return composeRewrite(base, manifest ?? loadDrawn(), { width, dpr });
}
