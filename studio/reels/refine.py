"""Second pass over the saved reels, restricted to the part of each recording where the reel itself is playing.

For each reel: the picture's shape (letterboxed 16:9, 4:3, full-screen vertical...), the reel's real length
(found from where the recording repeats itself), the cuts inside one play-through, pace, how many cuts land
on the beat, and the text on screen (titles, captions) plus the account / song / caption line.
Writes out/<id>_refined.json. Usage: python3 refine.py R01 R02 ...
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyse import audio, beats  # noqa: E402

# Where the reel itself is on screen in each recording (seconds), read off the contact sheets.
SPANS = {
    'R01': (0.3, 30.4), 'R02': (4.3, 34.1), 'R03': (0.3, 14.6), 'R04': (3.0, 30.4), 'R05': (3.0, 25.5),
    'R06': (3.0, 30.9), 'R07': (1.8, 12.4), 'R08': (2.8, 24.6), 'R09': (2.5, 14.8), 'R10': (2.8, 16.2),
    'R11': (1.6, 12.4), 'R12': (2.0, 24.7), 'R13': (2.4, 16.8), 'R14': (4.4, 25.5), 'R15': (3.2, 17.6),
    'R16': (1.5, 20.4), 'R17': (2.3, 71.5), 'R18': (2.2, 16.6), 'R19': (2.6, 26.2), 'R20': (2.8, 20.8),
    'R21': (2.8, 11.0), 'R22': (1.0, 49.4), 'R23': (1.2, 49.6), 'R24': (1.8, 14.5), 'R25': (1.1, 50.9),
    'R26': (1.2, 51.2), 'R27': (1.6, 16.5), 'R28': (0.2, 48.0),
    'T01': (2.0, 25.4), 'T02': (0.0, 9.3), 'T03': (0.5, 29.2), 'T04': (1.0, 91.5), 'T05': (1.5, 21.3),
    'T06': (1.0, 13.0), 'T07': (1.2, 71.0), 'T08': (0.8, 13.8), 'T09': (0.8, 15.0), 'T10': (1.2, 27.0),
    'T11': (1.2, 102.9), 'T12': (0.8, 13.4), 'T13': (0.5, 37.9), 'T14': (1.2, 18.8), 'T15': (1.8, 20.0),
    'T16': (1.8, 8.5), 'T17': (1.0, 19.1),
    'R29': (1.0, 23.4), 'R30': (1.0, 35.5), 'R31': (1.0, 12.79), 'R32': (1.8, 26.04), 'R33': (1.2, 19.3),
    'R34': (0.5, 13.27), 'R35': (0.5, 17.82), 'R36': (1.0, 17.5), 'R37': (0.8, 32.44), 'R38': (0.4, 11.5),
    'R39': (0.8, 13.25), 'R40': (0.3, 22.74), 'R41': (0.05, 12.27), 'R42': (0.4, 15.54), 'R43': (0.4, 10.1),
    'R44': (0.9, 28.0), 'R45': (1.0, 17.02), 'R46': (0.4, 13.38), 'R47': (0.2, 10.38), 'R48': (0.8, 26.5),
    'R49': (1.4, 19.97), 'T18': (0.5, 29.61), 'T19': (0.0, 25.36), 'T20': (0.5, 24.58), 'T21': (0.8, 16.15),
    'T22': (0.2, 9.85),
}
FPS = 10


def frames(path, t0, t1, w=96):
    """Grey frames at FPS between t0 and t1, full screen, scaled to w wide."""
    h = int(round(w * 2622 / 1206 / 2) * 2)
    r = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{t0:.2f}', '-t', f'{t1 - t0:.2f}', '-i', path, '-an',
                        '-vf', f'fps={FPS},scale={w}:{h}', '-pix_fmt', 'gray', '-f', 'rawvideo', '-'],
                       capture_output=True)
    a = np.frombuffer(r.stdout, dtype=np.uint8)
    n = len(a) // (w * h)
    return a[:n * w * h].reshape(n, h, w).astype(np.float32), h


def picture_rows(stack, h):
    """The rows the picture fills: the longest run of rows that aren't black bars."""
    cols = slice(int(0.05 * stack.shape[2]), int(0.80 * stack.shape[2]))
    lit = (stack[:, :, cols] > 14).mean(axis=2)  # per frame, per row
    rows = np.median(lit, axis=0) > 0.5
    best, run, start, best_start = 0, 0, 0, 0
    for i, v in enumerate(rows):
        if v:
            if run == 0:
                start = i
            run += 1
            if run > best:
                best, best_start = run, start
        else:
            run = 0
    return best_start, best_start + best


def shape_name(ratio):
    named = [(2.39, '2.39:1 scope'), (1.9, '1.9:1'), (16 / 9, '16:9'), (1.5, '3:2'), (4 / 3, '4:3'), (1.0, '1:1'),
             (4 / 5, '4:5'), (9 / 16, '9:16 full screen')]
    return min(named, key=lambda n: abs(np.log(ratio / n[0])))[1]


def loop_length(sig, min_s=4.0):
    """The lag at which the picture repeats itself, in seconds, and how clearly (lower is clearer)."""
    n = len(sig)
    best = (None, 9.9)
    scores = []
    for lag in range(int(min_s * FPS), n - int(1.0 * FPS)):
        d = np.abs(sig[:n - lag] - sig[lag:]).mean(axis=1)
        s = float(np.percentile(d, 35))
        scores.append(s)
        if s < best[1]:
            best = (lag / FPS, s)
    typical = float(np.median(scores)) if scores else 1.0
    return best[0], best[1] / (typical + 1e-6)


def ocr_words(img, tmpdir, min_conf=70):
    from PIL import Image
    p = os.path.join(tmpdir, 'o.png')
    Image.fromarray(img).save(p)
    r = subprocess.run(['tesseract', p, '-', '--psm', '11', 'tsv'], capture_output=True, text=True)
    words = []
    for line in r.stdout.splitlines()[1:]:
        parts = line.split('\t')
        if len(parts) == 12 and parts[11].strip():
            try:
                conf = float(parts[10])
            except ValueError:
                continue
            if conf >= min_conf and len(parts[11].strip()) > 1:
                words.append(parts[11].strip())
    return ' '.join(words)


def colour_frame(path, t, w=1206):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{t:.2f}', '-i', path, '-frames:v', '1', '-vf', f'scale={w}:-2',
                        '-pix_fmt', 'gray', '-f', 'rawvideo', '-'], capture_output=True)
    h = len(r.stdout) // w
    return np.frombuffer(r.stdout, dtype=np.uint8)[:h * w].reshape(h, w)


def main(ids):
    meta = {m['id']: m for m in json.load(open('meta.json'))}
    tmpdir = tempfile.mkdtemp(prefix='refine_')
    for rid in ids:
        m = meta[rid]
        path, dur = m['file'], m['dur']
        t0, t1 = SPANS[rid]
        t1 = min(t1, dur)
        stack, h = frames(path, t0, t1)
        top, bottom = picture_rows(stack, h)
        ratio = stack.shape[2] / max(1, (bottom - top))
        # signature: the picture area, small
        pic = stack[:, top:bottom, int(0.05 * stack.shape[2]):int(0.80 * stack.shape[2])]
        small = np.stack([f[::max(1, f.shape[0] // 24), ::3][:24, :24].ravel() for f in pic])
        L, clarity = loop_length(small)
        span = t1 - t0
        repeats = L is not None and clarity < 0.45 and span > L + 1.0
        reel_len = L if repeats else span
        # cuts from the first pass, inside the span
        first = json.load(open(f'out/{rid}.json'))
        cuts = [c for c in first['cuts'] if t0 + 0.3 < c < t1 - 0.2]
        if repeats:
            phases = sorted(((c - t0) % L) for c in cuts)
            uniq = []
            for p in phases:
                if not uniq or p - uniq[-1] > 0.2:
                    uniq.append(p)
            if len(uniq) > 1 and uniq[0] + L - uniq[-1] < 0.2:
                uniq.pop()
            per_loop = uniq
            n_shots = max(1, len(per_loop))
        else:
            per_loop = [c - t0 for c in cuts]
            n_shots = len(per_loop) + 1
        avg_shot = reel_len / n_shots
        # beat sync inside the span
        y = audio(path)
        sr = 22050
        seg = y[int(t0 * sr):int(t1 * sr)]
        bpm, bts, strength, loud = beats(seg)
        hit = hit_half = None
        if bpm and cuts and bts:
            b = np.array(bts) + t0
            half = 30 / bpm
            hit = round(sum(1 for c in cuts if np.min(np.abs(b - c)) <= 0.08) / len(cuts), 2)
            both = np.concatenate([b, b + half])
            hit_half = round(sum(1 for c in cuts if np.min(np.abs(both - c)) <= 0.08) / len(cuts), 2)
        # text: picture area every 0.8 s through one play-through, and the info line a few times
        texts, seen = [], set()
        scale = 1206 / stack.shape[2]
        y0, y1 = int(top * scale), int(bottom * scale)
        t = t0 + 0.2
        while t < min(t1, t0 + reel_len + 0.5):
            g = colour_frame(path, t)
            region = g[max(0, y0):min(g.shape[0], y1), :int(0.84 * g.shape[1])]
            if region.size:
                words = ocr_words(region, tmpdir)
                if words and words not in seen:
                    seen.add(words)
                    texts.append(f'{t - t0:.1f}s: {words}')
            t += 0.8
        info = []
        for tt in np.linspace(t0 + 0.5, t1 - 0.5, 3):
            g = colour_frame(path, tt)
            strip = g[int(0.68 * g.shape[0]):int(0.93 * g.shape[0]), :int(0.84 * g.shape[1])]
            info.append(ocr_words(255 - strip, tmpdir, min_conf=60))
        out = {
            'id': rid, 'span': [t0, t1], 'picture_rows': [round(top / h, 3), round(bottom / h, 3)],
            'aspect': round(ratio, 2), 'shape': shape_name(ratio), 'loop_s': L, 'loop_clarity': round(clarity, 2),
            'repeats': bool(repeats), 'reel_len_s': round(reel_len, 1), 'shots': n_shots,
            'avg_shot_s': round(avg_shot, 2), 'cut_phases': [round(p, 2) for p in per_loop], 'bpm': bpm,
            'beat_strength': strength, 'cuts_on_beat': hit, 'cuts_on_beat_or_half': hit_half,
            'screen_text': texts, 'info_line': info,
        }
        json.dump(out, open(f'out/{rid}_refined.json', 'w'), indent=1)
        print(rid, out['shape'], f"aspect={out['aspect']}", f"loop={L} clar={out['loop_clarity']} rep={repeats}",
              f"len={out['reel_len_s']} shots={n_shots} avg={out['avg_shot_s']} bpm={bpm} on={hit}/{hit_half}", flush=True)


if __name__ == '__main__':
    main(sys.argv[1:])
