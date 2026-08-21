class_name EnemyFlask
extends ThrownUtility
## El frasco del Environmental: vuela en parábola y deja un charco donde cae.
##
## Todo el trabajo interesante ya estaba hecho. El arco, el aterrizaje y el pool
## son de `ThrownUtility`, que es el mismo objeto que las utilidades del jugador
## con otra carga adentro; el charco es un `HazardZone` sin modificar, igual que
## el del slam del Elite. Lo único propio de esta clase es qué pasa al tocar el
## piso, que es exactamente lo que la clase base deja abierto.
##
## Por qué eso importa más de lo que parece: el charco hereda gratis la ley de
## `HazardZone` -avisa 0.6s antes de poder lastimar, y el decal se dibuja al radio
## exacto del daño- así que un arquetipo nuevo no puede romper la telegrafía ni
## por descuido. Si esto hubiera sido un área propia, sí.

## El charco que deja. `HazardZone`, pooleado.
@export var hazard_scene: PackedScene
@export var pool_radius: float = 3.0
@export var pool_duration: float = 5.0
@export var pool_damage: float = 8.0


func _ready() -> void:
	# El frasco pasa por encima de la horda, no la choca. Ver ThrownUtility.hit_mask.
	hit_mask = PhysicsLayers.WORLD


## Configura el charco antes del lanzamiento, para que los números vivan en el
## árbol de comportamiento del arquetipo y no acá.
func setup_pool(radius: float, duration: float, damage: float) -> void:
	pool_radius = maxf(radius, 0.1)
	pool_duration = maxf(duration, 0.1)
	pool_damage = maxf(damage, 0.0)


func _activate() -> void:
	_leave_pool()
	ObjectPool.release(self)


## Mismo gesto que `ActionEliteSlam._leave_pool()`, y a propósito: es el
## precedente de que el radio y la duración de un `HazardZone` son argumentos.
func _leave_pool() -> void:
	if hazard_scene == null:
		return
	var hazard: Node = ObjectPool.acquire(hazard_scene)
	var zone := hazard as HazardZone
	if zone == null:
		push_error("EnemyFlask: hazard_scene no es un HazardZone")
		return
	zone.global_position = global_position
	zone.setup(pool_damage, pool_radius, pool_duration)
