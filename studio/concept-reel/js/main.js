import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { buildWorld } from './world.js';
import { SHOTS, SPB, END_BEAT, FLASHES, LEAKS, danceTime, shotAt } from './shots.js';
import * as P from './paint.js';

const W = 1080, H = 1920;
const glCanvas = document.getElementById('gl');
const renderer = new THREE.WebGLRenderer({ canvas: glCanvas, antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(W, H, false);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const camera = new THREE.PerspectiveCamera(40, W / H, 0.05, 30000);
const only = new URLSearchParams(location.search).get('scenes');
const world = buildWorld(only ? only.split(',') : null);

const rimU = { color: { value: new THREE.Color('#ffffff') }, dir: { value: new THREE.Vector3(0, 0, 1) }, pow: { value: 2.6 } };
let dancer, mixer, hips;
// hips position (smoothed) and facing for every 1/60 s of the clip, measured once after loading
const TAB = { dt: 1 / 60, x: [], z: [], yaw: [] };
const tabAt = (arr, t) => arr[Math.max(0, Math.min(arr.length - 1, Math.round(t / TAB.dt)))];

const fx = document.getElementById('fx').getContext('2d');
const grainC = document.getElementById('grain').getContext('2d');
const flashEl = document.getElementById('flash');
const blurK = document.getElementById('dblurk');
const els = { kicker: document.getElementById('kicker'), l1: document.getElementById('l1'), l2: document.getElementById('l2'), l3: document.getElementById('l3'), end: document.getElementById('end') };

// film grain tiles
const grainTiles = [];
for (let k = 0; k < 4; k++) {
  const [c, g] = P.canvas(540, 960);
  const img = g.createImageData(540, 960), r = P.rng(900 + k);
  for (let i = 0; i < img.data.length; i += 4) { const v = 128 + (r() + r() + r() - 1.5) * 120; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
  g.putImageData(img, 0, 0);
  grainTiles.push(c);
}

function addRim(material) {
  material.onBeforeCompile = (shader) => {
    shader.uniforms.rimColor = rimU.color;
    shader.uniforms.rimDir = rimU.dir;
    shader.uniforms.rimPow = rimU.pow;
    shader.fragmentShader = 'uniform vec3 rimColor;\nuniform vec3 rimDir;\nuniform float rimPow;\n' + shader.fragmentShader.replace(
      '#include <emissivemap_fragment>',
      `#include <emissivemap_fragment>
       {
         vec3 Vv = normalize(vViewPosition);
         float ndv = clamp(dot(normal, Vv), 0.0, 1.0);
         float fr = pow(1.0 - ndv, rimPow);
         float side = smoothstep(-0.25, 0.75, dot(normal, rimDir));
         totalEmissiveRadiance += rimColor * fr * side;
       }`);
  };
  material.needsUpdate = true;
}

const easeOutCubic = (u) => 1 - Math.pow(1 - u, 3);
const smoothN = (t, a, b, c) => Math.sin(t * a) * 0.5 + Math.sin(t * b + 1.3) * 0.3 + Math.sin(t * c + 2.1) * 0.2;
const tmp = new THREE.Vector3();

function drawGlow(env, b) {
  fx.clearRect(0, 0, W, H);
  if (env.visibleSun) {
    tmp.copy(env.visibleSun).multiplyScalar(5000).add(camera.position).project(camera);
    if (tmp.z < 1) {
      const sx = (tmp.x * 0.5 + 0.5) * W, sy = (-tmp.y * 0.5 + 0.5) * H;
      const off = Math.hypot(Math.max(0, Math.abs(sx - W / 2) - W / 2), Math.max(0, Math.abs(sy - H / 2) - H / 2));
      const k = Math.exp(-off / 500);
      if (k > 0.01) {
        const zoom = 40 / camera.fov;
        const soft = 1 / Math.sqrt(zoom);
        let gr = fx.createRadialGradient(sx, sy, 0, sx, sy, Math.min(1150, 950 * Math.sqrt(zoom)));
        gr.addColorStop(0, `rgba(255,196,130,${0.45 * k * soft})`); gr.addColorStop(0.25, `rgba(255,150,100,${0.2 * k * soft})`); gr.addColorStop(1, 'rgba(255,120,90,0)');
        fx.fillStyle = gr; fx.fillRect(0, 0, W, H);
        gr = fx.createRadialGradient(sx, sy, 0, sx, sy, 140 * zoom);
        gr.addColorStop(0, `rgba(255,246,225,${0.75 * k})`); gr.addColorStop(1, 'rgba(255,230,190,0)');
        fx.fillStyle = gr; fx.fillRect(0, 0, W, H);
        // ghosts along the line through the centre
        const ghosts = [[-0.35, 60, '255,170,120', 0.16], [-0.7, 26, '160,200,255', 0.2], [-1.05, 110, '255,140,180', 0.08], [0.45, 34, '255,220,150', 0.12]];
        for (const [f, rad, col, a] of ghosts) {
          const gx = W / 2 + (sx - W / 2) * f, gy = H / 2 + (sy - H / 2) * f;
          const g2 = fx.createRadialGradient(gx, gy, 0, gx, gy, rad);
          g2.addColorStop(0, `rgba(${col},${a * k})`); g2.addColorStop(0.7, `rgba(${col},${a * 0.6 * k})`); g2.addColorStop(1, `rgba(${col},0)`);
          fx.fillStyle = g2; fx.beginPath(); fx.arc(gx, gy, rad, 0, Math.PI * 2); fx.fill();
        }
        // anamorphic streak
        const st = fx.createLinearGradient(sx - 700, sy, sx + 700, sy);
        st.addColorStop(0, 'rgba(255,170,120,0)'); st.addColorStop(0.5, `rgba(255,200,150,${0.22 * k})`); st.addColorStop(1, 'rgba(255,170,120,0)');
        fx.fillStyle = st; fx.fillRect(sx - 700, sy - 5, 1400, 10);
      }
    }
  }
  // light leaks sweeping across on some cuts
  for (const [lb, dir] of LEAKS) {
    const d = b - lb + 0.35;
    if (d < 0 || d > 1.1) continue;
    const p = d / 1.1;
    const a = Math.sin(p * Math.PI) * 0.6;
    const x = dir > 0 ? -300 + p * 1700 : 1380 - p * 1700;
    let gr = fx.createRadialGradient(x, 700, 0, x, 700, 900);
    gr.addColorStop(0, `rgba(255,120,60,${a})`); gr.addColorStop(0.5, `rgba(255,80,90,${a * 0.45})`); gr.addColorStop(1, 'rgba(255,60,80,0)');
    fx.fillStyle = gr; fx.fillRect(0, 0, W, H);
    gr = fx.createRadialGradient(x + 200 * dir, 1500, 0, x + 200 * dir, 1500, 700);
    gr.addColorStop(0, `rgba(255,190,90,${a * 0.6})`); gr.addColorStop(1, 'rgba(255,190,90,0)');
    fx.fillStyle = gr; fx.fillRect(0, 0, W, H);
  }
}

function drawGrain(f) {
  grainC.clearRect(0, 0, 540, 960);
  const tile = grainTiles[f % 4];
  const ox = (f * 137) % 540, oy = (f * 251) % 960;
  grainC.globalAlpha = 0.5;
  grainC.drawImage(tile, -ox, -oy); grainC.drawImage(tile, 540 - ox, -oy); grainC.drawImage(tile, -ox, 960 - oy); grainC.drawImage(tile, 540 - ox, 960 - oy);
  grainC.globalAlpha = 1;
}

function drawText(b) {
  const pop = (b0) => { const d = b - b0; if (d < 0) return [0, 1.3]; const p = Math.min(1, d / 0.3); const s = 1 + 0.3 * Math.pow(1 - p, 3) - 0.05 * Math.sin(p * Math.PI); return [Math.min(1, d / 0.12), s]; };
  const out = P.clamp((b - 7.1) / 0.8, 0, 1);
  const k = P.clamp(b / 0.6, 0, 1) * (1 - out);
  els.kicker.style.opacity = k;
  [['l1', 0], ['l2', 1], ['l3', 2]].forEach(([id, b0]) => {
    const [o, s] = pop(b0);
    els[id].style.opacity = o * (1 - out);
    els[id].style.transform = `translateY(${-out * 40}px) scale(${s})`;
  });
  const e = P.clamp((b - 44.15) / 0.9, 0, 1);
  els.end.style.opacity = e;
  els.end.style.transform = `translateY(${(1 - easeOutCubic(e)) * 30}px)`;
}

window.renderFrame = (t, f = 0) => {
  const b = t / SPB;
  const s = shotAt(b);
  const u = P.clamp((b - s.b0) / (s.b1 - s.b0), 0, 1);
  const env = world[s.scene];
  if (!env) return { shot: s.id, b, skipped: true };
  if (dancer.parent !== env.scene) env.scene.add(dancer);
  dancer.visible = s.dancer !== false;
  const at = danceTime(b);
  dancer.rotation.y = s.faceY || 0;
  mixer.setTime(at);
  dancer.updateMatrixWorld(true);
  hips.getWorldPosition(tmp);
  env.blob.position.set(tmp.x, 0.006, tmp.z);
  env.blob.visible = dancer.visible;

  const c = s.cam(u, b);
  if (s.dancer !== false) {
    // follow the dancer's sway like a camera operator would
    const k = s.follow ?? 1, th = s.faceY || 0;
    const hx = tabAt(TAB.x, at), hz = tabAt(TAB.z, at);
    const ox = (hx * Math.cos(th) + hz * Math.sin(th)) * k, oz = (-hx * Math.sin(th) + hz * Math.cos(th)) * k;
    c.pos = [c.pos[0] + ox, c.pos[1], c.pos[2] + oz];
    c.look = [c.look[0] + ox, c.look[1], c.look[2] + oz];
  }
  camera.position.set(c.pos[0], c.pos[1], c.pos[2]);
  let fov = c.fov;
  if (s.punch) { const db = b - Math.floor(b); fov *= 1 - 0.04 * Math.exp(-db * 7); }
  camera.fov = fov;
  camera.lookAt(c.look[0], c.look[1], c.look[2]);
  if (s.shake) {
    camera.rotateX(smoothN(t, 3.1, 5.3, 8.7) * 0.006 * s.shake);
    camera.rotateY(smoothN(t + 4, 2.7, 4.9, 7.9) * 0.006 * s.shake);
    camera.rotateZ(smoothN(t + 9, 1.9, 3.7, 6.1) * 0.004 * s.shake);
  }
  camera.updateProjectionMatrix();
  camera.updateMatrixWorld();

  rimU.dir.value.copy(env.sunDir).transformDirection(camera.matrixWorldInverse);
  rimU.color.value.set(env.rim.color).multiplyScalar(env.rim.strength);
  env.update(t, s.speed || 1);

  const bl = s.blur ? s.blur(u) : null;
  if (bl && bl.v > 0.5) {
    blurK.setAttribute('stdDeviation', `0 ${bl.v.toFixed(1)}`);
    glCanvas.style.filter = 'url(#dblur) contrast(1.04) saturate(1.07)';
  } else {
    glCanvas.style.filter = 'contrast(1.04) saturate(1.07)';
  }
  renderer.render(env.scene, camera);

  drawGlow(env, b);
  let fl = 0;
  for (const [fb, a] of FLASHES) { const d = b - fb; if (d >= -0.06 && d < 1.2) fl = Math.max(fl, a * (d < 0 ? (d + 0.06) / 0.06 : Math.exp(-d * 5))); }
  flashEl.style.opacity = fl.toFixed(3);
  drawGrain(f);
  drawText(b);
  return { shot: s.id, b };
};

window.META = { shots: SHOTS.map((s) => ({ id: s.id, t0: s.b0 * SPB, t1: s.b1 * SPB })), end: END_BEAT * SPB, spb: SPB };

new GLTFLoader().load('assets/Michelle.glb', (g) => {
  dancer = g.scene;
  dancer.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.receiveShadow = false;
      o.frustumCulled = false;
      o.material.metalness = 0.0;
      o.material.roughness = 0.62;
      addRim(o.material);
    }
    if (!hips && /Hips$/.test(o.name)) hips = o;
  });
  mixer = new THREE.AnimationMixer(dancer);
  mixer.clipAction(g.animations.find((a) => a.name === 'SambaDance')).play();
  // measure the clip: hips position and which way the dancer faces
  const q = new THREE.Quaternion(), f = new THREE.Vector3(), rawX = [], rawZ = [];
  for (let t = 0; t <= 18.25; t += TAB.dt) {
    mixer.setTime(t); dancer.updateMatrixWorld(true);
    hips.getWorldPosition(tmp); hips.getWorldQuaternion(q); f.set(0, 0, 1).applyQuaternion(q);
    rawX.push(tmp.x); rawZ.push(tmp.z); TAB.yaw.push(Math.atan2(f.x, f.z));
  }
  const win = 24;
  for (let i = 0; i < rawX.length; i++) {
    let sx = 0, sz = 0, n = 0;
    for (let j = Math.max(0, i - win); j <= Math.min(rawX.length - 1, i + win); j++) { sx += rawX[j]; sz += rawZ[j]; n++; }
    TAB.x.push(sx / n); TAB.z.push(sz / n);
  }
  // turn the dancer to face the camera in each shot (she turns away during parts of the clip)
  for (const s of SHOTS) {
    if (s.dancer === false) continue;
    let cx = 0, cz = 0;
    for (let k = 0; k <= 12; k++) { const y = tabAt(TAB.yaw, danceTime(s.b0 + (s.b1 - s.b0) * k / 12)); cx += Math.sin(y); cz += Math.cos(y); }
    s.faceY = -Math.atan2(cx, cz) + (s.faceAdd || 0) * Math.PI / 180;
  }
  // compile every scene once so the first frames are not slow
  for (const env of Object.values(world)) { env.scene.add(dancer); renderer.compile(env.scene, camera); }
  document.fonts.ready.then(() => { window.ready = true; });
});
