class_name ViewmodelArms
extends Node3D
## Brazos placeholder que sostienen el arma del viewmodel.
##
## Sin ellos el arma flotaba sola delante de la camara. Son cilindros y cajas a
## proposito: lo que resuelven es la lectura ("alguien la esta sosteniendo"), no
## la anatomia, y se reemplazan enteros el dia que haya un rig de brazos de
## verdad.
##
## No se cuelgan del pivot del arma sino al lado, y `WeaponComponent` les copia
## la posicion y el kick pero no el giro de recarga: la recarga es una vuelta
## entera del arma, y unos brazos atornillados a ella girarian por toda la
## pantalla. Mientras el arma gira, las manos la sueltan y la esperan.
##
## Las manos se ubican midiendo la malla del arma, igual que la boca del cañon en
## `WeaponComponent._align_muzzle_to_barrel()`: la derecha en la empuñadura, la
## izquierda bajo el guardamanos. Un arma nueva queda agarrada sin tocar nada.

## Donde nacen los brazos, en el espacio de la camara del viewmodel. Abajo y un
## poco detras del ojo, fuera de cuadro: solo se ve el antebrazo entrando.
const RIGHT_SHOULDER: Vector3 = Vector3(0.30, -0.50, 0.10)
const LEFT_SHOULDER: Vector3 = Vector3(-0.26, -0.52, 0.05)
## Un arma mas corta que esto se sostiene con las dos manos juntas (pistola).
const TWO_HAND_REACH: float = 0.32

const ARM_RADIUS: float = 0.038
const WRIST_RADIUS: float = 0.03
const HAND_SIZE: Vector3 = Vector3(0.07, 0.055, 0.1)

@export var sleeve_color: Color = Color(0.15, 0.17, 0.21)
@export var glove_color: Color = Color(0.07, 0.07, 0.08)


## Arma los dos brazos para un arma cuya malla ocupa `weapon_bounds`, medida en
## el espacio de este nodo. `pivot_offset` es donde queda este nodo respecto de
## la camara, para poder poner los hombros en el espacio de la camara.
func build(weapon_bounds: AABB, pivot_offset: Vector3) -> void:
	for child: Node in get_children():
		child.queue_free()
	if weapon_bounds.size == Vector3.ZERO:
		return

	var right_hand: Vector3 = grip_point(weapon_bounds)
	var left_hand: Vector3 = support_point(weapon_bounds)
	var sleeve: StandardMaterial3D = _material(sleeve_color)
	var glove: StandardMaterial3D = _material(glove_color)
	_add_arm(RIGHT_SHOULDER - pivot_offset, right_hand, sleeve, glove)
	_add_arm(LEFT_SHOULDER - pivot_offset, left_hand, sleeve, glove)


## La empuñadura: tercio de atras, parte baja. Adelante es -Z.
static func grip_point(bounds: AABB) -> Vector3:
	var centre: Vector3 = bounds.get_center()
	return Vector3(centre.x,
		bounds.position.y + bounds.size.y * 0.25,
		bounds.end.z - bounds.size.z * 0.3)


## El guardamanos, o la otra mano pegada a la primera si el arma es corta.
static func support_point(bounds: AABB) -> Vector3:
	var grip: Vector3 = grip_point(bounds)
	if bounds.size.z < TWO_HAND_REACH:
		return grip + Vector3(-0.035, -0.035, -0.01)
	var centre: Vector3 = bounds.get_center()
	return Vector3(centre.x,
		bounds.position.y + bounds.size.y * 0.3,
		bounds.position.z + bounds.size.z * 0.35)


# Private

func _add_arm(shoulder: Vector3, hand: Vector3, sleeve: Material, glove: Material) -> void:
	var along: Vector3 = hand - shoulder
	var length: float = along.length()
	if length < 0.01:
		return
	var basis: Basis = _basis_along(along / length)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = WRIST_RADIUS
	cylinder.bottom_radius = ARM_RADIUS
	cylinder.height = length
	cylinder.radial_segments = 10
	cylinder.rings = 1
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	arm.mesh = cylinder
	arm.material_override = sleeve
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El cilindro crece sobre su eje Y, centrado: la punta de arriba es la muñeca.
	arm.transform = Transform3D(basis, shoulder + along * 0.5)
	add_child(arm)

	var box := BoxMesh.new()
	box.size = HAND_SIZE
	var hand_mesh := MeshInstance3D.new()
	hand_mesh.name = "Hand"
	hand_mesh.mesh = box
	hand_mesh.material_override = glove
	hand_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_mesh.transform = Transform3D(basis, hand)
	add_child(hand_mesh)


## Una base ortonormal con Y apuntando a `direction`.
func _basis_along(direction: Vector3) -> Basis:
	var reference: Vector3 = Vector3.FORWARD
	if absf(direction.dot(reference)) > 0.95:
		reference = Vector3.RIGHT
	var x: Vector3 = reference.cross(direction).normalized()
	var z: Vector3 = x.cross(direction).normalized()
	return Basis(x, direction, z)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
