@tool
class_name AttachmentCatalog
extends Resource
## Todos los attachments, y lo que cuesta desbloquearlos: cuanta experiencia da
## cada cosa que se hace con un arma y cuanta pide cada nivel de maestria.

@export var attachments: Array[AttachmentData] = []

@export_group("Experiencia")
## Por cada kill con el arma equipada.
@export var xp_per_kill: int = 5
## Por cada bono de estilo de esa kill: jugar con estilo desbloquea antes.
@export var xp_per_style_bonus: int = 2
## Por cada oleada limpiada con el arma equipada al cerrarla.
@export var xp_per_wave: int = 40
## Por ganar la run, al arma equipada al final.
@export var xp_victory: int = 250
## Experiencia total que pide cada nivel, de menor a mayor. El nivel 1 se
## alcanza con el primer numero.
@export var level_thresholds: PackedInt32Array = PackedInt32Array([300, 1000, 2200])


func get_for_weapon(weapon_id: StringName) -> Array[AttachmentData]:
	var out: Array[AttachmentData] = []
	for attachment: AttachmentData in attachments:
		if attachment != null and attachment.weapon_id == weapon_id:
			out.append(attachment)
	return out


func find(attachment_id: StringName) -> AttachmentData:
	for attachment: AttachmentData in attachments:
		if attachment != null and attachment.id == attachment_id:
			return attachment
	return null


## El nivel que corresponde a `xp` (0 antes del primer umbral).
func level_for(xp: int) -> int:
	var level: int = 0
	for threshold: int in level_thresholds:
		if xp >= threshold:
			level += 1
	return level


func max_level() -> int:
	return level_thresholds.size()
