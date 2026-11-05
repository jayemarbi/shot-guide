// Painting helpers: seeded noise, layered landscape cards painted in (azimuth, elevation) space.
export const D2R = Math.PI / 180;

export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function noise1(seed) {
  const r = rng(seed), N = 4096, v = new Float32Array(N);
  for (let i = 0; i < N; i++) v[i] = r() * 2 - 1;
  return (x) => {
    const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
    return v[i & (N - 1)] * (1 - u) + v[(i + 1) & (N - 1)] * u;
  };
}

export function fbm1(n, x, oct = 5, gain = 0.5, lac = 2.07) {
  let s = 0, a = 1, f = 1, norm = 0;
  for (let o = 0; o < oct; o++) { s += a * n(x * f + o * 17.31); norm += a; a *= gain; f *= lac; }
  return s / norm;
}

export function ridged1(n, x, oct = 5, gain = 0.5, lac = 2.07) {
  let s = 0, a = 1, f = 1, norm = 0;
  for (let o = 0; o < oct; o++) { const v = 1 - Math.abs(n(x * f + o * 31.7)); s += a * v * v; norm += a; a *= gain; f *= lac; }
  return s / norm;
}

export function noise2(seed) {
  const r = rng(seed), N = 512, v = new Float32Array(N * N);
  for (let i = 0; i < N * N; i++) v[i] = r();
  return (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
    const u = xf * xf * (3 - 2 * xf), w = yf * yf * (3 - 2 * yf);
    const i0 = xi & (N - 1), i1 = (xi + 1) & (N - 1), j0 = (yi & (N - 1)) * N, j1 = ((yi + 1) & (N - 1)) * N;
    const a = v[j0 + i0], b = v[j0 + i1], c = v[j1 + i0], d = v[j1 + i1];
    return a + (b - a) * u + (c - a) * w + (a - b - c + d) * u * w;
  };
}

export function fbm2(n, x, y, oct = 5, gain = 0.5) {
  let s = 0, a = 1, f = 1, norm = 0;
  for (let o = 0; o < oct; o++) { s += a * n(x * f + o * 13.7, y * f + o * 7.1); norm += a; a *= gain; f *= 2.03; }
  return s / norm;
}

export const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
export const lerp = (a, b, t) => a + (b - a) * t;
export const smooth = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };

export function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return [c, c.getContext('2d')];
}

export function hex(c) {
  const n = parseInt(c.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export function rgba(c, a = 1) { const [r, g, b] = hex(c); return `rgba(${r},${g},${b},${a})`; }
export function mix(a, b, t) {
  const A = hex(a), B = hex(b);
  const m = A.map((v, i) => Math.round(v + (B[i] - v) * t));
  return '#' + m.map((v) => v.toString(16).padStart(2, '0')).join('');
}

export function vgrad(g, y0, y1, stops) {
  const gr = g.createLinearGradient(0, y0, 0, y1);
  for (const [o, c] of stops) gr.addColorStop(clamp(o, 0, 1), c);
  return gr;
}

// A cylinder card around the dancer, painted in angles: az (deg, + is right), el (deg, + is up).
export class Layer {
  constructor({ R, theta, eMin, eMax, w, h, az0 = 0 }) {
    Object.assign(this, { R, theta, eMin, eMax, w, h, az0 });
    this.yTop = R * Math.tan(eMax * D2R);
    this.yBot = R * Math.tan(eMin * D2R);
    [this.c, this.g] = canvas(w, h);
  }
  X(az) { return this.w * (0.5 + (az - this.az0) / this.theta); }
  Y(el) { const y = this.R * Math.tan(el * D2R); return this.h * (this.yTop - y) / (this.yTop - this.yBot); }
  AZ(x) { return this.az0 + (x / this.w - 0.5) * this.theta; }
  EL(py) { const y = this.yTop - (py / this.h) * (this.yTop - this.yBot); return Math.atan(y / this.R) / D2R; }
  pxPerDeg() { return this.w / this.theta; }
}

export function ridgeLine(L, elevFn, step = 2) {
  const pts = [];
  for (let x = -step * 2; x <= L.w + step * 2; x += step) pts.push([x, L.Y(elevFn(L.AZ(x)))]);
  return pts;
}

export function pathUnder(g, pts, bottom) {
  g.beginPath();
  g.moveTo(pts[0][0], bottom);
  for (const [x, y] of pts) g.lineTo(x, y);
  g.lineTo(pts[pts.length - 1][0], bottom);
  g.closePath();
}

// Paper-like grain inside whatever is already painted.
export function grain(L, amount = 0.05, seed = 1, scale = 1) {
  const { g, w, h } = L;
  const [ac, ag] = canvas(w, h);
  ag.drawImage(L.c, 0, 0);
  const [c, gc] = canvas(256, 256);
  const img = gc.createImageData(256, 256), r = rng(seed);
  for (let i = 0; i < img.data.length; i += 4) {
    const v = 128 + (r() - 0.5) * 255;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255;
  }
  gc.putImageData(img, 0, 0);
  g.save();
  g.globalCompositeOperation = 'overlay';
  g.globalAlpha = amount;
  const pat = g.createPattern(c, 'repeat');
  g.setTransform(scale, 0, 0, scale, 0, 0);
  g.fillStyle = pat;
  g.fillRect(0, 0, w / scale, h / scale);
  g.restore();
  // keep alpha where nothing is painted
  g.save();
  g.globalCompositeOperation = 'destination-in';
  g.drawImage(ac, 0, 0);
  g.restore();
}

function findPeaks(pts, minProm, minGap) {
  const peaks = [];
  for (let i = 2; i < pts.length - 2; i++) {
    const y = pts[i][1];
    if (y <= pts[i - 1][1] && y <= pts[i + 1][1] && y < pts[i - 2][1] && y < pts[i + 2][1]) {
      let l = i, r = i, lmax = y, rmax = y;
      while (l > 0 && pts[l][0] > pts[i][0] - minGap * 3) { l--; lmax = Math.max(lmax, pts[l][1]); }
      while (r < pts.length - 1 && pts[r][0] < pts[i][0] + minGap * 3) { r++; rmax = Math.max(rmax, pts[r][1]); }
      if (Math.min(lmax, rmax) - y > minProm) {
        if (peaks.length && pts[i][0] - pts[peaks[peaks.length - 1]][0] < minGap) {
          if (y < pts[peaks[peaks.length - 1]][1]) peaks[peaks.length - 1] = i;
        } else peaks.push(i);
      }
    }
  }
  return peaks;
}

// Mountains with a lit and a shaded face per peak, optional snow, haze and a sunlit rim.
export function mountains(L, o) {
  const g = L.g;
  const pts = ridgeLine(L, o.elev, o.step || 2);
  const top = Math.min(...pts.map((p) => p[1]));
  const bottom = o.bottom != null ? L.Y(o.bottom) : L.h + 4;
  const [mc, mg] = canvas(L.w, L.h);
  pathUnder(mg, pts, bottom);
  mg.fillStyle = vgrad(mg, top, bottom, o.body);
  mg.fill();
  mg.save();
  pathUnder(mg, pts, bottom);
  mg.clip();
  const n = noise1(o.seed || 7);
  // snow
  if (o.snow) {
    const s = o.snow;
    mg.beginPath();
    mg.moveTo(pts[0][0], pts[0][1]);
    for (const [x, y] of pts) mg.lineTo(x, y);
    for (let k = pts.length - 1; k >= 0; k--) {
      const [x, y] = pts[k];
      const el = L.EL(y), az = L.AZ(x);
      const above = Math.max(0, el - s.line);
      const streak = 0.35 + 1.3 * Math.pow(Math.abs(n(az * s.freq + 40)), 0.6);
      const depth = Math.max(0, (above * s.k + s.base) * streak + fbm1(n, az * 0.3, 3) * s.jitter);
      mg.lineTo(x, y + (L.Y(el - depth) - L.Y(el)));
    }
    mg.closePath();
    mg.fillStyle = s.color;
    mg.fill();
    // thin couloir streaks
    if (s.streaks) {
      const r = rng(o.seed * 3 + 1);
      mg.strokeStyle = s.color;
      for (let k = 0; k < s.streaks; k++) {
        const x0 = r() * L.w;
        const i0 = Math.round((x0 - pts[0][0]) / (o.step || 2));
        if (i0 < 0 || i0 >= pts.length) continue;
        const y0 = pts[i0][1];
        if (L.EL(y0) < s.line - 2) continue;
        mg.lineWidth = 1 + r() * 2.5;
        mg.globalAlpha = 0.5 + r() * 0.5;
        mg.beginPath();
        let x = x0, y = y0;
        mg.moveTo(x, y);
        const len = (20 + r() * 70) * (L.h / 1000);
        for (let j = 0; j < 8; j++) { x += (r() - 0.5) * 6; y += len / 8; mg.lineTo(x, y); }
        mg.stroke();
      }
      mg.globalAlpha = 1;
    }
  }
  // shaded faces
  if (o.facets) {
    const f = o.facets;
    const peaks = findPeaks(pts, f.minProm || 6, f.minGap || 30);
    const [fc, fg] = canvas(L.w, L.h);
    fg.fillStyle = '#000';
    const r = rng((o.seed || 7) * 11 + 5);
    const dir = -f.sun; // shadow side
    for (const pi of peaks) {
      const [px, py] = pts[pi];
      fg.beginPath();
      fg.moveTo(px, py);
      let k = pi;
      let steps = 0;
      while (k + dir > 0 && k + dir < pts.length - 1 && steps < 2000) {
        k += dir; steps++;
        fg.lineTo(pts[k][0], pts[k][1]);
        if (pts[k][1] > pts[k + dir][1] && pts[k][1] > py + 20) break; // reached a valley
      }
      const vx = pts[k][0];
      fg.lineTo(vx, bottom);
      const slant = (f.slant || 0.35) * (0.7 + r() * 0.6);
      const span = bottom - py;
      const bx = px + dir * slant * span;
      const jag = [];
      const segs = 18;
      for (let j = 0; j <= segs; j++) {
        const t = j / segs;
        const jx = px + dir * slant * span * t + (r() - 0.5) * (f.jag || 14) * Math.sin(t * Math.PI);
        jag.push([jx, py + span * t]);
      }
      fg.lineTo(bx, bottom);
      for (let j = segs; j >= 0; j--) fg.lineTo(jag[j][0], jag[j][1]);
      fg.closePath();
      fg.fill();
    }
    fg.globalCompositeOperation = 'source-in';
    fg.fillStyle = f.color;
    fg.fillRect(0, 0, L.w, L.h);
    mg.globalCompositeOperation = 'multiply';
    mg.globalAlpha = f.alpha ?? 1;
    mg.drawImage(fc, 0, 0);
    mg.globalAlpha = 1;
    mg.globalCompositeOperation = 'source-over';
  }
  if (o.bands) {
    const b = o.bands, r = rng((o.seed || 7) * 5 + 2);
    mg.globalCompositeOperation = 'multiply';
    for (const el of b.at) {
      mg.strokeStyle = b.color;
      mg.lineWidth = b.width * (0.6 + r() * 0.8);
      mg.globalAlpha = b.alpha * (0.6 + r() * 0.4);
      mg.beginPath();
      for (let x = -10; x <= L.w + 10; x += 6) {
        const y = L.Y(el + fbm1(n, L.AZ(x) * 0.35 + el, 3) * b.wave + (L.AZ(x) - (b.tiltAz || 0)) * (b.tilt || 0));
        if (x < 0) mg.moveTo(x, y); else mg.lineTo(x, y);
      }
      mg.stroke();
    }
    mg.globalAlpha = 1;
    mg.globalCompositeOperation = 'source-over';
  }
  if (o.haze) {
    const hz = o.haze;
    mg.fillStyle = vgrad(mg, L.Y(hz.top), L.Y(hz.bottom), [[0, rgba(hz.color, 0)], [1, rgba(hz.color, hz.alpha)]]);
    mg.fillRect(0, 0, L.w, L.h);
  }
  if (o.wash) { mg.fillStyle = rgba(o.wash.color, o.wash.alpha); mg.fillRect(0, 0, L.w, L.h); }
  mg.restore();
  if (o.rim) {
    const rm = o.rim;
    mg.lineJoin = 'round';
    for (let i = 1; i < pts.length; i++) {
      const [x0, y0] = pts[i - 1], [x1, y1] = pts[i];
      const slope = (y1 - y0) / (x1 - x0);
      let lit = rm.all ? 1 : clamp(-slope * rm.sun * 1.5 + 0.15, 0, 1);
      if (rm.focusAz != null) lit *= Math.exp(-Math.pow((L.AZ(x0) - rm.focusAz) / rm.focusWidth, 2));
      if (lit <= 0.02) continue;
      mg.strokeStyle = rgba(rm.color, rm.alpha * lit);
      mg.lineWidth = rm.width;
      mg.beginPath(); mg.moveTo(x0, y0 + rm.width * 0.4); mg.lineTo(x1, y1 + rm.width * 0.4); mg.stroke();
    }
  }
  L.g.drawImage(mc, 0, 0);
  return pts;
}

export function pine(g, x, y, h, col, snow, r) {
  const tiers = 4 + Math.floor(r() * 3);
  const w = h * (0.34 + r() * 0.12);
  g.fillStyle = col;
  g.fillRect(x - h * 0.02, y - h * 0.12, h * 0.04, h * 0.14);
  for (let i = 0; i < tiers; i++) {
    const t0 = i / tiers;
    const yb = y - h * (0.1 + t0 * 0.78);
    const ww = w * (1 - t0 * 0.8) * (0.9 + r() * 0.2);
    const th = h * (0.32 - t0 * 0.08);
    g.fillStyle = col;
    g.beginPath();
    g.moveTo(x - ww / 2, yb);
    g.quadraticCurveTo(x - ww * 0.15, yb - th * 0.45, x, yb - th);
    g.quadraticCurveTo(x + ww * 0.15, yb - th * 0.45, x + ww / 2, yb);
    g.quadraticCurveTo(x, yb - th * 0.12, x - ww / 2, yb);
    g.fill();
    if (snow) {
      g.fillStyle = snow;
      g.beginPath();
      g.moveTo(x - ww * 0.42, yb - th * 0.05);
      g.quadraticCurveTo(x - ww * 0.12, yb - th * 0.5, x, yb - th * 0.98);
      g.quadraticCurveTo(x - ww * 0.02, yb - th * 0.45, x + ww * 0.12, yb - th * 0.32);
      g.quadraticCurveTo(x - ww * 0.1, yb - th * 0.22, x - ww * 0.42, yb - th * 0.05);
      g.fill();
    }
  }
  g.fillStyle = col;
  g.beginPath(); g.moveTo(x - h * 0.03, y - h * 0.86); g.lineTo(x, y - h * 1.0); g.lineTo(x + h * 0.03, y - h * 0.86); g.fill();
}

// A band of trees standing on a ridge line.
export function forest(L, pts, o) {
  const r = rng(o.seed || 3);
  const g = L.g;
  const step = o.spacing;
  for (let x = -step; x < L.w + step; x += step * (0.5 + r())) {
    const i = clamp(Math.round((x - pts[0][0]) / (pts[1][0] - pts[0][0])), 0, pts.length - 1);
    const y = pts[i][1] + (o.sink || 0) * (0.6 + r() * 0.8);
    const az = L.AZ(x);
    if (o.skip && o.skip(az)) continue;
    const h = o.height * (0.6 + r() * 0.7) * (o.heightFn ? o.heightFn(az) : 1);
    if (h < 1.5) {
      g.fillStyle = o.color; g.fillRect(x, y - h, 1, h); continue;
    }
    pine(g, x, y, h, o.color, o.snow, r);
  }
}

export function softBlob(g, x, y, rx, ry, color, alpha) {
  g.save();
  g.translate(x, y);
  g.scale(1, ry / rx);
  const gr = g.createRadialGradient(0, 0, 0, 0, 0, rx);
  gr.addColorStop(0, rgba(color, alpha));
  gr.addColorStop(1, rgba(color, 0));
  g.fillStyle = gr;
  g.beginPath(); g.arc(0, 0, rx, 0, Math.PI * 2); g.fill();
  g.restore();
}

// Puffy cloud bank: union of circles with a lit top and a shaded base.
export function cloudBank(L, o) {
  const g = L.g, r = rng(o.seed || 9);
  const [cc, cg] = canvas(L.w, L.h);
  const base = L.Y(o.base), topEl = o.top;
  const n = noise1(o.seed || 9);
  const pts = [];
  for (let x = -100; x < L.w + 100; x += o.bump * (0.45 + r() * 0.5)) {
    const az = L.AZ(x);
    const el = topEl + fbm1(n, az * o.freq, 4) * o.amp + (o.shape ? o.shape(az) : 0);
    const rad = o.bump * (0.6 + r() * 0.8);
    pts.push([x, L.Y(el) + rad * 0.55, rad]);
  }
  cg.fillStyle = '#fff';
  for (const [x, y, rad] of pts) { cg.beginPath(); cg.arc(x, y, rad, 0, Math.PI * 2); cg.fill(); }
  const minY = Math.min(...pts.map((p) => p[1] - p[2]));
  cg.fillRect(-10, Math.min(...pts.map((p) => p[1])), L.w + 20, base - minY + L.h);
  cg.globalCompositeOperation = 'source-in';
  cg.fillStyle = vgrad(cg, minY, base, o.colors);
  cg.fillRect(0, 0, L.w, L.h);
  // highlights on the tops facing the sun
  cg.globalCompositeOperation = 'source-atop';
  for (const [x, y, rad] of pts) {
    const gr = cg.createRadialGradient(x + o.sun * rad * 0.35, y - rad * 0.45, rad * 0.05, x, y, rad * 1.05);
    gr.addColorStop(0, rgba(o.light, o.lightAlpha));
    gr.addColorStop(1, rgba(o.light, 0));
    cg.fillStyle = gr;
    cg.beginPath(); cg.arc(x, y, rad, 0, Math.PI * 2); cg.fill();
    const sh = cg.createRadialGradient(x - o.sun * rad * 0.45, y + rad * 0.5, rad * 0.1, x, y, rad * 1.1);
    sh.addColorStop(0, rgba(o.shade, o.shadeAlpha));
    sh.addColorStop(1, rgba(o.shade, 0));
    cg.fillStyle = sh;
    cg.beginPath(); cg.arc(x, y, rad, 0, Math.PI * 2); cg.fill();
  }
  if (o.haze) {
    cg.fillStyle = vgrad(cg, minY, base, [[0, rgba(o.haze, 0)], [1, rgba(o.haze, o.hazeAlpha)]]);
    cg.fillRect(0, 0, L.w, L.h);
  }
  g.drawImage(cc, 0, 0);
}

// Soft streaky sky clouds.
export function skyClouds(L, o) {
  const g = L.g, r = rng(o.seed || 21);
  g.save();
  g.filter = `blur(${o.blur || 6}px)`;
  for (let i = 0; i < o.count; i++) {
    const az = o.az0 + r() * (o.az1 - o.az0);
    const el = o.el0 + Math.pow(r(), 1.4) * (o.el1 - o.el0);
    const x = L.X(az), y = L.Y(el);
    const len = o.len * (0.4 + r());
    const th = o.thick * (0.5 + r() * 0.8) * (1 - (el - o.el0) / (o.el1 - o.el0) * 0.4);
    const colT = clamp((el - o.el0) / (o.el1 - o.el0), 0, 1);
    const col = mix(o.lowColor, o.highColor, colT);
    softBlob(g, x, y, len, th, col, o.alpha * (0.5 + r() * 0.5));
    softBlob(g, x + len * 0.1, y + th * 0.25, len * 0.7, th * 0.5, o.underColor || col, o.alpha * 0.8);
  }
  g.restore();
}

// Stylised skyline of towers with lit windows. buildings: [az, widthDeg, heightDeg, type]
export function skyline(L, o) {
  const g = L.g, r = rng(o.seed || 5);
  const baseY = L.Y(o.base);
  const pxd = L.pxPerDeg();
  const vScale = L.h / (L.Y(L.eMin) - L.Y(L.eMax));
  for (const b of o.buildings) {
    const [az, wd, hd, type] = b;
    const x0 = L.X(az) - (wd * pxd) / 2, w = wd * pxd;
    const yTop = L.Y(o.base + hd);
    const hpx = baseY - yTop;
    g.fillStyle = o.color;
    if (type === 'round') {
      g.fillRect(x0, yTop + w * 0.3, w, hpx - w * 0.3 + 2);
      g.beginPath(); g.ellipse(x0 + w / 2, yTop + w * 0.32, w / 2, w * 0.36, 0, Math.PI, 0); g.fill();
    } else if (type === 'spire') {
      g.fillRect(x0, yTop, w, hpx + 2);
      g.fillRect(x0 + w * 0.47, yTop - hpx * 0.18, w * 0.06, hpx * 0.18);
    } else if (type === 'step') {
      g.fillRect(x0, yTop + hpx * 0.12, w, hpx * 0.88 + 2);
      g.fillRect(x0 + w * 0.15, yTop, w * 0.7, hpx * 0.14);
    } else if (type === 'slant') {
      g.beginPath(); g.moveTo(x0, baseY + 2); g.lineTo(x0, yTop + hpx * 0.1); g.lineTo(x0 + w, yTop); g.lineTo(x0 + w, baseY + 2); g.fill();
    } else {
      g.fillRect(x0, yTop, w, hpx + 2);
    }
    // windows
    const cw = Math.max(2, w / Math.max(3, Math.round(w / (o.win * 2.2))));
    const ch = Math.max(2.5, o.win * 1.6 * (vScale / vScale));
    for (let yy = yTop + (type === 'round' ? w * 0.35 : 4) + ch; yy < baseY - ch; yy += ch * 1.7) {
      for (let xx = x0 + cw * 0.4; xx < x0 + w - cw * 0.6; xx += cw) {
        const p = r();
        if (p < o.lit) {
          const warm = r() < o.warm;
          g.fillStyle = warm ? rgba(o.warmColor, 0.55 + r() * 0.45) : rgba(o.coolColor, 0.45 + r() * 0.45);
          g.fillRect(xx, yy, cw * 0.55, ch * 0.75);
        }
      }
    }
    if (type === 'spire' || hd > o.beaconAbove) {
      softBlob(g, x0 + w / 2, yTop - (type === 'spire' ? hpx * 0.18 : 2), 9, 9, '#ff3b30', 0.9);
    }
  }
}
