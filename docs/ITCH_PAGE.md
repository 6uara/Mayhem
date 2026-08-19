# itch.io page — copy to paste

Source of truth for the store page text, kept in the repo so the ownership wording on itch
matches [LICENSE](../LICENSE), [THIRD_PARTY.md](../THIRD_PARTY.md) and the in-game footer. If you
change one, change all four.

---

## Short description (itch's "Short description or tagline", 120 char limit)

```
Ten waves. One run. No saves. A first-person arena shooter with a host who won't stop talking.
```

## Page body

```
TEN WAVES. ONE RUN. NO SAVES.

You get one run. Ten waves, each meaner than the last, and a broadcast host narrating your
performance whether you asked for commentary or not. Spend what you earn between waves, because
nothing carries over — when you die, you start again from wave one.

No accounts. No network. No launcher. Your best runs live in a save file on your machine.

CONTROLS
  WASD            move                Mouse       look
  Space           jump                LMB         fire
  Ctrl            crouch / slide      RMB         aim down sights
  Shift           dash                R           reload
  E               grapple             F           interact
  Q / X / C       utilities           1-4         weapons
  Wheel           cycle weapons       Esc         pause

Every one of these is rebindable in Options.

VIDEOS AND STREAMS
Record it, stream it, monetise it — Let's Plays, reviews, speedruns, all fine, no permission
needed. Attribution is appreciated, never required.

BUILDS
Windows and Linux, 64-bit. Download, unzip, run. Roughly 210 MB.

Version 0.3 — in development. Bug reports and feedback in the comments are read.

LICENCE
Copyright (c) 2026 Juan Guaragnini. All rights reserved.

MAYHEM is proprietary software. You are welcome to play it and to publish video of your own
sessions. Redistributing, re-uploading or mirroring the builds, and reusing the code or assets
in another project, are not permitted without written permission.

Built with Godot Engine 4.7 (MIT). Behavior trees by Beehave (MIT, (c) bitbrain). Typefaces:
IBM Plex ((c) IBM Corp.) and Archivo ((c) Omnibus-Type), both SIL Open Font License 1.1. Full
attribution ships with the game in THIRD_PARTY.md.
```

## Page settings checklist

- [ ] **Classification**: Games · **Kind of project**: Downloadable
- [ ] **Release status**: In development
- [ ] **Pricing**: decide before publishing — free, donation, or paid
- [ ] **Platforms**: tick Windows and Linux on each uploaded file, and mark them "executable"
- [ ] **Visibility**: keep as Draft or Restricted until the pre-release checklist in
      [EXPORT.md](EXPORT.md) passes, then flip to Public
- [ ] **Community**: comments on, so bug reports have somewhere to land
- [ ] Upload `THIRD_PARTY.md` and `LICENSE` inside the zip next to the executable
- [ ] Screenshots and a cover image (630x500 recommended by itch)

## What to actually zip

The exported `.exe` alone is not the deliverable. Ship:

```
mayhem-0.3.0-windows/
  mayhem.exe          <- the export, PCK embedded
  LICENSE
  THIRD_PARTY.md
```

`LICENSE` and `THIRD_PARTY.md` are copied in as part of packaging, not exported by Godot — the
export filter excludes `docs/*` and these live at the repo root, so nothing pulls them into the
build automatically. Copy them by hand or in whatever packaging script lands later.
