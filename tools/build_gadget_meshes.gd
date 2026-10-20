extends SceneTree
## Arma las mallas de los cuatro gadgets que tira el publico, a .res.
##
##   godot --headless --path . -s res://tools/build_gadget_meshes.gd
##
## Sale a assets/models/meshes/gadget_<id>.res, que es lo que apunta
## `UtilityData.pickup_mesh`. Se vuelve a correr si cambia una forma.
##
## Por que con primitivas de Godot y no modelado: lo que estas mallas tienen que
## resolver es la *silueta* - cuatro objetos que se distingan a 25 m mientras
## giran en el aire o en el piso - y para eso alcanzan cajas, cilindros y aros.
## El color de cada uno ya lo pone el `accent_color` del gadget; aca solo se
## decide la forma y cual parte brilla.
##
## Cada malla tiene dos superficies con nombre: "body" (neutro, mate) y "accent"
## (lo que se tiñe y brilla). `CrowdDropPickup` las busca por nombre, asi que el
## orden no importa. El brillo queda en tiras y marcos, lejos del 10% de la
## superficie que pide la ley de color.

const OUT_DIR: String = "res://assets/models/meshes/"

var _body := SurfaceTool.new()
var _accent := SurfaceTool.new()


func _initialize() -> void:
	_build("stun_grenade", _stun_grenade)
	_build("temp_wall", _temp_wall)
	_build("slow_field", _slow_field)
	_build("medkit", _medkit)
	_build("grapple_launcher", _grapple_launcher, "grapple_launcher.res")
	quit()


func _build(id: String, shape: Callable, file_name: String = "") -> void:
	_body = SurfaceTool.new()
	_accent = SurfaceTool.new()
	_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_accent.begin(Mesh.PRIMITIVE_TRIANGLES)
	shape.call()
	var mesh := ArrayMesh.new()
	_body.commit(mesh)
	mesh.surface_set_name(0, "body")
	_accent.commit(mesh)
	mesh.surface_set_name(1, "accent")
	# Materiales por defecto aunque el juego los reemplace: una superficie sin
	# material ensucia el log al liberarse, y en el editor la malla se ve como va.
	var body := StandardMaterial3D.new()
	body.albedo_color = Color("#2C3140")
	body.roughness = 0.7
	mesh.surface_set_material(0, body)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color("#E6E8EF")
	accent.emission_enabled = true
	accent.emission = Color("#E6E8EF")
	mesh.surface_set_material(1, accent)
	var path: String = OUT_DIR + (file_name if file_name != "" else "gadget_%s.res" % id)
	var error: int = ResourceSaver.save(mesh, path)
	print("gadget %s -> %s (%s)" % [id, path, "ok" if error == OK else str(error)])


# Formas. Todas centradas en el origen, unos 60 cm en su eje mas largo: es lo que
# media la esfera que reemplazan, y el halo y la caja de agarre estan hechos a
# esa medida.

## Lata alta con palanca y anilla: la granada se reconoce por la palanca, que
## asoma de un costado y hace asimetrica la silueta al girar.
func _stun_grenade() -> void:
	_add(_body, _cylinder(0.13, 0.13, 0.42, 12), Vector3.ZERO)
	_add(_body, _cylinder(0.09, 0.1, 0.07, 12), Vector3(0.0, 0.245, 0.0))
	_add(_body, _box(Vector3(0.05, 0.3, 0.06)), Vector3(0.15, 0.08, 0.0),
		Basis(Vector3.BACK, deg_to_rad(-8.0)))
	_add(_body, _torus(0.035, 0.055), Vector3(-0.07, 0.29, 0.0),
		Basis(Vector3.BACK, deg_to_rad(90.0)))
	for y: float in [-0.11, 0.11]:
		_add(_accent, _cylinder(0.136, 0.136, 0.035, 12), Vector3(0.0, y, 0.0))


## Una placa plegada parada sobre dos patas: el muro es el unico gadget plano y
## ancho, y se lo ve de canto la mitad de cada vuelta.
func _temp_wall() -> void:
	_add(_body, _box(Vector3(0.58, 0.42, 0.1)), Vector3(0.0, 0.02, 0.0))
	for x: float in [-0.22, 0.22]:
		_add(_body, _box(Vector3(0.1, 0.07, 0.24)), Vector3(x, -0.22, 0.0))
	# Marco de esquinas, en las dos caras: el corchete cuadrado es la forma de
	# "esto es tuyo" (cian), que es lo que el muro va a ser cuando se despliegue.
	for z: float in [-0.055, 0.055]:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			var at := Vector3(corner.x * 0.22, 0.02 + corner.y * 0.14, z)
			_add(_accent, _box(Vector3(0.1, 0.022, 0.012)), at - Vector3(corner.x * 0.04, 0.0, 0.0))
			_add(_accent, _box(Vector3(0.022, 0.08, 0.012)), at - Vector3(0.0, corner.y * 0.03, 0.0))


## Un disco bajo con cupula: es lo que despliega, un domo, en chico. Achatado a
## proposito para que contra la lata de la granada no haya duda.
func _slow_field() -> void:
	_add(_body, _cylinder(0.26, 0.3, 0.12, 16), Vector3(0.0, -0.1, 0.0))
	_add(_body, _hemisphere(0.2), Vector3(0.0, -0.04, 0.0))
	_add(_accent, _torus(0.27, 0.31), Vector3(0.0, -0.08, 0.0))
	_add(_accent, _sphere(0.045), Vector3(0.0, 0.17, 0.0))


## Una cruz gruesa. Es el unico que cura, y la cruz se lee sin color - el mint
## del gadget es el de la curacion, que de lejos se confunde con el cian.
func _medkit() -> void:
	# En los tres ejes: gira, y una cruz plana de canto es un palo.
	_add(_body, _box(Vector3(0.5, 0.17, 0.17)), Vector3.ZERO)
	_add(_body, _box(Vector3(0.17, 0.5, 0.17)), Vector3.ZERO)
	_add(_body, _box(Vector3(0.17, 0.17, 0.5)), Vector3.ZERO)
	for z: float in [-0.088, 0.088]:
		_add(_accent, _box(Vector3(0.36, 0.05, 0.01)), Vector3(0.0, 0.0, z))
		_add(_accent, _box(Vector3(0.05, 0.36, 0.01)), Vector3(0.0, 0.0, z))
	for x: float in [-0.088, 0.088]:
		_add(_accent, _box(Vector3(0.01, 0.05, 0.36)), Vector3(x, 0.0, 0.0))
		_add(_accent, _box(Vector3(0.01, 0.36, 0.05)), Vector3(x, 0.0, 0.0))


## El lanzador del gancho, en la muñeca izquierda del viewmodel. No es un gadget
## del publico pero sale del mismo taller: cuerpo neutro y acentos cuadrados,
## que en el jugador son cian (lo suyo).
##
## En metros del rig de brazos sin escalar, adelante es -Z (hacia la mano) y
## arriba +Y (el dorso del antebrazo). El origen es donde apoya en la manga.
func _grapple_launcher() -> void:
	_add(_body, _box(Vector3(0.07, 0.045, 0.17)), Vector3(0.0, 0.0225, 0.0))
	# El carrete atras, atravesado: es lo que dice "esto tira un cable".
	_add(_body, _cylinder(0.034, 0.034, 0.08, 12), Vector3(0.0, 0.05, 0.05),
		Basis(Vector3.BACK, deg_to_rad(90.0)))
	_add(_body, _cylinder(0.016, 0.02, 0.07, 8), Vector3(0.0, 0.03, -0.115),
		Basis(Vector3.RIGHT, deg_to_rad(90.0)))
	# Tres uñas del gancho asomando de la boca.
	for angle: float in [0.0, 120.0, 240.0]:
		var spin := Basis(Vector3.FORWARD, deg_to_rad(angle))
		_add(_body, _box(Vector3(0.008, 0.03, 0.022)),
			Vector3(0.0, 0.03, -0.152) + spin * Vector3(0.0, 0.016, 0.0), spin)
	# Acentos: dos cuadrados arriba y la tapa del carrete.
	for z: float in [-0.04, 0.0]:
		_add(_accent, _box(Vector3(0.022, 0.006, 0.022)), Vector3(0.0, 0.048, z))
	for x: float in [-0.041, 0.041]:
		_add(_accent, _cylinder(0.02, 0.02, 0.004, 12), Vector3(x, 0.05, 0.05),
			Basis(Vector3.BACK, deg_to_rad(90.0)))


# Primitivas

func _add(tool: SurfaceTool, mesh: PrimitiveMesh, at: Vector3,
		basis: Basis = Basis.IDENTITY) -> void:
	tool.append_from(mesh, 0, Transform3D(basis, at))


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 6
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	# Con is_hemisphere, height es el alto de la cupula, no el de la esfera entera.
	mesh.height = radius * 0.9
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh


func _hemisphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	# Con is_hemisphere, height es el alto de la cupula, no el de la esfera entera.
	mesh.height = radius * 0.9
	mesh.is_hemisphere = true
	mesh.radial_segments = 16
	mesh.rings = 4
	return mesh
