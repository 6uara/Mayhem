class_name MenuBackdrop
extends Node3D
## La ciudad de fondo del menu principal.
##
## Es literalmente el skyline de la arena -`CitySkyline`, el mismo script y el
## mismo `city_block.gdshader`- sembrado sin coliseo en el medio y mirado desde
## adentro del anillo. No se escribio una ciudad para el menu: si la del juego
## cambia de altura, de densidad o de color de ventana, esta cambia con ella, que
## es la unica forma de que el menu prometa el lugar al que despues entras.
##
## Va como 3D detras de un Control, sin `SubViewport`. Godot dibuja el mundo 3D y
## despues los canvas items encima, asi que el menu queda arriba de la ciudad sin
## pagar una textura intermedia ni una segunda pasada de render.

## El anillo de torres. Se le pasan las medidas del encuadre, no las de una
## arena: aca no hay gradas que rodear.
@export var skyline: CitySkyline
@export var camera: Camera3D

@export_group("Encuadre")
## Radio libre alrededor de la camara antes de que `CitySkyline` empiece a
## sembrar. La primera torre queda a esto mas su `stand_off`.
@export var clearing: float = 150.0
@export var camera_height: float = 24.0
## Cuanto mira para arriba.
##
## Las torres se siembran centradas en el piso, o sea con media torre hundida:
## en la arena esa mitad la tapa la tribuna, y aca no hay tribuna que la tape.
## Apuntar apenas por encima del horizonte deja las bases fuera de cuadro, que
## es mas barato y mas robusto que inventarle un suelo a una ciudad que no lo
## tiene.
@export var pitch_degrees: float = 14.0
@export var fov: float = 62.0

@export_group("Deriva")
## Grados por segundo. Lento a proposito: es un fondo, y lo que tiene que mirar
## el jugador son los botones.
@export var orbit_degrees_per_second: float = 1.1
## Cuanto se corre la camara del centro mientras gira.
##
## Girar en el lugar no da paralaje: la escena entera rota rigida y la ciudad se
## lee como un panorama pintado. Orbitando, los tres anillos de torres se cruzan
## entre si y recien ahi se lee que hay profundidad. Chico, para que la camara
## nunca se acerque a una torre.
@export var orbit_radius: float = 16.0

var _yaw: float = 0.0


func _ready() -> void:
	if skyline != null:
		skyline.populate(Vector3.ZERO, Vector2.ONE * clearing, 0.0)
	if camera != null:
		camera.fov = fov
		camera.current = true
	_place_camera()


func _process(delta: float) -> void:
	_yaw = fmod(_yaw + deg_to_rad(orbit_degrees_per_second) * delta, TAU)
	_place_camera()


# Private

## La camara orbita el centro y mira hacia afuera, que es donde estan las torres.
func _place_camera() -> void:
	if camera == null:
		return
	camera.position = Vector3(
		cos(_yaw) * orbit_radius, camera_height, sin(_yaw) * orbit_radius)
	# Mirando hacia afuera: la camara sin rotar mira a -Z, y este es el yaw que
	# lleva ese -Z sobre el radio (cos _yaw, 0, sin _yaw).
	camera.rotation = Vector3(deg_to_rad(pitch_degrees), -_yaw - PI * 0.5, 0.0)
