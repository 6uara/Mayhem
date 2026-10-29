"""Convierte un arma de Meshy en el viewmodel del juego, con su clip de recarga.

    blender -b assets/models/weapons/<Arma>.blend --python tools/blender/build_weapons.py

Sale a assets/models/weapons/<id>.glb (pistol, smg, rifle, shotgun: el id sale
del nombre del .blend, ver WEAPONS). El .blend no se toca: sigue siendo la
fuente de arte, y esto se vuelve a correr despues de editarlo.

Los cuatro llegan igual de Meshy: una sola malla cerrada de 100-240 mil
triangulos, de 1.9 m de largo sobre X con la boca del cañon hacia -X y Z
arriba, y tres texturas empaquetadas que se llaman igual en los cuatro
(Image_0..2). Por eso no se importan los .blend directo: Godot desempaqueta las
texturas a una carpeta compartida y las cuatro armas terminaban pisandose la
textura. El .glb las lleva adentro.

Lo que se hace:

- Decimar a ~40 mil triangulos. Un viewmodel se ve de cerca, pero 240 mil para
  una pistola es costo sin nada que mostrar.
- Separar la pieza que se mueve al recargar (cargador, corredera o guardamanos
  de bombeo) cortando la malla por una caja medida mirando el modelo de costado.
  Las dos piezas se cierran donde se corto, para que no se vea a traves.
- Escalar al largo que ya tenia el arma vieja en pantalla, asi viewmodel_scale
  queda en 1 y el encuadre no cambia.
- Un clip `reload` de 1 segundo que WeaponComponent recorre por el progreso de
  la recarga, no por reloj: cuadro 30 = recarga terminada, con la duracion que
  sea. Los tiempos acompañan a la mano izquierda de ViewmodelArms (suelta en
  0.1, cinturon 0.32-0.42, boca del cargador en 0.62, encastra en 0.72, vuelve
  en 0.9). El cuadro 0 y el 30 son la pose de reposo: una recarga cortada vuelve
  al reposo con solo buscar el cuadro 0.

La inclinacion del arma entera no esta aca sino en WeaponData
(`reload_tilt_degrees`): los brazos la tienen que seguir, y al clip no lo ven.
"""

import math
import os
import bpy
import bmesh
from mathutils import Vector

FPS = 30
FRAMES = 30
TARGET_FACES = 40000

# Cajas en unidades de Meshy (antes de escalar): x adelante-atras (-X es la
# boca), z abajo-arriba. Medidas de un render ortogonal de costado.
WEAPONS = {
    "Neonline_Pistol": {
        "id": "pistol",
        # Largo que tenia pew.fbx en pantalla (0.137 * viewmodel_scale 1.7).
        "length": 0.233,
        "part": "Slide",
        # La corredera: lo que esta por encima de la franja celeste, que es el
        # borde de arriba del armazon.
        "box": (-1.0, 1.0, 0.35, 1.0),
        "cuts": (("z", 0.35),),
    },
    "Neon_Specter_SMG": {
        "id": "smg",
        # Mas largo que el mac10 (0.32): este tiene culata.
        "length": 0.52,
        "part": "Magazine",
        "box": (-0.445, -0.295, -1.0, 0.07),
        "cuts": (("z", 0.07), ("x", -0.445), ("x", -0.295)),
    },
    "Neon_Striker_Rifle": {
        "id": "rifle",
        # ak47.fbx: 0.743 * 1.15.
        "length": 0.854,
        "part": "Magazine",
        "box": (-0.17, 0.13, -1.0, 0.09),
        "cuts": (("z", 0.09),),
    },
    "Shadowline_Shotgun": {
        "id": "shotgun",
        # shotgun.fbx: 0.634 * 1.15.
        "length": 0.729,
        "part": "Pump",
        "box": (-0.575, -0.245, -0.03, 0.09),
        "cuts": (("x", -0.575), ("x", -0.245)),
    },
}


def main():
    name = os.path.basename(bpy.data.filepath)
    config = next((c for key, c in WEAPONS.items() if key in name), None)
    if config is None:
        raise SystemExit("build_weapons: %s no esta en WEAPONS" % name)
    scene = bpy.context.scene
    scene.render.fps = FPS
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    body = next(o for o in bpy.data.objects if o.type == "MESH")
    body.name = "Body"
    # Cortar antes de decimar: decimada, una pared plana como la del cargador
    # queda en dos o tres triangulos largos que cruzan el corte, y la pieza sale
    # serruchada. Cada pieza se decima en la misma proporcion.
    ratio = min(TARGET_FACES / len(body.data.polygons), 1.0)
    part = _split(body, config["part"], config["box"], config["cuts"])
    for obj in (body, part):
        _decimate(obj, ratio)

    length = max(v.co.x for v in body.data.vertices) - min(v.co.x for v in body.data.vertices)
    scale = config["length"] / length
    meshes = [body, part]
    for obj in meshes:
        _origin_at(obj, _pivot_of(obj, config["part"]) if obj is part else Vector())
        _scale(obj, scale)

    if config["id"] == "shotgun":
        meshes.append(_shell(body))

    scene.frame_start = 0
    scene.frame_end = FRAMES
    ANIMATE[config["id"]](*meshes[1:])
    # Una sola animacion con el nombre que busca WeaponComponent: con un action
    # por objeto saldria un clip por pieza. El exportador junta en un clip las
    # pistas de NLA que se llaman igual.
    for obj in meshes[1:]:
        _to_nla(obj, "reload")

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    output = os.path.join(os.path.dirname(bpy.data.filepath), config["id"] + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=output,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=True,
        export_cameras=False,
        export_lights=False,
    )
    print("WEAPON written", output, "faces",
          sum(len(o.data.polygons) for o in meshes))


# Geometria

def _decimate(obj, ratio):
    if ratio >= 1.0:
        return
    modifier = obj.modifiers.new("Decimate", "DECIMATE")
    modifier.ratio = ratio
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


## Corta la pieza que esta dentro de `box` y la devuelve como objeto aparte.
## `cuts` son planos (eje, valor) por donde cortar antes, para que el borde de la
## pieza quede recto y no serruchado por los triangulos que cruzan la caja.
def _split(body, part_name, box, cuts):
    x0, x1, z0, z1 = box
    part = body.copy()
    part.data = body.data.copy()
    part.name = part_name
    bpy.context.scene.collection.objects.link(part)
    # Todo en bmesh y no con mesh.separate: el modo edicion recalcula la seleccion
    # desde los vertices, y se llevaba con el cargador las astillas de arriba del
    # corte cuyos tres vertices estaban en el borde.
    for obj, keep_inside in ((body, False), (part, True)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for axis, value in cuts:
            normal = (1.0, 0.0, 0.0) if axis == "x" else (0.0, 0.0, 1.0)
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(normal) * value, plane_no=normal)
        drop = []
        for f in bm.faces:
            c = f.calc_center_median()
            if (x0 <= c.x <= x1 and z0 <= c.z <= z1) != keep_inside:
                drop.append(f)
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        bm.to_mesh(obj.data)
        bm.free()
        _close(obj)
    return part


## Tapa los agujeros del corte. Las tapas nuevas no tienen UV propia y salian
## negras (el texel 0,0); toman la del borde que cierran, que es del mismo color
## que lo que rodea al corte.
def _close(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    old = set(bm.faces)
    edges = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    uv = bm.loops.layers.uv.active
    if uv is not None:
        for face in bm.faces:
            if face in old:
                continue
            for loop in face.loops:
                source = next((l for l in loop.vert.link_loops if l.face in old), None)
                if source is not None:
                    loop[uv].uv = source[uv].uv
    bm.to_mesh(obj.data)
    bm.free()


## Donde gira cada pieza: el cargador desde arriba (la boca del cargador), las
## piezas que se deslizan desde su centro.
def _pivot_of(obj, part_name):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    centre = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
    if part_name == "Magazine":
        centre.z = max(zs)
    return centre


def _origin_at(obj, point):
    bpy.context.scene.cursor.location = point
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")


def _scale(obj, factor):
    obj.location = obj.location * factor
    obj.scale = (factor, factor, factor)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


## El cartucho que la mano izquierda mete por la ventana de carga de la
## escopeta. La escopeta no tiene cargador que sacar: lo que se ve entrar es esto.
def _shell(body):
    xs = [v.co.x for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    length = max(xs) - min(xs)
    radius = length * 0.012
    depth = length * 0.075
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth,
                                        rotation=(0.0, math.pi / 2, 0.0))
    shell = bpy.context.object
    shell.name = "Shell"
    shell.data.materials.append(_material("ShellHull", (0.55, 0.06, 0.05, 1.0), 0.0, 0.5))
    shell.data.materials.append(_material("ShellBrass", (0.75, 0.55, 0.22, 1.0), 1.0, 0.35))
    # El culote de laton: las caras del extremo de atras (+X) y su franja.
    for poly in shell.data.polygons:
        if poly.center.x > depth * 0.3:
            poly.material_index = 1
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    # La ventana de carga: bajo el cajon de mecanismos, delante del guardamontes.
    shell.location = Vector((min(xs) + length * 0.52, 0.0, min(zs) + (max(zs) - min(zs)) * 0.38))
    return shell


def _material(name, colour, metallic, roughness):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


# Clips. Todo en metros despues de escalar, relativo a la pose de reposo, con el
# progreso de la recarga (0-1) en lugar del cuadro. +X es hacia atras, Z arriba.

def _keys(obj, poses):
    """poses: [(progreso, desplazamiento, rotacion en grados, escala), ...]"""
    # Las mallas de Meshy vienen en cuaternion, y ahi rotation_euler no se exporta.
    obj.rotation_mode = "XYZ"
    rest = obj.location.copy()
    for progress, offset, rotation, scale in poses:
        frame = round(progress * FRAMES)
        obj.location = rest + Vector(offset)
        obj.rotation_euler = [math.radians(a) for a in rotation]
        obj.scale = (scale, scale, scale)
        obj.keyframe_insert("location", frame=frame)
        obj.keyframe_insert("rotation_euler", frame=frame)
        obj.keyframe_insert("scale", frame=frame)
    obj.location = rest
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)


def _to_nla(obj, clip):
    action = obj.animation_data.action
    track = obj.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 0, action)
    obj.animation_data.action = None


Z0 = (0.0, 0.0, 0.0)
# Escondido: casi cero y no cero, porque con escala cero Godot no puede sacar la
# rotacion del nodo al importar y lo protesta.
HIDDEN = 0.001


## Cargador de rifle o subfusil: cae al soltarlo, desaparece fuera de cuadro y
## sube con la mano hasta encastrar.
def _magazine(mag, drop, tilt):
    below = (0.0, 0.0, -drop)
    _keys(mag, [
        (0.0, Z0, Z0, 1.0),
        (0.12, Z0, Z0, 1.0),
        (0.16, (0.0, 0.0, -drop * 0.08), (0.0, tilt * 0.3, 0.0), 1.0),
        (0.30, (drop * 0.1, 0.0, -drop * 1.2), (0.0, tilt, 0.0), 1.0),
        (0.33, below, Z0, HIDDEN),
        (0.43, below, Z0, HIDDEN),
        (0.46, (0.0, 0.0, -drop * 0.9), (0.0, -tilt * 0.4, 0.0), 1.0),
        (0.62, (0.0, 0.0, -drop * 0.12), (0.0, -tilt * 0.1, 0.0), 1.0),
        (0.68, (0.0, 0.0, -drop * 0.1), Z0, 1.0),
        (0.72, Z0, Z0, 1.0),
        (1.0, Z0, Z0, 1.0),
    ])


def _animate_rifle(mag):
    # El curvo del AK sale rotando hacia adelante, como se lo palanquea.
    _magazine(mag, 0.30, -18.0)


def _animate_smg(mag):
    _magazine(mag, 0.26, 0.0)


## La pistola no se puede abrir: el cargador esta dentro de la empuñadura. Lo que
## se ve es la corredera: al final de la recarga va atras y vuelve de golpe.
def _animate_pistol(slide):
    travel = (0.04, 0.0, 0.0)
    _keys(slide, [
        (0.0, Z0, Z0, 1.0),
        (0.76, Z0, Z0, 1.0),
        (0.82, travel, Z0, 1.0),
        (0.84, travel, Z0, 1.0),
        (0.87, Z0, Z0, 1.0),
        (1.0, Z0, Z0, 1.0),
    ])


## Escopeta: entra un cartucho por la ventana de carga con la mano izquierda y
## al final se bombea.
def _animate_shotgun(pump, shell):
    travel = (0.07, 0.0, 0.0)
    _keys(pump, [
        (0.0, Z0, Z0, 1.0),
        (0.78, Z0, Z0, 1.0),
        (0.84, travel, Z0, 1.0),
        (0.86, travel, Z0, 1.0),
        (0.91, Z0, Z0, 1.0),
        (1.0, Z0, Z0, 1.0),
    ])
    _keys(shell, [
        (0.0, (0.0, 0.0, -0.25), Z0, HIDDEN),
        (0.43, (0.0, 0.0, -0.25), Z0, HIDDEN),
        (0.46, (0.0, 0.0, -0.2), Z0, 1.0),
        (0.62, (0.0, 0.0, -0.03), Z0, 1.0),
        # Empujado hacia adelante, adentro del tubo.
        (0.70, (-0.05, 0.0, 0.0), Z0, 1.0),
        (0.72, (-0.06, 0.0, 0.0), Z0, HIDDEN),
        (1.0, (0.0, 0.0, -0.25), Z0, HIDDEN),
    ])


ANIMATE = {
    "pistol": _animate_pistol,
    "smg": _animate_smg,
    "rifle": _animate_rifle,
    "shotgun": _animate_shotgun,
}


main()
