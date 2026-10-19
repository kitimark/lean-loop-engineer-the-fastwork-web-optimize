# port-pin-gap
State: platform profile pin now GenSvg platform.pin (Visuals.tsx), css .loc svg 10x12 like original; assets.test updated.
people.deck: original prerenders and client-renders img /selling/icons/pin.svg (checked snapshot html and nodes js), so panel.tsx stays unchanged.
Verified: apps/site pnpm test + typecheck green; built dist/aot, port-svg no longer lists the pin (remaining: nav logo 9 vs 10 elements, other task).
Open: pixel equality via CI visual run.
