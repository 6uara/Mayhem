"""Prepara para el juego los props de Meshy de assets/models/props/.

    blender -b --python tools/blender/build_props.py -- <id>      (o "all")

<id> es una clave de PROPS. Lee el .glb fuente (que queda con importer="skip")
y escribe <id>.glb al lado. Llegan de a 250 mil a 1.2 millones de triangulos y
con texturas de 4K; un piso que se repite mil veces en la arena no puede pesar
eso, asi que se decima a `faces` y las texturas bajan a TEXTURE_SIZE.

Dos clases de prop:

- Los interactuables y el venue (`size`): salen al tamaño en metros con que se
  usan, la base en y = 0 y centrados. La escena los pone tal cual.
- Las piezas de arena (`unit`): salen normalizadas a la caja de una celda, x y z
  de -0.5 a 0.5 e y de 0 a 1, para que PieceMeshBuilder las estire sobre la
  misma caja que usa la colision greybox. y = 1 es la superficie que se pisa,
  no la punta del modelo: `z0` y `z1` dicen que altura del modelo (en unidades de
  Blender, como llega) va a 0 y cual a 1. Lo que sobresale por encima de 1 (las
  barandas de la pasarela) queda por encima de la colision, que es lo correcto.

Todo con Z arriba y el frente a +Y de Blender, que es -Z en Godot.
"""

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROPS_DIR = os.path.join(ROOT, "assets", "models", "props")
TEXTURE_SIZE = 1024
# A cuanto se baja la malla original antes de hornear sus normales sobre la
# decimada: el horneado con millones de triangulos tarda sin ganar nada a 1024.
BAKE_SOURCE_FACES = 150000

PROPS = {
    # Interactuables. `size` es (ancho, alto, profundidad) en metros; un None se
    # deriva del resto manteniendo la proporcion.
    "ammo_crate": {"source": "Interactive_Ammo_Crat.glb", "faces": 4000,
                   "size": (None, 0.75, None)},
    # Achatado: el pad no tiene colision solida, el jugador lo pisa por dentro
    # hasta que lo lanza, y medio metro de pad le tapaba las piernas.
    "jump_pad": {"source": "Interactive_Jump_Pad_.glb", "faces": 4000,
                 "size": (2.5, 0.32, 2.5)},
    "spawn_door": {"source": "Interactive_Spawn_Doo.glb", "faces": 6000,
                   "size": (None, 4.0, None)},
    # El gancho del ancla de grapple: cuelga, el aro de arriba es el soporte.
    # Sus franjas llegan cyan, que es el color de "se usa"; el ancla tiene el suyo
    # (Tokens.WORLD_GRAPPLE, violeta #A855FF = tono 0.755). `accent` repinta los
    # pixeles de ese rango de tono y los hace emitir.
    "grapple_hook": {"source": "Meshy_AI_Interactive_Grapple_A_1028234850_image-to-3d-texture.glb",
                     "faces": 6000, "size": (None, 1.6, None),
                     "accent": {"hues": (0.42, 0.6), "to": 0.755, "glow": 2.5}},
    # La plataforma movil: la misma caja que su colision (3.8 x 0.4 x 3.8). Las
    # flechas llegan apuntando a +X y la plataforma viaja por su +Z de Godot
    # (-Y de Blender): se gira para que marquen el recorrido.
    "moving_platform": {"source": "Meshy_AI_Interactive_Moving_Pl_1028234904_image-to-3d-texture.glb",
                        "faces": 6000, "size": (3.8, 0.4, 3.8), "yaw": -90.0},
    # El venue lo escala a lo ancho de la arena (ArenaColiseum.jumbotron_width).
    "jumbotron": {"source": "Venue_Jumbotron_3D.glb", "faces": 20000,
                  "size": (1.0, None, None)},
    # Piezas de arena. Medidas en un perfil de cada modelo.
    # Se hornea sobre una caja biselada (ver _bake_to_box): `faces` es lo que se
    # decima la fuente antes de hornear, no lo que sale.
    "floor_tile": {"source": "Modular_Floor_Tile_3D.glb", "faces": 60000,
                   "unit": True, "z1": 0.128, "bake": 0.03},
    # Variantes de la baldosa, mezcladas en el piso por PieceDefinition.art_variants:
    # la misma caja horneada, asi que pesan lo mismo que la base.
    "floor_damaged": {"source": "Floor_Damaged_3D.glb", "faces": 60000,
                      "unit": True, "bake": 0.03},
    "floor_circuits": {"source": "Floor_Tech_Circuits_3.glb", "faces": 60000,
                       "unit": True, "bake": 0.03},
    "floor_vent": {"source": "Floor_Vent_3D.glb", "faces": 60000,
                   "unit": True, "bake": 0.03},
    # La cubierta esta a -0.022; las barandas llegan a 0.121. Llega a lo largo
    # de X y la pieza es larga en Z de Godot: se gira.
    "catwalk": {"source": "Modular_Catwalk_3D.glb", "faces": 20000,
                "unit": True, "z0": -0.122, "z1": -0.022, "yaw": 90.0},
    # Sube hacia +Y de Blender (-Z de Godot). La superficie va de -0.068 en la
    # punta baja a 0.296 en la alta; la base (-0.285) queda debajo de 0, metida
    # en la baldosa de abajo, para que la rampa arranque al ras del piso.
    "ramp": {"source": "Modular_Ramp_3D.glb", "faces": 10000,
             "unit": True, "z0": -0.068, "z1": 0.296},
    "support": {"source": "Modular_Structural_Su.glb", "faces": 12000, "unit": True},
    "cover_low": {"source": "Modular_Cover_Low_3D.glb", "faces": 4000, "unit": True},
    "wall_1x1": {"source": "Modular_Wall_1x1_3D.glb", "faces": 3000, "unit": True},
    "wall_2x1": {"source": "Modular_Wall_2x1_3D.glb", "faces": 3000, "unit": True},
    # Una L con los brazos sobre +X y +Y de Blender y el hueco en -X -Y. La pieza
    # la gira (art_yaw_degrees) para que la esquina quede en su celda de origen.
    "wall_corner": {"source": "Modular_Wall_Corner_3.glb", "faces": 4000, "unit": True},
}


def main():
    key = sys.argv[sys.argv.index("--") + 1]
    for name in (PROPS if key == "all" else [key]):
        build(name, PROPS[name])


def build(name, config):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROPS_DIR, config["source"]))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        obj.data.transform(obj.matrix_world)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = meshes[0]
    body.name = "Body"

    if config.get("yaw"):
        body.data.transform(Matrix.Rotation(math.radians(config["yaw"]), 4, "Z"))
    if config.get("bake"):
        _decimate(body, config["faces"])
        body = _bake_to_box(body, config.get("z1"), config["bake"])
        config = dict(config, z1=None)
    else:
        high = body.copy()
        high.data = body.data.copy()
        bpy.context.scene.collection.objects.link(high)
        _decimate(high, BAKE_SOURCE_FACES)
        _decimate(body, config["faces"])
        _rebake_normals(high, body)
    if config.get("unit"):
        _normalize_unit(body, config.get("z0"), config.get("z1"))
    else:
        _normalize_size(body, config["size"])
    for poly in body.data.polygons:
        poly.use_smooth = True
    if config.get("accent"):
        _recolor_accent(body, config["accent"])
    for image in bpy.data.images:
        if image.size[0] > TEXTURE_SIZE:
            image.scale(TEXTURE_SIZE, TEXTURE_SIZE)

    output = os.path.join(PROPS_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=output,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_image_format="JPEG",
    )
    print("PROP written", output, "faces", len(body.data.polygons),
          "size", tuple(round(d, 3) for d in body.dimensions))


## La baldosa va mil veces en la arena por defecto: no se puede decimar a lo que
## cuesta eso (a 800 triangulos quedaba hecha astillas, la malla de Meshy no tiene
## caras planas que juntar). Lo que se hace es hornear su color, su relieve y su
## rugosidad sobre una caja biselada de un centenar de triangulos con UV limpia.
## `z1` es la cara de arriba de la caja.
def _bake_to_box(high, z1, bevel):
    scene = bpy.context.scene
    low_corner, high_corner = _bounds(high)
    top = high_corner.z if z1 is None else z1
    size = Vector((high_corner.x - low_corner.x, high_corner.y - low_corner.y, top - low_corner.z))
    centre = Vector(((low_corner.x + high_corner.x) * 0.5, (low_corner.y + high_corner.y) * 0.5,
                     low_corner.z + size.z * 0.5))
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    low = bpy.context.object
    low.name = "Body"
    low.scale = size
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    modifier = low.modifiers.new("Bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 2
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    material = bpy.data.materials.new("Tile")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    low.data.materials.append(material)
    images = {}
    for kind, colour_space in (("color", "sRGB"), ("normal", "Non-Color"), ("roughness", "Non-Color")):
        image = bpy.data.images.new("tile_" + kind, TEXTURE_SIZE, TEXTURE_SIZE)
        image.colorspace_settings.name = colour_space
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        images[kind] = node

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = bevel
    bake.max_ray_distance = bevel * 3.0
    bake.margin = 8
    bake.use_pass_direct = False
    bake.use_pass_indirect = False
    bake.use_pass_color = True
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    for kind, bake_type in (("color", "DIFFUSE"), ("normal", "NORMAL"), ("roughness", "ROUGHNESS")):
        nodes.active = images[kind]
        bpy.ops.object.bake(type=bake_type)
        images[kind].image.pack()

    links.new(images["color"].outputs["Color"], bsdf.inputs["Base Color"])
    links.new(images["roughness"].outputs["Color"], bsdf.inputs["Roughness"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    links.new(images["normal"].outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.3
    bpy.data.objects.remove(high)
    return low


## El mapa de normales de Meshy esta hecho para la malla entera. Sobre la
## decimada las normales de los vertices ya no son las que el mapa supone, y el
## resultado era una superficie negra con astillas de luz (la caja de municion
## con las grietas ambar de su propia luz). Se rehace horneando la malla
## original sobre la decimada, con la UV que la decimada conserva.
def _rebake_normals(high, low):
    scene = bpy.context.scene
    material = low.active_material
    nodes = material.node_tree.nodes
    normal_map = next((n for n in nodes if n.type == "NORMAL_MAP"), None)
    if normal_map is None:
        bpy.data.objects.remove(high)
        return
    image = bpy.data.images.new(low.name + "_normal", TEXTURE_SIZE, TEXTURE_SIZE)
    image.colorspace_settings.name = "Non-Color"
    target = nodes.new("ShaderNodeTexImage")
    target.image = image
    nodes.active = target
    reach = max(low.dimensions) * 0.01
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = reach
    bake.max_ray_distance = reach * 3.0
    bake.margin = 8
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type="NORMAL")
    image.pack()
    material.node_tree.links.new(target.outputs["Color"], normal_map.inputs["Color"])
    bpy.data.objects.remove(high)


## glTF parte los vertices en cada costura de UV, y para Blender cada costura
## es un borde abierto: decimado asi, el borde se separa en una grieta, y por
## las grietas se veia el piso iluminado del otro lado (la caja de municion
## salpicada de puntos ambar). Se sueldan antes; la UV va por esquina de cara,
## asi que soldar no la pierde.
def _weld(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()


## Repinta los acentos de la textura de color (los pixeles saturados dentro de
## `hues`) al tono `to`, y con esos mismos pixeles arma un mapa de emision: las
## franjas del modelo pasan a ser luz de ese color, y lo demas queda como estaba.
def _recolor_accent(obj, accent):
    import colorsys
    import numpy as np
    nodes = obj.active_material.node_tree.nodes
    links = obj.active_material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    source = bsdf.inputs["Base Color"].links[0].from_node
    image = source.image
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = pixels[:, :3]
    high = rgb.max(axis=1)
    low = rgb.min(axis=1)
    span = np.where(high - low > 1e-6, high - low, 1.0)
    sat = np.where(high > 1e-6, (high - low) / np.maximum(high, 1e-6), 0.0)
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    hue = np.where(high == r, ((g - b) / span) % 6.0,
          np.where(high == g, (b - r) / span + 2.0, (r - g) / span + 4.0)) / 6.0
    lo, hi = accent["hues"]
    mask = (sat > 0.3) & (high > 0.2) & (hue >= lo) & (hue <= hi)
    target = np.array(colorsys.hsv_to_rgb(accent["to"], 1.0, 1.0), dtype=np.float32)
    # Mismo brillo y saturacion que tenia el acento, otro tono.
    recolored = (low[:, None] + (high - low)[:, None] * target[None, :])
    rgb[mask] = recolored[mask]
    pixels[:, :3] = rgb
    image.pixels = pixels.ravel().tolist()
    image.pack()
    glow = np.zeros_like(pixels)
    glow[:, 3] = 1.0
    glow[mask, :3] = recolored[mask]
    emission = bpy.data.images.new(obj.name + "_glow", width, height)
    emission.pixels = glow.ravel().tolist()
    emission.pack()
    node = nodes.new("ShaderNodeTexImage")
    node.image = emission
    links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = accent["glow"]
    print("ACCENT pixels", int(mask.sum()), "of", len(mask))


def _decimate(obj, faces):
    count = len(obj.data.polygons)
    _weld(obj)
    if count <= faces:
        return
    modifier = obj.modifiers.new("Decimate", "DECIMATE")
    modifier.ratio = faces / count
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def _bounds(obj):
    co = [v.co for v in obj.data.vertices]
    low = Vector([min(c[i] for c in co) for i in range(3)])
    high = Vector([max(c[i] for c in co) for i in range(3)])
    return low, high


def _normalize_unit(obj, z0, z1):
    low, high = _bounds(obj)
    z0 = low.z if z0 is None else z0
    z1 = high.z if z1 is None else z1
    centre = (low + high) * 0.5
    size = high - low
    to_unit = Matrix.Diagonal((1.0 / size.x, 1.0 / size.y, 1.0 / (z1 - z0), 1.0)) \
        @ Matrix.Translation((-centre.x, -centre.y, -z0))
    obj.data.transform(to_unit)


def _normalize_size(obj, wanted):
    low, high = _bounds(obj)
    size = high - low
    # (ancho, alto, profundidad) es (x, z, y) en Blender.
    axes = [(0, wanted[0]), (2, wanted[1]), (1, wanted[2])]
    known = [target / size[axis] for axis, target in axes if target is not None]
    uniform = known[0]
    scale = [target / size[axis] if target is not None else uniform for axis, target in axes]
    sx, sz, sy = scale
    centre = (low + high) * 0.5
    obj.data.transform(Matrix.Diagonal((sx, sy, sz, 1.0))
                       @ Matrix.Translation((-centre.x, -centre.y, -low.z)))


main()
