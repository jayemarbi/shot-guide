// The edit: every shot starts and ends on a beat of a 133 BPM track.
export const BPM = 133;
export const SPB = 60 / BPM;
export const END_BEAT = 48.75;
const D2R = Math.PI / 180;

// Hip-bounce lows of the samba clip, one per beat once warped.
const M = [0.27, 0.87, 1.3, 1.83, 2.37, 2.93, 3.5, 4.1, 4.67, 5.3, 5.87, 6.53, 7.0, 7.63, 8.2, 8.77, 9.3, 9.9, 10.5, 11.17, 11.7, 12.3, 12.87, 13.5, 14.03, 14.6, 15.1, 15.73, 16.03, 16.37, 16.63, 16.93, 17.43, 18.0];
function warp(k) {
  k = Math.max(0, Math.min(k, M.length - 1));
  const i = Math.min(Math.floor(k), M.length - 2), f = k - i;
  return M[i] + (M[i + 1] - M[i]) * f;
}
export function danceTime(b) {
  if (b < 16) return warp(b);
  if (b < 24) return warp(b - 8);
  if (b < 40) return warp(b - 13);
  if (b < 43) return warp(27 + (b - 40) * 2);
  if (b < 44) return 18.0 + (b - 43) * 0.2;
  return 18.2;
}

export const ease = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
export const easeOut = (u) => 1 - Math.pow(1 - u, 3);
export const easeIn = (u) => u * u * u;
const L = (a, b, u) => a + (b - a) * u;
const LV = (a, b, u) => a.map((v, i) => v + (b[i] - v) * u);

function orbit(target, dist, height, az, fov) {
  const a = az * D2R;
  return { pos: [target[0] + Math.sin(a) * dist, height, target[2] + Math.cos(a) * dist], look: target, fov };
}
function aim(pos, az, el, fov) {
  const a = az * D2R, e = el * D2R;
  return { pos, look: [pos[0] + Math.sin(a) * Math.cos(e) * 10, pos[1] + Math.sin(e) * 10, pos[2] - Math.cos(a) * Math.cos(e) * 10], fov };
}

// Same framing at every location, so the dance carries straight across the cut.
const STD = (u) => ({ pos: [0, 0.98, L(5.2, 4.9, u)], look: [0, 0.92, 0], fov: 40 });

export const SHOTS = [
  { id: 'hook_wide', scene: 'redrocks', b0: 0, b1: 4, follow: 0.6, cam: (u) => { const e = ease(u); return { pos: [L(0.5, 0.2, e), L(1.25, 1.05, e), L(11.5, 8.8, e)], look: [0, L(2.6, 2.1, e), 0], fov: 46 }; } },
  { id: 'hook_low', scene: 'redrocks', b0: 4, b1: 8, shake: 0.35, cam: (u) => orbit([0, 1.12, 0], 3.7, 0.55, L(-24, -8, ease(u)), 44) },
  { id: 'swap_forest', scene: 'forest', b0: 8, b1: 10, cam: STD },
  { id: 'swap_lake', scene: 'lake', b0: 10, b1: 12, cam: (u) => ({ pos: [0, 0.78, L(5.0, 4.75, u)], look: [0, 0.98, 0], fov: 40 }) },
  { id: 'swap_city', scene: 'city', b0: 12, b1: 14, cam: STD },
  { id: 'swap_summit', scene: 'summit', b0: 14, b1: 16, cam: STD },
  { id: 'cut_pines', scene: 'forest', b0: 16, b1: 18, dancer: false, speed: 1.6, cam: (u) => aim([0.6, 1.2, 1.5], L(-10, -20, ease(u)), L(8, 24, ease(u)), 50) },
  { id: 'cut_fin', scene: 'redrocks', b0: 18, b1: 20, dancer: false, cam: (u) => aim([L(-1.2, 1.8, u), 1.7, 6], L(-22, -12, u), L(20, 27, u), 46) },
  { id: 'cut_reflection', scene: 'lake', b0: 20, b1: 21, dancer: false, cam: (u) => aim([0.4, 0.4, L(-4.2, -4.8, u)], -1, L(-7, -5, u), 44) },
  { id: 'cut_city', scene: 'city', b0: 21, b1: 22, dancer: false, speed: 60, cam: (u) => aim([0, 2.4, L(7.5, 7.0, u)], 1.5, L(3.6, 3.9, u), 24) },
  { id: 'cut_stars', scene: 'night', b0: 22, b1: 24, dancer: false, speed: 9,
    cam: (u) => { const w = u < 0.8 ? 0 : easeIn((u - 0.8) / 0.2); return aim([0, 1.0, 5], -14, L(L(14, 20, u), 75, w), 54); },
    blur: (u) => (u > 0.8 ? { v: 70 * Math.sin(((u - 0.8) / 0.2) * Math.PI * 0.5) } : null) },
  { id: 'drop_orbit', scene: 'summit', b0: 24, b1: 28, punch: true,
    cam: (u) => { const w = Math.min(1, u / 0.13); const o = orbit([0, 1.05, 0], 5.2, 1.3, L(38, -22, ease(u)), 40); if (w < 1) { const k = 1 - easeOut(w); o.look = [o.look[0], o.look[1] + k * 9, o.look[2]]; } return o; },
    blur: (u) => (u < 0.13 ? { v: 70 * (1 - u / 0.13) } : null) },
  { id: 'drop_low', scene: 'summit', b0: 28, b1: 32, punch: true, shake: 0.5, cam: (u) => orbit([0, 1.32, 0], 2.7, 0.42, L(-12, 6, u), 46) },
  { id: 'drop_dollyzoom', scene: 'summit', b0: 32, b1: 36,
    cam: (u) => { const e = ease(u); const d = L(3.0, 13.5, e); const fov = 2 * Math.atan(2.55 / (2 * d)) / D2R; return { pos: [0.15, 0.98, d], look: [0, 0.92, 0], fov }; } },
  { id: 'fast_redrocks', scene: 'redrocks', b0: 36, b1: 37, cam: STD },
  { id: 'fast_forest', scene: 'forest', b0: 37, b1: 38, cam: STD },
  { id: 'fast_lake', scene: 'lake', b0: 38, b1: 39, cam: (u) => ({ pos: [0, 0.78, 4.9], look: [0, 0.98, 0], fov: 40 }) },
  { id: 'fast_city', scene: 'city', b0: 39, b1: 40, cam: STD },
  { id: 'outro_silhouette', scene: 'summit', b0: 40, b1: END_BEAT, follow: 0.8,
    cam: (u, b) => { const k = ease(Math.max(0, (b - 43.5) / (END_BEAT - 43.5))); const d = L(16.5, 21, k); return { pos: [-Math.sin(3 * D2R) * d, L(0.62, 0.9, k), d], look: [0, L(0.95, 1.05, k), 0], fov: L(12.5, 17, k) }; } },
];

export const FLASHES = [[8, 0.35], [24, 0.95], [36, 0.45], [40, 0.3], [44, 0.55]];
export const LEAKS = [[4, 1], [16, -1], [28, 1]];

export function shotAt(b) {
  for (const s of SHOTS) if (b >= s.b0 && b < s.b1) return s;
  return SHOTS[SHOTS.length - 1];
}
