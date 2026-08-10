class_name TutorialHintCatalog
extends Resource
## Every first-time-mechanic hint, as data rather than string literals in
## TutorialHintManager. Mirrors HostCatalog's shape for the same reason: writing
## a hint is a content job, not a code change.

@export var hints: Array[TutorialHint] = []
