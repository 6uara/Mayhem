class_name TutorialHint
extends Resource
## One first-time-mechanic hint. Content lives here, not as string literals in
## TutorialHintManager, so writing a new hint is a data job (CLAUDE.md 1.2).

## Which mechanic this hint answers for - matches the id TutorialHintManager
## fires internally (&"move", &"jump", &"mantle", &"slide", &"dash", &"grapple",
## &"ads", &"reload", &"shop"). Also the key SaveManager persists "seen" under.
@export var id: StringName = &""
@export_multiline var text: String = ""
@export var duration: float = 4.0
## Input action whose live-bound key substitutes into the first "{action}" in
## `text`, e.g. "Press {action} to dash." Reads InputMap at display time, so a
## remapped key is never wrong. Empty = no substitution (multi-key mechanics
## like movement, or hints that don't name a single key).
@export var action: StringName = &""
