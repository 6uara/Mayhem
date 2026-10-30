class_name EnemyDeathBurst
extends Node3D
## Lo que queda en el aire cuando muere un enemigo: esquirlas en el color de su
## arquetipo, una bocanada de humo y un destello de luz que se apaga solo.
##
## Antes el enemigo volvia al pool y desaparecia entre dos cuadros. La kill se
## cobraba en la HUD y en el mundo no pasaba nada, que es justo al reves de lo
## que tiene que sentir un shooter. Es puramente visual: no lastima, no empuja,
## y no sabe nada del enemigo salvo su color, su altura y donde estaba.
##
## Del pool, como el resto de los efectos de alta rotacion: con una oleada de
## masa mueren varios por segundo.

@export var shards: GPUParticles3D
@export var smoke: GPUParticles3D
@export var flash: OmniLight3D

## Copia por instancia del material de las esquirlas, por la misma razon que
## ImpactEffect: los sub-recursos del .tscn son de todas las copias del pool, y
## teñir uno teñiria el estallido que todavia esta en pantalla.
var _shard_material: StandardMaterial3D
var _time_left: float = 0.0


func _ready() -> void:
	if shards != null and shards.draw_pass_1 != null:
		var mesh := shards.draw_pass_1.duplicate() as Mesh
		_shard_material = (mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		mesh.surface_set_material(0, _shard_material)
		shards.draw_pass_1 = mesh
	if flash != null:
		flash.light_energy = 0.0
		flash.visible = false


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if flash != null and flash.visible:
		var elapsed: float = Tokens.DEATH_BURST_LIFE - _time_left
		var left: float = 1.0 - clampf(elapsed / Tokens.DEATH_FLASH_TIME, 0.0, 1.0)
		flash.light_energy = Tokens.DEATH_FLASH_ENERGY * left * left
		# Apagada del todo y no en cero: una luz invisible igual cuesta en el
		# cluster mientras siga prendida.
		flash.visible = left > 0.0
	if _time_left <= 0.0:
		ObjectPool.release(self)


# Public API

## Revienta aca, del color y del tamaño del enemigo. `at` es el centro del
## cuerpo, no los pies.
func play_at(at: Vector3, color: Color, body_height: float) -> void:
	global_position = at
	scale = Vector3.ONE * clampf(body_height / Tokens.DEATH_BURST_HEIGHT, 0.5, 2.0)
	_time_left = Tokens.DEATH_BURST_LIFE
	if _shard_material != null:
		# Por encima de 1 para que el bloom las agarre: el umbral de la arena esta
		# justo debajo, y solo lo emisivo de verdad pasa.
		_shard_material.albedo_color = Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, 1.0)
	if shards != null:
		shards.restart()
	if smoke != null:
		smoke.restart()
	if flash != null:
		flash.light_color = color
		flash.light_energy = Tokens.DEATH_FLASH_ENERGY
		flash.visible = true


func _on_released() -> void:
	_time_left = 0.0
	if shards != null:
		shards.emitting = false
	if smoke != null:
		smoke.emitting = false
	if flash != null:
		flash.visible = false
