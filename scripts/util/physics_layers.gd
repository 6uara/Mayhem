class_name PhysicsLayers
extends Object
## Named physics layer bits, mirroring the layer names in project.godot.
## Never hardcode a layer mask integer anywhere else.

const WORLD: int = 1 << 0
const PLAYER: int = 1 << 1
const ENEMY: int = 1 << 2
const PLAYER_PROJECTILE: int = 1 << 3
const ENEMY_PROJECTILE: int = 1 << 4
const HITBOX: int = 1 << 5
const HURTBOX: int = 1 << 6
const PICKUP: int = 1 << 7
const GRAPPLE_ANCHOR: int = 1 << 8
const HAZARD: int = 1 << 9
const INTERACTABLE: int = 1 << 10
const TRIGGER: int = 1 << 11
