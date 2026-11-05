# Studio tools

These are the scripts Claude used outside the app. They were saved here on 6 November 2026 so they aren't lost when Claude's cloud workspace is cleared. None of them is part of the iPhone app or its build.

They ran in Claude's Linux workspace with ffmpeg 6.1, tesseract 5.3, Python 3, numpy, scipy and Pillow. Some paths are written for that workspace (`/home/claude/...`, `/mnt/user-data/uploads/...`), so change them before running anywhere else.

## reels/: measuring reference reels and TikToks

These measure Jody's screen recordings of reels he likes. The results are written up in the claude.ai Project doc `claude/reel-library.md` (19 formats, 70 references). The recordings themselves are on the SSD in `D:\Reference Reels\Analysed`.

| File | What it does |
|---|---|
| `meta.json` | One entry per recording: analysis ID, file, length, size, frame rate. Analysis IDs R37–R49 became R36–R48 in the library; analysis R36 was a duplicate recording and was dropped. |
| `analyse.py` | First pass for each recording: cuts (ffmpeg scene detection on the middle of the screen), tempo and beats (spectral flux, autocorrelation, snapping to onsets), how many cuts land on the beat, OCR of on-screen text (tesseract), and a contact sheet. Writes `out/<id>.json`, `out/<id>_sheet.jpg` and `out/<id>_ocr.txt`. |
| `refine.py` | Second pass, inside the part of the recording where the reel plays (`SPANS`). Finds the picture's shape, the length of one play-through and the cuts within it. Writes `out/<id>_refined.json`. |
| `recut.py` | Finds cuts again using only the picture area (letterbox bars hid soft cuts). Has manual length fixes in `LENGTH_FIX`. |
| `restart.py` | Finds where a reel starts again in its recording (best match to the opening frame). |
| `board.py`, `board_spec.json` | A one-page board of the formats, with frames from the reels in each. |
| `strip.py` | Frames from one recording at given times, side by side, for reading text. |

The `out/` results (contact sheets, OCR text, per-reel JSON) are left out on purpose. They contain frames and text from other creators' videos, and this repo is public.

## reference-sheet/

`sheet.py` and `sheet.json` generate the "Content reference sheet": the Shot Guide shots each of the 19 formats needs, ranked by how many formats use each shot. The sheet itself is a Claude Doc.

## concept-reel/: the Denver dance concept (1 November 2026)

A synthetic concept reel made before any real footage existed, to show the DANCE idea.

- **`reel.html` and `js/`:** a three.js scene of a dancer in painted landscapes, cut to a 133 BPM grid (`js/shots.js`).
- **`render.py`:** films the page frame by frame with headless Chromium.
- **`music.py`:** synthesises an original placeholder backing track at the same tempo.
- **`assemble.sh`:** joins the shots and adds the audio. It also makes a silent copy.
- **`check.py`:** samples frames to check the result.

Left out:

- three.js itself (`lib/three`, from npm);
- the two 3D models (`assets/Michelle.glb`, `assets/Stork.glb`, from the three.js examples).

Restore both before rendering. The output was 22 s, 1080×1920, 30 fps.

## walkthrough/: the Shot Guide 1.7 walkthrough video

`demo.html` is an HTML mock-up of the app's screens, driven by a frame-exact timeline. `render.py` films it scene by scene and joins the result (`ShotGuide_1.7_walkthrough.mp4`, 106.6 s).
