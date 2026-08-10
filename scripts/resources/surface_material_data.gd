class_name SurfaceMaterialData
extends Resource
## What a surface sounds and looks like when something hits it. One resource
## per material so impact feedback is a content job, not a code change.
##
## Grey-box first pass, same as the rest of the Phase 1 VFX (ImpactEffect's own
## docstring): `decal_texture` is left null until real art exists, and more
## than one material currently reuses `impact_world.wav` because no distinct
## sample has been recorded for it yet - see docs/Mayhem/12 Known Issues and
## Gaps.md. `accent_color` alone is enough to make materials read as different
## in the meantime.

@export var id: StringName = &""
@export var impact_sound: AudioStream
## Left null until real decal art exists - the decal still draws (tinted by
## `accent_color`) without one, same as it always has.
@export var decal_texture: Texture2D
## Tints both the decal and the impact spark particles.
@export var accent_color: Color = Color(0.1, 0.1, 0.12, 1)
## Flesh (and anything else soft) never gets a decal, regardless of texture.
@export var spawns_decal: bool = true
