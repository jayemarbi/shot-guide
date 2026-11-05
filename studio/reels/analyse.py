"""Breaks each saved reel down: cuts, pacing, the beat, how cuts sit on the beat, frames for a contact sheet,
and text read off the screen. Writes out/<id>.json, out/<id>_sheet.jpg and out/<id>_ocr.txt."""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.signal import find_peaks

OUT = 'out'
os.makedirs(OUT, exist_ok=True)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def cuts(path, dur):
    # Only the middle of the screen, away from Instagram's buttons and text, so UI doesn't hide the cuts.
    vf = "crop=iw*0.78:ih*0.62:iw*0.05:ih*0.12,scale=240:-2,select='gt(scene,0.27)',showinfo"
    r = run(['ffmpeg', '-hide_banner', '-i', path, '-an', '-vf', vf, '-f', 'null', '-'])
    times = []
    for line in r.stderr.splitlines():
        if 'pts_time:' in line:
            t = float(line.split('pts_time:')[1].split()[0])
            if 0.15 < t < dur - 0.15 and (not times or t - times[-1] > 0.12):
                times.append(round(t, 3))
    return times


def audio(path):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-ac', '1', '-ar', '22050', '-f', 'f32le', '-'], capture_output=True)
    return np.frombuffer(r.stdout, dtype=np.float32)


def beats(y, sr=22050):
    if len(y) < sr:
        return None, [], 0.0, 0.0
    hop, n = 512, 2048
    win = np.hanning(n)
    frames = np.lib.stride_tricks.sliding_window_view(y, n)[::hop] * win
    mag = np.abs(np.fft.rfft(frames, axis=1))
    logm = np.log1p(10 * mag)
    flux = np.maximum(0, np.diff(logm, axis=0)).sum(axis=1)
    flux = np.concatenate([[0], flux])
    flux -= np.convolve(flux, np.ones(16) / 16, 'same')
    flux = np.maximum(flux, 0)
    fps = sr / hop
    env = flux / (flux.max() + 1e-9)
    ac = np.correlate(env, env, 'full')[len(env) - 1:]
    ac /= ac[0] + 1e-9
    lags = np.arange(len(ac)) / fps
    ok = (lags >= 60 / 190) & (lags <= 60 / 70)
    if not ok.any():
        return None, [], 0.0, 0.0
    # prefer tempos near 120 a little, like a listener would
    weight = np.exp(-0.5 * (np.log2((60 / np.maximum(lags, 1e-6)) / 120) / 0.9) ** 2)
    score = ac * weight
    best = np.argmax(np.where(ok, score, -1))
    period = lags[best]
    strength = float(ac[best])
    bpm = 60 / period
    # phase: line a grid up with the onsets
    p = int(round(period * fps))
    phases = [env[ph::p].sum() for ph in range(p)]
    ph = int(np.argmax(phases))
    grid = np.arange(ph, len(env), p) / fps
    # let each beat snap to the nearest strong onset within 70 ms
    snapped = []
    for g in grid:
        i0, i1 = int(max(0, (g - 0.07) * fps)), int(min(len(env) - 1, (g + 0.07) * fps))
        seg = env[i0:i1 + 1]
        snapped.append((i0 + int(np.argmax(seg))) / fps if len(seg) and seg.max() > 0.15 else g)
    loud = float(20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-9))
    return round(bpm, 1), [round(b, 3) for b in snapped], round(strength, 2), round(loud, 1)


def on_beat(cut_times, beat_times, bpm):
    if not cut_times or not beat_times or not bpm:
        return None, None
    b = np.array(beat_times)
    half = 30 / bpm
    near = sum(1 for c in cut_times if np.min(np.abs(b - c)) <= 0.09)
    halfs = np.concatenate([b, b + half])
    near_half = sum(1 for c in cut_times if np.min(np.abs(halfs - c)) <= 0.09)
    return round(near / len(cut_times), 2), round(near_half / len(cut_times), 2)


def frame(path, t, w):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{t:.3f}', '-i', path, '-frames:v', '1', '-vf', f'scale={w}:-2',
                        '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True)
    from io import BytesIO
    return Image.open(BytesIO(r.stdout)).convert('RGB') if r.stdout else None


def ocr(img):
    import tempfile
    fd, tmp = tempfile.mkstemp(suffix='.png', prefix='ocr_')
    os.close(fd)
    img.convert('L').save(tmp)
    r = run(['tesseract', tmp, '-', '--psm', '11'])
    os.remove(tmp)
    words = [l.strip() for l in r.stdout.splitlines() if len(l.strip()) > 2]
    return ' | '.join(words)


def sheet(rid, path, dur, cut_times):
    # first frame big (hook text, account, song label), then one frame from the middle of each shot
    shots = [0.0] + cut_times + [dur]
    mids = [(shots[i] + shots[i + 1]) / 2 for i in range(len(shots) - 1)]
    if len(mids) > 24:
        idx = np.linspace(0, len(mids) - 1, 24).round().astype(int)
        mids = [mids[i] for i in idx]
    if len(mids) < 6:
        mids = list(np.linspace(0.4, dur - 0.4, 8))
    big = frame(path, 0.4, 420)
    tw = 168
    thumbs = [(t, frame(path, t, tw)) for t in mids]
    th = thumbs[0][1].height if thumbs and thumbs[0][1] else 365
    cols = 8
    rows = (len(thumbs) + cols - 1) // cols
    W = 420 + 10 + cols * (tw + 4)
    H = max(big.height if big else 900, rows * (th + 18)) + 30
    s = Image.new('RGB', (W, H), (18, 18, 18))
    d = ImageDraw.Draw(s)
    d.text((6, 6), f'{rid}  {dur:.1f}s  cuts {len(cut_times)}', fill=(255, 220, 0))
    if big:
        s.paste(big, (0, 24))
    for k, (t, im) in enumerate(thumbs):
        x = 430 + (k % cols) * (tw + 4)
        y = 24 + (k // cols) * (th + 18)
        if im:
            s.paste(im, (x, y + 14))
        d.text((x + 2, y), f'{t:.1f}s', fill=(255, 220, 0))
    s.save(os.path.join(OUT, f'{rid}_sheet.jpg'), quality=86)


def main(ids):
    meta = json.load(open('meta.json'))
    for m in meta:
        if ids and m['id'] not in ids:
            continue
        rid, path, dur = m['id'], m['file'], m['dur']
        c = cuts(path, dur)
        y = audio(path)
        bpm, bts, strength, loud = beats(y)
        hit, hit_half = on_beat(c, bts, bpm)
        shots = np.diff([0.0] + c + [dur]) if True else []
        info = {
            **m, 'cuts': c, 'n_shots': len(c) + 1,
            'avg_shot_s': round(float(np.mean(shots)), 2), 'median_shot_s': round(float(np.median(shots)), 2),
            'first_cut_s': c[0] if c else None, 'bpm': bpm, 'beat_strength': strength, 'loudness_db': loud,
            'cuts_on_beat': hit, 'cuts_on_beat_or_half': hit_half,
        }
        texts = {}
        for t in (0.3, 1.2, 2.5, 4.0):
            if t < dur:
                im = frame(path, t, 1206)
                if im:
                    texts[str(t)] = ocr(im)
        with open(os.path.join(OUT, f'{rid}_ocr.txt'), 'w') as f:
            for k, v in texts.items():
                f.write(f'[{k}s] {v}\n')
        sheet(rid, path, dur, c)
        json.dump(info, open(os.path.join(OUT, f'{rid}.json'), 'w'), indent=1)
        print(rid, f"{dur}s shots={info['n_shots']} avg={info['avg_shot_s']}s first_cut={info['first_cut_s']} bpm={bpm} "
              f"strength={strength} on_beat={hit} on_beat_or_half={hit_half} loud={loud}dB", flush=True)


if __name__ == '__main__':
    main(sys.argv[1:])
