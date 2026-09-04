@tool
class_name ValidationRules
extends Resource
## The thresholds behind the warning-level rules. Data, so tuning "how small is
## too small" never means editing the validator.

## Fewer walkable cells than this and the arena is a corridor, not an arena.
@export var min_walkable_cells: int = 24
## Enemy spawns closer than this to the player spawn give no reaction time.
@export var min_spawn_distance: int = 4
