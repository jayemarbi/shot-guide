# Shot Guide

An iPhone app for filming the jodyseescoolstuff shot list. Start a trip at a place, pick any of the 19 shots (extras are marked), and the camera opens with that shot's settings. The trip page lists them in the order you'll film them: on the way, arriving (transition In halves), first look, at the spot (easiest first, the ones worth taking your time over last) and leaving (transition Out halves), with a line about when golden hour and sunset are. The camera has a level line and a grid that can be switched off. Every shot has a countdown (off up to 10 minutes) and either stops by itself after a length you choose or keeps rolling until you stop it; the app remembers your choices for each shot. Phone-in-hand shots show live prompts while you record; shots with you in them show a timeline first, count you in with the flash, keep the screen clean and replay the take straight after.

Every clip is saved already named (`Place_YYYY-MM-DD_SHOT_##.mov`), filed under `Library/<continent>/<country>/<state>/<date> <place>/`, and listed in that trip's `catalog.csv` with its location, light, camera settings and tags.

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

**With an SSD (the main way).** Plug the SSD into the iPhone. On a trip's page, tap **Export trip** › **Copy to SSD or folder**, and choose the SSD. The trip goes into `Shot Guide/<continent>/<country>/<state>/<date> <place>/` beside the trips already there, with its `catalog.csv` and `trip.json`. Clips already on the drive are skipped, so copying a trip again only adds new takes. The SSD needs to be formatted exFAT (or APFS) for the iPhone to write to it, and exFAT also works on Windows.

**Without the SSD.** **Export trip** › **Make a .zip file** packs the trip into one file with the same `Shot Guide/...` folders inside. Copy it to the PC with iTunes (phone button near the top left › **File Sharing** › Shot Guide › **Save to**), or the Apple Devices app (Files › Shot Guide), or share it by AirDrop. Unzip it in the folder that holds your `Shot Guide` folder and it slots in beside the other trips.

## Code map

| Folder | What's in it |
| --- | --- |
| `ShotGuide/Models` | The 13 shots and their timelines, trips and clips, tags, countries and states |
| `ShotGuide/Services` | Saving trips and the catalogue, location, sun position, tag suggestions |
| `ShotGuide/Camera` | Camera set-up per shot, recording, time-lapse, the live preview |
| `ShotGuide/Views` | Trip list, new trip, shot list, camera screen, review and tagging |
