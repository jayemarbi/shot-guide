"""Cuts again, looking only at the picture itself (the black bars of letterboxed reels were diluting the
first pass, so soft or dark cuts were missed). Updates out/<id>_refined.json with 'cuts2', 'shots2', 'avg2'."""
import json
import subprocess
import sys

import numpy as np

META = {m['id']: m for m in json.load(open('meta.json'))}
# Reel lengths read off the recordings where the repeat-finder can't see one (static shots fool it).
LENGTH_FIX = {'R07': 9.6, 'T03': 27.1, 'T04': 88.2, 'T08': 12.1, 'T12': 11.8, 'T16': 4.9}


def scene_cuts(path, t0, t1, box, threshold):
    x, y, w, h = box
    vf = (f"crop=iw*{w:.3f}:ih*{h:.3f}:iw*{x:.3f}:ih*{y:.3f},scale=240:-2,"
          f"select='gt(scene,{threshold})',showinfo")
    r = subprocess.run(['ffmpeg', '-hide_banner', '-ss', f'{t0:.2f}', '-t', f'{t1 - t0:.2f}', '-i', path, '-an',
                        '-vf', vf, '-f', 'null', '-'], capture_output=True, text=True)
    times = []
    for line in r.stderr.splitlines():
        if 'pts_time:' in line:
            t = t0 + float(line.split('pts_time:')[1].split()[0])
            if t0 + 0.3 < t < t1 - 0.2 and (not times or t - times[-1] > 0.25):
                times.append(round(t, 3))
    return times


def main(ids):
    for rid in ids:
        ref = json.load(open(f'out/{rid}_refined.json'))
        t0, t1 = ref['span']
        top, bottom = ref['picture_rows']
        if ref['aspect'] > 0.9:
            box = (0.0, top + 0.004, 0.87, bottom - top - 0.008)
            threshold = 0.2
        else:
            box = (0.02, 0.13, 0.82, 0.62)
            threshold = 0.27
        cuts = scene_cuts(META[rid]['file'], t0, t1, box, threshold)
        L = LENGTH_FIX.get(rid, ref['loop_s'] if ref['repeats'] else None)
        span = t1 - t0
        if L and span > L + 1.0:
            phases = sorted(((c - t0) % L) for c in cuts)
            uniq = []
            for p in phases:
                if not uniq or p - uniq[-1] > 0.25:
                    uniq.append(p)
            if len(uniq) > 1 and uniq[0] + L - uniq[-1] < 0.25:
                uniq.pop()
            shots = max(1, len(uniq))
            length = L
        else:
            shots = len(cuts) + 1
            length = LENGTH_FIX.get(rid, span)
        ref.update({'cuts2': cuts, 'shots2': shots, 'reel_len2_s': round(length, 1), 'avg2': round(length / shots, 2)})
        json.dump(ref, open(f'out/{rid}_refined.json', 'w'), indent=1)
        print(rid, f"len={length:.1f} shots {ref['shots']} -> {shots}  avg {ref['avg_shot_s']} -> {ref['avg2']}", flush=True)


if __name__ == '__main__':
    main(sys.argv[1:])
