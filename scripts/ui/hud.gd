extends CanvasLayer
## Combat HUD, built to SPEC-STYLEGUIDE-HUD.
##
## Layout law: the centre 900x500 is a no-UI zone. Only the reticle, damage chevrons
## and hitmarkers may enter it - every cluster anchors to its own corner, so an
## ultrawide screen pushes them apart rather than stretching them.
##
## The HUD never polls: every value arrives on a signal from the gameplay layer.

const LOW_AMMO_PIP_STEP: int = 2  ## above AMMO_PIP_MAX, one pip per 2 rounds

@onready var _root: Control = $Root
@onready var _reticle: Reticle = $Root/Reticle

# Wave cluster
@onready var _wave_number: Label = $Root/WaveCluster/WaveRow/Value
@onready var _enemies_left: Label = $Root/WaveCluster/EnemiesRow/Count

# Timer cluster
@onready var _elapsed: Label = $Root/TimerCluster/TimeRow/Elapsed
@onready var _par: Label = $Root/TimerCluster/TimeRow/Par
@onready var _par_bar: SegmentStrip = $Root/TimerCluster/ParBar
@onready var _no_damage_mark: ColorRect = $Root/TimerCluster/NoDamageRow/Mark
@onready var _no_damage_label: Label = $Root/TimerCluster/NoDamageRow/Text

# Currency
@onready var _currency: Label = $Root/CurrencyCluster/CurrencyRow/Amount
@onready var _powerups: VBoxContainer = $Root/CurrencyCluster/PowerUpList

# Vitals
@onready var _health_value: Label = $Root/VitalsCluster/HealthRow/Value
@onready var _critical_tag: HBoxContainer = $Root/VitalsCluster/HealthRow/CriticalTag
@onready var _health_segments: SegmentStrip = $Root/VitalsCluster/HealthSegments
@onready var _dash_pips: SegmentStrip = $Root/VitalsCluster/DashRow/Pips

# Abilities
@onready var _ability_bar: HBoxContainer = $Root/AbilityBar

# Weapon
@onready var _ammo_mag: Label = $Root/WeaponCluster/AmmoRow/Magazine
@onready var _ammo_reserve: Label = $Root/WeaponCluster/AmmoRow/Reserve
@onready var _reload_prompt: HBoxContainer = $Root/WeaponCluster/AmmoRow/ReloadPrompt
@onready var _ammo_pips: SegmentStrip = $Root/WeaponCluster/AmmoPips
@onready var _weapon_list: VBoxContainer = $Root/WeaponCluster/WeaponList

# Overlays
@onready var _subtitle_box: PanelContainer = $Root/SubtitleBox
@onready var _subtitle_tag: Label = $Root/SubtitleBox/Row/Tag
@onready var _subtitle_text: Label = $Root/SubtitleBox/Row/Body
@onready var _hint_box: PanelContainer = $Root/TutorialHintBox
@onready var _hint_text: Label = $Root/TutorialHintBox/Text
@onready var _announce: VBoxContainer = $Root/AnnounceLayer
@onready var _announce_tag: Label = $Root/AnnounceLayer/TagPill/Tag
@onready var _announce_title: Label = $Root/AnnounceLayer/Title
@onready var _damage_indicators: DamageIndicators = $Root/DamageIndicators
@onready var _state_overlays: Control = $Root/StateOverlays
@onready var _speed_lines: SpeedLinesOverlay = $Root/StateOverlays/SpeedLines

var _player: Player
var _weapon: WeaponComponent
var _announce_timer: float = 0.0
var _utility_slots: Array[Control] = []
var _grapple_slot: Control

## What _tick_wave() last wrote into the timer cluster. It runs every frame, but
## the values it derives change on transitions - a new wave, crossing par, taking
## the first hit - so these let it push only what actually moved.
var _wave_shown: WaveData
var _over_par_shown: bool = false
var _intact_shown: bool = true
## The two labels _tick_wave() writes every frame, held as the values they were
## last built from rather than as the strings themselves. Both are counters that
## step - one per second, one per kill - so 59 frames out of 60 were formatting a
## String and re-laying out a Label to produce what was already on screen.
var _elapsed_seconds_shown: int = -1
var _remaining_shown: int = -1
## Last state pushed into the grapple slot. Assigning `theme_type_variation`
## invalidates the control and re-notifies its subtree whether or not the
## variation differs, so this is the same transition-only rule the timer cluster
## below already follows.
var _grapple_state_shown: int = -1


func _ready() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_hud_scale()

	EventBus.ammo_changed.connect(_on_ammo_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.settings_applied.connect(_apply_hud_scale)
	UpgradeManager.upgrades_changed.connect(_refresh_powerups)
	NarratorManager.subtitle_shown.connect(_on_subtitle_shown)
	NarratorManager.subtitle_hidden.connect(_on_subtitle_hidden)
	TutorialHintManager.hint_shown.connect(_on_hint_shown)
	TutorialHintManager.hint_hidden.connect(_on_hint_hidden)

	_subtitle_box.visible = false
	_hint_box.visible = false
	_announce.visible = false
	_critical_tag.visible = false
	_reload_prompt.visible = false
	_on_currency_changed(EconomyManager.currency)
	EventBus.spectating_changed.connect(_on_spectating_changed)
	_bind_player.call_deferred()


func _process(delta: float) -> void:
	if _announce_timer > 0.0:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce.visible = false

	if _player == null:
		return
	# On a client, health arrives as a replicated value rather than as a
	# damaged() signal: the hit landed on the host, against the host's copy of
	# this body. Nothing fires locally to refresh the bar, so it is read every
	# frame instead. Solo runs keep the signal path and skip this entirely.
	if NetworkManager.is_online():
		_refresh_health()
	_tick_weapon()
	_tick_movement()
	_tick_wave()


# Binding

func _bind_player() -> void:
	# Our own body, never a teammate's - this HUD shows one player's health, ammo
	# and dash charges, and on every machine that player is the local one.
	_player = Players.local() as Player
	if _player == null:
		# Normal on a client: the scene is up but our body is still in flight
		# from the host. Bind when it lands instead of warning about it.
		if not EventBus.local_player_spawned.is_connected(_on_local_player_spawned):
			EventBus.local_player_spawned.connect(_on_local_player_spawned)
		return

	if _player.health != null:
		_player.health.damaged.connect(_refresh_health.unbind(2))
		_player.health.healed.connect(_refresh_health.unbind(2))
		_refresh_health()
	if _player.weapon_holder != null:
		_player.weapon_holder.weapon_changed.connect(_on_weapon_equipped)
		_player.weapon_holder.weapon_replaced.connect(_rebuild_weapon_list)
		_on_weapon_equipped(_player.weapon)
		_rebuild_weapon_list()
	if _player.utility != null:
		_player.utility.utility_changed.connect(_on_utility_changed.unbind(2))
		_player.utility.armed_changed.connect(_on_utility_armed)
	_build_ability_bar()


func _on_local_player_spawned(_player_node: Node3D) -> void:
	EventBus.local_player_spawned.disconnect(_on_local_player_spawned)
	_bind_player()


## This HUD reads one player's health, ammo and dash charges - and a spectator
## has none of those. Leaving it up would show a frozen readout of the corpse
## the camera just left behind.
func _on_spectating_changed(is_spectating: bool, _target_name: String) -> void:
	visible = not is_spectating


## Three utility slots plus the grapple, separated by a divider.
func _build_ability_bar() -> void:
	for child: Node in _ability_bar.get_children():
		child.queue_free()
	_utility_slots.clear()

	var keys: Array[String] = ["Q", "X", "C"]
	for i: int in UtilityComponent.SLOT_COUNT:
		var data: UtilityData = _player.utility.get_slot_data(i) if _player.utility != null else null
		var slot: Control = _make_slot(_icon_for_utility(data), keys[i] if i < keys.size() else "")
		_ability_bar.add_child(slot)
		_utility_slots.push_back(slot)

	var divider := ColorRect.new()
	divider.color = Tokens.LINE
	divider.custom_minimum_size = Vector2(1, Tokens.SLOT_SIZE.y)
	_ability_bar.add_child(divider)

	_grapple_slot = _make_slot(MayhemIcon.Kind.GRAPPLE, "GRAPPLE")
	_ability_bar.add_child(_grapple_slot)
	# Fresh nodes, so whatever the old ones were showing says nothing about these.
	_grapple_state_shown = -1


func _make_slot(kind: MayhemIcon.Kind, keybind: String) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AbilitySlot"
	panel.custom_minimum_size = Tokens.SLOT_SIZE

	var icon := MayhemIcon.new()
	icon.kind = kind
	icon.custom_minimum_size = Vector2(Tokens.SLOT_ICON, Tokens.SLOT_ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(icon)

	var count := Label.new()
	count.name = "Count"
	count.theme_type_variation = &"NumSecond"
	count.add_theme_font_size_override("font_size", 18)
	count.add_theme_color_override("font_color", Tokens.TEXT)
	count.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	count.offset_left = -26
	count.offset_top = 4
	count.offset_right = -6
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(count)

	column.add_child(panel)

	var key := Label.new()
	key.name = "Keybind"
	key.theme_type_variation = &"Keybind"
	key.text = keybind
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(key)

	column.set_meta(&"icon", icon)
	column.set_meta(&"count", count)
	column.set_meta(&"panel", panel)
	return column


func _icon_for_utility(data: UtilityData) -> MayhemIcon.Kind:
	if data == null:
		return MayhemIcon.Kind.NONE
	match data.id:
		&"stun_grenade": return MayhemIcon.Kind.STUN_GRENADE
		&"temp_wall": return MayhemIcon.Kind.TEMP_WALL
		&"slow_field": return MayhemIcon.Kind.SLOW_FIELD
	return MayhemIcon.Kind.NONE


# Per-frame state

func _tick_weapon() -> void:
	if _weapon == null:
		return
	_reticle.set_spread(_weapon.get_current_spread(), _player.camera.fov)
	_reticle.ads_progress = _weapon.ads_progress
	if _player.grapple != null:
		_reticle.is_anchor_available = _player.grapple.is_anchor_in_range


func _tick_movement() -> void:
	var movement: MovementComponent = _player.movement
	if movement != null:
		_dash_pips.configure(movement.get_dash_charges_max(),
			movement.get_dash_charges_available())
		_dash_pips.progress = movement.dash_charges.get_next_charge_progress()

	# Real horizontal speed, not MovementComponent.get_move_speed()'s target -
	# the same "excess over a normal run" Player._tick_speed_fov() already
	# computes for FOV. Runs even if the grapple slot below is unwired.
	if _speed_lines != null:
		_speed_lines.set_speed(Vector3(_player.velocity.x, 0.0, _player.velocity.z).length())

	if _grapple_slot == null or _player.grapple == null:
		return
	# Ready / attached / cooling, expressed by border and label, not colour alone.
	# Three states, so the whole thing is one comparison: the slot is only touched
	# on the frame it actually moves between them.
	var state: int = 0
	if _player.grapple.is_grappling:
		state = 2
	elif _player.grapple.is_anchor_in_range:
		state = 1
	if state == _grapple_state_shown:
		return
	_grapple_state_shown = state

	var panel: PanelContainer = _grapple_slot.get_meta(&"panel")
	var icon: MayhemIcon = _grapple_slot.get_meta(&"icon")
	var key: Label = _grapple_slot.get_node("Keybind")
	panel.theme_type_variation = &"AbilitySlotReady" if state > 0 else &"AbilitySlot"
	icon.color = Tokens.PLAYER if state > 0 else Tokens.DIM
	key.text = "ATTACHED" if state == 2 else "GRAPPLE"


func _tick_wave() -> void:
	var wave: WaveData = WaveManager.get_current_wave()
	if wave == null or not WaveManager.is_wave_active:
		return
	var elapsed: float = WaveManager.get_wave_duration()
	var over_par: bool = elapsed > wave.par_time
	var intact: bool = WaveManager.get_damage_taken_this_wave() <= 0.0
	# A wave's par_time is authored and never moves while it is running, so the
	# PAR label is formatted once when the wave changes rather than rebuilt 60
	# times a second.
	var is_new_wave: bool = wave != _wave_shown
	if is_new_wave:
		_wave_shown = wave
		_par.text = "/ PAR %s" % _format_time(wave.par_time)
		# A pooled HUD outlives the wave it was showing, and the new wave may open
		# on the same numbers the old one closed on.
		_elapsed_seconds_shown = -1
		_remaining_shown = -1

	# Same rule as the colour blocks below, for the same reason: these are counters
	# that step, and the frames between steps have nothing to say.
	var remaining: int = WaveManager.get_remaining_count()
	if remaining != _remaining_shown:
		_remaining_shown = remaining
		_enemies_left.text = "%d" % remaining

	var elapsed_seconds: int = int(elapsed)
	if elapsed_seconds != _elapsed_seconds_shown:
		_elapsed_seconds_shown = elapsed_seconds
		_elapsed.text = _format_time(elapsed)

	var ratio: float = clampf(elapsed / maxf(wave.par_time, 0.01), 0.0, 1.0)
	_par_bar.filled = int(round(ratio * float(_par_bar.count)))

	# Past par the whole bar flips to ENEMY: the speed bonus is gone, and the HUD
	# says so the moment it happens rather than at the breakdown screen.
	#
	# Both blocks below fire on transitions only. add_theme_color_override()
	# invalidates the control and re-notifies its subtree on every call, whether
	# or not the colour actually differs, so calling it unconditionally from a
	# per-frame tick pays that cost 60 times a second to cross the same boundary
	# once. The state each one wrote is mirrored here so a re-entry after a wave
	# change still repaints.
	if is_new_wave or over_par != _over_par_shown:
		_over_par_shown = over_par
		_par_bar.filled_color = Tokens.ENEMY if over_par else Tokens.PLAYER
		_elapsed.add_theme_color_override("font_color",
			Tokens.ENEMY if over_par else Tokens.TEXT)

	if is_new_wave or intact != _intact_shown:
		_intact_shown = intact
		_no_damage_mark.color = Tokens.PLAYER if intact else Tokens.LINE
		_no_damage_label.text = "NO DAMAGE - INTACT" if intact else "NO DAMAGE - LOST"
		_no_damage_label.add_theme_color_override("font_color",
			Tokens.MUTED if intact else Tokens.DIM)


# Signal handlers

func _refresh_health() -> void:
	if _player == null or _player.health == null:
		return
	var health: HealthComponent = _player.health
	_health_value.text = "%d" % ceili(health.current_health)

	# One segment = a tenth of max, rounded up so the last only empties at zero.
	var fraction: float = health.get_health_fraction()
	_health_segments.set_filled_with_ghost(ceili(fraction * float(Tokens.HEALTH_SEGMENTS)))

	var is_critical: bool = fraction <= Tokens.LOW_HEALTH_PCT
	_critical_tag.visible = is_critical
	_health_value.add_theme_color_override("font_color",
		Tokens.ENEMY if is_critical else Tokens.TEXT)
	_health_segments.filled_color = Tokens.ENEMY if is_critical else Tokens.PLAYER
	_set_low_health_overlay(is_critical)


func _on_ammo_changed(current: int, reserve: int) -> void:
	_ammo_mag.text = "%d" % current
	_ammo_reserve.text = "/ %d" % reserve
	if _weapon == null:
		return

	var magazine: int = maxi(_weapon.get_magazine_size(), 1)
	var is_low: bool = float(current) / float(magazine) <= Tokens.LOW_AMMO_PCT
	# Low ammo is three signals: colour, a blink, and a RELOAD prompt.
	_ammo_mag.add_theme_color_override("font_color",
		Tokens.REWARD if is_low else Tokens.TEXT)
	_reload_prompt.visible = is_low
	_ammo_pips.filled_color = Tokens.REWARD if is_low else Tokens.PLAYER

	# Above the cap one pip covers two rounds, so the strip stays glanceable.
	var step: int = 1 if magazine <= Tokens.AMMO_PIP_MAX else LOW_AMMO_PIP_STEP
	_ammo_pips.configure(ceili(float(magazine) / float(step)),
		ceili(float(current) / float(step)))


func _on_weapon_equipped(weapon: WeaponComponent) -> void:
	_weapon = weapon
	if weapon == null or weapon.data == null:
		return
	_reticle.sight = _sight_for(weapon.data.id)
	_on_ammo_changed(weapon.get_ammo(), weapon.get_reserve())
	_rebuild_weapon_list()


func _sight_for(weapon_id: StringName) -> Reticle.Sight:
	match weapon_id:
		&"rifle_ak": return Reticle.Sight.RIFLE
		&"shotgun": return Reticle.Sight.SHOTGUN
		&"smg": return Reticle.Sight.SMG
		&"pistol": return Reticle.Sight.PISTOL
	return Reticle.Sight.HIPFIRE


## One weapon carried at a time (loadout design, see WeaponHolder), so this is a
## single indicator rather than a list - same cyan-rail HUDPanel treatment the
## multi-weapon list used to give the equipped row.
func _rebuild_weapon_list() -> void:
	if _player == null or _player.weapon_holder == null:
		return
	for child: Node in _weapon_list.get_children():
		child.queue_free()

	var weapon: WeaponComponent = _player.weapon_holder.current
	if weapon == null or weapon.data == null:
		return

	var row := PanelContainer.new()
	row.theme_type_variation = &"HUDPanel"

	var name_label := Label.new()
	name_label.theme_type_variation = &"HUDLabel"
	name_label.text = weapon.data.display_name.to_upper()
	name_label.add_theme_color_override("font_color", Tokens.TEXT)
	row.add_child(name_label)

	_weapon_list.add_child(row)


func _on_currency_changed(total: int) -> void:
	_currency.text = "%d" % total


## Only temporary upgrades get a chip - a permanent one has no countdown to show.
func _refresh_powerups() -> void:
	for child: Node in _powerups.get_children():
		child.queue_free()
	for upgrade: UpgradeData in UpgradeManager.get_owned():
		if not upgrade.is_temporary:
			continue
		var chip := PowerUpChip.new()
		_powerups.add_child(chip)
		chip.setup(upgrade)


func _on_utility_changed() -> void:
	if _player == null or _player.utility == null:
		return
	for i: int in _utility_slots.size():
		var slot: Control = _utility_slots[i]
		var count: Label = slot.get_meta(&"count")
		var icon: MayhemIcon = slot.get_meta(&"icon")
		var carried: int = _player.utility.get_carried(i)
		count.text = "%d" % carried
		# Nothing carried reads as unavailable, not merely as a zero.
		icon.color = Tokens.TEXT if carried > 0 else Tokens.DIM


## Un gadget en la mano tiene que verse. En modo equipar el jugador queda con
## algo cargado esperando el disparo, y sin señal en pantalla es un estado
## invisible: llegas al tiroteo creyendo que tenes el arma.
func _on_utility_armed(slot: int) -> void:
	for i: int in _utility_slots.size():
		var panel: PanelContainer = _utility_slots[i].get_meta(&"panel")
		panel.modulate = Tokens.REWARD if i == slot else Color.WHITE


func _on_weapon_fired(_weapon_id: StringName) -> void:
	_reticle.note_shot_fired()


func _on_damage_dealt(target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0:
		return
	_reticle.show_hit(Reticle.Hit.HEADSHOT if is_headshot else Reticle.Hit.BODY)
	if target == null:
		return


func _on_enemy_killed(_type: StringName, _position: Vector3, _reward: int) -> void:
	_reticle.show_hit(Reticle.Hit.KILL)


func _on_player_damaged(_amount: float, _remaining: float) -> void:
	_refresh_health()
	_flash_damage()


## Called by whatever dealt the damage when it knows where it came from; the
## indicator falls back to the nearest enemy when nobody reports a direction.
func note_damage_from(world_position: Vector3) -> void:
	if _player == null:
		return
	_damage_indicators.add_hit_from(world_position - _player.global_position)


func _on_wave_started(wave_index: int, config: WaveData) -> void:
	_wave_number.text = "%02d" % (wave_index + 1)
	var is_elite: bool = config != null and config.is_elite_wave
	_wave_number.add_theme_color_override("font_color",
		Tokens.HAZARD if is_elite else Tokens.TEXT)
	_set_elite_stripe(is_elite)
	if is_elite:
		announce("ELITE", "THE WARDEN ENTERS", Tokens.HAZARD)
	else:
		announce("WAVE %d" % (wave_index + 1), "", Tokens.REWARD)


# Overlays

## Tag pill, display title, accent rule. Sits at y=180, clear of the no-UI zone.
func announce(tag: String, title: String, tint: Color) -> void:
	_announce_tag.text = tag
	_announce_tag.get_parent().self_modulate = tint
	_announce_title.text = title
	_announce_title.visible = not title.is_empty()
	_announce.visible = true
	_announce_timer = Tokens.ANNOUNCE_LIFE


## Three treatments, per SPEC-MENUS-HOST 7.3. Tier 3 drops the HOST tag and sets
## the line itself in display type - reserved for the beats that should land.
func _on_subtitle_shown(text: String, _duration: float, tier: int) -> void:
	if not bool(SettingsManager.get_value("accessibility/subtitles_enabled")):
		return
	_subtitle_text.text = text
	_apply_subtitle_tier(tier)
	_subtitle_box.visible = true
	_subtitle_box.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_subtitle_box, "modulate:a", 1.0, Tokens.SUBTITLE_FADE_IN)


func _apply_subtitle_tier(tier: int) -> void:
	var is_punchline: bool = tier == NarratorManager.Tier.PUNCHLINE
	_subtitle_tag.visible = not is_punchline
	_subtitle_text.theme_type_variation = &"DisplaySmall" if is_punchline else &"Subtitle"
	_subtitle_text.add_theme_color_override("font_color",
		Tokens.REWARD if is_punchline else Tokens.TEXT)

	# The rail is the tier's signal: amber for a taunt, acid for a threat.
	var rail: Color = Tokens.HAZARD if tier == NarratorManager.Tier.WARNING else Tokens.REWARD
	var box: StyleBox = _subtitle_box.get_theme_stylebox("panel").duplicate()
	var chamfered := box as ChamferStyleBox
	if chamfered != null:
		chamfered.rail_color = rail
		# A punchline swaps the dark box for a faint wash of its own colour.
		chamfered.fill_color = Tokens.REWARD if is_punchline else Tokens.VOID
		chamfered.fill_alpha = 0.10 if is_punchline else Tokens.SUBTITLE_ALPHA
		_subtitle_box.add_theme_stylebox_override("panel", chamfered)
	_subtitle_tag.add_theme_color_override("font_color", rail)


func _on_subtitle_hidden() -> void:
	if not _subtitle_box.visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_subtitle_box, "modulate:a", 0.0, Tokens.SUBTITLE_FADE_OUT)
	tween.tween_callback(func() -> void: _subtitle_box.visible = false)


## A first-time-mechanic prompt (TutorialHintManager) - neutral HUD overlay,
## same fade treatment as the subtitle box but never a Host line: the Host
## talks to the crowd, not the player.
func _on_hint_shown(text: String, _duration: float) -> void:
	_hint_text.text = text
	_hint_box.visible = true
	_hint_box.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_hint_box, "modulate:a", 1.0, Tokens.SUBTITLE_FADE_IN)


func _on_hint_hidden() -> void:
	if not _hint_box.visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_hint_box, "modulate:a", 0.0, Tokens.SUBTITLE_FADE_OUT)
	tween.tween_callback(func() -> void: _hint_box.visible = false)


func _set_low_health_overlay(is_critical: bool) -> void:
	var frame: Control = _state_overlays.get_node_or_null("LowHealthFrame")
	if frame == null:
		return
	frame.visible = is_critical
	if not is_critical:
		return
	# Reduce-flashing swaps the breathing pulse for a static frame of the same
	# colour, so the information survives without the motion.
	if bool(SettingsManager.get_value("accessibility/reduce_flashing")):
		frame.modulate.a = 1.0
		return
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(frame, "modulate:a", 0.55, Tokens.LOW_HEALTH_PULSE * 0.5)
	tween.tween_property(frame, "modulate:a", 1.0, Tokens.LOW_HEALTH_PULSE * 0.5)


func _set_elite_stripe(is_elite: bool) -> void:
	var stripe: Control = _state_overlays.get_node_or_null("EliteStripe")
	if stripe != null:
		stripe.visible = is_elite


func _flash_damage() -> void:
	var vignette: Control = _state_overlays.get_node_or_null("DamageVignette")
	if vignette == null:
		return
	vignette.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_property(vignette, "modulate:a", 0.0, Tokens.DAMAGE_PULSE)


func _apply_hud_scale() -> void:
	var factor: float = float(SettingsManager.get_value("hud/scale", 1.0))
	scale = Vector2(factor, factor)


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
