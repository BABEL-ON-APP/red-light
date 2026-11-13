# Red Light video

This folder makes the Red Light demo video in code. The video has no voice: only text, drawings and sound.

- `video.html`: all scenes. The function `seek(t)` draws the frame for time `t` in seconds.
- `render.cjs`: opens `video.html` in headless Chromium and saves one picture for each frame.
- `audio.py`: makes the sound from the event list. It uses no samples.

The drawn screen is a simulation. A layer multiplies each colour channel by the preset values from `main.swift`. The video does not run the app.

## Requirements

- Node.js and a Playwright package with Chromium. Set `PW` to the path of the Playwright package.
- Python 3 with numpy.
- ffmpeg.
- A network connection for the three Google Fonts.

## Make the video

Run these commands from this folder.

1. Set an output folder for the frames: `export OUT=/tmp/redlight-video`
2. Render the frames: `node render.cjs full 30`
3. Make the sound: `python3 audio.py $OUT/events.json $OUT/audio.wav 32`
4. Join them:
   `ffmpeg -framerate 30 -i $OUT/frames/f%05d.jpg -i $OUT/audio.wav -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 192k -shortest ../demo.mp4`
5. Delete the frames: `rm -rf $OUT/frames`

## Make the GIF

`ffmpeg -ss 2.8 -t 12 -i ../demo.mp4 -vf "fps=12,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 ../demo.gif`

## Make the hero picture

1. Render one still: `node render.cjs stills 6.5`
2. Scale it: `ffmpeg -i $OUT/stills/t006.5.png -vf scale=1600:900:flags=lanczos ../hero.png`

## Change the video

- To change text or timing, edit the scene blocks in `video.html`. Each block has a start time `a` and an end time `b`.
- To look at single frames, run `node render.cjs stills 5.3 13.5 18`. The numbers are times in seconds.
- To change a sound, edit its function in `audio.py`. Scenes add sounds with `EVENTS.push({ t, type })`.
