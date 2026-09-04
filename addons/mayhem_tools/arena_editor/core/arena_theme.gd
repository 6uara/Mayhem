@tool
class_name ArenaTheme
extends Resource
## Everything that surrounds an authored arena: the stands, the backdrop, the
## sky, and the drop that kills you.
##
## The grid is the part the player builds. This is the part they never touch and
## always see - and it is a resource rather than code so a new venue is an
## authored scene plus a `.tres`, the same deal as a new piece.

const THEME_DIR: String = "res://data/arena_themes"

@export var id: StringName = &"default"
@export var display_name: String = "Default"

@export_group("Surroundings")
## Instanced under the arena and, if it has `setup(bounds: AABB)`, told how big
## the arena is so it can put its walls and stands around the real footprint.
## A theme with no shell still gets sky, sun and a kill plane.
@export var shell_scene: PackedScene
## Left empty the runtime builds the default one, which matches the greybox.
@export var environment: Environment
@export var sun_rotation_degrees: Vector3 = Vector3(-45.0, -30.0, 0.0)
@export var sun_energy: float = 1.1
@export var sun_color: Color = Color(1.0, 0.97, 0.92)

@export_group("Pit")
## The hole in the middle of `shell_scene`, in the shell's own units, measured
## with `tools/measure_shell_pit.gd`. Lives here rather than on the shell script
## so a tool can ask "what shape is this venue" without instancing a scene - the
## arena editor uses it to warn when an arena and its venue disagree.
@export var pit_size: Vector2 = Vector2(19.0, 9.5)
@export var pit_center: Vector2 = Vector2(0.0, -4.75)

@export_group("Bounds")
## Metres below the lowest cell where falling stops being a fall and becomes a
## death. Without it a player who walks off the edge falls forever.
@export var kill_plane_depth: float = 30.0
## Metres of margin the kill volume adds around the grid footprint, so stepping
## just off the edge still lands in it.
@export var kill_plane_margin: float = 200.0


## Every theme on disk, always with a usable default even before any exist.
static func list_themes() -> Array[ArenaTheme]:
	var themes: Array[ArenaTheme] = []
	if DirAccess.dir_exists_absolute(THEME_DIR):
		for file_name: String in DirAccess.get_files_at(THEME_DIR):
			var clean: String = file_name.trim_suffix(".remap")
			if clean.get_extension().to_lower() != "tres":
				continue
			var theme := load(THEME_DIR.path_join(clean)) as ArenaTheme
			if theme != null:
				themes.append(theme)
	if themes.is_empty():
		themes.append(ArenaTheme.new())
	themes.sort_custom(func(a: ArenaTheme, b: ArenaTheme) -> bool:
		return a.display_name < b.display_name)
	return themes


## The theme an arena asks for, or the first one available. An arena never fails
## to load because someone renamed a theme file.
static func find(theme_id: StringName) -> ArenaTheme:
	var themes: Array[ArenaTheme] = list_themes()
	for theme: ArenaTheme in themes:
		if theme.id == theme_id:
			return theme
	return themes[0]


## How far the venue has to stretch to fit `footprint` (x, z in metres), per
## axis. A pit shaped like the arena returns two equal numbers; the further
## apart they are, the more the terraces are pulled out of shape on one side.
func get_fit(footprint: Vector2, margin: float = 0.0) -> Vector2:
	var wanted: Vector2 = footprint + Vector2.ONE * margin * 2.0
	return Vector2(wanted.x / maxf(pit_size.x, 0.001), wanted.y / maxf(pit_size.y, 0.001))


## 1.0 when the arena has the same proportions as the pit; 2.0 when one axis has
## to stretch twice as much as the other.
func get_stretch(footprint: Vector2, margin: float = 0.0) -> float:
	var fit: Vector2 = get_fit(footprint, margin)
	var low: float = minf(fit.x, fit.y)
	if low <= 0.0:
		return 1.0
	return maxf(fit.x, fit.y) / low


## The arena footprint that fits this venue without stretching anything: the pit
## proportions, scaled to whatever the longer side should be.
func suggest_footprint(longest_side: float) -> Vector2:
	var ratio: float = pit_size.y / maxf(pit_size.x, 0.001)
	if pit_size.y > pit_size.x:
		return Vector2(longest_side * (pit_size.x / pit_size.y), longest_side)
	return Vector2(longest_side, longest_side * ratio)


## Falls back to the greybox arena's look, so an arena is lit and framed even
## before anyone authors a venue for it.
func get_environment() -> Environment:
	if environment != null:
		return environment
	var built := Environment.new()
	built.background_mode = Environment.BG_COLOR
	built.background_color = Color(0.117, 0.235, 0.396)
	built.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	built.ambient_light_color = Color(0.5, 0.55, 0.65)
	built.ambient_light_energy = 0.6
	built.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	built.glow_enabled = true
	built.glow_intensity = 0.9
	built.glow_hdr_threshold = 1.05
	return built
