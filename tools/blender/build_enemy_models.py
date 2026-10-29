"""Prepara para el juego los modelos de enemigos que llegan de Meshy como .glb.

    blender -b --python tools/blender/build_enemy_models.py -- <id>

<id> es una clave de MODELS (rusher, bomber, healer, ranger, flyer). Lee el .glb
fuente de assets/models/enemies/ y escribe el del juego en la carpeta del
arquetipo. Los fuentes quedan con importer="skip": Godot no los carga.

Llegan como una sola malla quieta, sin esqueleto ni clips, y algunas con mucho
mas detalle del que pide un enemigo que se ve a diez metros y del que puede
haber veinte en pantalla (el perro trae 528 mil triangulos). Lo que se hace:

- Decimar a `faces` triangulos.
- Pararlo: `up` y `front` dicen hacia donde mira cada eje del modelo tal como
  llega, y se lo gira para que quede con Z arriba y el frente a +Y de Blender,
  que es -Z en Godot: hacia donde avanza un cuerpo. Asi EnemyData no necesita
  model_yaw_degrees ni model_pitch_degrees para estos.
- Apoyarlo con la base en z = 0 y centrarlo en X/Y.
- Si el arquetipo camina (`rig`), un esqueleto chico con piel rigida por zonas y
  los clips que busca EnemyModelMotion (idle, run, attack). Ver RIGS.

Los que flotan (bomber, healer, flyer) no llevan clips: los anima
EnemyModelMotion por estado (flotar, inclinarse, inflarse al curar).
"""

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ENEMIES = os.path.join(ROOT, "assets", "models", "enemies")
FPS = 30

# Ejes de Blender, para decir como llega cada modelo.
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))

MODELS = {
    "rusher": {
        "source": "SciFi_Robot_Dog.glb",
        "output": "Melee/Rusher.glb",
        "faces": 16000,
        "up": Z,
        "front": -Y,
        "rig": "dog",
    },
    "bomber": {
        "source": "bomb_robot_lowpoly.glb",
        "output": "Bomber/Bomber.glb",
        "faces": 9000,
        "up": Z,
        "front": -Y,
    },
    "healer": {
        "source": "healer_robot_quad.glb",
        "output": "Healer/Healer.glb",
        "faces": 20000,
        "up": Z,
        "front": -Y,
    },
    "ranger": {
        "source": "ranger_robot_lowpoly.glb",
        "output": "Ranged/Ranger.glb",
        "faces": 16000,
        "up": Z,
        "front": -Y,
        "rig": "humanoid",
    },
    "flyer": {
        "source": "scifi_combat_drone_qu.glb",
        "output": "RangedFlyer/Flyer.glb",
        "faces": 14000,
        "up": Z,
        "front": X,
    },
    "environmental": {
        "source": "acid_barrel_robot_3d.glb",
        "output": "Enviromental/Environmental.glb",
        "faces": 16000,
        "up": Z,
        "front": -Y,
        "rig": "acid_walker",
    },
    "summoner": {
        "source": "robot_sorcerer_quad.glb",
        "output": "Summoner/Summoner.glb",
        "faces": 20000,
        "up": Z,
        "front": -Y,
        "rig": "sorcerer",
    },
}


def main():
    key = sys.argv[sys.argv.index("--") + 1]
    config = MODELS[key]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=os.path.join(ENEMIES, config["source"]))
    body = _join([o for o in scene.objects if o.type == "MESH"])
    body.name = "Body"
    _decimate(body, config["faces"])
    _stand(body, config["up"], config["front"])

    objects = [body]
    if config.get("rig") in RIGS:
        objects.append(RIGS[config["rig"]](body, key))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    output = os.path.join(ENEMIES, config["output"])
    os.makedirs(os.path.dirname(output), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_skins=True,
        export_cameras=False,
        export_lights=False,
    )
    dims = body.dimensions
    print("ENEMY written", output, "faces", len(body.data.polygons),
          "size", tuple(round(d, 3) for d in dims))


# Geometria

def _join(meshes):
    for obj in meshes:
        obj.data = obj.data.copy()
        obj.data.transform(obj.matrix_world)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj)
    return meshes[0]


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


def _decimate(obj, faces):
    count = len(obj.data.polygons)
    _weld(obj)
    if count <= faces:
        return
    modifier = obj.modifiers.new("Decimate", "DECIMATE")
    modifier.ratio = faces / count
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def _stand(obj, up, front):
    """Gira para que `up` quede en +Z y `front` en +Y, y apoya la base en z = 0."""
    up = up.normalized()
    front = (front - up * front.dot(up)).normalized()
    side = front.cross(up)
    # Columnas: a donde va cada eje de destino, expresado en el modelo.
    to_model = Matrix((side, front, up)).transposed()
    obj.data.transform(to_model.inverted().to_4x4())
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    centre = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    obj.data.transform(Matrix.Translation(-centre))


# Esqueletos. Todo en coordenadas del modelo ya parado: frente +Y, Z arriba,
# base en z = 0, en las unidades en que llega (EnemyData lo escala con
# model_fit_height, asi que estos numeros no cambian si cambia el alto en juego).
# Las articulaciones se midieron en renders ortogonales de frente y de costado.
#
# Piel rigida por zonas, como el Ranger anterior: son robots, y una pieza que gira
# entera alrededor de su articulacion es justo lo que se espera ver. `_split`
# mezcla un poco en cada corte para que la junta no se abra al doblar.

def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def _split(value, joint, below, above, blend=0.03):
    w = smoothstep(joint - blend, joint + blend, value)
    return {below: 1.0 - w, above: w}


def _rig(body, name, bones, weigh, clips):
    """bones: [(nombre, padre, cabeza, cola)]. weigh(co) -> {hueso: peso}.
    clips: {nombre: [(cuadro, {hueso: [(eje, grados)]}, subida)]}; `subida`
    mueve la raiz en Z, en unidades del modelo."""
    scene = bpy.context.scene
    arm_data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, arm_data)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, parent, head, tail in bones:
        eb = arm_data.edit_bones.new(bone)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    body.vertex_groups.clear()
    groups = {}
    for v in body.data.vertices:
        for bone, w in weigh(v.co).items():
            if w <= 0.0:
                continue
            if bone not in groups:
                groups[bone] = body.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, "REPLACE")
    body.parent = rig
    body.modifiers.new("Armature", "ARMATURE").object = rig

    rest3 = {b.name: b.matrix_local.to_3x3() for b in arm_data.bones}
    rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    root = bones[0][0]
    root_up = (rest3[root].inverted() @ Z).normalized()
    for clip, keys in clips.items():
        action = bpy.data.actions.new(clip)
        rig.animation_data.action = action
        for frame, parts, lift in keys:
            for b in arm_data.bones:
                q = Quaternion()
                for axis, degrees in parts.get(b.name, []):
                    local = (rest3[b.name].inverted() @ axis).normalized()
                    q = Quaternion(local, math.radians(degrees)) @ q
                pb = rig.pose.bones[b.name]
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=frame, group=b.name)
            pb = rig.pose.bones[root]
            pb.location = root_up * lift
            pb.keyframe_insert("location", frame=frame, group=root)
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        track.strips.new(clip, keys[0][0], action)
        track.mute = True
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    return rig


def _loop(frames, sample, step=2):
    return [(f,) + sample(f / frames * math.tau) for f in range(0, frames + 1, step)]


# El Rusher: un perro de cuatro patas con la cabeza encima del lomo. Las rodillas
# de las cuatro apuntan atras, asi que doblar es girar la canilla a +X (el pie
# viaja adelante y arriba). Lado L es +X.
DOG_BODY_Z = 1.15
DOG_NECK = Vector((0.0, 0.62, 1.42))
DOG_LEG_X = 0.33
DOG_LEG_MIN_X = 0.215
DOG_LEG_TOP_Z = 1.33
DOG_FRONT_Y = -0.13
DOG_LEGS = {
    # pata: (cadera u hombro, rodilla, tobillo) en (y, z)
    "front": ((0.35, 1.16), (0.19, 0.58), (0.49, 0.135)),
    "rear": ((-0.61, 1.17), (-0.82, 0.55), (-0.66, 0.145)),
}


def _rig_dog(body, key):
    bones = [
        ("root", None, (0.0, -0.1, DOG_BODY_Z - 0.15), (0.0, -0.1, DOG_BODY_Z)),
        ("body", "root", (0.0, -0.6, DOG_BODY_Z), (0.0, 0.5, DOG_BODY_Z)),
        ("head", "body", DOG_NECK, DOG_NECK + Vector((0.0, 0.3, 0.0))),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        for leg, (hip, knee, ankle) in DOG_LEGS.items():
            x = sign * DOG_LEG_X
            bones += [
                ("thigh_%s.%s" % (leg, side), "body", (x,) + hip, (x,) + knee),
                ("shin_%s.%s" % (leg, side), "thigh_%s.%s" % (leg, side), (x,) + knee, (x,) + ankle),
            ]

    def weigh(co):
        if abs(co.x) > DOG_LEG_MIN_X and co.z < DOG_LEG_TOP_Z:
            side = "L" if co.x > 0.0 else "R"
            leg = "front" if co.y > DOG_FRONT_Y else "rear"
            knee_z = DOG_LEGS[leg][1][1]
            return _split(co.z, knee_z, "shin_%s.%s" % (leg, side), "thigh_%s.%s" % (leg, side))
        return _split(co.z, DOG_NECK.z, "body", "head", 0.015)

    def legs(**angles):
        """angles: thigh_front_L=(swing, fold)... -> partes."""
        parts = {}
        for name, (swing, fold) in angles.items():
            leg, side = name.rsplit("_", 1)
            parts["thigh_%s.%s" % (leg, side)] = [(X, swing)]
            parts["shin_%s.%s" % (leg, side)] = [(X, fold)]
        return parts

    def idle(t):
        parts = legs(front_L=(0.0, 0.0), front_R=(0.0, 0.0), rear_L=(0.0, 0.0), rear_R=(0.0, 0.0))
        parts["body"] = [(X, 1.5 * math.sin(t))]
        parts["head"] = [(Z, 20.0 * math.sin(t * 0.5)), (X, 4.0 * math.sin(t + 0.6))]
        return parts, 0.01 * math.sin(t)

    def run(t):
        # Trote: las patas en diagonal van juntas.
        def leg(phase):
            s = math.sin(t + phase)
            return (28.0 * s, 45.0 * max(0.0, math.cos(t + phase)))
        parts = legs(front_L=leg(0.0), rear_R=leg(0.0), front_R=leg(math.pi), rear_L=leg(math.pi))
        parts["body"] = [(X, -4.0 + 2.0 * math.sin(t * 2.0))]
        parts["head"] = [(X, 6.0 * math.sin(t * 2.0 + 0.5))]
        return parts, 0.04 * abs(math.sin(t))

    def lunge(body_pitch, head_pitch, front, rear, lift):
        parts = legs(front_L=(front, front * 0.3), front_R=(front, front * 0.3),
                     rear_L=(rear, 0.0), rear_R=(rear, 0.0))
        parts["root"] = [(X, body_pitch)]
        parts["head"] = [(X, head_pitch)]
        return parts, lift

    clips = {
        "idle": _loop(60, idle, 4),
        "run": _loop(16, run),
        # Se recoge (cuadro 5), se tira encima con la cabeza baja (9) y vuelve.
        "attack": [(0,) + lunge(0.0, 0.0, 0.0, 0.0, 0.0),
                   (5,) + lunge(8.0, 10.0, -12.0, 10.0, -0.04),
                   (9,) + lunge(-14.0, -28.0, 38.0, -24.0, 0.06),
                   (14,) + lunge(-6.0, -12.0, 15.0, -8.0, 0.02),
                   (22,) + lunge(0.0, 0.0, 0.0, 0.0, 0.0)],
    }
    return _rig(body, "RusherRig", bones, weigh, clips)


# El Ranger: humanoide, el cañon en el antebrazo derecho (+X, mirando a +Y). El
# brazo del cañon llega con el antebrazo adelante y hacia abajo; AIM lo levanta
# hasta horizontal. Para un hueso que cuelga, +X lleva el pie o la mano adelante;
# para la columna, +X la echa atras.
R_BODY_Y = -0.09
R_HIP = (0.083, 0.559)
R_KNEE_Z = 0.344
R_ANKLE_Z = 0.067
R_WAIST_Z = 0.611
R_NECK_Z = 0.846
R_SHOULDER = (0.125, 0.799)
R_ELBOW_Z = 0.637
R_AIM = 32.0


def _rig_humanoid(body, key):
    y = R_BODY_Y

    def at(x, z, dy=0.0):
        return (x, y + dy, z)

    bones = [
        ("root", None, at(0.0, R_HIP[1] - 0.06), at(0.0, R_HIP[1])),
        ("hips", "root", at(0.0, R_HIP[1]), at(0.0, R_WAIST_Z)),
        ("spine", "hips", at(0.0, R_WAIST_Z), at(0.0, R_NECK_Z)),
        ("head", "spine", at(0.0, R_NECK_Z), at(0.0, R_NECK_Z + 0.1)),
    ]
    for side, sign in (("L", -1.0), ("R", 1.0)):
        sx = sign * R_SHOULDER[0]
        hx = sign * R_HIP[0]
        bones += [
            ("upper_arm." + side, "spine", at(sx, R_SHOULDER[1]), at(sx, R_ELBOW_Z)),
            ("forearm." + side, "upper_arm." + side, at(sx, R_ELBOW_Z), at(sx, R_ELBOW_Z - 0.2)),
            ("thigh." + side, "hips", at(hx, R_HIP[1]), at(hx, R_KNEE_Z)),
            ("shin." + side, "thigh." + side, at(hx, R_KNEE_Z), at(hx, R_ANKLE_Z)),
        ]

    def weigh(co):
        ax = abs(co.x)
        side = "R" if co.x > 0.0 else "L"
        # Sobre los tobillos: la punta de un pie pasa el umbral de los brazos.
        if co.z > 0.37 and (ax > 0.115 or (ax > 0.09 and co.z > 0.62)):
            if side == "R":
                # El antebrazo del cañon sale hacia adelante desde el codo.
                fore = co.z < R_ELBOW_Z + 0.01 or co.y > y + 0.06
                return {"forearm.R" if fore else "upper_arm.R": 1.0}
            return _split(co.z, R_ELBOW_Z, "forearm.L", "upper_arm.L")
        if co.z > R_WAIST_Z:
            return _split(co.z, R_NECK_Z, "spine", "head", 0.015)
        if co.z > R_HIP[1] or (ax < 0.02 and co.z > 0.5):
            return _split(co.z, R_WAIST_Z - 0.03, "hips", "spine", 0.02)
        return _split(co.z, R_KNEE_Z, "shin." + side, "thigh." + side)

    def aim(kick=0.0, drift=0.0):
        return {"upper_arm.R": [(X, 6.0 + drift)], "forearm.R": [(X, R_AIM + kick)]}

    def idle(t):
        parts = aim(drift=2.0 * math.sin(t + 0.7))
        parts.update({
            "spine": [(X, 1.5 * math.sin(t)), (Z, 4.0 * math.sin(t * 0.5))],
            "head": [(Z, 18.0 * math.sin(t * 0.5 + 0.4))],
            "upper_arm.L": [(X, 4.0 * math.sin(t + 1.0))],
            "forearm.L": [(X, 8.0 + 3.0 * math.sin(t + 1.4))],
        })
        return parts, 0.004 * math.sin(t)

    def run(t):
        s = math.sin(t)
        c = math.cos(t)
        parts = aim(drift=3.0 * math.sin(t * 2.0))
        parts.update({
            "hips": [(Z, -7.0 * s)],
            "spine": [(X, -8.0), (Z, 9.0 * s)],
            "upper_arm.L": [(X, -30.0 * s)],
            "forearm.L": [(X, 30.0 + 15.0 * max(0.0, s))],
            "thigh.L": [(X, 32.0 * s)],
            "thigh.R": [(X, -32.0 * s)],
            "shin.L": [(X, -12.0 - 60.0 * max(0.0, -c))],
            "shin.R": [(X, -12.0 - 60.0 * max(0.0, c))],
        })
        return parts, 0.02 * abs(s)

    def shot(kick, lean, lift):
        parts = aim(kick=kick)
        parts.update({
            "spine": [(X, lean)],
            "head": [(X, -lean * 0.6)],
            "upper_arm.L": [(X, -lean * 1.5)],
            "forearm.L": [(X, 8.0)],
        })
        return parts, lift

    clips = {
        "idle": _loop(60, idle, 4),
        "run": _loop(20, run),
        # Patea en el cuadro 2 (sale el tiro), se acomoda y vuelve a apuntar.
        "attack": [(0,) + shot(0.0, 0.0, 0.0), (2,) + shot(28.0, 9.0, -0.01),
                   (7,) + shot(10.0, 4.0, -0.005), (24,) + shot(0.0, 0.0, 0.0)],
    }
    return _rig(body, "RangerRig", bones, weigh, clips)


# El Environmental: un tanque de acido sobre cuatro patas en diagonal, con un
# brazo lanzador de tres tramos del lado izquierdo (-X; mira a +Y). Las patas se
# miden de la malla: cada una es lo que queda por debajo del tanque y lejos de su
# eje, repartido por cuadrante, y su cadera, rodilla y pie salen del perfil radial
# de sus propios vertices.
ACID_LEG_TOP_Z = 0.215
ACID_HUB_RADIUS = 0.13
ACID_ARM_SIDE_X = -0.036
ACID_ARM_LOW_Z = 0.40
ACID_TANK_TOP_Z = 0.63
ACID_ELBOW_Z = 0.72
ACID_WRIST_X = -0.2


def _rig_acid_walker(body, key):
    verts = [v.co.copy() for v in body.data.vertices]
    low = [c for c in verts if c.z < ACID_LEG_TOP_Z]
    cx = sum(c.x for c in low) / len(low)
    cy = sum(c.y for c in low) / len(low)

    def leg_of(co):
        dx, dy = co.x - cx, co.y - cy
        if co.z >= ACID_LEG_TOP_Z or math.hypot(dx, dy) <= ACID_HUB_RADIUS:
            return None
        return ("F" if dy > 0.0 else "B") + ("L" if dx < 0.0 else "R")

    legs = {}
    for c in verts:
        leg = leg_of(c)
        if leg is not None:
            legs.setdefault(leg, []).append(c)
    profile = {}
    for leg, points in legs.items():
        mx = sum(p.x for p in points) / len(points) - cx
        my = sum(p.y for p in points) / len(points) - cy
        direction = Vector((mx, my, 0.0)).normalized()
        radii = [Vector((p.x - cx, p.y - cy, 0.0)).dot(direction) for p in points]
        r0, r1 = min(radii), max(radii)
        knee_r = r0 + (r1 - r0) * 0.45
        near_knee = [p.z for p, r in zip(points, radii) if abs(r - knee_r) < (r1 - r0) * 0.1]
        knee_z = max(near_knee) if near_knee else ACID_LEG_TOP_Z
        profile[leg] = (direction, r0, knee_r, r1, knee_z)

    def at_radius(direction, radius, z):
        return Vector((cx, cy, z)) + direction * radius

    bones = [
        ("root", None, (cx, cy, 0.25), (cx, cy, 0.4)),
        ("body", "root", (cx, cy, 0.4), (cx, cy, ACID_TANK_TOP_Z)),
        ("upper_arm", "body", (ACID_ARM_SIDE_X - 0.03, cy + 0.07, 0.47), (-0.03, cy + 0.07, ACID_ELBOW_Z)),
        ("forearm", "upper_arm", (-0.03, cy + 0.07, ACID_ELBOW_Z), (ACID_WRIST_X, cy + 0.07, 0.86)),
        ("launcher", "forearm", (ACID_WRIST_X, cy + 0.07, 0.86), (-0.38, cy + 0.07, 0.88)),
    ]
    for leg, (direction, r0, knee_r, r1, knee_z) in profile.items():
        hip = at_radius(direction, r0, ACID_LEG_TOP_Z - 0.02)
        knee = at_radius(direction, knee_r, knee_z)
        foot = at_radius(direction, r1, 0.02)
        bones += [("thigh." + leg, "body", hip, knee), ("shin." + leg, "thigh." + leg, knee, foot)]

    def weigh(co):
        leg = leg_of(co)
        if leg is not None:
            direction, r0, knee_r, r1, knee_z = profile[leg]
            radius = Vector((co.x - cx, co.y - cy, 0.0)).dot(direction)
            return _split(radius, knee_r, "thigh." + leg, "shin." + leg, 0.02)
        if (co.x < ACID_ARM_SIDE_X and co.z > ACID_ARM_LOW_Z) or co.z > ACID_TANK_TOP_Z + 0.01:
            if co.z < ACID_ELBOW_Z:
                return {"upper_arm": 1.0}
            return {"launcher" if co.x <= ACID_WRIST_X else "forearm": 1.0}
        return {"body": 1.0}

    def tangent(leg):
        direction = profile[leg][0]
        return Vector((-direction.y, direction.x, 0.0))

    def legs_pose(phases, swing, lift):
        parts = {}
        for leg, phase in phases.items():
            s = math.sin(phase)
            # Paso alrededor de la vertical: las patas abren en diagonal, y
            # giradas de costado el pie de atras se metia en el piso.
            parts["thigh." + leg] = [(Z, swing * s), (tangent(leg), -lift * max(0.0, math.cos(phase)))]
            parts["shin." + leg] = [(tangent(leg), lift * 0.6 * max(0.0, math.cos(phase)))]
        return parts

    def idle(t):
        parts = legs_pose({leg: 0.0 for leg in profile}, 0.0, 0.0)
        parts["body"] = [(Z, 3.0 * math.sin(t * 0.5))]
        parts["upper_arm"] = [(X, 4.0 * math.sin(t)), (Z, 10.0 * math.sin(t * 0.5 + 0.3))]
        parts["forearm"] = [(X, 3.0 * math.sin(t + 0.8))]
        parts["launcher"] = [(Z, 8.0 * math.sin(t * 0.5 + 1.1))]
        return parts, 0.006 * math.sin(t)

    def walk(t):
        phases = {"FL": t, "BR": t, "FR": t + math.pi, "BL": t + math.pi}
        parts = legs_pose({leg: phases[leg] for leg in profile}, 16.0, 22.0)
        parts["body"] = [(Y, 2.5 * math.sin(t * 2.0))]
        parts["upper_arm"] = [(X, -6.0 + 3.0 * math.sin(t * 2.0))]
        return parts, 0.012 * abs(math.sin(t))

    def throw(arm, fore, launcher, lean):
        parts = legs_pose({leg: 0.0 for leg in profile}, 0.0, 0.0)
        parts["body"] = [(X, lean)]
        parts["upper_arm"] = [(X, arm)]
        parts["forearm"] = [(X, fore)]
        parts["launcher"] = [(X, launcher)]
        return parts, 0.0

    clips = {
        "idle": _loop(60, idle, 4),
        "walk": _loop(24, walk),
        # El brazo se echa atras (cuadro 6) y latiguea adelante (10): ahi sale
        # el frasco.
        "attack": [(0,) + throw(0.0, 0.0, 0.0, 0.0), (6,) + throw(28.0, 18.0, 10.0, 3.0),
                   (10,) + throw(-38.0, -25.0, -15.0, -4.0), (16,) + throw(-12.0, -8.0, -4.0, -1.0),
                   (26,) + throw(0.0, 0.0, 0.0, 0.0)],
    }
    return _rig(body, "EnvironmentalRig", bones, weigh, clips)


# El Summoner: un hechicero de tunica. La tunica va entera con la raiz (flota, no
# camina); el torso, la cabeza y los dos brazos se mueven. Mira a +Y, derecha +X.
S_ROBE_TOP_Z = 0.53
S_NECK_Z = 0.785
S_SHOULDER = (0.125, 0.729)
S_ELBOW = (0.187, 0.62)
S_HAND = (0.26, 0.505)
S_ARM_Y = 0.03


def _rig_sorcerer(body, key):
    bones = [
        ("root", None, (0.0, 0.0, 0.3), (0.0, 0.0, S_ROBE_TOP_Z)),
        ("spine", "root", (0.0, 0.0, S_ROBE_TOP_Z), (0.0, 0.0, S_NECK_Z)),
        ("head", "spine", (0.0, 0.0, S_NECK_Z), (0.0, 0.0, 0.95)),
    ]
    for side, sign in (("L", -1.0), ("R", 1.0)):
        bones += [
            ("upper_arm." + side, "spine", (sign * S_SHOULDER[0], S_ARM_Y, S_SHOULDER[1]),
             (sign * S_ELBOW[0], S_ARM_Y, S_ELBOW[1])),
            ("forearm." + side, "upper_arm." + side, (sign * S_ELBOW[0], S_ARM_Y, S_ELBOW[1]),
             (sign * S_HAND[0], S_ARM_Y, S_HAND[1])),
        ]

    def weigh(co):
        ax = abs(co.x)
        side = "R" if co.x > 0.0 else "L"
        # Brazo: por fuera del torso y de la capa (que va detras), por debajo del
        # hombro. Abajo, mas afuera todavia: ahi empiezan los paños de la tunica.
        is_arm = co.y > -0.03 and co.z < S_SHOULDER[1] + 0.02 and co.z > 0.45 \
            and (ax > 0.17 or (ax > 0.12 and co.z > 0.56))
        if is_arm:
            return _split(co.z, S_ELBOW[1], "forearm." + side, "upper_arm." + side, 0.02)
        if co.z < S_ROBE_TOP_Z:
            return _split(co.z, S_ROBE_TOP_Z - 0.03, "root", "spine", 0.03)
        if co.z > S_NECK_Z and ax < 0.1:
            return _split(co.z, S_NECK_Z, "spine", "head", 0.015)
        return {"spine": 1.0}

    def arms(raise_deg, fore_deg, spread=0.0):
        """+X adelanta un brazo que cuelga; `spread` lo abre hacia afuera."""
        return {
            "upper_arm.L": [(X, raise_deg), (Y, spread)],
            "upper_arm.R": [(X, raise_deg), (Y, -spread)],
            "forearm.L": [(X, fore_deg)],
            "forearm.R": [(X, fore_deg)],
        }

    def idle(t):
        parts = arms(8.0 + 3.0 * math.sin(t), 12.0 + 4.0 * math.sin(t + 0.6))
        parts["spine"] = [(X, 2.0 * math.sin(t)), (Z, 5.0 * math.sin(t * 0.5))]
        parts["head"] = [(Z, 14.0 * math.sin(t * 0.5 + 0.4)), (X, 3.0 * math.sin(t + 0.3))]
        return parts, 0.01 * math.sin(t)

    def move(t):
        parts = arms(-14.0 + 4.0 * math.sin(t * 2.0), 8.0, 6.0)
        parts["spine"] = [(X, -10.0), (Z, 4.0 * math.sin(t))]
        parts["head"] = [(X, 6.0)]
        return parts, 0.015 * math.sin(t * 2.0)

    def cast(raise_deg, fore_deg, arch, lift):
        parts = arms(raise_deg, fore_deg, 18.0 * raise_deg / 120.0)
        parts["spine"] = [(X, arch)]
        parts["head"] = [(X, arch * 0.8)]
        return parts, lift

    clips = {
        "idle": _loop(60, idle, 4),
        "move": _loop(30, move),
        # Junta (8), alza los brazos hacia adelante y arriba (16), sostiene el
        # conjuro y los baja.
        "cast": [(0,) + cast(8.0, 12.0, 0.0, 0.0), (8,) + cast(30.0, 40.0, -6.0, -0.01),
                 (16,) + cast(125.0, 15.0, 10.0, 0.03), (26,) + cast(120.0, 10.0, 8.0, 0.03),
                 (36,) + cast(8.0, 12.0, 0.0, 0.0)],
    }
    return _rig(body, "SummonerRig", bones, weigh, clips)


RIGS = {
    "dog": _rig_dog,
    "humanoid": _rig_humanoid,
    "acid_walker": _rig_acid_walker,
    "sorcerer": _rig_sorcerer,
}


main()
