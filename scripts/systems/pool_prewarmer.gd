class_name PoolPrewarmer
extends Node
## Prewarms the pooled scenes that are not enemies, while the loading screen is
## still up.
##
## ObjectPool's own contract is "so the first shot never hitches", and only the
## enemies were ever prewarmed (EnemySpawner). Everything else - the player's
## bullets, their impacts, the Ranger's shots, the Bomber's blast - instantiated
## on its first use, in the middle of the first fight it appeared in. One hitch per
## type, and always at the moment the game is trying to feel responsive.
##
## Counts are what a busy moment keeps alive at once, not a run's total: the pool
## grows on its own past them, it just does so with a hitch.

@export var scenes: Array[PackedScene] = []
## One count per entry of `scenes`, same order.
@export var counts: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	if scenes.size() != counts.size():
		push_error("PoolPrewarmer: %d scenes but %d counts" % [scenes.size(), counts.size()])
	for index: int in mini(scenes.size(), counts.size()):
		if scenes[index] != null and counts[index] > 0:
			ObjectPool.prewarm(scenes[index], counts[index])
