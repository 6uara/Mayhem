extends GutTest
## El techo del estadio.
##
## Existe por una razon de juego antes que de imagen: el gancho llega a 28 metros
## y sube con upgrades, y un limite abierto arriba obliga a decidir que pasa
## cuando alguien lo supera. Lo que hay que sostener es que efectivamente cierre,
## y que cerrar no cueste la noche que se acaba de construir.

const SHELL_SCENE: String = "res://scenes/arena/shells/coliseum_shell.tscn"
const BOUNDS := AABB(Vector3.ZERO, Vector3(72.0, 20.0, 72.0))
const REACH := Vector2(60.0, 60.0)
const RIM: float = 35.0


func _roof() -> ArenaRoof:
	var roof := ArenaRoof.new()
	add_child_autofree(roof)
	roof.setup(BOUNDS, REACH, RIM)
	return roof


func test_the_roof_sits_above_the_stands() -> void:
	var roof: ArenaRoof = _roof()
	assert_gt(roof.get_height(), RIM, "el techo no puede quedar dentro de la tribuna")
	assert_almost_eq(roof.get_height(), RIM + roof.rise_above_rim, 0.01)


func test_it_actually_closes_the_arena() -> void:
	# Sin esto todo el techo es decorado y el limite sigue abierto por arriba.
	var roof: ArenaRoof = _roof()
	var ceiling := roof.get_node("Ceiling") as StaticBody3D
	assert_not_null(ceiling, "el techo tiene que parar al jugador")
	var shape := (ceiling.get_child(0) as CollisionShape3D).shape as BoxShape3D
	assert_gt(shape.size.x, BOUNDS.size.x,
		"la tapa tiene que pasarse del borde, o queda una junta por donde colarse")
	assert_gt(shape.size.z, BOUNDS.size.z)


func test_the_ceiling_is_high_enough_to_be_out_of_the_way() -> void:
	# El gancho llega a 28 metros y sube con upgrades. Un techo por debajo de eso
	# convierte el limite en una molestia en vez de en un limite.
	var roof: ArenaRoof = _roof()
	var ceiling := roof.get_node("Ceiling") as StaticBody3D
	assert_gt(ceiling.position.y, 28.0)


func test_the_oculus_stays_open() -> void:
	# Cerrar no puede costar la noche: el hueco del medio es por donde se ve el
	# cielo y por donde bajan los haces.
	var roof: ArenaRoof = _roof()
	var oculus: Vector2 = roof.get_oculus_reach(REACH)
	assert_gt(oculus.x, 0.0)
	assert_lt(oculus.x, REACH.x, "el oculo es un hueco, no el techo entero")


func test_the_beams_reach_the_floor() -> void:
	# Un haz que se queda a mitad de camino se lee como un cono flotando.
	var roof: ArenaRoof = _roof()
	var beams := roof.get_node("Roof/Beams")
	assert_eq(beams.get_child_count(), roof.beams)
	for child: Node in beams.get_children():
		var mesh := child as MeshInstance3D
		var cone := mesh.mesh as CylinderMesh
		var bottom: float = mesh.position.y - cone.height * 0.5
		assert_almost_eq(bottom, BOUNDS.position.y, 0.01)


func test_the_beams_cast_no_shadows() -> void:
	# Son conos aditivos, no luces: una SpotLight3D con sombras por cada haz
	# costaria mas que todo el resto del venue junto.
	var roof: ArenaRoof = _roof()
	for child: Node in roof.get_node("Roof/Beams").get_children():
		assert_eq((child as MeshInstance3D).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_the_venue_closes_the_gap_between_wall_and_roof() -> void:
	# La pared tiene que llegar hasta el techo, no hasta una altura suelta: si
	# quedara corta habria una junta por donde salir volando.
	var shell := (load(SHELL_SCENE) as PackedScene).instantiate() as ArenaColiseum
	add_child_autofree(shell)
	shell.setup(BOUNDS)
	var roof := shell.get_node("Roof") as ArenaRoof
	var wall := shell.get_node("EnergyWall") as EnergyWall
	assert_almost_eq(BOUNDS.position.y + wall.height, roof.get_height(), 0.01)
