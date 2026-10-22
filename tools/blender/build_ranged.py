"""Le arma esqueleto y clips al Ranger y lo exporta para Godot.

    blender -b assets/models/enemies/Ranged/Ranged.blend --python tools/blender/build_ranged.py

Sale a assets/models/enemies/Ranged/Ranged.glb. El .blend no se toca: sigue
siendo la fuente de arte, y esto se vuelve a correr despues de editarlo.

El modelo llega como piezas rigidas sueltas, sin rig: el cuerpo entero (pelvis,
torso y casco, con espejo), una pieza por pierna, una por brazo -el derecho
termina en el cañon, que es otra pieza; el izquierdo, en la cuchilla-. Se le
pone un esqueleto humanoide chico y cada pieza se reparte entre sus huesos por
altura: el cuerpo entre cadera, pecho y cabeza; cada pierna entre muslo y
canilla en la rodilla; cada brazo entre brazo y antebrazo en el codo. Las
alturas de las articulaciones salen de mirar el .blend: son los huecos entre
los segmentos del modelo.

Clips, con los nombres que busca EnemyModelMotion:

- idle    (loop) respira, mira alrededor; el cañon queda apuntando al frente.
- run     (loop) corre inclinado, la cuchilla acompaña el paso y el cañon
          sigue apuntando: es un tirador que se reposiciona, no uno que huye.
- attack  el retroceso del disparo: el cañon patea hacia arriba en el cuadro 2
          y el cuerpo se echa atras. Lo dispara `ability_used`, que
          `ActionRangedAttack` emite al disparar.

Como el resto de los modelos de enemigos, llega acostado (alto a lo largo de Y
en Blender, el frente hacia +Z); lo para `model_pitch_degrees` en ranger.tres.
"""

import math
import os
import bpy
from mathutils import Quaternion, Vector

OUTPUT = os.path.join(os.path.dirname(bpy.data.filepath), "Ranged.glb")
FPS = 30

# El modelo no esta en el origen del .blend: su eje es x = -1.76.
CX = -1.76
Z = -0.05
# Alturas de las articulaciones (Y del .blend), medidas en los huecos del modelo.
HIP_Y = 0.15
WAIST_Y = 0.35
NECK_Y = 0.86
SHOULDER_Y = 0.74
ELBOW_Y = 0.47
KNEE_Y = -0.65
FOOT_Y = -1.15
HIP_X = 0.17
SHOULDER_X = 0.25

# Pieza -> como se reparte. "R" es el lado -X: la derecha del Ranger, que mira a +Z.
PARTS = {
    "Plane": "body",            # pelvis, torso y casco (con espejo)
    "Plane.001": "leg.L",
    "Plane.002": "leg.R",
    "Plane.003": "arm.R",       # el brazo del cañon
    "Torus": "cannon",          # el cañon
    "Plane.004": "arm.L",       # el brazo de la cuchilla, con la cuchilla
}

# Los ejes del modelo, en el espacio de Blender.
SIDE = Vector((1.0, 0.0, 0.0))     # para un hueso que cuelga, (-) lo lleva adelante
UP = Vector((0.0, 1.0, 0.0))       # girar aca es mirar o torcerse a un costado
FRONT = Vector((0.0, 0.0, 1.0))    # girar aca es ladearse


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def split(v_y, joint, lower, upper, blend=0.04):
    """Pesos de dos huesos que se tocan en `joint`: abajo uno, arriba el otro."""
    w = smoothstep(joint - blend, joint + blend, v_y)
    return {lower: 1.0 - w, upper: w}


def main():
    scene = bpy.context.scene
    scene.render.fps = FPS
    # El .blend llego guardado en modo edicion, y desde ahi no se aplican
    # modificadores.
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    def at(x, y, z=Z):
        return (CX + x, y, z)

    bones = [
        # nombre, padre, cabeza, cola
        ("root", None, at(0.0, HIP_Y - 0.1), at(0.0, HIP_Y)),
        ("hips", "root", at(0.0, HIP_Y), at(0.0, WAIST_Y)),
        ("spine", "hips", at(0.0, WAIST_Y), at(0.0, NECK_Y)),
        ("head", "spine", at(0.0, NECK_Y), at(0.0, NECK_Y + 0.17)),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bones += [
            ("upper_arm." + side, "spine", at(sign * SHOULDER_X, SHOULDER_Y), at(sign * SHOULDER_X, ELBOW_Y)),
            ("forearm." + side, "upper_arm." + side, at(sign * SHOULDER_X, ELBOW_Y), at(sign * SHOULDER_X, 0.1)),
            ("thigh." + side, "hips", at(sign * HIP_X, HIP_Y), at(sign * HIP_X, KNEE_Y)),
            ("shin." + side, "thigh." + side, at(sign * HIP_X, KNEE_Y), at(sign * HIP_X, FOOT_Y)),
        ]

    arm_data = bpy.data.armatures.new("RangerRig")
    rig = bpy.data.objects.new("RangerRig", arm_data)
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
    bpy.ops.object.mode_set(mode="OBJECT")

    def weights(kind, y):
        if kind == "body":
            if y < (WAIST_Y + NECK_Y) * 0.5:
                return split(y, WAIST_Y, "hips", "spine")
            # El cuello es un corte duro en el modelo, y el casco gira entero.
            return split(y, NECK_Y, "spine", "head", 0.02)
        if kind == "cannon":
            return {"forearm.R": 1.0}
        if kind.startswith("leg."):
            side = kind[-1]
            return split(y, KNEE_Y, "shin." + side, "thigh." + side)
        side = kind[-1]
        return split(y, ELBOW_Y, "forearm." + side, "upper_arm." + side)

    meshes = []
    for obj_name, kind in PARTS.items():
        obj = bpy.data.objects[obj_name]
        # Sin copia, una malla compartida recibiria el transform dos veces.
        obj.data = obj.data.copy()
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            with bpy.context.temp_override(object=obj, active_object=obj):
                bpy.ops.object.modifier_apply(modifier=mod.name)
        # El esqueleto esta en el origen sin rotar: se hornea el transform de cada
        # pieza en sus vertices para que la piel no dependa de el.
        obj.data.transform(obj.matrix_world)
        obj.matrix_world.identity()
        obj.vertex_groups.clear()
        groups = {}
        for v in obj.data.vertices:
            for bone, w in weights(kind, v.co.y).items():
                if w <= 0.0:
                    continue
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([v.index], w, "REPLACE")
        obj.parent = rig
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        meshes.append(obj)

    rest3 = {b.name: b.matrix_local.to_3x3() for b in arm_data.bones}

    def rot(bone, axis, degrees):
        """Giro sobre un eje del modelo, pasado al espacio local del hueso."""
        local = (rest3[bone].inverted() @ axis).normalized()
        return Quaternion(local, math.radians(degrees))

    def pose(lift=0.0, **parts):
        """parts: hueso -> lista de (eje, grados). Lo que no aparece va a reposo.
        `lift` sube (+) o baja la raiz, en metros del .blend."""
        out = {}
        for b in arm_data.bones:
            q = Quaternion()
            for axis, deg in parts.get(b.name.replace(".", "_"), []):
                q = rot(b.name, axis, deg) @ q
            out[b.name] = q
        return out, lift

    def aim(kick=0.0, drift=0.0):
        """El brazo del cañon apuntando al frente, a la altura del pecho: el
        brazo un poco adelante, el antebrazo horizontal. `kick` lo levanta."""
        return dict(
            upper_arm_R=[(SIDE, -30.0 + drift + kick * 0.3), (FRONT, -6.0)],
            forearm_R=[(SIDE, -60.0 - kick)],
        )

    def loop_keys(frames, sample, step=2):
        return [(f, sample(f / frames * math.tau)) for f in range(0, frames + 1, step)]

    def idle(t):
        parts = aim(drift=2.0 * math.sin(t + 0.7))
        parts.update(
            spine=[(SIDE, 1.5 * math.sin(t)), (UP, 4.0 * math.sin(t * 0.5))],
            head=[(UP, 18.0 * math.sin(t * 0.5 + 0.4)), (SIDE, 3.0 * math.sin(t))],
            upper_arm_L=[(SIDE, 4.0 * math.sin(t + 1.0)), (FRONT, 6.0)],
            forearm_L=[(SIDE, -12.0 + 3.0 * math.sin(t + 1.4))],
            thigh_L=[(SIDE, -4.0)],
            thigh_R=[(SIDE, -2.0)],
            shin_L=[(SIDE, 8.0)],
            shin_R=[(SIDE, 4.0)],
        )
        return pose(lift=-0.008 + 0.004 * math.sin(t), **parts)

    def run(t):
        s = math.sin(t)
        c = math.cos(t)
        parts = aim(drift=3.0 * math.sin(t * 2.0))
        parts.update(
            hips=[(UP, -7.0 * s)],
            spine=[(SIDE, 10.0), (UP, 9.0 * s)],
            head=[(UP, -6.0 * s), (SIDE, -6.0)],
            # La cuchilla va con la pierna contraria, como cualquier brazo al correr.
            upper_arm_L=[(SIDE, 32.0 * s), (FRONT, 8.0)],
            forearm_L=[(SIDE, -35.0 - 15.0 * max(0.0, -s))],
            thigh_L=[(SIDE, -32.0 * s)],
            thigh_R=[(SIDE, 32.0 * s)],
            # La rodilla se dobla mientras la pierna viaja hacia adelante.
            shin_L=[(SIDE, 12.0 + 60.0 * max(0.0, c))],
            shin_R=[(SIDE, 12.0 + 60.0 * max(0.0, -c))],
        )
        return pose(lift=0.025 * abs(s), **parts)

    def shot(kick, lean, lift):
        parts = aim(kick=kick)
        parts.update(
            spine=[(SIDE, lean)],
            head=[(SIDE, lean * 0.6)],
            upper_arm_L=[(FRONT, 6.0), (SIDE, -lean * 1.5)],
            forearm_L=[(SIDE, -12.0)],
            thigh_L=[(SIDE, -4.0)],
            thigh_R=[(SIDE, 3.0)],
            shin_L=[(SIDE, 8.0 + abs(lean))],
            shin_R=[(SIDE, 4.0 + abs(lean))],
        )
        return pose(lift=lift, **parts)

    clips = {
        "idle": loop_keys(60, idle, 4),
        "run": loop_keys(20, run),
        # 24 cuadros: patea en el 2 (sale el tiro), se acomoda y vuelve a apuntar.
        "attack": [(0, shot(0.0, 0.0, -0.008)), (2, shot(28.0, -9.0, -0.02)),
                   (7, shot(10.0, -4.0, -0.014)), (24, shot(0.0, 0.0, -0.008))],
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
    print("RANGER written", OUTPUT)


main()
