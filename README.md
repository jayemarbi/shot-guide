# Shot Guide

An iPhone app for filming the jodyseescoolstuff shot list. Start a trip at a place, pick its type (Mountain and hiking, Waterfalls and rainforest, Beach and coast, City, Road trip, Snow or General), then pick any of the 30 shots (extras are marked) and the camera opens with that shot's settings. The trip page lists them in the order you'll film them: on the way, arriving (transition In halves), first look, at the spot (easiest first, the ones worth taking your time over last), creative extras and leaving (transition Out halves), with a line about when golden hour and sunset are. The type tunes which shots count, how many takes each needs and the tips; snow days film a little brighter. Days are added as you go: each day has its own shot list and counts, and can move to a new place with its own type.

The camera has pinch to zoom (up to 20x; it resets after each take), a level line and a grid that can be switched off. Every shot has a countdown (off up to 10 minutes) and either stops by itself after a length you choose or keeps rolling until you stop it; the app remembers your choices for each shot. Phone-in-hand shots show live prompts while you record; shots with you in them show a timeline first, count you in with the flash, keep the screen clean and replay the take straight after. Quick clip on the trip page starts filming straight away, with no guidance.

The creative shots are MATCH CUT (a see-through still of your last one to line up the next), CLONE (focus and exposure lock, and the flash tells you when to move), JUMP (Out and In halves), RISE, ORBIT, DOLLY ZOOM (the app zooms while you walk back, with a box to keep the person in), HYPERLAPSE (with a crosshair), SILHOUETTE (darkened so you stay black against the sky), REFLECTION, SOUNDS and DANCE.

DANCE plays a song in your AirPods (or on the speaker) while you dance or lip-sync. Songs come from a video, screen recording or audio file and are kept in On My iPhone › Shot Guide › Songs for every trip. The song starts during the countdown so the chosen point lands as recording starts: carry on from 10 seconds before where the last take ended, start from the top, or pick a point. Each clip logs the song and exactly where in it the clip starts (allowing for Bluetooth delay), and the song is copied into the trip folder (`SONG_<name>.m4a`) so it reaches the SSD for cutting to the beat.

After each take you can name the clip. The name box is filled in with the last name you used within 300 m, with recent names one tap away, and the name goes on the end of the file name. Still and slow shots get a take check for shake and tilt. While recording, Mark (or volume down) saves the moment's time with the clip. Shots that stop by themselves keep rolling 2 extra seconds for the edit. Movement shots film at 60 fps, dropping to 30 once the sun is down. Sound is recorded in stereo with wind noise reduction where the phone supports it. The camera warns when the phone is getting too hot or the battery is low for a long shot, and notifications come before golden hour, sunset and blue hour on a trip you're filming. VOICEOVER records sound only, for narration. Each trip has Trip facts (distance, time, cost, tips; saved as `facts.txt`), Add from Photos for clips and photos from other cameras (each can be given a shot type), and shows how many minutes of 4K fit in the space left. TALK, REACTION, SECOND ANGLE and VOICEOVER show which mic is recording. The trips screen shows when this install stops opening, in orange for the last 2 days.

Every clip is saved already named (`Place_YYYY-MM-DD_SHOT_##_Name.mov`, where the place is the day's), filed under `Library/<continent>/<country>/<state>/<date> <place>/`, and listed in that trip's `catalog.csv` with its location, light, camera settings, tags, name, day, trip type and take check.

## How it's built

There's no Mac involved. Every push to `main` runs `.github/workflows/build.yml` on a GitHub macOS runner:

1. XcodeGen turns `project.yml` into an Xcode project.
2. Xcode builds the app without signing it.
3. The workflow packs `ShotGuide.ipa` and puts it on the `builds` branch, along with the app's details and any build errors.

The newest app is always at <https://github.com/jayemarbi/shot-guide/raw/builds/ShotGuide.ipa>.

## Installing it (free Apple ID)

1. On a Windows PC, install [Sideloadly](https://sideloadly.io) plus iTunes and iCloud from Apple's website (not the Microsoft Store versions).
2. Plug in the iPhone, drag `ShotGuide.ipa` into Sideloadly, enter your Apple ID and click Start.
3. First time only: turn on Developer Mode (Settings › Privacy & Security › Developer Mode), restart, then trust the app under Settings › General › VPN & Device Management.

Apps signed with a free Apple ID stop opening after 7 days. Install the same file again over the top; trips and clips stay. Deleting the app deletes its clips, so copy trips to the PC first.

## Getting footage off the phone

Both ways first get the clips ready for editing, on the phone, once per clip: a cutout mask (`<clip>_mask.mov`, white where you are) for every shot you're in, and captions (`<clip>.srt`, plus the text in the catalogue) for TALK, REACTION and SECOND ANGLE. Keep the app open while that runs.

**With an SSD (the main way).** Plug the SSD into the iPhone. On a trip's page, tap **Export trip** › **Copy to SSD or folder**, and choose the SSD. The trip goes into `Shot Guide/<continent>/<country>/<state>/<date> <place>/` beside the trips already there, with its `catalog.csv` and `trip.json`. Clips already on the drive are skipped, so copying a trip again only adds new takes, and clips renamed since the last copy are renamed on the drive too. After a copy, **Free up space** takes the copied clips off the phone; the trip keeps its shot list, names and counts. The SSD needs to be formatted exFAT (or APFS) for the iPhone to write to it, and exFAT also works on Windows.

**Without the SSD.** **Export trip** › **Make a .zip file** packs the trip into one file with the same `Shot Guide/...` folders inside. Copy it to the PC with iTunes (phone button near the top left › **File Sharing** › Shot Guide › **Save to**), or the Apple Devices app (Files › Shot Guide), or share it by AirDrop. Unzip it in the folder that holds your `Shot Guide` folder and it slots in beside the other trips.

## Code map

| Folder | What's in it |
| --- | --- |
| `ShotGuide/Models` | The shots and their timelines, trip types and how they tune the list, trips, days and clips, tags, countries and states |
| `ShotGuide/Services` | Saving trips and the catalogue, location, sun position and light alerts, tag suggestions, masks and captions, the install's expiry |
| `ShotGuide/Camera` | Camera set-up per shot, recording, time-lapse, the live preview, the level and take check |
| `ShotGuide/Views` | Trip list, new trip, days and trip types, shot list, camera screen, review, naming and tagging |
