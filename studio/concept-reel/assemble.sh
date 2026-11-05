#!/bin/sh
# Join the rendered shots, add the backing track, and make a silent copy for adding the real song in Instagram.
set -e
cd "$(dirname "$0")"
python3 render.py join
ffmpeg -y -loglevel error -i out/reel_video.mp4 -i out/music.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart out/Denver_dance_concept.part.mp4
mv out/Denver_dance_concept.part.mp4 out/Denver_dance_concept.mp4
ffmpeg -y -loglevel error -i out/reel_video.mp4 -f lavfi -i anullsrc=r=48000:cl=stereo -map 0:v -map 1:a -c:v copy -c:a aac -b:a 128k -shortest -movflags +faststart out/Denver_dance_concept_no_music.part.mp4
mv out/Denver_dance_concept_no_music.part.mp4 out/Denver_dance_concept_no_music.mp4
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate -of compact out/Denver_dance_concept.mp4
