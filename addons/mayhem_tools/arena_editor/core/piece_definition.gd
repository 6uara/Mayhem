@tool
class_name PieceDefinition
extends Resource
## One entry of the arena editor's closed piece catalog.
##
## Everything the editor and the loader need to know about a piece lives here, so
## adding a piece to MAYHEM's arena vocabulary is editing a `.tres`, never code.

enum Category { FLOOR, RAMP, WALL, PLATFORM, PROP }

## Stable identifier. Never recycle the id of a deleted piece: saved arenas
## reference pieces by id and would silently pick up the wrong geometry.
@export var id: StringName = &""
@export var display_name: String = ""
## Geometry instanced at load. Left empty the loader builds a greybox box from
## `footprint` and `greybox_color`, which is what the shipped catalog does.
@export var scene: PackedScene

@export_group("Grid")
## Cells the piece occupies, relative to its origin cell, unrotated.
@export var footprint: Array[Vector3i] = [Vector3i.ZERO]
## Cells an agent can stand in, relative to the origin cell, unrotated.
@export var walkable_cells: Array[Vector3i] = []
## Blocks line of travel through its footprint even where a walkable cell overlaps.
@export var blocks_navigation: bool = false
## Ramps are the only pieces that connect two height levels.
@export var connects_levels: bool = false
## What a piece needs in its cell before it can go there. Meaningless on ground
## pieces: they *are* the floor.
enum Support {
	## Anywhere its own layer is free. Structure - walls, pillars, cover - which
	## stacks on itself to build height.
	ANY,
	## A flat floor tile in the same cell. A bounce pad on the bare grid would
	## hang in the air, and one on a ramp would sit at an angle its scene was
	## never modelled for.
	FLOOR,
	## A cell with no ground at all. What hangs in the air: a grapple anchor is
	## only worth shooting at if it is over your head, not sitting on the floor
	## beside you.
	EMPTY,
}

@export var support: Support = Support.ANY
## Lowest grid level this piece may be placed at. Zero means anywhere; a grapple
## anchor uses it to stay high enough that grappling to it is a move rather than
## a step.
@export var min_level: int = 0

@export_group("Traversal links")
## Cells this piece connects its own cell to, beyond the four neighbours - a
## bounce pad reaching two levels up, a jump link crossing a gap, a zip line
## dropping across the arena. Unrotated, like `footprint`.
##
## Without this the flood fill would call an arena that is only crossable by pad
## "unreachable" and refuse to save it, and the enemies would never use the link
## either. The offset has to match the tuning of the scene behind it: a pad at
## bounce_velocity 20 apexes at 8.3m, which is two 3m levels with margin.
@export var link_offsets: Array[Vector3i] = []
## Player-only traversal - a bounce pad launches bodies in the player group and
## nothing else, and no enemy grapples. These links count when asking "can the
## player get there" and are ignored when asking "can an enemy path there",
## which are different questions the validator has to keep apart.
@export var link_players_only: bool = true
## A pad throws you up; it does not bring you back down. One-way links are also
## the only ones that do not become a bidirectional navigation link at load.
@export var link_is_one_way: bool = true

@export_group("Presentation")
@export var category: Category = Category.FLOOR
@export var icon: Texture2D
@export var greybox_color: Color = Color(0.55, 0.55, 0.58)
## Fraction of the cell the greybox box fills on each axis.
@export var greybox_extents: Vector3 = Vector3(1.0, 1.0, 1.0)


## Ground pieces are what you stand on; body pieces are what stands on them.
## A cell holds at most one of each, which is what lets a wall sit on a floor
## tile without the two counting as an overlap.
func is_ground() -> bool:
	return category == Category.FLOOR or category == Category.RAMP 		or category == Category.PLATFORM


## Metres of cell height this piece fills, from the cell floor up.
func height_fraction() -> float:
	return clampf(greybox_extents.y, 0.0, 1.0)


## `cell` turned `rotation` quarter turns around Y. Right-handed: (x, z) -> (-z, x).
static func rotate_cell(cell: Vector3i, rotation: int) -> Vector3i:
	var turns: int = posmod(rotation, 4)
	var result := cell
	for _i: int in turns:
		result = Vector3i(-result.z, result.y, result.x)
	return result


func get_footprint(rotation: int = 0) -> Array[Vector3i]:
	return _rotated(footprint, rotation)


func get_walkable_cells(rotation: int = 0) -> Array[Vector3i]:
	return _rotated(walkable_cells, rotation)


func get_link_offsets(rotation: int = 0) -> Array[Vector3i]:
	return _rotated(link_offsets, rotation)


# Private

func _rotated(cells: Array[Vector3i], rotation: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell: Vector3i in cells:
		out.append(rotate_cell(cell, rotation))
	return out
