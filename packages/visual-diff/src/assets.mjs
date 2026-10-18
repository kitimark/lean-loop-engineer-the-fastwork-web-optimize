// The asset premise: a port of lean/Fw/Gate/Pixel.lean (`Img.loaded`, `imagesLoaded`, `needed`, `fontsLoaded`), checked against
// packages/contracts/golden/gate/pixel-assets.jsonl (test/assets.test.mjs). The page only reports (`assetsInPage` in page.mjs);
// these functions decide.
//   img  = { complete, w, h }                 an <img> that touches the crop (w, h = natural size)
//   face = { family, status }                 one FontFace of document.fonts; status unloaded | loading | loaded | error

/** Fw.Gate.Pixel.Img.loaded: complete and a non-zero natural size (a failed load is complete with size 0). */
export const imgLoaded = (i) => i.complete === true && i.w > 0 && i.h > 0;

/** Fw.Gate.Pixel.imagesLoaded. */
export const imagesLoaded = (imgs) => imgs.every(imgLoaded);

/** Fw.Gate.Pixel.needed: the used first families that the page declares a face for. */
export const needed = (fams, faces) => fams.filter((f) => faces.some((x) => x.family === f));

/** Fw.Gate.Pixel.fontsLoaded: no face loading or failed, and every needed family has a loaded face. */
export const fontsLoaded = (fams, faces) =>
  faces.every((x) => x.status !== 'loading' && x.status !== 'error') &&
  needed(fams, faces).every((f) => faces.some((x) => x.family === f && x.status === 'loaded'));
