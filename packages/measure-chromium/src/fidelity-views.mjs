// The views every font-fidelity engine measures (task counts-font-fidelity). m430 is the lane's swipe viewport; p430 is the
// phone's Safari viewport (results/phone/2026-10-17-s1/counts-original.json: 430 x 775), so the lane page height is read
// against the phone's own at the same inner height; d1280 is the desktop profile's viewport (desktop-1280.json).
export const VIEWS = [
  { id: 'm430', width: 430, height: 932, dpr: 3, mobile: true },
  { id: 'p430', width: 430, height: 775, dpr: 3, mobile: true },
  { id: 'd1280', width: 1280, height: 800, dpr: 1, mobile: false },
];
