# Shot Guide

An iPhone app for filming the jodyseescoolstuff shot list. Start a trip at a place, pick any of the 13 shots, and the camera opens with that shot's settings. Phone-in-hand shots show live prompts while you record; shots with you in them show a timeline first, count you in with the flash, keep the screen clean and replay the take straight after.

Every clip is saved already named (`Place_YYYY-MM-DD_SHOT_##.mov`), filed under `Library/<continent>/<country>/<state>/<date> <place>/`, and listed in that trip's `catalog.csv` with its location, light, camera settings and tags.

## How it's built

There's no Mac involved. Every push to `main` runs `.github/workflows/build.yml` on a GitHub macOS runner:

1. XcodeGen turns `project.yml` into an Xcode project.
2. Xcode builds the app without signing it.
3. The workflow packs `ShotGuide.ipa` and attaches it to the run as an artifact.

## Installing it (free Apple ID)

1. On a Windows PC, install [Sideloadly](https://sideloadly.io) plus iTunes and iCloud from Apple's website (not the Microsoft Store versions).
2. Plug in the iPhone, drag `ShotGuide.ipa` into Sideloadly, enter your Apple ID and click Start.
3. First time only: turn on Developer Mode (Settings › Privacy & Security › Developer Mode), restart, then trust the app under Settings › General › VPN & Device Management.

Apps signed with a free Apple ID stop opening after 7 days. Install the same file again over the top; trips and clips stay. Deleting the app deletes its clips, so copy trips to the PC first.

## Getting footage off the phone

On a trip's page, tap **Export trip**. Then plug into the PC, open Apple Devices › Files › Shot Guide, select the `.zip` and click Save.

## Code map

| Folder | What's in it |
| --- | --- |
| `ShotGuide/Models` | The 13 shots and their timelines, trips and clips, tags, countries and states |
| `ShotGuide/Services` | Saving trips and the catalogue, location, sun position, tag suggestions |
| `ShotGuide/Camera` | Camera set-up per shot, recording, time-lapse, the live preview |
| `ShotGuide/Views` | Trip list, new trip, shot list, camera screen, review and tagging |
