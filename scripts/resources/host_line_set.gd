class_name HostLineSet
extends Resource
## Every line the Host has for one occasion.
##
## Grouped rather than authored one resource per line because the grouping is what
## the pacing rules act on: NarratorManager cools down a whole category at once, so
## "he already commented on a kill streak" is the unit that matters, not which
## particular sentence he used.

## The occasion. HostDirector maps gameplay events onto these.
@export var id: StringName = &""
## Several, so the same moment does not produce the same sentence twice in a run.
@export_multiline var lines: Array[String] = []

@export_group("Delivery")
## STANDARD taunts, WARNING for something the player must act on, PUNCHLINE for the
## once-a-wave line that gets the display treatment.
@export var tier: NarratorManager.Tier = NarratorManager.Tier.STANDARD
## FLAVOR is droppable; CRITICAL always lands and ignores pacing.
@export var priority: NarratorManager.Priority = NarratorManager.Priority.FLAVOR
## 0 uses the manager's default. Raise it for lines that would otherwise fire on
## every kill in a wave.
@export var category_cooldown: float = 0.0


func has_lines() -> bool:
	return not lines.is_empty()
