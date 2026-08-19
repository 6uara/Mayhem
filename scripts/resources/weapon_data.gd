class_name WeaponData
extends Resource
## Static definition of a weapon. All balance numbers live in the .tres instance.

@export var id: StringName = &""
@export var display_name: String = ""
@export var projectile_scene: PackedScene
## First-person viewmodel, instantiated under the weapon's ViewModel node.
@export var viewmodel: PackedScene
@export var viewmodel_scale: float = 1.0
@export var viewmodel_offset: Vector3 = Vector3.ZERO
@export var viewmodel_rotation_degrees: Vector3 = Vector3.ZERO

@export_group("Damage")
@export var damage: float = 10.0
@export var headshot_multiplier: float = 2.0
@export var falloff_start: float = 20.0
@export var falloff_end: float = 45.0
@export var falloff_min_multiplier: float = 0.5

@export_group("Firing")
## Rounds per second.
@export var fire_rate: float = 8.0
## Projectiles emitted per trigger pull (shotgun > 1).
@export var projectiles_per_shot: int = 1
## El disparo se resuelve al apretar el gatillo y la bala que se ve es adorno.
##
## Las armas del jugador van a 140-180 m/s: a treinta metros la bala tarda menos
## de dos decimas, o sea que nadie la esta liderando a proposito. Lo que si se
## paga es un raycast por bala por frame mientras vuela, y medido sobre una
## oleada elite eso era dos tercios del costo de disparar.
##
## Apagalo para un arma cuyo tiempo de vuelo sea parte del diseno - un
## lanzagranadas, algo con arco. Los proyectiles enemigos son otra cosa y no
## pasan por aca: ahi el vuelo es la mecanica (se esquivan) y siguen siendo
## proyectiles de verdad.
@export var is_hitscan: bool = true
## Una trazadora cada cuantas balas. 1 las dibuja todas.
##
## Ver WeaponComponent._wants_tracer: lo caro de disparar es el nodo por bala, no
## la cuenta que hace. Esto es la perilla que lo baja sin cambiar como se lee el
## disparo.
##
## Lo que lo hace gratis es que el ojo rellena el hueco a lo largo del tiempo: a
## quince disparos por segundo, una de cada tres se sigue leyendo como una linea
## de fuego continua. Por eso es una perilla para cadencia alta y no para
## projectiles_per_shot alto - la escopeta manda sus nueve perdigones de una sola
## vez, ahi el patron de dispersion es el visual entero y no hay balas siguientes
## que lo completen. Ralearla se ve como una escopeta mas floja, y encima ahorra
## poco: tira 1.4 veces por segundo. Va en 1 a proposito.
##
## Una bala que no se dibuja tampoco deja impacto ni calcomania: el impacto lo
## genera la trazadora al llegar. El feedback de pegarle a un enemigo no depende
## de esto - sale de take_hit por EventBus.damage_dealt, siempre.
@export_range(1, 10, 1) var tracer_every_n_shots: int = 1
## Velocidad de la bala. Con is_hitscan sigue usandose: es a la que viaja la
## trazadora, que es lo unico que queda volando.
@export var projectile_speed: float = 120.0
@export var projectile_gravity: float = 0.0

@export_group("Ammo")
@export var magazine_size: int = 30
@export var reserve_ammo_max: int = 120
@export var reload_time: float = 2.0

@export_group("Recoil and spread")
@export var recoil_pattern: RecoilPattern
## Spread cone half-angle in degrees.
@export var spread_hipfire: float = 1.5
@export var spread_ads: float = 0.3
@export var spread_moving_multiplier: float = 2.0
@export var spread_airborne_multiplier: float = 3.0

@export_group("ADS")
@export var ads_fov: float = 55.0
@export var ads_transition_time: float = 0.15
@export var ads_move_speed_multiplier: float = 0.7


## Damage multiplier from distance falloff.
func get_falloff_multiplier(distance: float) -> float:
	if distance <= falloff_start or falloff_end <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return falloff_min_multiplier
	var t: float = (distance - falloff_start) / (falloff_end - falloff_start)
	return lerpf(1.0, falloff_min_multiplier, t)


## Final damage for one projectile hit.
func get_damage(distance: float, is_headshot: bool) -> float:
	var value: float = damage * get_falloff_multiplier(distance)
	if is_headshot:
		value *= headshot_multiplier
	return value


func get_shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.001)
