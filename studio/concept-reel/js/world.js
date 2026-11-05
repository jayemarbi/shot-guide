// The five locations (plus a night variant), each its own THREE.Scene built from painted cylinder cards.
import * as THREE from 'three';
import { Reflector } from 'three/addons/objects/Reflector.js';
import * as P from './paint.js';

const D2R = P.D2R;

export function dirFrom(az, el) {
  const a = az * D2R, e = el * D2R;
  return new THREE.Vector3(Math.sin(a) * Math.cos(e), Math.sin(e), -Math.cos(a) * Math.cos(e));
}

function tex(c) {
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

function card(L, order) {
  const T = L.theta * D2R;
  const start = Math.PI - L.az0 * D2R - T / 2;
  const geo = new THREE.CylinderGeometry(L.R, L.R, L.yTop - L.yBot, 128, 1, true, start, T);
  const uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setX(i, 1 - uv.getX(i));
  const mat = new THREE.MeshBasicMaterial({ map: tex(L.c), transparent: true, side: THREE.BackSide, toneMapped: false, depthWrite: false, fog: false });
  const m = new THREE.Mesh(geo, mat);
  m.position.y = (L.yTop + L.yBot) / 2;
  m.renderOrder = order;
  return m;
}

const SKY_VS = `varying vec3 vDir; void main(){ vDir = normalize((modelMatrix * vec4(position,1.0)).xyz - cameraPosition*0.0); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`;
const SKY_FS = `
uniform float sEl[10]; uniform vec3 sCol[10]; uniform int sN;
uniform vec3 sunDir; uniform vec3 sunCol; uniform vec3 glowCol; uniform float sunSize; uniform float glow; uniform float glowWide;
uniform float stars; uniform float mw; uniform mat3 starRot;
varying vec3 vDir;
float hash(vec3 p){ p = fract(p*0.3183099 + 0.1); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
float vnoise(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f*f*(3.0-2.0*f);
  return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x), mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
             mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x), mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y), f.z); }
void main(){
  vec3 d = normalize(vDir);
  float e = asin(clamp(d.y,-1.0,1.0));
  vec3 col = sCol[0];
  for (int i = 1; i < 10; i++) { if (i >= sN) break; col = mix(col, sCol[i], smoothstep(sEl[i-1], sEl[i], e)); }
  float a = acos(clamp(dot(d, sunDir), -1.0, 1.0));
  col += glowCol * (glow * exp(-a*a/0.004) + glow*0.5*exp(-a*a/0.03) + glowWide * exp(-a*2.2));
  if (sunSize > 0.0) { float disc = 1.0 - smoothstep(sunSize*0.94, sunSize, a); col = mix(col, sunCol, disc); }
  if (stars > 0.0) {
    vec3 sd = starRot * d;
    vec3 p = sd * 260.0; vec3 ip = floor(p); vec3 fp = fract(p);
    float h = hash(ip);
    if (h > 0.972) {
      vec3 sp = vec3(hash(ip+1.7), hash(ip+3.1), hash(ip+5.3))*0.6+0.2;
      float dd = length(fp - sp);
      float b = smoothstep(0.22, 0.0, dd) * (0.35 + 0.65*(h-0.972)/0.028);
      col += mix(vec3(0.75,0.85,1.0), vec3(1.0,0.9,0.75), hash(ip+9.0)) * b * stars * smoothstep(0.02, 0.3, e);
    }
    float band = exp(-pow(dot(sd, normalize(vec3(0.55,0.35,0.76))) / 0.16, 2.0));
    float n = vnoise(sd*5.0)*0.55 + vnoise(sd*11.0)*0.3 + vnoise(sd*27.0)*0.15;
    col += vec3(0.62,0.6,0.9) * band * smoothstep(0.35, 0.9, n) * mw * smoothstep(0.0, 0.35, e);
  }
  gl_FragColor = vec4(col, 1.0);
  #include <colorspace_fragment>
}`;

function sky(o) {
  const stops = o.stops;
  const sEl = new Array(10).fill(3.2), sCol = new Array(10).fill(0).map(() => new THREE.Color('#000'));
  stops.forEach(([el, c], i) => { sEl[i] = el * D2R; sCol[i] = new THREE.Color(c); });
  const u = {
    sEl: { value: sEl }, sCol: { value: sCol }, sN: { value: stops.length },
    sunDir: { value: (o.sun || new THREE.Vector3(0, 0, -1)).clone().normalize() },
    sunCol: { value: new THREE.Color(o.sunCol || '#fff3d6') }, glowCol: { value: new THREE.Color(o.glowCol || '#ffb070') },
    sunSize: { value: (o.sunSize || 0) * D2R }, glow: { value: o.glow || 0 }, glowWide: { value: o.glowWide || 0 },
    stars: { value: o.stars || 0 }, mw: { value: o.mw || 0 }, starRot: { value: new THREE.Matrix3() },
  };
  const mat = new THREE.ShaderMaterial({ uniforms: u, vertexShader: SKY_VS, fragmentShader: SKY_FS, side: THREE.BackSide, depthWrite: false, toneMapped: false });
  const m = new THREE.Mesh(new THREE.SphereGeometry(14000, 64, 32), mat);
  m.renderOrder = -100;
  m.frustumCulled = false;
  m.onBeforeRender = (r, s, cam) => { m.position.copy(cam.position); };
  return m;
}

// Ground texture as a top-down map: canvas top = far (-z).
function groundCanvas(size, o) {
  const [c, g] = P.canvas(size, size);
  const img = g.createImageData(size, size), d = img.data;
  const n = P.noise2(o.seed || 1);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = x / size, v = y / size;
      const a1 = P.fbm2(n, u * o.scale, v * o.scale, 5);
      const a2 = P.fbm2(n, u * o.scale * 5 + 40, v * o.scale * 5 + 40, 3);
      const col = o.color(a1, a2, u, v);
      const dx = u - 0.5, dy = v - 0.5;
      const rr = Math.sqrt(dx * dx + dy * dy) * 2;
      let al = 1;
      if (o.edge) {
        const e = o.edge(Math.atan2(dy, dx), a1);
        const soft = o.soft || 0.025;
        al = P.clamp((e - rr) / soft, 0, 1);
      }
      const i = (y * size + x) * 4;
      d[i] = col[0]; d[i + 1] = col[1]; d[i + 2] = col[2]; d[i + 3] = al * 255;
    }
  }
  g.putImageData(img, 0, 0);
  return [c, g];
}

function groundMesh(c, size, y = 0, order = 1) {
  const t = tex(c);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.MeshBasicMaterial({ map: t, transparent: true, toneMapped: false, depthWrite: true, fog: false }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = y;
  m.renderOrder = order;
  return m;
}

function basePlane(color, size, y = -0.01, order = 0) {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.MeshBasicMaterial({ color, toneMapped: false, fog: false }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = y;
  m.renderOrder = order;
  return m;
}

const lerpc = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
const ledge = (behind, front, wob = 0.05) => (ang, a) => behind + (front - behind) * Math.pow(0.5 + 0.5 * Math.sin(ang), 1.4) + wob * Math.sin(ang * 5 + 1.7) + wob * 0.7 * Math.sin(ang * 11) + (a - 0.5) * wob * 2;
const H = P.hex;

function lights(scene, o) {
  scene.add(new THREE.HemisphereLight(o.hemiSky, o.hemiGround, o.hemi));
  const key = new THREE.DirectionalLight(o.keyColor, o.key);
  key.position.copy(o.keyDir).multiplyScalar(20);
  key.castShadow = o.shadow !== false;
  key.shadow.mapSize.set(2048, 2048);
  const s = o.shadowBox || 4;
  Object.assign(key.shadow.camera, { left: -s, right: s, top: s, bottom: -s, near: 1, far: 60 });
  key.shadow.bias = -0.0004;
  key.shadow.normalBias = 0.02;
  scene.add(key, key.target);
  if (o.fill) {
    const fill = new THREE.DirectionalLight(o.fillColor, o.fill);
    fill.position.copy(o.fillDir).multiplyScalar(20);
    scene.add(fill, fill.target);
  }
}

function shadowCatcher(scene, color, opacity, size = 16) {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.ShadowMaterial({ color, opacity, toneMapped: false, fog: false }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = 0.004;
  m.receiveShadow = true;
  m.renderOrder = 2;
  scene.add(m);
}

function contactBlob(scene, color, opacity) {
  const [c, g] = P.canvas(128, 128);
  const gr = g.createRadialGradient(64, 64, 4, 64, 64, 64);
  gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(0.5, 'rgba(0,0,0,0.55)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
  const t = new THREE.CanvasTexture(c);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(1.25, 0.85), new THREE.MeshBasicMaterial({ map: t, color, transparent: true, opacity, depthWrite: false, toneMapped: false, fog: false }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = 0.006;
  m.renderOrder = 3;
  scene.add(m);
  return m;
}

function boulder(seed, color, scale) {
  const geo = new THREE.IcosahedronGeometry(1, 2);
  const n = P.noise2(seed);
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const v = new THREE.Vector3().fromBufferAttribute(p, i);
    const k = 0.75 + 0.45 * P.fbm2(n, v.x * 1.3 + 5, v.z * 1.3 + v.y * 0.7 + 5, 3);
    v.multiplyScalar(k);
    v.y *= 0.62;
    p.setXYZ(i, v.x, v.y, v.z);
  }
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color, roughness: 0.95, flatShading: true }));
  m.scale.setScalar(scale);
  m.castShadow = true; m.receiveShadow = true;
  return m;
}

const PINE = {
  geo: new THREE.ConeGeometry(1, 1, 9, 1), green: new THREE.MeshStandardMaterial({ color: '#1f3a35', roughness: 0.95, flatShading: true }),
  snow: new THREE.MeshStandardMaterial({ color: '#f4f7fb', roughness: 0.85, flatShading: true }), trunk: new THREE.MeshStandardMaterial({ color: '#3b2c28', roughness: 1 }),
};
function pine3D(h, r) {
  const g = new THREE.Group();
  const tr = new THREE.Mesh(new THREE.CylinderGeometry(h * 0.025, h * 0.035, h * 0.2, 6), PINE.trunk);
  tr.position.y = h * 0.1; g.add(tr);
  const tiers = 5;
  for (let i = 0; i < tiers; i++) {
    const t = i / tiers;
    const rad = h * 0.27 * (1 - t * 0.78), th = h * 0.3 * (1 - t * 0.25);
    const y = h * (0.14 + t * 0.7) + th * 0.5;
    const c = new THREE.Mesh(PINE.geo, PINE.green);
    c.scale.set(rad, th, rad); c.position.y = y; c.rotation.y = r() * 6.28; c.castShadow = true;
    const s = new THREE.Mesh(PINE.geo, PINE.snow);
    s.scale.set(rad * 0.86, th * 0.52, rad * 0.86); s.position.y = y + th * 0.26; s.rotation.y = r() * 6.28;
    g.add(c, s);
  }
  return g;
}

function bareTree(g, x, y, h, r) {
  const branch = (x0, y0, ang, len, w, d) => {
    const x1 = x0 + Math.cos(ang) * len, y1 = y0 + Math.sin(ang) * len;
    g.lineWidth = Math.max(0.7, w);
    g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
    if (d >= 6 || len < 2.5) return;
    const k = 2 + (r() < 0.35 ? 1 : 0);
    for (let i = 0; i < k; i++) {
      const a = ang + (r() - 0.5) * 0.9 + (i - (k - 1) / 2) * 0.42;
      branch(x1, y1, a, len * (0.66 + r() * 0.14), w * 0.66, d + 1);
    }
  };
  g.lineCap = 'round';
  branch(x, y, -Math.PI / 2 + (r() - 0.5) * 0.1, h * 0.34, h * 0.04, 0);
}

// ---------------------------------------------------------------- Red Rocks, golden hour
function redRocks() {
  const scene = new THREE.Scene();
  const sunDir = dirFrom(200, 9);
  scene.add(sky({ stops: [[-12, '#7a7bac'], [-1, '#8a8abb'], [2.5, '#a59dc8'], [8, '#ddb1c4'], [15, '#ebbfc7'], [28, '#c5bddb'], [55, '#8fa8d6'], [90, '#6c8bc6']], sun: sunDir, glowWide: 0.03, glowCol: '#ffd8b0' }));

  const far = new P.Layer({ R: 3000, theta: 110, eMin: -9, eMax: 3, w: 4096, h: 1024 });
  const nf = P.noise1(11);
  P.mountains(far, { elev: (az) => -2.05 + P.fbm1(nf, az * 0.12, 4) * 0.1, body: [[0, '#b7a4cb'], [0.12, '#9a8bb4'], [1, '#6c6286']], seed: 11, step: 3 });
  P.skyline(far, {
    base: -2.08, color: '#9089b0', win: 0.8, lit: 0, warm: 0, beaconAbove: 99, seed: 4,
    buildings: [[4.6, 0.12, 0.22], [4.8, 0.1, 0.38], [4.95, 0.08, 0.3, 'round'], [5.1, 0.1, 0.5], [5.25, 0.12, 0.42], [5.4, 0.08, 0.26], [5.55, 0.1, 0.33], [5.75, 0.14, 0.2], [4.35, 0.14, 0.15], [6.0, 0.16, 0.14]],
  });
  far.g.fillStyle = P.vgrad(far.g, far.Y(-1.4), far.Y(-3.6), [[0, 'rgba(233,190,205,0)'], [0.5, 'rgba(233,190,205,0.45)'], [1, 'rgba(233,190,205,0)']]);
  far.g.globalCompositeOperation = 'source-atop';
  far.g.fillRect(0, 0, far.w, far.h);
  far.g.globalCompositeOperation = 'source-over';
  scene.add(card(far, -50));

  const mid = new P.Layer({ R: 700, theta: 150, eMin: -28, eMax: 0, w: 4096, h: 1536 });
  const n2 = P.noise1(12), n3 = P.noise1(13), n4 = P.noise1(14);
  P.mountains(mid, { elev: (az) => -3.2 + P.fbm1(n2, az * 0.07, 4) * 0.8 + Math.max(0, 1 - Math.abs(az + 30) / 25) * 0.9, body: [[0, '#a2716f'], [0.3, '#82646f'], [1, '#5e4b5a']], seed: 12, rim: { color: '#ffc39a', width: 2, alpha: 0.55, sun: -1 }, haze: { top: -3, bottom: -7, color: '#b9a3c6', alpha: 0.45 } });
  const p3 = P.mountains(mid, { elev: (az) => -5.4 + P.fbm1(n3, az * 0.09, 5) * 1.3, body: [[0, '#7a6458'], [1, '#463a40']], seed: 13, rim: { color: '#ffbb8e', width: 2, alpha: 0.5, sun: -1 }, haze: { top: -5.5, bottom: -10, color: '#a990b5', alpha: 0.4 } });
  P.forest(mid, p3, { spacing: 5, height: 9, color: '#3a3b33', seed: 31, sink: 3 });
  const p4 = P.mountains(mid, { elev: (az) => -9 + P.fbm1(n4, az * 0.11, 5) * 2.2, body: [[0, '#5d4a40'], [1, '#2f262a']], seed: 14, rim: { color: '#ffb080', width: 2.5, alpha: 0.55, sun: -1 } });
  P.forest(mid, p4, { spacing: 7, height: 16, color: '#2d3129', seed: 32, sink: 6 });
  P.grain(mid, 0.06, 3);
  scene.add(card(mid, -40));

  // the two big sandstone fins either side of the view
  const fin = (az0, poly, seed, light) => {
    const L = new P.Layer({ R: 70, theta: 70, eMin: -40, eMax: 46, w: 2048, h: 3072, az0 });
    const g = L.g, r = P.rng(seed), n = P.noise1(seed);
    const pts = [];
    for (let i = 0; i < poly.length; i++) {
      const [a0, e0] = poly[i], [a1, e1] = poly[(i + 1) % poly.length];
      const steps = 40;
      for (let s = 0; s < steps; s++) {
        const t = s / steps;
        const a = a0 + (a1 - a0) * t, e = e0 + (e1 - e0) * t;
        const len = Math.hypot(a1 - a0, e1 - e0);
        const nx = -(e1 - e0) / len, ny = (a1 - a0) / len;
        const k = P.fbm1(n, (i * 7 + t * len * 0.35), 4) * 0.9;
        pts.push([L.X(a + nx * k), L.Y(e + ny * k)]);
      }
    }
    g.save();
    g.beginPath(); pts.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); g.closePath();
    g.fillStyle = P.vgrad(g, L.Y(40), L.Y(-38), [[0, '#f29152'], [0.3, '#dc6c3c'], [0.62, '#a8452c'], [1, '#5c2219']]);
    g.fill();
    g.clip();
    // the slab's thickness: a darker face along the inner edge
    g.fillStyle = P.vgrad(g, L.Y(40), L.Y(-38), [[0, '#9a3f33'], [0.5, '#6e2a2a'], [1, '#3a1518']]);
    g.beginPath();
    const inner = light.inner;
    inner.forEach(([a, e], i) => { const x = L.X(a), y = L.Y(e); if (i) g.lineTo(x, y); else g.moveTo(x, y); });
    for (let i = inner.length - 1; i >= 0; i--) { const [a, e] = inner[i]; g.lineTo(L.X(a - light.dir * light.thick * (0.6 + 0.4 * Math.sin(i))), L.Y(e)); }
    g.closePath();
    g.fill();
    // strata following the tilt of the slab
    g.globalCompositeOperation = 'multiply';
    for (let k = 0; k < 70; k++) {
      const el = -40 + k * 1.3 + r() * 0.8;
      g.strokeStyle = r() < 0.5 ? 'rgba(150,60,40,0.55)' : 'rgba(120,40,30,0.4)';
      g.lineWidth = 1 + r() * 4;
      g.beginPath();
      for (let x = -20; x <= L.w + 20; x += 12) {
        const az = L.AZ(x);
        const y = L.Y(el + (az - az0) * light.tilt + P.fbm1(n, az * 0.2 + k * 3.1, 3) * 0.6);
        if (x < 0) g.moveTo(x, y); else g.lineTo(x, y);
      }
      g.stroke();
    }
    // shadowed inner face
    const sx = L.X(light.edgeAz);
    const sg = g.createLinearGradient(sx, 0, sx + light.dir * 260, 0);
    sg.addColorStop(0, 'rgba(90,50,90,0.55)'); sg.addColorStop(0.6, 'rgba(140,80,100,0.18)'); sg.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = sg;
    g.fillRect(0, 0, L.w, L.h);
    // vertical cracks
    for (let k = 0; k < 30; k++) {
      const x = r() * L.w, y = L.Y(-10 + r() * 45);
      g.strokeStyle = 'rgba(90,30,25,0.5)'; g.lineWidth = 1 + r() * 2;
      g.beginPath(); g.moveTo(x, y);
      let xx = x, yy = y;
      for (let j = 0; j < 10; j++) { xx += (r() - 0.5) * 8; yy += 14 + r() * 20; g.lineTo(xx, yy); }
      g.stroke();
    }
    g.globalCompositeOperation = 'source-over';
    // warm glow from the low sun on the upper face
    g.fillStyle = P.vgrad(g, L.Y(42), L.Y(5), [[0, 'rgba(255,190,120,0.35)'], [1, 'rgba(255,190,120,0)']]);
    g.globalCompositeOperation = 'screen';
    g.fillRect(0, 0, L.w, L.h);
    g.globalCompositeOperation = 'source-over';
    // junipers on ledges near the base
    for (let k = 0; k < 90; k++) {
      const az = az0 + (r() - 0.5) * 70, el = -38 + Math.pow(r(), 1.6) * 40;
      const x = L.X(az), y = L.Y(el);
      const s = 6 + r() * 16;
      g.fillStyle = r() < 0.5 ? '#2f3a26' : '#3c4a2e';
      for (let j = 0; j < 4; j++) { g.beginPath(); g.ellipse(x + (r() - 0.5) * s, y + (r() - 0.5) * s * 0.4, s * (0.5 + r() * 0.4), s * (0.35 + r() * 0.25), 0, 0, Math.PI * 2); g.fill(); }
    }
    g.restore();
    // bright rim along the top edge
    g.strokeStyle = 'rgba(255,214,160,0.75)'; g.lineWidth = 3;
    g.beginPath();
    let started = false;
    for (const [x, y] of pts) {
      if (L.EL(y) > light.rimFrom) { if (!started) { g.moveTo(x, y); started = true; } else g.lineTo(x, y); } else started = false;
    }
    g.stroke();
    P.grain(L, 0.08, seed);
    return card(L, -20);
  };
  scene.add(fin(-42, [[-78, -40], [-78, 8], [-62, 14], [-47, 21], [-33, 29], [-24, 32], [-17.5, 30], [-12.5, 21], [-9.6, 7], [-8.2, -6], [-7.6, -40]], 41,
    { tilt: 0.12, edgeAz: -8, dir: -1, rimFrom: 4, thick: 2.6, inner: [[-17.5, 30], [-12.5, 21], [-9.6, 7], [-8.2, -6], [-7.6, -40]] }));
  scene.add(fin(42, [[6.8, -40], [7.6, -9], [9.0, 5], [11.4, 19], [14.4, 29], [18.2, 35.5], [24.5, 37.5], [32, 33], [47, 23], [78, 13], [78, -40]], 42,
    { tilt: -0.1, edgeAz: 7.2, dir: 1, rimFrom: 4, thick: 3.2, inner: [[18.2, 35.5], [14.4, 29], [11.4, 19], [9.0, 5], [7.6, -9], [6.8, -40]] }));

  const [gc] = groundCanvas(1024, {
    seed: 5, scale: 9,
    color: (a, b, u, v) => {
      let c = lerpc(H('#c46a40'), H('#94442a'), P.smooth(0.3, 0.8, a));
      c = lerpc(c, H('#de8a55'), P.smooth(0.6, 0.85, b) * 0.45);
      const strata = 0.5 + 0.5 * Math.sin((v * 60 + a * 6));
      c = lerpc(c, H('#7f3522'), P.smooth(0.85, 1, strata) * 0.35);
      const rr = Math.hypot(u - 0.5, v - 0.5) * 2;
      c = lerpc(c, H('#6d2c1d'), P.smooth(0.18, 0.3, rr) * (v < 0.5 ? 0.35 : 0) * P.smooth(0.5, 0.2, v));
      return c;
    },
    edge: ledge(0.3, 0.9, 0.04),
  });
  scene.add(groundMesh(gc, 30, 0, 1));
  const b1 = boulder(71, '#3c4a2e', 0.6); b1.position.set(-3.4, 0.1, -2.4); scene.add(b1);
  const b2 = boulder(72, '#33402a', 0.45); b2.position.set(2.9, 0.05, -3.0); scene.add(b2);
  const b3 = boulder(73, '#a24e2e', 0.9); b3.position.set(4.6, 0.0, 1.5); scene.add(b3);
  const b4 = boulder(74, '#9a4a2c', 0.7); b4.position.set(-4.4, 0.0, 3.2); scene.add(b4);

  const key = dirFrom(200, 11);
  lights(scene, { hemiSky: '#a9b4e0', hemiGround: '#a0583a', hemi: 0.9, keyColor: '#ffc690', key: 3.2, keyDir: key, fill: 0.5, fillColor: '#c9b6ff', fillDir: dirFrom(20, 20), shadowBox: 5 });
  shadowCatcher(scene, '#3d1830', 0.5, 26);
  const blob = contactBlob(scene, '#2a0f10', 0.45);
  return { name: 'redrocks', scene, sunDir: key, rim: { color: '#ffd2a0', strength: 0.55 }, glow: null, blob, update() {} };
}

// ---------------------------------------------------------------- Snowy pine forest, snowing
function forest() {
  const scene = new THREE.Scene();
  const sunDir = dirFrom(-24, 17);
  scene.add(sky({ stops: [[-6, '#dfe6ee'], [0, '#e7edf3'], [7, '#dce4ed'], [22, '#c6d2e0'], [55, '#b0c0d5'], [90, '#a2b4cb']], sun: sunDir, glow: 0.35, glowWide: 0.18, glowCol: '#fff4e0' }));

  const far = new P.Layer({ R: 5000, theta: 120, eMin: -2, eMax: 12, w: 4096, h: 1024 });
  const nf = P.noise1(21);
  P.mountains(far, {
    elev: (az) => 2.2 + P.ridged1(nf, az * 0.05 + 3, 5) * 7.5 - 2.5, body: [[0, '#f1f4f9'], [1, '#d7deea']], seed: 21,
    facets: { sun: -1, color: '#aeb9d2', alpha: 0.9, minProm: 10, minGap: 50, slant: 0.3 },
    haze: { top: 6, bottom: -0.5, color: '#e3e9f0', alpha: 0.75 }, wash: { color: '#e3e9f0', alpha: 0.12 },
  });
  scene.add(card(far, -50));

  const m1 = new P.Layer({ R: 1100, theta: 130, eMin: -3, eMax: 8, w: 4096, h: 1024 });
  const n1 = P.noise1(22);
  const r1 = P.mountains(m1, { elev: (az) => 1.4 + P.fbm1(n1, az * 0.06, 4) * 1.4, body: [[0, '#b7c3d1'], [1, '#c9d2dd']], seed: 22 });
  P.forest(m1, r1, { spacing: 5, height: 18, color: '#8a9bae', snow: '#e4eaf2', seed: 23, sink: 4 });
  m1.g.fillStyle = P.vgrad(m1.g, m1.Y(2.5), m1.Y(-0.5), [[0, 'rgba(230,236,242,0.15)'], [1, 'rgba(230,236,242,0.85)']]);
  m1.g.globalCompositeOperation = 'source-atop'; m1.g.fillRect(0, 0, m1.w, m1.h); m1.g.globalCompositeOperation = 'source-over';
  scene.add(card(m1, -45));

  const m2 = new P.Layer({ R: 320, theta: 140, eMin: -6, eMax: 15, w: 4096, h: 1536 });
  const n2 = P.noise1(24);
  const r2 = P.mountains(m2, { elev: (az) => 0.9 + P.fbm1(n2, az * 0.07, 4) * 1.1, body: [[0, '#6f8291'], [1, '#8798a8']], seed: 24 });
  P.forest(m2, r2, { spacing: 10, height: 85, color: '#4b616d', snow: '#eef3f8', seed: 25, sink: 10 });
  m2.g.fillStyle = P.vgrad(m2.g, m2.Y(6), m2.Y(-0.5), [[0, 'rgba(230,236,242,0.05)'], [1, 'rgba(230,236,242,0.7)']]);
  m2.g.globalCompositeOperation = 'source-atop'; m2.g.fillRect(0, 0, m2.w, m2.h); m2.g.globalCompositeOperation = 'source-over';
  scene.add(card(m2, -40));

  const near = (az0, trees, seed) => {
    const L = new P.Layer({ R: 24, theta: 64, eMin: -12, eMax: 58, w: 2048, h: 3072, az0 });
    const r = P.rng(seed);
    for (const [az, hgt] of trees) {
      const x = L.X(az), y = L.Y(-3.4), top = L.Y(Math.atan(hgt / 24) / D2R);
      P.pine(L.g, x, y, y - top, '#21363b', '#f3f6fa', r);
    }
    L.g.fillStyle = P.vgrad(L.g, L.Y(10), L.Y(-4), [[0, 'rgba(225,232,240,0)'], [1, 'rgba(225,232,240,0.35)']]);
    L.g.globalCompositeOperation = 'source-atop'; L.g.fillRect(0, 0, L.w, L.h); L.g.globalCompositeOperation = 'source-over';
    return card(L, -20);
  };
  scene.fog = new THREE.Fog('#e4eaf1', 9, 75);
  const pr = P.rng(28);
  const spots = [[-3.6, 1.2, 7], [3.9, 0.4, 8.5], [-5.2, -4.5, 10], [5.6, -6, 11], [-2.6, -12, 9], [7.5, -14, 13], [-8, -10, 12], [-12, -20, 14], [11, -22, 12],
    [-4.5, -26, 13], [3.5, -30, 11], [-16, -34, 15], [15, -36, 14], [-24, -42, 16], [22, -45, 15], [0.5, -48, 13], [-9, -52, 14], [9, -56, 15],
    [-30, -18, 15], [28, -16, 14], [-6.5, 4.5, 9], [7, 5, 10], [-20, -6, 12], [19, -4, 13], [-34, -50, 16], [32, -58, 15]];
  for (const [x, z, h] of spots) { const t = pine3D(h * (0.85 + pr() * 0.3), pr); t.position.set(x, 0, z); scene.add(t); }

  scene.add(basePlane('#e8edf4', 1200, -0.01, 0));
  const [gc] = groundCanvas(1024, {
    seed: 6, scale: 6,
    color: (a, b) => {
      let c = lerpc(H('#f4f7fb'), H('#d3dcea'), P.smooth(0.4, 0.8, a));
      c = lerpc(c, H('#ffffff'), P.smooth(0.7, 0.9, b) * 0.6);
      return c;
    },
    edge: () => 0.95, soft: 0.25,
  });
  scene.add(groundMesh(gc, 30, 0, 1));

  // falling snow
  const N = 3200, pos = new Float32Array(N * 3), seeds = [];
  const r = P.rng(77);
  for (let i = 0; i < N; i++) seeds.push([r() * 22 - 11, r() * 9, r() * 26 - 18, 0.6 + r() * 0.9, r() * 6.28, 0.2 + r() * 0.5]);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  const [fc, fg] = P.canvas(64, 64);
  const fgr = fg.createRadialGradient(32, 32, 2, 32, 32, 30);
  fgr.addColorStop(0, 'rgba(255,255,255,1)'); fgr.addColorStop(0.4, 'rgba(255,255,255,0.8)'); fgr.addColorStop(1, 'rgba(255,255,255,0)');
  fg.fillStyle = fgr; fg.fillRect(0, 0, 64, 64);
  const flakes = new THREE.Points(geo, new THREE.PointsMaterial({ size: 0.1, map: new THREE.CanvasTexture(fc), transparent: true, depthWrite: false, toneMapped: false, color: '#ffffff', opacity: 0.95 }));
  flakes.renderOrder = 10;
  flakes.frustumCulled = false;
  scene.add(flakes);

  lights(scene, { hemiSky: '#e9eef8', hemiGround: '#d9e2ee', hemi: 1.6, keyColor: '#fff3e2', key: 1.3, keyDir: dirFrom(-24, 30), fill: 0.8, fillColor: '#dfe8ff', fillDir: dirFrom(160, 25), shadowBox: 4 });
  shadowCatcher(scene, '#5a6a8a', 0.22, 16);
  const blob = contactBlob(scene, '#55627e', 0.35);
  return {
    name: 'forest', scene, sunDir, rim: { color: '#ffffff', strength: 0.35 }, glow: null, blob,
    update(t, speed = 1) {
      const tt = t * speed;
      for (let i = 0; i < N; i++) {
        const [x, y, z, v, ph, sw] = seeds[i];
        pos[i * 3] = x + Math.sin(tt * 0.9 + ph) * sw;
        pos[i * 3 + 1] = ((y - tt * v) % 9 + 9) % 9;
        pos[i * 3 + 2] = z + Math.cos(tt * 0.7 + ph) * sw * 0.5;
      }
      geo.attributes.position.needsUpdate = true;
    },
  };
}

// ---------------------------------------------------------------- Alpine lake at sunrise, mirror reflection
const WaterShader = {
  name: 'LakeWater',
  uniforms: { color: { value: null }, tDiffuse: { value: null }, textureMatrix: { value: null }, time: { value: 0 }, tint: { value: new THREE.Color('#2e3d52') }, ripple: { value: 0.012 } },
  vertexShader: `uniform mat4 textureMatrix; varying vec4 vUv; varying vec3 vWorld;
    void main(){ vUv = textureMatrix * vec4(position,1.0); vWorld = (modelMatrix*vec4(position,1.0)).xyz; gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
  fragmentShader: `uniform sampler2D tDiffuse; uniform float time; uniform vec3 tint; uniform float ripple; varying vec4 vUv; varying vec3 vWorld;
    float w(vec2 p){ return sin(p.x*1.9 + time*1.2)*0.5 + sin(p.y*2.7 - time*0.9 + p.x*0.6)*0.35 + sin((p.x-p.y)*5.3 + time*1.9)*0.15; }
    void main(){
      float d = length(vWorld.xz - cameraPosition.xz);
      vec2 off = vec2(w(vWorld.xz*0.9), w(vWorld.zx*1.1 + 3.0)) * ripple / (1.0 + d*0.08);
      vec4 uv = vUv; uv.xy += off * uv.w;
      vec3 refl = texture2DProj(tDiffuse, uv).rgb;
      vec3 V = normalize(cameraPosition - vWorld);
      float fres = 0.55 + 0.45*pow(1.0 - max(V.y, 0.0), 4.0);
      vec3 col = mix(tint, refl * 0.92, fres);
      gl_FragColor = vec4(col, 1.0);
      #include <colorspace_fragment>
    }`,
};

function lake() {
  const scene = new THREE.Scene();
  const sunDir = dirFrom(150, 6);
  scene.add(sky({ stops: [[-6, '#f3c6b2'], [0, '#ffdcbc'], [2.5, '#ffd0bd'], [7, '#f0bac6'], [16, '#d2bedd'], [34, '#a8b8e1'], [70, '#88a5da'], [90, '#7998d2']], sun: sunDir, glowWide: 0.03, glowCol: '#ffd7b8' }));

  const far = new P.Layer({ R: 6000, theta: 100, eMin: -3, eMax: 17, w: 4096, h: 1536 });
  const nf = P.noise1(31);
  const pyr = (az, c, h, s) => h - Math.abs(az - c) * s;
  P.mountains(far, {
    elev: (az) => Math.max(3.8 + P.fbm1(nf, az * 0.08, 4) * 1.6, pyr(az, -3.4, 13.4, 2.3), pyr(az, 2.9, 12.1, 2.5), pyr(az, -13, 8.6, 1.5), pyr(az, 12.5, 7.9, 1.4)) + P.fbm1(nf, az * 0.9 + 9, 3) * 0.35,
    body: [[0, '#f19a85'], [0.3, '#bd7276'], [0.62, '#7a5874'], [1, '#4d4767']], seed: 31,
    snow: { color: '#ffe8de', line: 6, k: 0.22, base: 0.5, freq: 1.3, jitter: 0.6, streaks: 45 },
    bands: { at: [5.6, 7.1, 8.8], color: '#8a5a70', width: 3, alpha: 0.18, wave: 0.35 },
    facets: { sun: 1, color: '#8a84b8', alpha: 0.85, minProm: 18, minGap: 60, slant: 0.42, jag: 18 },
    rim: { color: '#ffd8bd', width: 2, alpha: 0.7, sun: 1 },
    haze: { top: 3.5, bottom: -1, color: '#ffd9ca', alpha: 0.6 },
  });
  P.grain(far, 0.05, 31);
  scene.add(card(far, -50));

  const mid = new P.Layer({ R: 1800, theta: 130, eMin: -4, eMax: 8, w: 4096, h: 1024 });
  const nm = P.noise1(32);
  const rm = P.mountains(mid, { elev: (az) => Math.min(6, 0.15 + Math.max(0, Math.abs(az) - 6.5) * 0.17 + P.fbm1(nm, az * 0.1, 4) * 0.35), body: [[0, '#38534e'], [1, '#22332f']], seed: 32, rim: { color: '#ffcfaa', width: 1.5, alpha: 0.4, sun: 1 } });
  P.forest(mid, rm, { spacing: 4, height: 14, color: '#22382f', snow: '#cfd9d6', seed: 33, sink: 6 });
  const r = P.rng(34);
  for (let k = 0; k < 160; k++) {
    const az = (r() < 0.5 ? -1 : 1) * (8 + r() * 50), x = mid.X(az);
    const i = Math.round((x - rm[0][0]) / 2);
    if (i < 0 || i >= rm.length) continue;
    const y = rm[i][1] + 6 + r() * 30;
    mid.g.fillStyle = r() < 0.6 ? 'rgba(214,190,160,0.75)' : 'rgba(190,170,150,0.6)';
    mid.g.fillRect(x, y, 1.2, 6 + r() * 10);
  }
  mid.g.fillStyle = P.vgrad(mid.g, mid.Y(1.2), mid.Y(-0.2), [[0, 'rgba(255,228,214,0)'], [1, 'rgba(255,228,214,0.45)']]);
  mid.g.globalCompositeOperation = 'source-atop'; mid.g.fillRect(0, 0, mid.w, mid.h); mid.g.globalCompositeOperation = 'source-over';
  scene.add(card(mid, -45));

  const mist = new P.Layer({ R: 500, theta: 120, eMin: -2, eMax: 2, w: 2048, h: 256 });
  P.skyClouds(mist, { count: 30, az0: -60, az1: 60, el0: -0.4, el1: 0.5, len: 130, thick: 9, lowColor: '#fff2ea', highColor: '#fff2ea', alpha: 0.4, blur: 8, seed: 35 });
  scene.add(card(mist, -30));

  const water = new Reflector(new THREE.PlaneGeometry(8000, 8000), { textureWidth: 768, textureHeight: 1366, clipBias: 0.003, shader: WaterShader });
  water.rotation.x = -Math.PI / 2;
  water.position.y = -0.09;
  water.material.toneMapped = false;
  water.renderOrder = -35;
  scene.add(water);

  const [gc] = groundCanvas(1024, {
    seed: 8, scale: 9,
    color: (a, b, u, v) => {
      let c = lerpc(H('#8f8b8f'), H('#5d5a62'), P.smooth(0.3, 0.75, a));
      c = lerpc(c, H('#b7aca6'), P.smooth(0.65, 0.9, b) * 0.6);
      const rr = Math.hypot(u - 0.5, v - 0.5) * 2;
      c = lerpc(c, H('#3a3a44'), P.smooth(0.5, 0.66, rr) * 0.6);
      return c;
    },
    edge: (ang, a) => 0.62 + 0.08 * Math.sin(ang * 2 + 0.4) + 0.06 * Math.sin(ang * 5 + 2) + (a - 0.5) * 0.15, soft: 0.02,
  });
  scene.add(groundMesh(gc, 10, 0, 1));
  const bA = boulder(81, '#8b8790', 1.0); bA.position.set(-2.8, -0.1, -1.6); scene.add(bA);
  const bB = boulder(82, '#7d7a84', 0.65); bB.position.set(2.5, -0.12, -3.2); scene.add(bB);
  const bC = boulder(83, '#94909a', 0.5); bC.position.set(-1.6, -0.12, 2.3); scene.add(bC);
  const bD = boulder(84, '#86828c', 0.38); bD.position.set(1.9, -0.1, 0.9); scene.add(bD);

  lights(scene, { hemiSky: '#c9cfee', hemiGround: '#6c6f7a', hemi: 1.0, keyColor: '#ffcba8', key: 2.6, keyDir: dirFrom(150, 14), fill: 0.45, fillColor: '#b4c2ff', fillDir: dirFrom(-30, 25), shadowBox: 4 });
  shadowCatcher(scene, '#3a3550', 0.42, 10);
  const blob = contactBlob(scene, '#2a2732', 0.4);
  return {
    name: 'lake', scene, sunDir: dirFrom(150, 14), rim: { color: '#ffd9c0', strength: 0.4 }, glow: null, blob,
    update(t) { water.material.uniforms.time.value = t; },
  };
}

// ---------------------------------------------------------------- Denver skyline at blue hour
function city() {
  const scene = new THREE.Scene();
  const glowDir = dirFrom(6, -2);
  const skyM = sky({ stops: [[-6, '#1b2142'], [-0.6, '#9b5a5c'], [0.5, '#ec9670'], [2.0, '#d9806f'], [4.5, '#946d92'], [10, '#51619f'], [22, '#2c4185'], [45, '#1d2c66'], [90, '#121b46']], sun: glowDir, glow: 0.12, glowWide: 0.09, glowCol: '#ff9466', stars: 0.35 });
  scene.add(skyM);

  const clouds = new P.Layer({ R: 4000, theta: 160, eMin: 2, eMax: 40, w: 4096, h: 1536 });
  P.skyClouds(clouds, { count: 30, az0: -80, az1: 80, el0: 4, el1: 30, len: 220, thick: 12, lowColor: '#b07a90', highColor: '#3d4c86', underColor: '#e48f7e', alpha: 0.5, blur: 6, seed: 41 });
  const cloudCard = card(clouds, -60);
  scene.add(cloudCard);

  const far = new P.Layer({ R: 9000, theta: 110, eMin: -1, eMax: 4, w: 4096, h: 768 });
  const nf = P.noise1(42);
  P.mountains(far, { elev: (az) => 0.9 + P.ridged1(nf, az * 0.07 + 2, 5) * 1.3 - 0.3 + Math.max(0, 1 - Math.abs(az + 14) / 6) * 0.7, body: [[0, '#30335f'], [1, '#3c3e6c']], seed: 42, rim: { color: '#ff9f78', width: 1.5, alpha: 0.4, all: true }, haze: { top: 0.8, bottom: -0.6, color: '#8a6a8a', alpha: 0.55 } });
  scene.add(card(far, -50));

  const sk = new P.Layer({ R: 2600, theta: 90, eMin: -1.5, eMax: 8.5, w: 4096, h: 1024 });
  P.softBlob(sk.g, sk.X(2), sk.Y(0.3), 900, 90, '#ff9c6a', 0.35);
  P.skyline(sk, {
    base: -0.2, color: '#121831', win: 1.6, lit: 0.42, warm: 0.7, warmColor: '#ffd590', coolColor: '#c2d8ff', beaconAbove: 4.8, seed: 43,
    buildings: [
      [-9.5, 0.6, 1.2], [-8.6, 0.9, 1.7], [-7.5, 0.7, 2.3], [-6.6, 1.0, 1.5], [-5.6, 0.8, 2.8, 'step'], [-4.6, 0.7, 2.2], [-3.8, 0.9, 3.4],
      [-2.9, 0.6, 2.6, 'slant'], [-2.0, 0.85, 4.1], [-1.25, 0.55, 3.7, 'spire'], [-0.4, 0.95, 5.5], [0.55, 0.8, 4.6, 'step'],
      [1.55, 1.05, 4.8, 'round'], [2.55, 0.85, 5.3], [3.4, 0.6, 3.6, 'slant'], [4.2, 0.9, 4.2], [5.1, 0.7, 2.9], [5.9, 0.9, 3.4, 'step'],
      [6.9, 0.8, 2.3], [7.8, 1.0, 1.8], [8.9, 0.7, 2.5], [9.8, 0.9, 1.4], [10.8, 1.2, 1.1], [-10.8, 1.1, 0.9], [12, 1.4, 0.8], [-12.2, 1.4, 0.7],
    ],
  });
  scene.add(card(sk, -45));

  const park = new P.Layer({ R: 280, theta: 150, eMin: -4, eMax: 12, w: 4096, h: 1024 });
  const pg = park.g, r = P.rng(44);
  pg.fillStyle = '#0c1126';
  pg.fillRect(0, park.Y(-0.05), park.w, park.h);
  pg.strokeStyle = '#0c1126';
  for (let k = 0; k < 34; k++) {
    const side = k % 2 ? 1 : -1;
    const az = side * (13 + r() * 60);
    bareTree(pg, park.X(az), park.Y(0), park.Y(0) - park.Y(4 + r() * 4.5), r);
  }
  for (let k = 0; k < 18; k++) {
    const az = (r() - 0.5) * 140;
    if (Math.abs(az) < 8) continue;
    const x = park.X(az), y = park.Y(0.5 + r() * 0.4);
    P.softBlob(pg, x, y, 18, 18, '#ffbf73', 0.75);
    P.softBlob(pg, x, y, 4, 4, '#fff1d0', 1);
  }
  scene.add(card(park, -30));

  scene.add(basePlane('#121925', 900, -0.01, 0));
  const lampX = -1.35, lampZ = 0.45;
  const [gc] = groundCanvas(1024, {
    seed: 9, scale: 8,
    color: (a, b, u, v) => {
      let c = lerpc(H('#1c2633'), H('#111823'), P.smooth(0.35, 0.75, a));
      const px = (u - 0.5) * 16, pz = (v - 0.5) * 16;
      const path = Math.abs(px - Math.sin(pz * 0.35) * 1.2 - 0.6);
      if (path < 0.75) c = lerpc(c, H('#4f4a4d'), P.smooth(0.75, 0.6, path) * 0.85);
      const dl = Math.hypot(px - lampX, pz - lampZ);
      c = lerpc(c, H('#c89260'), Math.exp(-dl * dl / 3.2) * 0.55);
      return c;
    },
    edge: () => 0.96, soft: 0.2,
  });
  scene.add(groundMesh(gc, 16, 0, 1));

  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, 2.7, 12), new THREE.MeshStandardMaterial({ color: '#15161c', roughness: 0.6, metalness: 0.3 }));
  pole.position.set(lampX, 1.35, lampZ);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.15, 20, 14), new THREE.MeshBasicMaterial({ color: '#fff0d0', toneMapped: false }));
  head.position.set(lampX, 2.78, lampZ);
  const [lc, lg] = P.canvas(128, 128);
  const lgr = lg.createRadialGradient(64, 64, 2, 64, 64, 64);
  lgr.addColorStop(0, 'rgba(255,214,150,0.9)'); lgr.addColorStop(0.25, 'rgba(255,180,110,0.35)'); lgr.addColorStop(1, 'rgba(255,170,100,0)');
  lg.fillStyle = lgr; lg.fillRect(0, 0, 128, 128);
  const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(lc), blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
  halo.scale.set(2.2, 2.2, 1);
  halo.position.copy(head.position);
  halo.renderOrder = 20;
  const lamp = new THREE.PointLight('#ffb36b', 26, 0, 2);
  lamp.position.set(lampX, 2.6, lampZ + 0.2);
  scene.add(pole, head, halo, lamp);

  lights(scene, { hemiSky: '#55689f', hemiGround: '#1e232d', hemi: 0.75, keyColor: '#9db8ff', key: 0.5, keyDir: dirFrom(12, 20), shadow: false, fill: 0.3, fillColor: '#ffb47a', fillDir: dirFrom(150, 30) });
  const blob = contactBlob(scene, '#05070c', 0.55);
  return {
    name: 'city', scene, sunDir: dirFrom(12, 10), rim: { color: '#a9c6ff', strength: 0.55 }, glow: null, blob,
    update(t, speed = 1) { cloudCard.rotation.y = t * speed * 0.004; },
  };
}

// ---------------------------------------------------------------- Summit above the clouds at sunset (and its night variant)
function summit(night = false) {
  const scene = new THREE.Scene();
  const sunDir = dirFrom(3, 2.4);
  const skyM = night
    ? sky({ stops: [[-6, '#1a2146'], [0, '#2b3567'], [3, '#202a58'], [12, '#151d45'], [40, '#0b1130'], [90, '#060a20']], stars: 1.0, mw: 1.0 })
    : sky({ stops: [[-6, '#e3a08b'], [-1, '#ffc98f'], [0.6, '#ffd08e'], [2.6, '#ffb26f'], [6, '#ff8e66'], [12, '#e8667b'], [22, '#aa518d'], [40, '#5c408e'], [65, '#35306f'], [90, '#22234f']], sun: sunDir, sunSize: 1.5, sunCol: '#fff4d8', glow: 1.1, glowWide: 0.32, glowCol: '#ffaa6a' });
  scene.add(skyM);

  if (!night) {
    const sc = new P.Layer({ R: 3500, theta: 170, eMin: 1, eMax: 38, w: 4096, h: 1536 });
    P.skyClouds(sc, { count: 34, az0: -85, az1: 85, el0: 4, el1: 30, len: 210, thick: 11, lowColor: '#ffb27c', highColor: '#c8608f', underColor: '#ffd3a0', alpha: 0.55, blur: 5, seed: 51 });
    scene.add(card(sc, -60));
  }

  const far = new P.Layer({ R: 7000, theta: 150, eMin: -6, eMax: 3, w: 4096, h: 768 });
  const nf = P.noise1(52);
  const pk = (az, c, h, s) => h - Math.abs(az - c) * s;
  P.mountains(far, {
    elev: (az) => Math.max(-4, pk(az, -24, 2.6, 0.62), pk(az, -12, 1.4, 0.55), pk(az, 17, 2.9, 0.66), pk(az, 31, 1.6, 0.5), pk(az, -42, 1.2, 0.45)) + P.fbm1(nf, az * 0.6, 3) * 0.15,
    body: night ? [[0, '#1d2244'], [1, '#161a36']] : [[0, '#6a5289'], [1, '#4a3b6b']], seed: 52,
    rim: night ? { color: '#8ea2ff', width: 1.5, alpha: 0.3, all: true } : { color: '#ffbf8e', width: 2, alpha: 0.95, all: true, focusAz: 3, focusWidth: 45 },
  });
  scene.add(card(far, -50));

  const clouds1 = new P.Layer({ R: 2600, theta: 170, eMin: -30, eMax: -1.5, w: 4096, h: 1536 });
  P.cloudBank(clouds1, night
    ? { base: -30, top: -3.1, amp: 0.5, freq: 0.2, bump: 26, colors: [[0, '#56609a'], [1, '#232a56']], light: '#a2b0ff', lightAlpha: 0.35, shade: '#12163a', shadeAlpha: 0.4, sun: 1, seed: 53 }
    : { base: -30, top: -2.4, amp: 0.5, freq: 0.2, bump: 30, colors: [[0, '#ffdcbc'], [0.35, '#efb0ad'], [1, '#9078ab']], light: '#fff2dc', lightAlpha: 0.85, shade: '#7a67a0', shadeAlpha: 0.35, sun: 1, haze: '#ffc9a6', hazeAlpha: 0.2, seed: 53 });
  scene.add(card(clouds1, -45));

  const clouds2 = new P.Layer({ R: 1000, theta: 170, eMin: -40, eMax: -3, w: 4096, h: 1536 });
  P.cloudBank(clouds2, night
    ? { base: -40, top: -6.2, amp: 1.0, freq: 0.15, bump: 60, colors: [[0, '#4a5490'], [1, '#1c2148']], light: '#9eadff', lightAlpha: 0.3, shade: '#0e1230', shadeAlpha: 0.45, sun: 1, seed: 54 }
    : { base: -40, top: -4.6, amp: 1.0, freq: 0.15, bump: 64, colors: [[0, '#ffe3c6'], [0.3, '#f3b7b0'], [1, '#8a6fa8']], light: '#fff4e2', lightAlpha: 0.9, shade: '#6a5a96', shadeAlpha: 0.4, sun: 1, seed: 54 });
  scene.add(card(clouds2, -40));

  const outcrop = (az0, fn, seed) => {
    const L = new P.Layer({ R: 45, theta: 70, eMin: -32, eMax: 22, w: 2048, h: 2048, az0 });
    const n = P.noise1(seed);
    P.mountains(L, {
      elev: (az) => fn(az) + P.fbm1(n, az * 0.5, 4) * 1.4, bottom: -32, body: night ? [[0, '#14172c'], [1, '#0b0d1c']] : [[0, '#45364f'], [1, '#261f30']], seed,
      snow: { color: night ? '#3a4270' : '#e7cfe0', line: -12, k: 0.05, base: 0.6, freq: 2.2, jitter: 1.2, streaks: 60 },
      facets: { sun: 1, color: night ? '#5a5f90' : '#8a73a8', alpha: 0.7, minProm: 20, minGap: 80, slant: 0.5, jag: 26 },
      rim: night ? { color: '#8fa0ff', width: 2, alpha: 0.35, all: true } : { color: '#ffb27a', width: 3.5, alpha: 0.95, all: true },
    });
    P.grain(L, 0.08, seed);
    return card(L, -20);
  };
  scene.add(outcrop(-42, (az) => (az < -16 ? Math.min(9, -3 + (-16 - az) * 1.4) - Math.max(0, -40 - az) * 0.15 : -40), 55));
  scene.add(outcrop(42, (az) => (az > 17 ? Math.min(6, -4 + (az - 17) * 1.1) - Math.max(0, az - 45) * 0.12 : -40), 56));

  const [gc] = groundCanvas(1024, {
    seed: 10, scale: 7,
    color: night
      ? (a, b) => lerpc(H('#1c1f33'), H('#2c3150'), P.smooth(0.55, 0.8, b))
      : (a, b) => {
        let c = lerpc(H('#4d3f52'), H('#2f2737'), P.smooth(0.3, 0.75, a));
        c = lerpc(c, H('#7a5f6e'), P.smooth(0.6, 0.85, b) * 0.4);
        if (a > 0.6 && b > 0.45) c = lerpc(c, H('#e9d4e2'), P.smooth(0.6, 0.7, a) * 0.85);
        return c;
      },
    edge: ledge(0.24, 0.92, 0.04), soft: 0.02,
  });
  scene.add(groundMesh(gc, 30, 0, 1));
  const r1 = boulder(91, night ? '#1b1e33' : '#4b3d55', 0.8); r1.position.set(-3.2, 0, -0.6); scene.add(r1);
  const r2 = boulder(92, night ? '#191c30' : '#43374d', 0.55); r2.position.set(3.0, 0, 0.8); scene.add(r2);
  const r3 = boulder(93, night ? '#191c30' : '#3f3349', 1.1); r3.position.set(-5.2, -0.1, 4.5); scene.add(r3);

  if (night) {
    lights(scene, { hemiSky: '#3a4a8a', hemiGround: '#10121f', hemi: 0.4, keyColor: '#8fa0ff', key: 0.4, keyDir: dirFrom(30, 30), shadow: false });
  } else {
    lights(scene, { hemiSky: '#a77fc9', hemiGround: '#3c2433', hemi: 0.5, keyColor: '#ffae70', key: 3.4, keyDir: dirFrom(3, 13), fill: 0.3, fillColor: '#b896e6', fillDir: dirFrom(175, 15), shadowBox: 6 });
    shadowCatcher(scene, '#2a1530', 0.45, 24);
  }
  const blob = contactBlob(scene, '#12080f', 0.5);
  return {
    name: night ? 'night' : 'summit', scene, sunDir: night ? dirFrom(30, 30) : dirFrom(3, 13), visibleSun: night ? null : sunDir,
    rim: night ? { color: '#8fa0ff', strength: 0.3 } : { color: '#ffb57c', strength: 1.15 }, blob,
    update(t, speed = 1) {
      if (night) {
        const a = t * speed * 0.05;
        skyM.material.uniforms.starRot.value.setFromMatrix4(new THREE.Matrix4().makeRotationAxis(new THREE.Vector3(0.0, 0.62, -0.78).normalize(), a));
      }
    },
  };
}

export function buildWorld(only) {
  const all = { redrocks: redRocks, forest, lake, city, summit: () => summit(false), night: () => summit(true) };
  const out = {};
  for (const [k, f] of Object.entries(all)) if (!only || only.includes(k)) out[k] = f();
  return out;
}
