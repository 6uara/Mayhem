"""Lista los archivos de assets/ que nada del proyecto referencia.

El export usa `all_resources`: todo lo importado viaja en el .pck, se use o no.
Medido al escribir esto, assets/ pesaba ~230 MB y el build 210 MB, con packs
enteros de flipbooks, texturas de ruido y modelos de armas que ninguna escena
toca. Esto los encuentra para poder sacarlos del export (`exclude_filter`, ver
docs/EXPORT.md) sin borrarlos del repo.

Una referencia es la ruta `res://...` del archivo, o el `uid://` que Godot le
asigno en su `.import`, en cualquier .tscn/.tres/.gd/.gdshader/.godot/.cfg.
Lo que el codigo arma por formato (`res://assets/audio/voice/%s/%s.ogg`) no se
puede ver asi: esas carpetas van en DYNAMIC y nunca se listan.

    python tools/find_unused_assets.py            # lista y totales
    python tools/find_unused_assets.py --filter   # carpetas enteras, para el exclude_filter
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_EXT = (".tscn", ".tres", ".gd", ".gdshader", ".godot", ".cfg", ".import")
ASSET_DIR = "assets"
# Carpetas que el codigo lee armando la ruta en tiempo de ejecucion.
DYNAMIC = ("assets/audio/voice/",)
# Lo que nunca va en un build aunque nadie lo referencie: es fuente.
SOURCE_EXT = (".blend", ".blend1", ".psd", ".kra", ".xcf")


def _rel(path: str) -> str:
    return os.path.relpath(path, ROOT).replace("\\", "/")


def _compact(unused: list[str], every: list[str]) -> list[str]:
    """Solo carpetas enteras sin usar, como `carpeta/*`.

    Archivo por archivo no: una textura que ninguna escena nombra puede ser la que
    un .fbx usa por dentro (ak47_0.png la usa ak47.fbx, que si esta en uso), y
    sacarla del build deja el modelo blanco. Lo suelto se revisa a mano con el
    listado sin --filter.
    """
    unused_set = set(unused)
    patterns: list[str] = []
    covered: set[str] = set()
    folders = sorted({os.path.dirname(rel) for rel in unused}, key=len)
    for folder in folders:
        if any(folder.startswith(done + "/") or folder == done for done in covered):
            continue
        inside = [rel for rel in every if rel.startswith(folder + "/")]
        if inside and all(rel in unused_set for rel in inside):
            patterns.append(folder + "/*")
            covered.add(folder)
    return patterns


def main() -> int:
    uid_of: dict[str, str] = {}
    assets: list[str] = []
    for folder, _dirs, files in os.walk(os.path.join(ROOT, ASSET_DIR)):
        for name in files:
            path = os.path.join(folder, name)
            rel = _rel(path)
            if name.endswith(".import"):
                with open(path, encoding="utf-8", errors="ignore") as handle:
                    match = re.search(r'uid="(uid://[a-z0-9]+)"', handle.read())
                if match:
                    uid_of[rel[: -len(".import")]] = match.group(1)
                continue
            if name.endswith(".uid"):
                continue
            assets.append(rel)

    corpus_parts: list[str] = []
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "builds")]
        for name in files:
            if not name.endswith(SCAN_EXT):
                continue
            path = os.path.join(folder, name)
            # El .import de un asset no cuenta como referencia a si mismo.
            if name.endswith(".import"):
                continue
            with open(path, encoding="utf-8", errors="ignore") as handle:
                corpus_parts.append(handle.read())
    corpus = "\n".join(corpus_parts)

    unused: list[tuple[str, int]] = []
    for rel in assets:
        if rel.startswith(DYNAMIC):
            continue
        res_path = "res://" + rel
        uid = uid_of.get(rel, "")
        if res_path in corpus or (uid and uid in corpus):
            continue
        unused.append((rel, os.path.getsize(os.path.join(ROOT, rel))))

    unused.sort()
    total = sum(size for _rel_path, size in unused)
    if "--filter" in sys.argv:
        print(",".join(_compact([rel for rel, _size in unused], assets)))
        return 0
    for rel, size in unused:
        print("%8.1f KB  %s" % (size / 1024.0, rel))
    print("\n%d unused files, %.1f MB" % (len(unused), total / 1024.0 / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
