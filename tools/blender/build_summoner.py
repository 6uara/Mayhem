"""Le arma esqueleto y clips al Summoner y lo exporta para Godot.

    blender -b assets/models/enemies/Summoner/Summoner.blend --python tools/blender/build_summoner.py

Sale a assets/models/enemies/Summoner/Summoner.glb. El .blend no se toca: sigue
siendo la fuente de arte, y esto se vuelve a correr despues de editarlo.

El modelo llega como seis piezas rigidas sueltas (tunica, cabeza, ojo, dos brazos
y el baculo), sin rig. Para que tenga clips se le pone un esqueleto chico y cada
pieza se pesa entera a un hueso, menos la tunica: el ruedo queda pesado a la raiz
y el pecho al cuerpo, asi al balancearse se dobla en vez de girar como una tabla.

Clips, con los nombres que busca EnemyModelMotion:

- idle  (loop) balanceo lento, la cabeza que mira, el baculo que respira.
- move  (loop) inclinado hacia adelante, el brazo libre y el baculo que acompañan.
- cast  levanta el baculo y lo clava: es el instante de la invocacion.

Como el resto de los modelos de enemigos, llega acostado (alto a lo largo de Y
en Blender, la cara hacia +Z); lo para `model_pitch_degrees` en summoner.tres.
"""

import math
import os
import bpy
from mathutils import Quaternion, Vector

OUTPUT = os.path.join(os.path.dirname(bpy.data.filepath), "Summoner.glb")
FPS = 30

# Pieza -> hueso. Los nombres son los del .blend tal como llego.
PARTS = {
    "Plane": "body",            # tunica (con espejo)
    "Icosphere": "head",
    "Icosphere.003": "head",    # el ojo que brilla
    "Icosphere.001": "arm.L",   # el brazo libre, del lado +X
    "Icosphere.002": "arm.R",   # el brazo que sostiene el baculo
    "Icosphere.004": "staff",
}

# Huesos en coordenadas de Blender: Y es el alto del modelo, +Z su frente.
BONES = [
    # nombre, padre, cabeza, cola
    ("root", None, (0.0, -1.12, 0.0), (0.0, -0.9, 0.0)),
    ("body", "root", (0.0, -0.95, 0.0), (0.0, 0.45, 0.0)),
    ("head", "body", (0.0, 0.5, -0.01), (0.0, 0.8, -0.01)),
    ("arm.L", "body", (0.2, 0.42, 0.0), (0.3, -0.15, 0.0)),
    ("arm.R", "body", (-0.24, 0.42, 0.0), (-0.6, 0.22, 0.0)),
    ("staff", "arm.R", (-0.6, 0.22, 0.0), (-0.6, 0.85, 0.0)),
]

# Los ejes del modelo, en el espacio de Blender.
SIDE = Vector((1.0, 0.0, 0.0))     # girar acá inclina hacia adelante (+) o atras
UP = Vector((0.0, 1.0, 0.0))       # girar acá es mirar a un costado
FRONT = Vector((0.0, 0.0, 1.0))    # girar acá es ladearse


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def main():
    scene = bpy.context.scene
    scene.render.fps = FPS

    arm_data = bpy.data.armatures.new("SummonerRig")
    rig = bpy.data.objects.new("SummonerRig", arm_data)
    scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")

    meshes = []
    for obj_name, bone in PARTS.items():
        obj = bpy.data.objects[obj_name]
        # Los dos brazos pueden compartir malla (duplicado enlazado): sin copia, el
        # transform de abajo se aplicaria dos veces sobre los mismos vertices.
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
        if obj_name == "Plane":
            body = obj.vertex_groups.new(name="body")
            root = obj.vertex_groups.new(name="root")
            for v in obj.data.vertices:
                w = smoothstep(-1.1, -0.1, v.co.y)
                body.add([v.index], w, "REPLACE")
                root.add([v.index], 1.0 - w, "REPLACE")
        else:
            group = obj.vertex_groups.new(name=bone)
            group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
        obj.parent = rig
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        meshes.append(obj)

    rest3 = {b.name: b.matrix_local.to_3x3() for b in arm_data.bones}

    def rot(bone, axis, degrees):
        """Giro sobre un eje del modelo, pasado al espacio local del hueso."""
        local = (rest3[bone].inverted() @ axis).normalized()
        return Quaternion(local, math.radians(degrees))

    def pose(**parts):
        """parts: hueso -> lista de (eje, grados). Lo que no aparece va a reposo."""
        out = {}
        for b in arm_data.bones:
            q = Quaternion()
            for axis, deg in parts.get(b.name.replace(".", "_"), []):
                q = rot(b.name, axis, deg) @ q
            out[b.name] = q
        return out

    def loop_keys(frames, sample):
        return [(f, sample(f / frames * math.tau)) for f in range(0, frames + 1, 5)]

    def idle(t):
        return pose(
            body=[(FRONT, 2.0 * math.sin(t)), (SIDE, 1.5 * math.sin(t + 1.3))],
            head=[(SIDE, 4.0 * math.sin(t * 2.0 + 0.5)), (UP, 6.0 * math.sin(t))],
            arm_L=[(SIDE, 6.0 * math.sin(t + 0.8)), (FRONT, 3.0 * math.sin(t))],
            arm_R=[(SIDE, 2.0 * math.sin(t + 2.0))],
            staff=[(FRONT, 3.0 * math.sin(t + 0.4))],
        )

    def move(t):
        return pose(
            body=[(SIDE, 9.0 + 2.0 * math.sin(t * 2.0)), (FRONT, 3.0 * math.sin(t))],
            head=[(SIDE, -6.0 + 3.0 * math.sin(t * 2.0 + 1.0))],
            arm_L=[(SIDE, -14.0 * math.sin(t)), (FRONT, 6.0)],
            arm_R=[(SIDE, 6.0 * math.sin(t + 0.5))],
            staff=[(SIDE, -8.0 + 5.0 * math.sin(t + 0.9))],
        )

    neutral = pose()
    raised = pose(
        body=[(SIDE, -8.0)],
        head=[(SIDE, -14.0)],
        arm_L=[(FRONT, 70.0), (SIDE, -30.0)],
        arm_R=[(FRONT, -45.0)],
        staff=[(FRONT, 25.0)],
    )
    slam = pose(
        body=[(SIDE, 14.0)],
        head=[(SIDE, 12.0)],
        arm_L=[(SIDE, -80.0), (FRONT, 20.0)],
        arm_R=[(FRONT, 12.0), (SIDE, 20.0)],
        staff=[(FRONT, -6.0)],
    )
    settle = pose(
        body=[(SIDE, 6.0)],
        head=[(SIDE, 4.0)],
        arm_L=[(SIDE, -40.0), (FRONT, 10.0)],
        arm_R=[(FRONT, 6.0), (SIDE, 8.0)],
    )

    clips = {
        "idle": loop_keys(60, idle),
        "move": loop_keys(30, move),
        # 36 cuadros: arriba rapido, clava a los 9 (la invocacion) y vuelve lento.
        "cast": [(0, neutral), (6, raised), (9, slam), (18, settle), (36, neutral)],
    }

    rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for clip_name, keys in clips.items():
        action = bpy.data.actions.new(clip_name)
        rig.animation_data.action = action
        for frame, bone_rotations in keys:
            for bone_name, q in bone_rotations.items():
                pb = rig.pose.bones[bone_name]
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)
        action.use_fake_user = True
        track = rig.animation_data.nla_tracks.new()
        track.name = clip_name
        track.strips.new(clip_name, keys[0][0], action)
        track.mute = True
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()

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
    print("SUMMONER written", OUTPUT)


main()
