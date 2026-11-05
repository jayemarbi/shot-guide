import functools, http.server, threading, json
from playwright.sync_api import sync_playwright
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
srv=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Q,directory='/home/claude/reel'))
threading.Thread(target=srv.serve_forever,daemon=True).start()
with sync_playwright() as p:
    b=p.chromium.launch(args=['--use-angle=swiftshader','--enable-unsafe-swiftshader'])
    pg=b.new_page(viewport={'width':540,'height':960})
    pg.goto(f'http://127.0.0.1:{srv.server_address[1]}/probe.html'); pg.wait_for_function('window.ready===true',timeout=60000)
    out=pg.evaluate('window.probe()')
    json.dump(out,open('/home/claude/reel/out/probe.json','w'))
    b.close()
