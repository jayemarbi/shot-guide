"""Contact sheet of frames from the finished reel, at the moments that matter."""
import subprocess
from PIL import Image, ImageDraw

SRC = 'out/Denver_dance_concept.mp4'
SPB = 60 / 133
beats = [0.5, 3, 5, 8.05, 9, 11, 13, 15, 17, 19, 20.5, 21.5, 22.5, 23.9, 24.05, 24.6, 26, 30, 33, 35.5, 36.5, 37.5, 38.5, 39.5, 42, 44.1, 47]
W, H = 216, 384
cols = 9
sheet = Image.new('RGB', (W * cols, H * ((len(beats) + cols - 1) // cols)), 'black')
d = ImageDraw.Draw(sheet)
for i, b in enumerate(beats):
    t = b * SPB
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-ss', f'{t:.3f}', '-i', SRC, '-frames:v', '1', '-vf', f'scale={W}:{H}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True).stdout
    im = Image.frombytes('RGB', (W, H), raw)
    x, y = (i % cols) * W, (i // cols) * H
    sheet.paste(im, (x, y))
    d.text((x + 5, y + 5), f'b{b} {t:.2f}s', fill='yellow')
sheet.save('out/final_sheet.jpg', quality=88)
print('sheet saved')
