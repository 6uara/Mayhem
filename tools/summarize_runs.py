"""Resume los logs de RunLogger (user://runs/run_*.json) de una tanda de playtest.

    python tools/summarize_runs.py <carpeta>
    python tools/summarize_runs.py <carpeta> --by-layers
    python tools/summarize_runs.py <carpeta> --json      # el resumen como JSON

Contesta las preguntas de docs/PLAYTEST.md: en que ola y de que se muere, si la
movilidad se usa, si la tienda se lee, si los contratos y los pedidos del
publico se juegan. Solo libreria estandar: lo corre cualquiera que tenga Python.

Lee los formatos 2 a 4. Los campos que un formato viejo no tiene se cuentan como
ausentes, no como cero: un log del formato 2 no dice nada del gancho, y
promediarlo como "cero ganchos" mentiria.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path


def load_runs(folder: Path) -> list[dict]:
    runs = []
    for path in sorted(folder.rglob("run_*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"  salteo {path.name}: {error}", file=sys.stderr)
            continue
        data["_file"] = path.name
        runs.append(data)
    return runs


def _mean(values: list[float]) -> float | None:
    return round(statistics.fmean(values), 2) if values else None


def summarize(runs: list[dict]) -> dict:
    deaths = Counter()
    killers = Counter()
    damage = Counter()
    per_wave: dict[int, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    contracts_offered = 0
    contracts_signed = 0
    contracts_paid = 0
    requests_total = 0
    requests_done = 0
    purchases = Counter()
    victories = 0

    for run in runs:
        if run.get("victory"):
            victories += 1
        else:
            deaths[int(run.get("died_in_wave", -1)) + 1] += 1
        if run.get("killed_by"):
            killers[run["killed_by"]] += 1
        for cause, amount in run.get("damage_by_cause", {}).items():
            damage[cause] += float(amount)
        for purchase in run.get("purchases", []):
            purchases[purchase.get("item", "?")] += 1

        for wave in run.get("waves", []):
            number = int(wave.get("index", -1)) + 1
            bucket = per_wave[number]
            bucket["damage"].append(float(wave.get("damage_taken", 0.0)))
            if wave.get("cleared") and wave.get("par_time"):
                bucket["over_par"].append(
                    float(wave.get("duration", 0.0)) / float(wave["par_time"]))
            if "rating_avg" in wave:
                bucket["rating_avg"].append(float(wave["rating_avg"]))
            if "shop_seconds" in wave:
                bucket["shop_s"].append(float(wave["shop_seconds"]))
            if "gadgets_used" in wave:
                bucket["gadgets"].append(float(wave["gadgets_used"]))
            movement = wave.get("movement")
            if isinstance(movement, dict):
                for key in ("grapples", "fast_falls", "slide_s", "air_s", "still_s",
                            "avg_speed", "seconds"):
                    if key in movement:
                        bucket[key].append(float(movement[key]))
            offered = [o for o in wave.get("rules_offered", []) if str(o).startswith("contract:")]
            contracts_offered += len(offered)
            if wave.get("contract"):
                contracts_signed += 1
                if int(wave.get("contract_paid", 0)) > 0:
                    contracts_paid += 1
            for request in wave.get("crowd_requests", []):
                requests_total += 1
                requests_done += 1 if request.get("success") else 0

    waves = {}
    for number in sorted(per_wave):
        bucket = per_wave[number]
        row = {key: _mean(values) for key, values in bucket.items()}
        row["runs"] = len(bucket["damage"])
        seconds = bucket.get("seconds") or []
        if seconds and bucket.get("still_s"):
            # La fraccion de la oleada parado en el piso: el numero que dice si
            # el pilar de la movilidad se juega.
            row["still_share"] = round(sum(bucket["still_s"]) / max(sum(seconds), 0.01), 2)
        waves[number] = row

    total_damage = sum(damage.values()) or 1.0
    return {
        "runs": len(runs),
        "victories": victories,
        "deaths_by_wave": dict(sorted(deaths.items())),
        "killed_by": dict(killers.most_common()),
        "damage_share": {cause: round(amount / total_damage, 2)
                         for cause, amount in damage.most_common()},
        "contracts": {"offered": contracts_offered, "signed": contracts_signed,
                      "paid": contracts_paid},
        "crowd_requests": {"started": requests_total, "done": requests_done},
        "top_purchases": dict(purchases.most_common(10)),
        "waves": waves,
    }


def print_summary(title: str, summary: dict) -> None:
    print(f"\n=== {title}  ({summary['runs']} runs, {summary['victories']} victorias)")
    print("Muertes por ola:", summary["deaths_by_wave"] or "-")
    print("Lo que mato:    ", summary["killed_by"] or "-")
    print("Daño por origen:", summary["damage_share"] or "-")
    c = summary["contracts"]
    print(f"Contratos:       ofrecidos {c['offered']}, firmados {c['signed']}, pagados {c['paid']}")
    r = summary["crowd_requests"]
    print(f"Pedidos:         {r['done']} cumplidos de {r['started']}")
    print("Mas comprado:   ", summary["top_purchases"] or "-")
    columns = ["runs", "damage", "over_par", "rating_avg", "shop_s", "gadgets", "grapples",
               "fast_falls", "slide_s", "air_s", "still_share", "avg_speed"]
    print("\nola " + " ".join(f"{name:>11}" for name in columns))
    for number, row in summary["waves"].items():
        cells = []
        for name in columns:
            value = row.get(name)
            cells.append(f"{'-' if value is None else value:>11}")
        print(f"{number:>3} " + " ".join(cells))


def main() -> int:
    # La consola de Windows no es UTF-8 por defecto: "Daño" salia roto.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", type=Path)
    parser.add_argument("--by-layers", action="store_true",
                        help="una tabla por combinacion de capas apagadas (layers_off)")
    parser.add_argument("--json", action="store_true", help="imprimir el resumen como JSON")
    args = parser.parse_args()

    runs = load_runs(args.folder)
    if not runs:
        print(f"No hay run_*.json en {args.folder}", file=sys.stderr)
        return 1

    groups: dict[str, list[dict]] = {"todas": runs}
    if args.by_layers:
        groups = defaultdict(list)
        for run in runs:
            off = run.get("layers_off")
            key = "sin datos de capas" if off is None else (
                "todo encendido" if not off else "sin " + ", ".join(off))
            groups[key].append(run)

    summaries = {name: summarize(group) for name, group in groups.items()}
    if args.json:
        print(json.dumps(summaries, indent=2, ensure_ascii=False))
    else:
        for name, summary in summaries.items():
            print_summary(name, summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
