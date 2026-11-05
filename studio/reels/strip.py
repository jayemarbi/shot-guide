"""strip.py RID t1 t2 ... : frames from one recording at the given times, side by side, labelled, for reading text."""
import json, subprocess, sys
from io import BytesIO
from PIL import Image, ImageDraw
meta = {m['id']: m for m in json.load(open('/home/claude/reels/meta.json'))}
rid = sys.argv[1]; times = [float(x) for x in sys.argv[2:]]
crop = (0, 0.06, 1, 0.82)   # skip the status bar and the comment box
tiles = []
for t in times:
    r = subprocess.run(['ffmpeg','-v','error','-ss',f'{t:.2f}','-i',meta[rid]['file'],'-frames:v','1','-f','image2pipe','-vcodec','png','-'],capture_output=True)
    im = Image.open(BytesIO(r.stdout)).convert('RGB')
    W, H = im.size
    im = im.crop((int(crop[0]*W), int(crop[1]*H), int(crop[2]*W), int(crop[3]*H)))
    im = im.resize((300, int(300*im.height/im.width)))
    tile = Image.new('RGB', (im.width, im.height + 18), (20,20,20)); tile.paste(im, (0, 18))
    ImageDraw.Draw(tile).text((3, 3), f'{rid} {t:.1f}s', fill=(255,220,0)); tiles.append(tile)
w, h = tiles[0].size
sheet = Image.new('RGB', (len(tiles)*(w+4), h), (10,10,10))
for i, t in enumerate(tiles): sheet.paste(t, (i*(w+4), 0))
out = f'/home/claude/reels/new/strips/{rid}.jpg'; sheet.save(out, quality=85); print(out, sheet.size)
