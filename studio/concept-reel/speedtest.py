import base64, functools, http.server, os, sys, threading, time
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=HERE)
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]

with sync_playwright() as p:
    b = p.chromium.launch(args=['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'])
    page = b.new_page(viewport={'width': 1080, 'height': 1920}, device_scale_factor=1)
    errs = []
    page.on('pageerror', lambda e: errs.append(str(e)))
    page.on('console', lambda m: errs.append(m.text))
    page.goto(f'http://127.0.0.1:{port}/test.html')
    page.wait_for_function('window.ready === true', timeout=60000)
    cdp = page.context.new_cdp_session(page)
    print('gl:', page.evaluate("(() => { const c=document.querySelector('canvas'); const gl=c.getContext('webgl2'); const d=gl.getExtension('WEBGL_debug_renderer_info'); return d?gl.getParameter(d.UNMASKED_RENDERER_WEBGL):'?'; })()"))
    for i in range(6):
        t = 2.0 + i * 0.5
        ms = page.evaluate(f'window.renderAt({t})')
        t0 = time.time()
        shot = cdp.send('Page.captureScreenshot', {'format': 'jpeg', 'quality': 92})
        cap = (time.time() - t0) * 1000
        print(f'frame {i}: render {ms:.0f} ms, capture {cap:.0f} ms')
        if i == 3:
            open(os.path.join(HERE, 'out_test.jpg'), 'wb').write(base64.b64decode(shot['data']))
    print('console:', errs[:8])
    b.close()
