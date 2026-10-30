"""Hace la version toon de las texturas de color de los modelos.

    godot --headless --path . -s tools/list_albedo_textures.gd -- albedo.json
    blender -b --python tools/blender/flatten_textures.py -- albedo.json [colores] [radio] [saturacion]

Por cada textura de la lista escribe `<nombre>_toon.png` al lado y no toca la
original: ToonStyle cambia una por otra en el juego cuando el estilo toon esta
prendido, asi que apagarlo sigue mostrando los modelos como llegaron de Meshy.

Tres pasos, en este orden:

1. Un desenfoque chico (`radio`, en pixeles de una textura de 1024; escala con el
   tamaño). Borra la mugre, los rayones y el grano que Meshy pinta encima de todo,
   que con la luz en bandas es lo que mas delata el origen realista. Va antes de
   reducir colores para que las manchas salgan limpias y no moteadas.
2. Reducir la textura a `colores` tonos (k-means sobre una muestra, default 8).
   Son las manchas planas del toon. Por textura y no una paleta global: cada
   modelo conserva sus colores.
3. Un poco mas de saturacion (default 1.15). Al perder el detalle el color es lo
   que queda para leer la pieza: el azul del piso, el color de cada arquetipo.

Determinista (semilla fija): correrlo dos veces da los mismos archivos.
"""

import json
import os
import sys

import bpy
import numpy as np

DEFAULT_COLORS = 8
DEFAULT_RADIUS = 2.0
DEFAULT_SATURATION = 1.15
REFERENCE_SIZE = 1024
KMEANS_SAMPLES = 40000
KMEANS_ITERATIONS = 16
SEED = 1337
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    with open(args[0], encoding="utf-8") as handle:
        paths = json.load(handle)
    colors = int(args[1]) if len(args) > 1 else DEFAULT_COLORS
    radius = float(args[2]) if len(args) > 2 else DEFAULT_RADIUS
    saturation = float(args[3]) if len(args) > 3 else DEFAULT_SATURATION
    for path in paths:
        flatten(path, colors, radius, saturation)


def flatten(path, colors, radius, saturation):
    source = bpy.data.images.load(path)
    width, height = source.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    source.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    rgb = pixels[:, :, :3]

    scaled = max(1, int(round(radius * width / REFERENCE_SIZE)))
    rgb = _box_blur(rgb, scaled)
    rgb = _quantize(rgb, colors)
    luma = (rgb @ LUMA)[:, :, None]
    rgb = np.clip(luma + (rgb - luma) * saturation, 0.0, 1.0)

    out = np.concatenate([rgb, pixels[:, :, 3:4]], axis=2).astype(np.float32)
    target = os.path.splitext(path)[0] + "_toon.png"
    image = bpy.data.images.new(os.path.basename(target), width, height, alpha=True)
    image.pixels.foreach_set(out.ravel())
    image.filepath_raw = target
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    bpy.data.images.remove(source)
    print("TOON written", target, "%dx%d" % (width, height), "blur", scaled)


## Desenfoque de caja separable con sumas acumuladas: el costo no depende del
## radio, y con numpy una textura de 2K tarda una fraccion de segundo.
def _box_blur(rgb, radius):
    result = rgb
    for axis in (0, 1):
        padded = np.pad(result, [(radius + 1, radius) if a == axis else (0, 0)
                                 for a in range(3)], mode="edge")
        summed = np.cumsum(padded, axis=axis, dtype=np.float64)
        size = result.shape[axis]
        upper = np.take(summed, np.arange(2 * radius + 1, 2 * radius + 1 + size), axis=axis)
        lower = np.take(summed, np.arange(0, size), axis=axis)
        result = ((upper - lower) / (2 * radius + 1)).astype(np.float32)
    return result


def _quantize(rgb, colors):
    flat = rgb.reshape(-1, 3)
    rng = np.random.default_rng(SEED)
    sample = flat[rng.choice(len(flat), size=min(KMEANS_SAMPLES, len(flat)), replace=False)]
    centers = _kmeans_init(sample, colors, rng)
    for _ in range(KMEANS_ITERATIONS):
        labels = _nearest(sample, centers)
        for k in range(len(centers)):
            members = sample[labels == k]
            if len(members):
                centers[k] = members.mean(axis=0)
    labels = np.concatenate([_nearest(chunk, centers)
                             for chunk in np.array_split(flat, max(1, len(flat) // 262144))])
    return centers[labels].reshape(rgb.shape)


## k-means++: cada centro nuevo lejos de los que ya hay. Con un inicio al azar,
## un color chico pero importante (la franja de acento de un enemigo) se lo come
## el azul del cuerpo.
def _kmeans_init(sample, colors, rng):
    centers = [sample[rng.integers(len(sample))]]
    for _ in range(1, colors):
        distance = np.min(((sample[:, None, :] - np.array(centers)[None, :, :]) ** 2).sum(axis=2),
                          axis=1)
        total = distance.sum()
        if total <= 0.0:
            break
        centers.append(sample[rng.choice(len(sample), p=distance / total)])
    return np.array(centers, dtype=np.float32)


def _nearest(points, centers):
    return np.argmin(((points[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2), axis=1)


main()
