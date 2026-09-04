# Third-party components

MAYHEM itself is proprietary (see [LICENSE](LICENSE)). The components listed here are **not**
— each keeps its own licence, and those licences travel with every build we ship. This file is
what satisfies their attribution requirements, so it must ship alongside the game and stay
accurate.

## Engine

**Godot Engine 4.7** — MIT License. Copyright (c) 2014-present Godot Engine contributors;
copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
<https://godotengine.org> · <https://github.com/godotengine/godot/blob/master/LICENSE.txt>

Godot bundles further third-party libraries under their own permissive licences (FreeType,
Thorvg, mbedTLS, miniupnpc and others). Their full notices are reproduced in
`COPYRIGHT.txt` in the Godot source distribution and apply to the engine portion of the
executable.

## Addons that ship in the build

**Beehave 2.9.2** — MIT License. Copyright (c) 2023 bitbrain. Behavior tree framework; drives
the five enemy AI trees under `scenes/enemies/ai/`.
<https://github.com/bitbrain/beehave> · full text: `addons/beehave/LICENSE`

## Addons that do NOT ship

Present in the repository for development only, and excluded from release builds by the export
filter documented in [docs/EXPORT.md](docs/EXPORT.md). Listed for completeness:

- **GUT** (Godot Unit Test) — MIT License, copyright (c) Butch Wesley. Test framework.
  Carries one local change: its daily version check against github is behind the
  `gut/check_for_updates` project setting, off by default. See `docs/TESTING.md`.
- **Phantom Camera** — MIT License. Installed, currently unused.
- **Debug Draw** — MIT License. Installed, currently unused.

## Fonts

All three ship inside the executable and are licensed under the **SIL Open Font License 1.1**,
which permits bundling in a commercial product provided the licence accompanies the fonts and
the fonts are not sold on their own.

| Font | Copyright | Source |
| --- | --- | --- |
| IBM Plex Sans (Regular, SemiBold) | Copyright (c) 2017 IBM Corp. | <https://github.com/IBM/plex> |
| IBM Plex Mono (SemiBold) | Copyright (c) 2017 IBM Corp. | <https://github.com/IBM/plex> |
| Archivo (Variable) | Copyright (c) Omnibus-Type | <https://github.com/Omnibus-Type/Archivo> |

> **Open item.** The OFL requires the licence text itself to be distributed with the fonts, and
> `ui/fonts/` currently holds only the font files. Download `OFL.txt` from each project above
> and commit it next to the fonts (`ui/fonts/OFL-IBMPlex.txt`, `ui/fonts/OFL-Archivo.txt`)
> before the public release. Naming the licence here is necessary but not by itself sufficient.

## Original assets

Every model, texture, shader, sound effect and music track in `assets/` is original to this
project. The current SFX and music are procedurally generated placeholders produced by
`tools/generate_placeholder_sfx.py` and `tools/generate_placeholder_music.py` — no third-party
material, no attribution owed. See `assets/audio/music/CREDITS.md`.

**If licensed or commissioned audio replaces the placeholders, add it to this file in the same
pass** — title, composer or licensor, licence, and any attribution string the licence requires
in-game.
