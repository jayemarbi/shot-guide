"""Where each reel starts again in its recording: the later frame that best matches the reel's opening frame.
Usage: python3 restart.py R29 R30 ..."""
import json, subprocess, sys
import numpy as np
sys.path.insert(0, '/home/claude/reels')
from refine import SPANS, frames, picture_rows
meta = {m['id']: m for m in json.load(open('/home/claude/reels/meta.json'))}
for rid in sys.argv[1:]:
    m = meta[rid]; t0, t1 = SPANS[rid]; t1 = min(t1, m['dur'])
    st, h = frames(m['file'], t0, t1)
    top, bot = picture_rows(st, h)
    pic = st[:, top:bot, int(0.05*st.shape[2]):int(0.80*st.shape[2])]
    ref = pic[3:6].mean(axis=0)  # t0+0.3..0.5 s
    d = np.array([np.abs(f - ref).mean() for f in pic])
    fps = 10
    lo = int(3.0*fps)
    if len(d) > lo + 5:
        k = lo + int(np.argmin(d[lo:]))
        typical = float(np.median(d[lo:]))
        print(rid, f"span {t0}-{t1}  best restart at {t0 + k/fps:.1f}s (reel ~{k/fps:.1f}s)  diff {d[k]:.1f} vs typical {typical:.1f}  picture rows {top}-{bot} of {h}")
    else:
        print(rid, 'too short')
