extends CanvasLayer
## Combat HUD: crosshair, hitmarkers, ammo and narrator subtitles.
## Reads gameplay state through EventBus and the player group - it never reaches
## up into the game scene.

const LOW_AMMO_FRACTION: float = 0.25

@onready var _crosshair: Crosshair = $Crosshair
@onready var _hitmarker: Hitmarker = $Hitmarker
@onready var _ammo_label: Label = $AmmoLabel
@onready var _subtitle: Label = $Subtitle
@onready var _dash_pips: DashPips = $DashPips
@onready var _weapon_label: Label = $WeaponLabel
@onready var _utility_label: Label = $UtilityLabel
@onready var _currency_label: Label = $CurrencyLabel

var _player: Player
var _weapon: WeaponComponent


func _ready() -> void:
	EventBus.ammo_changed.connect(_on_ammo_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.weapon_switched.connect(_on_weapon_switched)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	NarratorManager.subtitle_shown.connect(_on_subtitle_shown)
	NarratorManager.subtitle_hidden.connect(_on_subtitle_hidden)
	_subtitle.text = ""
	_on_currency_changed(EconomyManager.currency)
	_bind_player()


func _process(_delta: float) -> void:
	if _player == null:
		return
	if _weapon != null:
		_crosshair.set_spread(_weapon.get_current_spread(), _player.camera.fov)
	if _player.grapple != null:
		_crosshair.set_anchor_available(_player.grapple.is_anchor_in_range)
	if _player.movement != null and _dash_pips != null:
		var movement: MovementComponent = _player.movement
		_dash_pips.update_charges(
			movement.get_dash_charges_available(),
			movement.get_dash_charges_max(),
			movement.dash_charges.get_next_charge_progress())


# Private

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		push_warning("HUD: no node in the 'player' group, crosshair spread disabled")
		return
	_weapon = _player.weapon
	if _player.weapon_holder != null:
		_player.weapon_holder.weapon_changed.connect(_on_weapon_equipped)
	if _weapon != null:
		_on_ammo_changed(_weapon.get_ammo(), _weapon.get_reserve())
		_on_weapon_equipped(_weapon)
	if _player.utility != null:
		_player.utility.utility_changed.connect(_on_utility_changed)
		_refresh_utilities()


func _on_weapon_equipped(weapon: WeaponComponent) -> void:
	_weapon = weapon
	if weapon == null or weapon.data == null:
		return
	_weapon_label.text = weapon.data.display_name.to_upper()
	_on_ammo_changed(weapon.get_ammo(), weapon.get_reserve())


func _on_weapon_switched(_weapon_id: StringName) -> void:
	if _player != null:
		_on_weapon_equipped(_player.weapon)


func _on_currency_changed(total: int) -> void:
	_currency_label.text = "%d" % total


func _on_utility_changed(_slot: int, _carried: int) -> void:
	_refresh_utilities()


## One line per slot: key, name and how many are carried. Utilities are useless
## if the player cannot see they have any.
func _refresh_utilities() -> void:
	if _player == null or _player.utility == null:
		return
	var parts: Array[String] = []
	for i: int in UtilityComponent.SLOT_COUNT:
		var data: UtilityData = _player.utility.get_slot_data(i)
		if data == null:
			continue
		parts.push_back("[%d] %s x%d" % [i + 1, data.display_name, _player.utility.get_carried(i)])
	_utility_label.text = "
".join(parts)


func _on_ammo_changed(current: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [current, reserve]
	var is_low: bool = _weapon != null \
		and float(current) <= float(_weapon.get_magazine_size()) * LOW_AMMO_FRACTION
	_ammo_label.modulate = Color(1, 0.35, 0.3) if is_low else Color.WHITE


func _on_damage_dealt(target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0:
		return
	var kind: Hitmarker.Kind = Hitmarker.Kind.HEADSHOT if is_headshot else Hitmarker.Kind.BODY
	if _is_dead(target):
		kind = Hitmarker.Kind.KILL
	_hitmarker.show_hit(kind)


func _is_dead(target: Node) -> bool:
	if target == null:
		return false
	for child: Node in target.get_children():
		var health := child as HealthComponent
		if health != null:
			return health.is_dead
	return false


func _on_subtitle_shown(text: String, _duration: float) -> void:
	if not bool(SettingsManager.get_value("accessibility/subtitles_enabled")):
		return
	_subtitle.text = text


func _on_subtitle_hidden() -> void:
	_subtitle.text = ""
