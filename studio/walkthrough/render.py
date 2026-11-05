"""Film demo.html: stills for checking, or every scene as its own mp4, then one joined video.

python3 render.py stills 0:2.5 3:6.8 ...   -> out/still_<scene>_<t>.jpg
python3 render.py scenes [i j ...]          -> out/sNN.mp4 (all scenes when none are named)
python3 render.py join                      -> out/ShotGuide_1.7_walkthrough.mp4
"""
import base64
import os
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

W, H, FPS = 1080, 1920, 30
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
os.makedirs(OUT, exist_ok=True)


def open_page(p):
    browser = p.chromium.launch()
    page = browser.new_page(viewport={'width': W, 'height': H}, device_scale_factor=1)
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.on('console', lambda m: errors.append(m.text) if m.type == 'error' else None)
    page.goto('file://' + os.path.join(HERE, 'demo.html'))
    page.wait_for_function('window.ready === true', timeout=30000)
    cdp = page.context.new_cdp_session(page)
    return browser, page, cdp, errors


def grab(page, cdp, i, t):
    page.evaluate('([i, t]) => window.renderScene(i, t)', [i, t])
    shot = cdp.send('Page.captureScreenshot', {'format': 'jpeg', 'quality': 92})
    return base64.b64decode(shot['data'])


def stills(args):
    with sync_playwright() as p:
        browser, page, cdp, errors = open_page(p)
        for arg in args:
            i, t = arg.split(':')
            data = grab(page, cdp, int(i), float(t))
            path = os.path.join(OUT, f'still_{int(i):02d}_{float(t):05.2f}.jpg')
            with open(path, 'wb') as f:
                f.write(data)
            print(path)
        print('errors:', errors)
        browser.close()


def scenes(which):
    with sync_playwright() as p:
        browser, page, cdp, errors = open_page(p)
        meta = page.evaluate('window.SCENES_META')
        todo = which or list(range(len(meta)))
        for i in todo:
            sc = meta[i]
            frames = round(sc['dur'] * FPS)
            final = os.path.join(OUT, f"{sc['id']}.mp4")
            part = os.path.join(OUT, f"{sc['id']}.part.mp4")
            ff = subprocess.Popen(
                ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', str(FPS), '-c:v', 'mjpeg',
                 '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p',
                 '-r', str(FPS), '-g', '60', part],
                stdin=subprocess.PIPE)
            start = time.time()
            for f in range(frames):
                ff.stdin.write(grab(page, cdp, i, f / FPS))
            ff.stdin.close()
            if ff.wait() == 0:
                os.replace(part, final)
                print(f"{sc['id']}: {frames} frames in {time.time() - start:.0f} s", flush=True)
            else:
                print(f"{sc['id']}: ffmpeg failed", flush=True)
        print('errors:', errors)
        browser.close()


def join():
    with sync_playwright() as p:
        browser, page, cdp, errors = open_page(p)
        meta = page.evaluate('window.SCENES_META')
        browser.close()
    listing = os.path.join(OUT, 'list.txt')
    with open(listing, 'w') as f:
        for sc in meta:
            f.write(f"file '{sc['id']}.mp4'\n")
    final = os.path.join(OUT, 'ShotGuide_1.7_walkthrough.mp4')
    part = os.path.join(OUT, 'ShotGuide_1.7_walkthrough.part.mp4')
    rc = subprocess.call(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', listing,
                          '-c', 'copy', '-movflags', '+faststart', part])
    if rc == 0:
        os.replace(part, final)
        print(final)


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'stills':
        stills(sys.argv[2:])
    elif cmd == 'scenes':
        scenes([int(x) for x in sys.argv[2:]])
    elif cmd == 'join':
        join()
