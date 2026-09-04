@tool
extends SceneTree
## Cuanto cuesta el coliseo: triangulos del cuenco y espectadores sembrados.
##
##   godot --headless --script tools/measure_coliseum.gd
##
## El plan del venue anota que hay que medir esto y no suponerlo: el cuenco es
## una malla generada cuyo tamano depende de cuatro exports que se tocan a ojo, y
## la tribuna crece con el perimetro por la cantidad de filas. Los dos numeros
## salen distintos en cada arena.

const SHELL: String = "res://scenes/arena/shells/coliseum_shell.tscn"


func _initialize() -> void:
	for side: float in [48.0, 72.0, 96.0]:
		_report(side)
	quit()


func _report(side: float) -> void:
	var shell := (load(SHELL) as PackedScene).instantiate() as ArenaColiseum
	root.add_child(shell)
	shell.setup(AABB(Vector3.ZERO, Vector3(side, 20.0, side)))

	var bowl := shell.get_node("Coliseum/Bowl") as MeshInstance3D
	var crowd := shell.get_node("Crowd") as CrowdStands
	var triangles: int = 0
	for surface: int in bowl.mesh.get_surface_count():
		triangles += (bowl.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			as PackedVector3Array).size() / 3

	print("\n== arena de %.0f x %.0f m" % [side, side])
	print("  cuenco:       %6d triangulos" % triangles)
	print("  filas:        %6d" % shell.get_seat_rows().size())
	print("  espectadores: %6d  (1 draw call)" % crowd.get_seat_count())
	print("  altura grada: %6.1f m" % (
		(shell.get_seat_rows()[shell.get_seat_rows().size() - 1]["path"]
			as PackedVector3Array)[0].y))
	shell.queue_free()
	root.remove_child(shell)
