"""A one-page board of the formats in the saved reels: a row per format, a few frames from the reels in it."""
import json
import subprocess
import sys
from io import BytesIO

from PIL import Image, ImageDraw, ImageFont

META = {m['id']: m for m in json.load(open('meta.json'))}
ROW_H = 230
GAP = 8
WIDTH = 1400
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FONT_REG = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'


def grab(rid, t, rot=0, box=None):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{t:.2f}', '-i', META[rid]['file'], '-frames:v', '1',
                        '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True)
    im = Image.open(BytesIO(r.stdout)).convert('RGB')
    ref = json.load(open(f'out/{rid}_refined.json'))
    top, bottom = ref['picture_rows']
    W, H = im.size
    if box:  # a box of my own, as fractions of the screen
        box = (int(W * box[0]), int(H * box[1]), int(W * box[2]), int(H * box[3]))
    elif ref['aspect'] > 0.9:  # letterboxed: just the picture
        box = (0, int(top * H) + 2, int(W * 0.87), int(bottom * H) - 2)
    else:  # full screen: the middle, clear of Instagram's header, buttons and caption
        box = (int(W * 0.02), int(H * 0.13), int(W * 0.84), int(H * 0.72))
    c = im.crop(box)
    if rot:
        c = c.rotate(rot, expand=True)
    return c.resize((max(1, int(c.width * ROW_H / c.height)), ROW_H), Image.LANCZOS)


def main(spec_path, out_path):
    spec = json.load(open(spec_path))
    title_font = ImageFont.truetype(FONT, 30)
    head_font = ImageFont.truetype(FONT, 24)
    sub_font = ImageFont.truetype(FONT_REG, 18)
    tag_font = ImageFont.truetype(FONT_REG, 15)
    rows = []
    for row in spec['rows']:
        tiles = []
        for f in row['frames']:
            o = f[2] if len(f) > 2 else {}
            tiles.append((o.get('label', f[0]), grab(f[0], f[1], o.get('rot', 0), o.get('box'))))
        # fit the row to the width: scale down if needed
        total = sum(im.width for _, im in tiles) + GAP * (len(tiles) - 1)
        scale = min(1.0, (WIDTH - 40) / total)
        tiles = [(rid, im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)) for rid, im in tiles]
        rows.append((row, tiles))
    height = 90 + sum(70 + max(im.height for _, im in tiles) + 34 for _, tiles in rows) + 20
    board = Image.new('RGB', (WIDTH, height), (17, 17, 19))
    d = ImageDraw.Draw(board)
    d.text((20, 22), spec['title'], font=title_font, fill=(245, 245, 245))
    d.text((20, 60), spec['subtitle'], font=sub_font, fill=(170, 170, 175))
    y = 100
    for row, tiles in rows:
        d.text((20, y), row['name'], font=head_font, fill=(255, 196, 61))
        d.text((20, y + 32), row['line'], font=sub_font, fill=(200, 200, 205))
        y += 70
        x = 20
        h = max(im.height for _, im in tiles)
        for rid, im in tiles:
            board.paste(im, (x, y))
            d.text((x + 2, y + im.height + 6), rid, font=tag_font, fill=(150, 150, 155))
            x += im.width + GAP
        y += h + 34
    board.save(out_path, quality=88)
    print(board.size)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
