extends CanvasLayer
## Combat HUD: crosshair, hitmarkers, ammo and narrator subtitles.
## Reads gameplay state through EventBus and the player group - it never reaches
## up into the game scene.

const LOW_AMMO_FRACTION: float = 0.25

@onready var _crosshair: Crosshair = $Crosshair
@onready var _hitmarker: Hitmarker = $Hitmarker
@onready var _ammo_label: Label = $AmmoLabel
@onready var _subtitle: Label = $Subtitle

var _player: Player
var _weapon: WeaponComponent


func _ready() -> void:
	EventBus.ammo_changed.connect(_on_ammo_changed)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	NarratorManager.subtitle_shown.connect(_on_subtitle_shown)
	NarratorManager.subtitle_hidden.connect(_on_subtitle_hidden)
	_subtitle.text = ""
	_bind_player()


func _process(_delta: float) -> void:
	if _weapon == null or _player == null:
		return
	_crosshair.set_spread(_weapon.get_current_spread(), _player.camera.fov)


# Private

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		push_warning("HUD: no node in the 'player' group, crosshair spread disabled")
		return
	_weapon = _player.weapon
	if _weapon != null:
		_on_ammo_changed(_weapon.get_ammo(), _weapon.get_reserve())


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
