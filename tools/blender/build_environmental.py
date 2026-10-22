"""Le arma esqueleto y clips al Environmental y lo exporta para Godot.

    blender -b assets/models/enemies/Enviromental/Enviromental.blend --python tools/blender/build_environmental.py

Sale a assets/models/enemies/Enviromental/Environmental.glb. El .blend no se
toca: sigue siendo la fuente de arte, y esto se vuelve a correr despues de
editarlo. (La carpeta y el .blend se llaman "Enviromental", sin la n, tal como
llegaron; el .glb usa el nombre del arquetipo.)

El modelo llega como piezas rigidas sueltas, sin rig: el tanque (con la franja
que brilla), cuatro patas hechas con geometry nodes y, arriba, el lanzador -un
soporte y un brazo con la boca por donde sale el frasco-. Se le pone un
esqueleto chico y cada pieza se pesa entera a un hueso, menos las patas: cada una
tiene muslo y canilla, partida en el arco, para que al caminar la pata se
levante doblandose en vez de girar entera como un compas.

Clips, con los nombres que busca EnemyModelMotion:

- idle    (loop) el tanque respira, el lanzador barre de lado a lado buscando.
- walk    (loop) paso en diagonal (adelante-izquierda con atras-derecha), el
          tanque se mece y el lanzador se queda mirando adelante.
- attack  el tiro: se agacha, el brazo patea hacia arriba en el cuadro 3 -el
          instante en que sale el frasco- y vuelve. Lo dispara `ability_used`,
          que `ActionThrowFlask` emite al tirar.

Como el resto de los modelos de enemigos, llega acostado (alto a lo largo de Y
en Blender, el frente hacia +Z); lo para `model_pitch_degrees` en
environmental.tres.
"""

import math
import os
import bpy
from mathutils import Quaternion, Vector

OUTPUT = os.path.join(os.path.dirname(bpy.data.filepath), "Environmental.glb")
FPS = 30

# Pieza -> hueso. Los nombres son los del .blend tal como llego.
PARTS = {
    "Cylinder": "body",         # el tanque, con la franja que brilla
    "Cube": "turret",           # el soporte del lanzador
    "Cube.001": "turret",       # su franja que brilla
    "Cube.002": "turret",
    "Cube.003": "launcher",     # el brazo que apunta adelante
    "Cube.004": "launcher",
    "Torus.001": "launcher",    # la boca
    "Torus.002": "launcher",    # su anillo que brilla
}

# Pata -> (pieza, esquina). La esquina es lo que la empareja en el paso.
LEGS = {
    "FL": "Icosphere",
    "FR": "Icosphere.001",
    "BR": "Icosphere.002",
    "BL": "Icosphere.003",
}
# Donde se dobla la pata, medido en el .blend: el punto mas alto del arco, a
# 0.18 hacia afuera de la cadera. El pie apoya a 0.24 y a -0.29 de alto.
KNEE_OUT = 0.18
KNEE_Y = 0.02
FOOT_OUT = 0.24
FOOT_Y = -0.29

# Los ejes del modelo, en el espacio de Blender.
SIDE = Vector((1.0, 0.0, 0.0))     # girar aca es cabecear hacia adelante o atras
UP = Vector((0.0, 1.0, 0.0))       # girar aca es mirar a un costado
FRONT = Vector((0.0, 0.0, 1.0))    # girar aca es ladearse


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def outward(hip):
    return Vector((hip.x, 0.0, hip.z)).normalized()


def main():
    scene = bpy.context.scene
    scene.render.fps = FPS
    hips = {corner: bpy.data.objects[name].matrix_world.translation.copy()
            for corner, name in LEGS.items()}

    bones = [
        # nombre, padre, cabeza, cola
        ("root", None, (0.0, -0.3, 0.0), (0.0, -0.15, 0.0)),
        ("body", "root", (0.0, -0.12, 0.0), (0.0, 0.5, 0.0)),
        ("turret", "body", (-0.009, 0.5, 0.0), (-0.009, 0.6, 0.0)),
        ("launcher", "turret", (-0.009, 0.608, 0.049), (-0.009, 0.608, 0.15)),
    ]
    for corner, hip in hips.items():
        out = outward(hip)
        knee = hip + out * KNEE_OUT
        knee.y = KNEE_Y
        foot = hip + out * FOOT_OUT
        foot.y = FOOT_Y
        # Las patas cuelgan de la raiz y no del tanque: el tanque se mece al
        # caminar, y si las patas lo siguieran los pies patinarian en el piso.
        bones.append(("thigh." + corner, "root", tuple(hip), tuple(knee)))
        bones.append(("shin." + corner, "thigh." + corner, tuple(knee), tuple(foot)))

    arm_data = bpy.data.armatures.new("EnvironmentalRig")
    rig = bpy.data.objects.new("EnvironmentalRig", arm_data)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail in bones:
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            # Encadenado solo donde la cabeza cae en la cola del padre.
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    def bake(obj):
        """Aplica modificadores y transform: la piel no depende del objeto."""
        obj.data = obj.data.copy()
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            with bpy.context.temp_override(object=obj, active_object=obj):
                bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.data.transform(obj.matrix_world)
        obj.matrix_world.identity()
        obj.vertex_groups.clear()

    def skin(obj):
        obj.parent = rig
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = rig

    meshes = []
    for obj_name, bone in PARTS.items():
        obj = bpy.data.objects[obj_name]
        bake(obj)
        group = obj.vertex_groups.new(name=bone)
        group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
        skin(obj)
        meshes.append(obj)

    for corner, obj_name in LEGS.items():
        obj = bpy.data.objects[obj_name]
        hip = hips[corner]
        out = outward(hip)
        bake(obj)
        thigh = obj.vertex_groups.new(name="thigh." + corner)
        shin = obj.vertex_groups.new(name="shin." + corner)
        for v in obj.data.vertices:
            reach = (v.co - hip).dot(out)
            # La canilla es lo que baja pasado el arco: afuera y por debajo de el.
            w = smoothstep(KNEE_OUT - 0.05, KNEE_OUT + 0.01, reach) \
                * (1.0 - smoothstep(-0.08, 0.0, v.co.y))
            shin.add([v.index], w, "REPLACE")
            thigh.add([v.index], 1.0 - w, "REPLACE")
        skin(obj)
        meshes.append(obj)

    rest3 = {b.name: b.matrix_local.to_3x3() for b in arm_data.bones}
    rest_head = {b.name: b.head_local.copy() for b in arm_data.bones}
    rest_tail = {b.name: b.tail_local.copy() for b in arm_data.bones}

    def rot(bone, axis, degrees):
        """Giro sobre un eje del modelo, pasado al espacio local del hueso."""
        local = (rest3[bone].inverted() @ axis).normalized()
        return Quaternion(local, math.radians(degrees))

    # El eje que levanta cada pata hacia afuera: horizontal y perpendicular a
    # su direccion. El signo se elige probando, para que "+" suba el pie.
    lift_axis = {}
    for corner, hip in hips.items():
        axis = UP.cross(outward(hip)).normalized()
        foot = rest_tail["shin." + corner] - hip
        if (Quaternion(axis, 0.3) @ foot).y < foot.y:
            axis = -axis
        lift_axis[corner] = axis

    def pose(lift=0.0, **parts):
        """parts: hueso -> lista de (eje, grados). Lo que no aparece va a reposo.
        `lift` baja (-) o sube (+) la raiz, en metros del .blend."""
        out = {}
        for b in arm_data.bones:
            q = Quaternion()
            for axis, deg in parts.get(b.name.replace(".", "_"), []):
                q = rot(b.name, axis, deg) @ q
            out[b.name] = q
        return out, lift

    def leg(corner, swing, raise_deg, fold):
        """Una pata: `swing` adelante (+) o atras, `raise_deg` la levanta hacia
        afuera y `fold` dobla la rodilla para que el pie no se arrastre.

        El paso gira el muslo sobre la vertical, no de costado: las patas salen
        en diagonal, y girarlas sobre el eje lateral hundia en el piso el pie
        que iba atras. Sobre la vertical el pie se corre sin cambiar de alto.
        Del lado izquierdo y del derecho el mismo giro va para lados opuestos."""
        side = 1.0 if hips[corner].x > 0.0 else -1.0
        return {
            "thigh_" + corner: [(UP, -swing * side), (lift_axis[corner], raise_deg)],
            "shin_" + corner: [(lift_axis[corner], -fold)],
        }

    def loop_keys(frames, sample, step=3):
        return [(f, sample(f / frames * math.tau)) for f in range(0, frames + 1, step)]

    def idle(t):
        parts = dict(
            body=[(SIDE, 1.5 * math.sin(t)), (FRONT, 1.0 * math.sin(t + 1.1))],
            turret=[(UP, 28.0 * math.sin(t))],
            launcher=[(SIDE, -4.0 + 3.0 * math.sin(t * 2.0 + 0.6))],
        )
        for corner, phase in (("FL", 0.0), ("FR", 1.6), ("BR", 3.1), ("BL", 4.7)):
            parts.update(leg(corner, 0.0, 2.0 * math.sin(t + phase), 1.5 * math.sin(t + phase)))
        return pose(lift=0.004 * math.sin(t * 2.0), **parts)

    def walk(t):
        parts = dict(
            body=[(SIDE, 4.0), (FRONT, 3.0 * math.sin(t))],
            turret=[(UP, -2.0 * math.sin(t))],
            launcher=[(SIDE, 2.0 * math.sin(t * 2.0 + 0.5))],
        )
        # Paso en diagonal: dos patas en el aire y dos apoyadas, siempre.
        for corner, phase in (("FL", 0.0), ("BR", 0.0), ("FR", math.pi), ("BL", math.pi)):
            p = t + phase
            air = max(0.0, math.sin(p))
            parts.update(leg(corner, -18.0 * math.cos(p), 22.0 * air, 30.0 * air))
        return pose(lift=0.012 * abs(math.sin(t)), **parts)

    neutral = pose()
    brace = pose(
        lift=-0.025,
        body=[(SIDE, -7.0)],
        turret=[],
        launcher=[(SIDE, -30.0)],
        **{k: v for c in LEGS for k, v in leg(c, 0.0, 10.0, 18.0).items()},
    )
    kick = pose(
        lift=-0.035,
        body=[(SIDE, -10.0)],
        launcher=[(SIDE, -52.0)],
        **{k: v for c in LEGS for k, v in leg(c, 0.0, 14.0, 24.0).items()},
    )
    settle = pose(
        lift=0.006,
        body=[(SIDE, 3.0)],
        launcher=[(SIDE, -12.0)],
        **{k: v for c in LEGS for k, v in leg(c, 0.0, -3.0, -4.0).items()},
    )

    clips = {
        "idle": loop_keys(60, idle, 5),
        "walk": loop_keys(24, walk),
        # 30 cuadros: se agacha, patea en el 3 (sale el frasco) y vuelve lento.
        "attack": [(0, neutral), (2, brace), (4, kick), (12, settle), (30, neutral)],
    }

    rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    root_up = (rest3["root"].inverted() @ UP).normalized()
    for clip_name, keys in clips.items():
        action = bpy.data.actions.new(clip_name)
        rig.animation_data.action = action
        for frame, (bone_rotations, lift) in keys:
            for bone_name, q in bone_rotations.items():
                pb = rig.pose.bones[bone_name]
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)
            root = rig.pose.bones["root"]
            root.location = root_up * lift
            root.keyframe_insert("location", frame=frame, group="root")
        action.use_fake_user = True
        track = rig.animation_data.nla_tracks.new()
        track.name = clip_name
        track.strips.new(clip_name, keys[0][0], action)
        track.mute = True
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_cameras=False,
        export_lights=False,
    )
    print("ENVIRONMENTAL written", OUTPUT)


main()
