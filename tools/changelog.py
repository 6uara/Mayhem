"""Arma el CHANGELOG desde los Conventional Commits y propone la version siguiente.

    python tools/changelog.py                 # muestra la seccion nueva, no escribe nada
    python tools/changelog.py --write         # la agrega arriba de CHANGELOG.md, "Sin publicar"
    python tools/changelog.py --write --bump  # como version: sube application/config/version
    python tools/changelog.py --since v0.3.0  # desde otra referencia

Desde donde: el ultimo tag `vX.Y.Z` alcanzable desde HEAD. Si no hay ninguno (el
repo no taggeo versiones hasta 0.3.0), el commit que puso la version actual en
project.godot.

Version semantica, con la regla de antes de 1.0: un cambio que rompe (`!` en el
tipo o `BREAKING CHANGE:` en el cuerpo) sube la minor, no la major - en 0.x la
major queda para el release. `feat` sube la minor, `fix` y `perf` la patch, lo
demas no mueve la version.

Para el release: `--write --bump`, revisar el texto, commitear
(`chore(release): vX.Y.Z`) y taggear `vX.Y.Z` sobre ese commit. El tag es lo que
hace que la proxima corrida arranque de ahi.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "project.godot"
CHANGELOG = ROOT / "CHANGELOG.md"

HEADER_RE = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]+)\))?(?P<bang>!)?:\s*(?P<subject>.+)$")
VERSION_RE = re.compile(r'^config/version="(?P<version>[^"]+)"', re.MULTILINE)
SEPARATOR = "\x1f"
RECORD_END = "\x1e"

# Titulo de cada seccion, en el orden en que salen. Lo que no esta aca (chore,
# test, ci, style, build) es trabajo interno: cuenta en el resumen, no en el
# texto para el jugador.
SECTIONS = [
    ("breaking", "Cambios que rompen"),
    ("feat", "Agregado"),
    ("fix", "Corregido"),
    ("perf", "Rendimiento"),
    ("refactor", "Interno"),
    ("docs", "Documentacion"),
]


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout


def current_version() -> str:
    match = VERSION_RE.search(PROJECT.read_text(encoding="utf-8"))
    return match.group("version") if match else "0.0.0"


def find_base() -> str | None:
    tags = git("tag", "--list", "v[0-9]*", "--merged", "HEAD", "--sort=-v:refname").split()
    if tags:
        return tags[0]
    version = current_version()
    found = git("log", "--format=%H", f"-Sconfig/version=\"{version}\"", "--",
                "project.godot").split()
    # El mas viejo de los que tocaron esa cadena: el que la puso.
    return found[-1] if found else None


def read_commits(base: str | None) -> list[dict]:
    span = f"{base}..HEAD" if base else "HEAD"
    raw = git("log", span, "--no-merges",
              f"--format=%h{SEPARATOR}%s{SEPARATOR}%b{RECORD_END}")
    commits = []
    for record in raw.split(RECORD_END):
        record = record.strip("\n")
        if not record:
            continue
        sha, subject, body = (record.split(SEPARATOR) + ["", ""])[:3]
        match = HEADER_RE.match(subject.strip())
        if not match:
            commits.append({"sha": sha, "type": "other", "scope": "", "subject": subject,
                            "breaking": False})
            continue
        commits.append({
            "sha": sha,
            "type": match.group("type"),
            "scope": match.group("scope") or "",
            "subject": match.group("subject").strip(),
            "breaking": bool(match.group("bang")) or "BREAKING CHANGE:" in body,
        })
    return commits


def next_version(version: str, commits: list[dict]) -> str:
    try:
        major, minor, patch = (int(part) for part in version.split(".")[:3])
    except ValueError:
        return version
    breaking = any(c["breaking"] for c in commits)
    feature = any(c["type"] == "feat" for c in commits)
    fix = any(c["type"] in ("fix", "perf") for c in commits)
    if breaking:
        if major == 0:
            return f"0.{minor + 1}.0"
        return f"{major + 1}.0.0"
    if feature:
        return f"{major}.{minor + 1}.0"
    if fix:
        return f"{major}.{minor}.{patch + 1}"
    return version


def render(version: str, commits: list[dict], released: bool = True) -> str:
    # Sin --bump la seccion es lo que se junto desde la ultima version, todavia
    # sin numero: el numero lo pone el release, no cada corrida.
    title = f"## {version} - {date.today().isoformat()}" if released \
        else f"## Sin publicar (proxima: {version})"
    lines = [title, ""]
    for key, title in SECTIONS:
        if key == "breaking":
            entries = [c for c in commits if c["breaking"]]
        else:
            entries = [c for c in commits if c["type"] == key and not c["breaking"]]
        if not entries:
            continue
        lines.append(f"### {title}")
        lines.append("")
        for commit in sorted(entries, key=lambda c: (c["scope"], c["subject"])):
            scope = f"**{commit['scope']}**: " if commit["scope"] else ""
            lines.append(f"- {scope}{commit['subject']} ({commit['sha']})")
        lines.append("")
    others = [c for c in commits if c["type"] == "other"]
    internal = len(commits) - sum(1 for c in commits
                                  if c["breaking"] or c["type"] in dict(SECTIONS))
    if internal:
        lines.append(f"_{internal} commits internos (chore, test, ci...)"
                     + (f", {len(others)} sin formato convencional" if others else "")
                     + "._")
        lines.append("")
    return "\n".join(lines)


def write_changelog(section: str) -> None:
    title = "# Changelog\n\nGenerado con `tools/changelog.py` desde los Conventional Commits.\n\n"
    existing = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else title
    if not existing.startswith("# Changelog"):
        existing = title + existing
    # Una seccion "Sin publicar" vieja se reemplaza, no se apila.
    if "\n## Sin publicar" in existing:
        before, _, after = existing.partition("\n## Sin publicar")
        _, sep, later = after.partition("\n## ")
        existing = before + ("\n## " + later if sep else "\n")
    head, _, rest = existing.partition("\n## ")
    body = head.rstrip() + "\n\n" + section.rstrip() + "\n"
    if rest:
        body += "\n## " + rest
    CHANGELOG.write_text(body, encoding="utf-8", newline="\n")


def bump(version: str) -> None:
    text = PROJECT.read_text(encoding="utf-8")
    PROJECT.write_text(VERSION_RE.sub(f'config/version="{version}"', text, count=1),
                       encoding="utf-8", newline="\n")


def main() -> int:
    # La consola de Windows no es UTF-8 por defecto: "Daño" salia roto.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--since", help="referencia desde donde (tag, commit)")
    parser.add_argument("--write", action="store_true", help="escribir CHANGELOG.md")
    parser.add_argument("--bump", action="store_true", help="subir la version en project.godot")
    parser.add_argument("--version", help="forzar la version de la seccion")
    args = parser.parse_args()

    base = args.since or find_base()
    commits = read_commits(base)
    if not commits:
        print(f"Nada nuevo desde {base}.")
        return 0
    old = current_version()
    new = args.version or next_version(old, commits)
    section = render(new, commits, released=args.bump)
    print(f"desde {base or 'el principio'}: {len(commits)} commits, {old} -> {new}\n",
          file=sys.stderr)
    print(section)
    if args.write:
        write_changelog(section)
        print(f"escrito {CHANGELOG.relative_to(ROOT)}", file=sys.stderr)
    if args.bump and new != old:
        bump(new)
        print(f"project.godot: {old} -> {new}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
