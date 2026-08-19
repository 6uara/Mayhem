# MAYHEM

**Ten waves. One run. No saves.**

A first-person arena shooter built in Godot 4.7. You get one run through ten escalating waves,
spending what you earn between them, with a broadcast host narrating your performance whether
you want the commentary or not.

## Status

Version 0.3 — in development, heading for a public release on itch.io.

## Playing

Download a build from the itch.io page and run it. Nothing to install, no account, no network
connection — the game never talks to a server, and your best runs live in a local save file.

## Building from source

Requires Godot **4.7-stable** with matching export templates.

```bash
# Run the test suite
godot --headless -s addons/gut/gut_cmdln.gd -gexit

# Export a release build
godot --headless --export-release "Windows Release" builds/release/mayhem.exe
```

`export_presets.cfg` is gitignored — see [docs/EXPORT.md](docs/EXPORT.md) to recreate it, and for
the exclude filter that keeps tests, docs and unused addons out of shipping builds.

## Documentation

- [docs/EXPORT.md](docs/EXPORT.md) — export presets, feature tags, pre-release checklist
- [docs/TESTING.md](docs/TESTING.md) — test suite layout and conventions
- [docs/ADDONS.md](docs/ADDONS.md) — which addons are installed and why

## Licence

Copyright (c) 2026 Juan Guaragnini. All rights reserved.

MAYHEM is **proprietary** — the source and assets in this repository are not open source and
carry no permissive licence. Playing the published builds and streaming or monetising video of
your own sessions is explicitly fine; redistributing the game or reusing its code and assets is
not. Full terms in [LICENSE](LICENSE).

Bundled third-party components keep their own licences — see [THIRD_PARTY.md](THIRD_PARTY.md).
