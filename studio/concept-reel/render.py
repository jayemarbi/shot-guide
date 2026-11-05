"""Film reel.html frame by frame.

python3 render.py stills 0.5 3.2 ...      -> out/still_<t>.jpg
python3 render.py shots [id ...]          -> out/shots/<id>.mp4 (all when none named)
python3 render.py join                    -> out/reel_video.mp4 (no sound)
"""
import base64
import functools
import http.server
import json
import os
import subprocess
import sys
import threading
import time

from playwright.sync_api import sync_playwright

W, H, FPS = 1080, 1920, 30
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
SHOTS_DIR = os.path.join(OUT, 'shots')
os.makedirs(SHOTS_DIR, exist_ok=True)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


def serve():
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=HERE))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv.server_address[1]


def open_page(p, scenes=None):
    port = serve()
    browser = p.chromium.launch(args=['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'])
    page = browser.new_page(viewport={'width': W, 'height': H}, device_scale_factor=1)
    errors = []
    page.on('pageerror', lambda e: errors.append('pageerror: ' + str(e)))
    page.on('console', lambda m: errors.append(f'{m.type}: {m.text}') if m.type in ('error', 'warning') else None)
    page.goto(f'http://127.0.0.1:{port}/reel.html' + (f'?scenes={scenes}' if scenes else ''))
    try:
        page.wait_for_function('window.ready === true', timeout=240000)
    except Exception:
        print('\n'.join(errors[:20]))
        raise
    cdp = page.context.new_cdp_session(page)
    return browser, page, cdp, errors


def grab(page, cdp, t, f):
    page.evaluate('([t, f]) => window.renderFrame(t, f)', [t, f])
    shot = cdp.send('Page.captureScreenshot', {'format': 'jpeg', 'quality': 93})
    return base64.b64decode(shot['data'])


def stills(times):
    scenes = None
    if times and times[0].startswith('--scenes='):
        scenes = times[0].split('=', 1)[1]
        times = times[1:]
    with sync_playwright() as p:
        t0 = time.time()
        browser, page, cdp, errors = open_page(p, scenes)
        print(f'loaded in {time.time() - t0:.0f} s')
        for ts in times:
            t = float(ts)
            info = page.evaluate('([t, f]) => window.renderFrame(t, f)', [t, int(t * FPS)])
            if info.get('skipped'):
                continue
            data = base64.b64decode(cdp.send('Page.captureScreenshot', {'format': 'jpeg', 'quality': 93})['data'])
            path = os.path.join(OUT, f'still_{t:06.3f}.jpg')
            with open(path, 'wb') as f:
                f.write(data)
            print(path)
        print('console:', '\n'.join(dict.fromkeys(errors)) or 'clean')
        browser.close()


def shots(which):
    with sync_playwright() as p:
        browser, page, cdp, errors = open_page(p)
        meta = page.evaluate('window.META')
        todo = [s for s in meta['shots'] if not which or s['id'] in which]
        for s in todo:
            f0, f1 = round(s['t0'] * FPS), round((s['t1'] if s['id'] != meta['shots'][-1]['id'] else meta['end']) * FPS)
            final = os.path.join(SHOTS_DIR, f"{s['id']}.mp4")
            part = os.path.join(SHOTS_DIR, f"{s['id']}.part.mp4")
            ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', str(FPS), '-c:v', 'mjpeg', '-i', '-',
                                   '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '17', '-pix_fmt', 'yuv420p', '-r', str(FPS), '-g', '30', part],
                                  stdin=subprocess.PIPE)
            start = time.time()
            for f in range(f0, f1):
                ff.stdin.write(grab(page, cdp, f / FPS, f))
            ff.stdin.close()
            if ff.wait() == 0:
                os.replace(part, final)
                print(f"{s['id']}: frames {f0}-{f1} in {time.time() - start:.0f} s", flush=True)
            else:
                print(f"{s['id']}: ffmpeg failed", flush=True)
        print('console:', '\n'.join(dict.fromkeys(errors)) or 'clean')
        with open(os.path.join(OUT, 'meta.json'), 'w') as f:
            json.dump(meta, f)
        browser.close()


def join():
    meta = json.load(open(os.path.join(OUT, 'meta.json')))
    listing = os.path.join(OUT, 'list.txt')
    with open(listing, 'w') as f:
        for s in meta['shots']:
            f.write(f"file 'shots/{s['id']}.mp4'\n")
    part = os.path.join(OUT, 'reel_video.part.mp4')
    rc = subprocess.call(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', listing, '-c', 'copy', part])
    if rc == 0:
        os.replace(part, os.path.join(OUT, 'reel_video.mp4'))
        print('joined')


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'stills':
        stills(sys.argv[2:])
    elif cmd == 'shots':
        shots(sys.argv[2:])
    elif cmd == 'join':
        join()
