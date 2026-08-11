extends SceneTree
## Sets default per-bus gain staging and a Master safety limiter, then saves the
## result back to res://default_bus_layout.tres.
##
## This is a FIRST-PASS gain hierarchy, not a mixed build - see the docstring in
## docs/Mayhem/06 Waves and Economy.md's audio section (or 12 Known Issues and
## Gaps.md) for what still needs a person with speakers and headphones to
## finish: perceptual loudness balance, EQ, reverb sends, and the "does an
## elite wave actually sound right" listening pass. What this script DOES do is
## mechanical: apply the priority order already decided (identify threats
## without looking > Weapons, the #1 portfolio pillar > Impacts > ambient
## Enemies/World > Music, a bed, never the protagonist > UI) as relative dB
## offsets, and add a limiter so a worst-case elite wave (27 enemies, full auto,
## every impact landing at once) can't clip.
##
## Manipulates the live AudioServer state (this project's default_bus_layout.tres
## loads automatically at boot since it sits at res://) rather than hand-editing
## the .tres - bus effects don't have a friendly typed resource API to author by
## hand, and this project already got burned once by hand-editing a text
## resource format it didn't fully understand (see the .tscn/.tres comment
## gotcha in 08 VFX and Shaders.md).
##
##     godot --headless --path . -s tools/configure_audio_mix.gd
##
## Idempotent: rerunning reapplies the same values and replaces the limiter
## rather than stacking a second one.

const OUTPUT_PATH: String = "res://default_bus_layout.tres"

## bus name -> volume_db offset relative to unity. Buses not listed are left
## at whatever the layout on disk already has (Master itself: 0.0, untouched
## here besides the limiter).
const BUS_VOLUMES: Dictionary = {
	"VO": 2.0,        # The Host, and enemy windups - identifiable without looking.
	"Weapons": 1.0,   # Portfolio pillar #1.
	"Impacts": 0.0,   # Closes the gunplay feedback loop.
	"Enemies": 0.0,   # Threat audio; kept at unity rather than pushed back.
	"World": -2.0,    # Movement/world SFX - least critical of the SFX children.
	"Music": -6.0,    # A bed. Never the protagonist.
	"UI": -1.0,       # Feedback chrome.
}


func _initialize() -> void:
	for bus_name: String in BUS_VOLUMES:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index < 0:
			push_warning("configure_audio_mix: no bus named '%s'" % bus_name)
			continue
		AudioServer.set_bus_volume_db(index, float(BUS_VOLUMES[bus_name]))

	_apply_master_limiter()

	var layout: AudioBusLayout = AudioServer.generate_bus_layout()
	var error: int = ResourceSaver.save(layout, OUTPUT_PATH)
	if error != OK:
		push_error("configure_audio_mix: failed to save %s (%d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("Wrote %s: %d buses, Master limiter %.1f/%.1f dB (ceiling/threshold)" % [
		OUTPUT_PATH, AudioServer.bus_count, -1.0, -6.0])
	quit()


## Removes any limiter already on Master before adding one, so rerunning this
## script can't stack duplicates.
func _apply_master_limiter() -> void:
	const MASTER: int = 0
	for i in range(AudioServer.get_bus_effect_count(MASTER) - 1, -1, -1):
		if AudioServer.get_bus_effect(MASTER, i) is AudioEffectLimiter:
			AudioServer.remove_bus_effect(MASTER, i)

	var limiter := AudioEffectLimiter.new()
	# Catches transient pileups (an elite wave's worst case) without audibly
	# squashing normal play - ceiling stays just under 0 dBFS, threshold well
	# below it so the limiter only engages on real peaks.
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -6.0
	AudioServer.add_bus_effect(MASTER, limiter)
