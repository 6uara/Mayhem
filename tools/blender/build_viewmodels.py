"""Prepara para el juego los viewmodels de Meshy: brazos y arma en una sola malla.

    blender -b --python tools/blender/build_viewmodels.py -- <id>      (o "all")

<id> es una clave de VIEWMODELS. Lee el .glb fuente de
assets/models/Arms/New ArmGuns/ (que queda con importer="skip") y escribe
assets/models/viewmodels/<id>.glb.

Reemplaza al par build_fp_arms.py + build_weapons.py: los brazos ya no son un rig
con IK que busca la empuñadura de un arma aparte, vienen modelados agarrandola.
Llegan de a 1.2 a 1.4 millones de triangulos y con texturas de 4K; se ven de muy
cerca pero ocupan media pantalla como mucho, asi que se deciman a `faces` y las
texturas bajan a TEXTURE_SIZE.

Cada uno sale:

- Con la boca del cañon hacia +Y de Blender (-Z en Godot) y Z arriba. Meshy los
  entrega cada uno girado a su manera; `yaw` los endereza.
- Centrado en su caja y a escala SCALE (Meshy los normaliza a unos 1.9 m de
  largo). El tamaño en pantalla lo da `WeaponData.viewmodel_scale`.
- Con un Empty "Muzzle" en la boca del cañon: el punto mas adelantado del
  modelo, que en los cuatro es el arma y no una mano. WeaponComponent pone ahi
  el fogonazo y de ahi salen los tiros. Antes se medía sobre la caja del arma
  sola; con los brazos adentro, la caja ya no dice donde esta el cañon.
"""

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE_DIR = os.path.join(ROOT, "assets", "models", "Arms", "New ArmGuns")
OUTPUT_DIR = os.path.join(ROOT, "assets", "models", "viewmodels")
TEXTURE_SIZE = 2048
SCALE = 0.5
# Que tan atras de la punta se juntan los vertices que definen la boca: lo que
# queda en los primeros milimetros del cañon, no el cañon entero.
MUZZLE_DEPTH = 0.01

VIEWMODELS = {
    # `yaw` en grados alrededor de Z, para que la boca quede hacia +Y.
    "pistol": {"source": "fps_cybernetic_viewmo.glb", "faces": 60000, "yaw": 0.0},
    "smg": {"source": "fps_cybernetic_viewmoSMG.glb", "faces": 60000, "yaw": -90.0},
    "rifle": {"source": "FPS_Viewmodel_Arms_an.glb", "faces": 60000, "yaw": -90.0},
    # Meshy la entrego con el arma girada unos 26 grados respecto de los brazos:
    # se endereza el arma, que es la que tiene que apuntar adonde va el tiro.
    "shotgun": {"source": "fps_cyber_shotgun_vie.glb", "faces": 60000, "yaw": 154.3},
}


def main():
    key = sys.argv[sys.argv.index("--") + 1]
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name in (VIEWMODELS if key == "all" else [key]):
        build(name, VIEWMODELS[name])


def build(name, config):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SOURCE_DIR, config["source"]))
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

    body.data.transform(Matrix.Rotation(math.radians(config["yaw"]), 4, "Z"))
    _decimate(body, config["faces"])
    low, high = _bounds(body)
    centre = (low + high) * 0.5
    body.data.transform(Matrix.Scale(SCALE, 4) @ Matrix.Translation(-centre))
    for poly in body.data.polygons:
        poly.use_smooth = True
    for image in bpy.data.images:
        if image.size[0] > TEXTURE_SIZE:
            image.scale(TEXTURE_SIZE, TEXTURE_SIZE)

    muzzle = bpy.data.objects.new("Muzzle", None)
    bpy.context.scene.collection.objects.link(muzzle)
    muzzle.location = _muzzle_point(body)

    output = os.path.join(OUTPUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    muzzle.select_set(True)
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
    print("VIEWMODEL written", output, "faces", len(body.data.polygons),
          "size", tuple(round(d, 3) for d in body.dimensions),
          "muzzle", tuple(round(c, 3) for c in muzzle.location))


## La boca: el centro de los vertices que estan en los primeros milimetros del
## frente (+Y). Un solo vertice era cualquier esquina del freno de boca.
def _muzzle_point(obj):
    tip = max(v.co.y for v in obj.data.vertices)
    front = [v.co for v in obj.data.vertices if v.co.y >= tip - MUZZLE_DEPTH]
    x = sum(c.x for c in front) / len(front)
    z = sum(c.z for c in front) / len(front)
    return Vector((x, tip, z))


## Ver build_props.py: glTF parte los vertices en cada costura de UV, y decimado
## asi el borde se abre en grietas. Se sueldan antes.
def _weld(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()


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


main()
