"""Arma los brazos de primera persona listos para Godot a partir de arms_rig.blend.

    blender -b assets/models/Arms/arms_rig.blend --python tools/blender/build_fp_arms.py

Sale a assets/models/Arms/fp_arms.glb. El .blend no se toca: es la fuente de arte
y se sigue editando ahi; esto se vuelve a correr despues.

Por que un paso aparte y no importar el .blend directo:

- arms_rig.blend trae el rig de Rigify entero (392 huesos, controles, MCH/ORG) y
  la malla con dos modificadores Armature, uno al metarig y otro al rig. glTF
  solo sabe de un esqueleto por malla, y el que elegia no era el bueno.
- La pose que se ve en Blender (pulgar arriba / pulgar abajo) no es una
  animacion: es la pose del rig. El importador exporta la pose de reposo, asi que
  en Godot llegaban en T.
- El material es un Diffuse BSDF, que el exportador de glTF no sabe leer: la
  textura no viajaba.

Lo que sale es un esqueleto chico (pecho, hombro, brazo, antebrazo, mano y tres
falanges por dedo, por lado), con la malla espejada aplicada y los pesos de los
huesos de twist sumados a su padre, y estos clips:

- grip_idle  (loop) las dos manos cerradas sobre el arma, respirando apenas.
- fire       el indice derecho aprieta el gatillo y vuelve.
- reload     las manos sueltan, la izquierda agarra el cargador, golpea y
             vuelve a cerrar. Se reproduce por progreso de recarga, no por
             tiempo (ver ViewmodelArms).
- equip      de mano abierta a mano cerrada, al sacar el arma.
- open       mano abierta y relajada, una sola pose.
- grapple    la derecha en el arma, la izquierda abierta tirando el gancho.

Los clips solo mueven dedos y muñeca: donde va cada mano lo resuelve la IK de
Godot contra el arma que este en mano, que cambia de largo de una a otra. Los
brazos quedan en la pose del rig para que en Blender se lean.

La curva de los dedos sale de la pose del propio rig: el puño que armo quien
modelo es la referencia de "dedo cerrado", y el resto son fracciones de eso.
"""

import math
import os
import bpy
from mathutils import Quaternion, Vector

OUTPUT = os.path.join(os.path.dirname(bpy.data.filepath), "fp_arms.glb")
SOURCE_RIG = "arm_game_rig"
SOURCE_MESH = "arms_final"
FPS = 30

FINGERS = ["thumb", "f_index", "f_middle", "f_ring", "f_pinky"]
SIDES = ["L", "R"]


def bone_map():
    """Hueso DEF de origen -> hueso limpio. None es 'al pecho'."""
    out = {"DEF-spine.003": "chest"}
    for s in SIDES:
        out["DEF-shoulder.%s" % s] = "shoulder.%s" % s
        out["DEF-upper_arm.%s" % s] = "upper_arm.%s" % s
        out["DEF-forearm.%s" % s] = "forearm.%s" % s
        out["DEF-hand.%s" % s] = "hand.%s" % s
        for f in FINGERS:
            for i in (1, 2, 3):
                out["DEF-%s.0%d.%s" % (f, i, s)] = "%s.0%d.%s" % (f, i, s)
    return out


def parent_of(name):
    if name == "chest":
        return None
    base, side = name.rsplit(".", 1)
    if base == "shoulder":
        return "chest"
    if base == "upper_arm":
        return "shoulder.%s" % side
    if base == "forearm":
        return "upper_arm.%s" % side
    if base == "hand":
        return "forearm.%s" % side
    finger, index = base.rsplit(".", 1)
    if index == "01":
        return "hand.%s" % side
    return "%s.0%d.%s" % (finger, int(index) - 1, side)


# Pesos: los grupos de twist (.001) y cualquier DEF que no este en el mapa van a
# su padre logico. Los grupos con nombres del metarig se ignoran: los movia el
# modificador al metarig, que esta en reposo y no deformaba nada.
def target_group(group_name, mapping):
    if group_name in mapping:
        return mapping[group_name]
    if not group_name.startswith("DEF-"):
        return None
    for twist in ("upper_arm", "forearm"):
        for s in SIDES:
            if group_name.startswith("DEF-%s.%s" % (twist, s)):
                return "%s.%s" % (twist, s)
    return "chest"


def main():
    scene = bpy.context.scene
    scene.render.fps = FPS
    src_rig = bpy.data.objects[SOURCE_RIG]
    src_mesh = bpy.data.objects[SOURCE_MESH]
    mapping = bone_map()

    # Pose evaluada del rig de origen, con constraints: de ahi salen el puño y la
    # pose de los brazos.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    src_eval = src_rig.evaluated_get(depsgraph)
    rest = {}
    posed = {}
    for src_name, dst_name in mapping.items():
        rest[dst_name] = src_rig.data.bones[src_name].matrix_local.copy()
        posed[dst_name] = src_eval.pose.bones[src_name].matrix.copy()

    # --- Esqueleto limpio ---
    arm_data = bpy.data.armatures.new("FPArms")
    rig = bpy.data.objects.new("FPArms", arm_data)
    scene.collection.objects.link(rig)
    rig.matrix_world = src_rig.matrix_world.copy()
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for src_name, dst_name in mapping.items():
        src_bone = src_rig.data.bones[src_name]
        eb = arm_data.edit_bones.new(dst_name)
        eb.head = src_bone.head_local
        eb.tail = src_bone.tail_local
        # La matriz trae el roll; asignarla despues de head/tail lo conserva.
        eb.matrix = src_bone.matrix_local
        eb.length = src_bone.length
    for dst_name in mapping.values():
        p = parent_of(dst_name)
        if p:
            arm_data.edit_bones[dst_name].parent = arm_data.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")

    # --- Malla: espejo aplicado, sin armature, pesos rehechos ---
    mesh_obj = src_mesh.copy()
    mesh_obj.data = src_mesh.data.copy()
    mesh_obj.name = "FPArmsMesh"
    scene.collection.objects.link(mesh_obj)
    mesh_obj.parent = None
    mesh_obj.matrix_world = src_mesh.matrix_world.copy()
    for mod in list(mesh_obj.modifiers):
        if mod.type == "ARMATURE":
            mesh_obj.modifiers.remove(mod)
    bpy.context.view_layer.objects.active = mesh_obj
    for mod in list(mesh_obj.modifiers):
        with bpy.context.temp_override(object=mesh_obj, active_object=mesh_obj):
            bpy.ops.object.modifier_apply(modifier=mod.name)

    names = {g.index: g.name for g in mesh_obj.vertex_groups}
    weights = []
    for v in mesh_obj.data.vertices:
        acc = {}
        for g in v.groups:
            dst = target_group(names[g.group], mapping)
            if dst is None or g.weight <= 0.0:
                continue
            acc[dst] = acc.get(dst, 0.0) + g.weight
        weights.append(acc)
    mesh_obj.vertex_groups.clear()
    groups = {n: mesh_obj.vertex_groups.new(name=n) for n in mapping.values()}
    for vi, acc in enumerate(weights):
        total = sum(acc.values())
        if total <= 0.0:
            groups["chest"].add([vi], 1.0, "REPLACE")
            continue
        for n, w in acc.items():
            groups[n].add([vi], w / total, "REPLACE")

    mesh_obj.parent = rig
    mesh_obj.matrix_parent_inverse = rig.matrix_world.inverted()
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig

    _fix_material(mesh_obj)

    # --- Poses ---
    # Rotacion local de cada hueso en la pose del rig, relativa a su reposo, en la
    # jerarquia nueva. Es lo que hay que poner en rotation_quaternion.
    def local_pose(name):
        p = parent_of(name)
        if p is None:
            rel_rest = rest[name]
            rel_pose = posed[name]
        else:
            rel_rest = rest[p].inverted() @ rest[name]
            rel_pose = posed[p].inverted() @ posed[name]
        return (rel_rest.inverted() @ rel_pose).to_quaternion()

    rig_pose = {n: local_pose(n) for n in mapping.values()}
    ident = Quaternion()

    def curl(name, amount):
        """Fraccion del puño del rig: 0 es el dedo estirado del reposo, 1 el puño.
        Por eje y angulo y no por slerp: el gatillo apretado pasa un poco de 1."""
        axis, angle = rig_pose[name].to_axis_angle()
        return Quaternion(axis, angle * amount)

    # El pulgar del rig esta estirado (pulgar arriba / abajo): su pose no sirve de
    # puño. Se lo cierra a mano, girando cada falange hacia la palma. La palma mira
    # a -Z en el reposo (pose en T, palmas abajo), de ahi el eje.
    THUMB_FULL_DEGREES = {1: 30.0, 2: 45.0, 3: 50.0}

    def thumb_curl(name, amount):
        index = int(name.split(".")[1])
        rest3 = rest[name].to_3x3()
        along = (rest3 @ Vector((0.0, 1.0, 0.0))).normalized()
        axis = along.cross(Vector((0.0, 0.0, -1.0))).normalized()
        local_axis = (rest3.inverted() @ axis).normalized()
        return Quaternion(local_axis, math.radians(THUMB_FULL_DEGREES[index]) * amount)

    def hand_pose(side, fingers, thumb, index=None):
        out = {}
        for f in FINGERS:
            for i in (1, 2, 3):
                n = "%s.0%d.%s" % (f, i, side)
                if f == "thumb":
                    out[n] = thumb_curl(n, thumb)
                elif f == "f_index" and index is not None:
                    out[n] = curl(n, index)
                else:
                    out[n] = curl(n, fingers)
        return out

    def arms_pose():
        out = {}
        for s in SIDES:
            for b in ("shoulder", "upper_arm", "forearm", "hand"):
                n = "%s.%s" % (b, s)
                out[n] = rig_pose[n]
        out["chest"] = ident
        return out

    # Sobre un arma el pulgar derecho va a medio cerrar, a lo largo del costado.
    GRIP_R = hand_pose("R", 1.0, 1.0, index=0.55)
    GRIP_L = hand_pose("L", 0.85, 0.8)
    OPEN_R = hand_pose("R", 0.12, 0.0)
    OPEN_L = hand_pose("L", 0.12, 0.0)
    MAG_L = hand_pose("L", 0.65, 0.9)

    def merge(*parts):
        out = arms_pose()
        for p in parts:
            out.update(p)
        return out

    def wrist(side, pitch_deg, yaw_deg=0.0):
        n = "hand.%s" % side
        q = Quaternion((1, 0, 0), math.radians(pitch_deg)) @ Quaternion((0, 0, 1), math.radians(yaw_deg))
        return {n: rig_pose[n] @ q}

    def squeeze(side, index_amount, fingers_amount):
        return hand_pose(side, fingers_amount, 1.0, index=index_amount)

    clips = {
        "grip_idle": (True, [
            (0, merge(GRIP_R, GRIP_L)),
            (30, merge(squeeze("R", 0.58, 0.97), hand_pose("L", 0.8, 0.3), wrist("L", 2.0))),
            (60, merge(GRIP_R, GRIP_L)),
        ]),
        "fire": (False, [
            (0, merge(GRIP_R, GRIP_L)),
            (2, merge(squeeze("R", 1.0, 1.05), GRIP_L, wrist("R", -4.0))),
            (6, merge(GRIP_R, GRIP_L)),
        ]),
        # 30 cuadros = 1 s. Godot lo recorre por progreso de recarga, asi que el
        # largo solo fija las proporciones entre los tramos.
        "reload": (False, [
            (0, merge(GRIP_R, GRIP_L)),
            (4, merge(OPEN_R, OPEN_L)),
            (9, merge(OPEN_R, MAG_L, wrist("L", -20.0))),
            (15, merge(OPEN_R, MAG_L, wrist("L", -25.0, 10.0))),
            (20, merge(OPEN_R, MAG_L, wrist("L", 10.0))),
            (23, merge(OPEN_R, OPEN_L, wrist("L", 20.0))),
            (26, merge(GRIP_R, OPEN_L)),
            (30, merge(GRIP_R, GRIP_L)),
        ]),
        "equip": (False, [
            (0, merge(OPEN_R, OPEN_L)),
            (6, merge(OPEN_R, OPEN_L, wrist("R", 8.0), wrist("L", 8.0))),
            (12, merge(GRIP_R, GRIP_L)),
        ]),
        "open": (True, [
            (0, merge(OPEN_R, OPEN_L)),
            (1, merge(OPEN_R, OPEN_L)),
        ]),
        # Tirando el gancho: la derecha sigue en el arma y la izquierda se abre,
        # dedos casi rectos, la mano que apunta. Muñeca neutra: la orientacion la
        # pone la IK de Godot, alineada con el antebrazo.
        "grapple": (True, [
            (0, merge(GRIP_R, hand_pose("L", 0.06, 0.0))),
            (1, merge(GRIP_R, hand_pose("L", 0.06, 0.0))),
        ]),
    }

    rig.animation_data_create()
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for clip_name, (loop, keys) in clips.items():
        action = bpy.data.actions.new(clip_name)
        rig.animation_data.action = action
        for frame, pose in keys:
            for bone_name, q in pose.items():
                pb = rig.pose.bones[bone_name]
                pb.rotation_quaternion = q
                pb.location = (0, 0, 0)
                pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)
        action.use_fake_user = True
        # Cada accion a su pista de NLA: es como el exportador de glTF sabe que
        # tiene que mandar las cinco y no solo la activa.
        track = rig.animation_data.nla_tracks.new()
        track.name = clip_name
        track.strips.new(clip_name, keys[0][0], action)
        track.mute = True
        rig.animation_data.action = None

    # Pose de reposo en Blender: la del agarre, para que el archivo se lea.
    for n, q in merge(GRIP_R, GRIP_L).items():
        rig.pose.bones[n].rotation_quaternion = q

    # --- Exportar solo lo nuevo ---
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh_obj.select_set(True)
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
        export_def_bones=False,
        export_cameras=False,
        export_lights=False,
        export_image_format="AUTO",
    )
    print("FP_ARMS written", OUTPUT)


def _fix_material(mesh_obj):
    """El Diffuse BSDF pasa a Principled con la misma textura, que glTF si lee."""
    for slot in mesh_obj.material_slots:
        src = slot.material
        if src is None or src.node_tree is None:
            continue
        image = None
        for node in src.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                image = node.image
        mat = bpy.data.materials.new(src.name)
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 0.75
        bsdf.inputs["Metallic"].default_value = 0.0
        if image is not None:
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = image
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        slot.material = mat


main()
