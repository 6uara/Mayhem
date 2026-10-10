class_name ViewmodelRig
extends SubViewportContainer
## Renders the equipped weapon in its own world, composited over the main view.
##
## A viewmodel is half a metre of geometry held ~35cm from the eye, so in the main
## world it does what any object that close does: it intersects the wall you are
## standing against, and the camera's near plane slices through it. Neither is
## fixable by moving the model - the world is simply not where a viewmodel belongs.
##
## Its own World3D solves both at once. Nothing in the arena exists in here to
## clip against, and the field of view is decoupled from the player's, so a player
## on 120 FOV gets a wide arena without a fisheye rifle.
##
## Weapons keep their logic in the main world. `WeaponComponent` sends only the
## visual pivot here; the muzzle node, and therefore where rounds actually spawn,
## stays where the body is.

## Narrower than the world camera on purpose - viewmodels distort badly at the wide
## FOVs first-person players prefer, which is why shipped games separate the two.
@export var viewmodel_fov: float = 62.0
@export var camera: Camera3D
## Weapon pivots are parented here.
@export var slots: Node3D


func _ready() -> void:
	if camera != null:
		camera.fov = viewmodel_fov
	_configure_viewport()
	EventBus.settings_applied.connect(_configure_viewport)


## El arma se dibuja en un segundo pase 3D entero, a la resolucion de la ventana.
## Medido en una Radeon 680M, ese pase costaba unos 4 ms por frame - casi tanto
## como toda la horda - para dibujar un arma.
##
## Lo que se le saca no se ve en un arma: el atlas de sombras de luces puntuales
## (ninguna luz de aca proyecta sombra) y el antialias de pantalla. Y se le da la
## misma escala de render que al mundo, asi que bajar la calidad en opciones
## tambien abarata esto, que antes quedaba siempre a resolucion completa.
func _configure_viewport() -> void:
	var viewport := get_node_or_null(^"SubViewport") as SubViewport
	if viewport == null:
		return
	viewport.positional_shadow_atlas_size = 0
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = false
	viewport.use_debanding = false
	viewport.use_occlusion_culling = false
	var main: Viewport = get_viewport()
	if main != null:
		viewport.scaling_3d_mode = main.scaling_3d_mode
		viewport.scaling_3d_scale = main.scaling_3d_scale


## Where WeaponComponent should mount its viewmodel.
func get_slot_parent() -> Node3D:
	return slots
