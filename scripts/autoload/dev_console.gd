extends CanvasLayer
## In-game developer console. Debug builds only.
##
## The point is to reach a game state fast: jump to wave 8 with a full wallet and
## two upgrades, and see whether the thing that looked wrong on paper is wrong in
## the hands. Every command is a thin call into a system that already exists -
## the console owns no gameplay rules of its own, so it cannot drift from the
## game it is meant to be testing.
##
## Commands live in `_commands` as data: name -> {args, help, handler}. Adding one
## is one entry, and `help` and Tab completion pick it up for free.

const HISTORY_LIMIT: int = 50
const OUTPUT_LIMIT: int = 200
const OPEN_HEIGHT: float = 0.45  ## fraction of the viewport
## Freeze reason, so the console pausing the game cannot fight the pause menu.
const FREEZE_REASON: StringName = &"dev_console"
const CROWD_DROP_SCENE: PackedScene = preload("res://scenes/arena/crowd_drop_pickup.tscn")

var _commands: Dictionary = {}
var _history: PackedStringArray = PackedStringArray()
var _history_index: int = -1

var _root: Control
var _output: RichTextLabel
var _input: LineEdit
var _god_mode: bool = false


func _ready() -> void:
	# Shipping a command line that can hand out money is a debug-build feature.
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_commands()
	_build_ui()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"dev_console"):
		toggle()
		get_viewport().set_input_as_handled()


# Public API

func toggle() -> void:
	set_open(not _root.visible)


func set_open(open: bool) -> void:
	_root.visible = open
	if open:
		_input.clear()
		_input.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		GameManager.set_freeze(FREEZE_REASON, true)
	else:
		GameManager.set_freeze(FREEZE_REASON, false)
		if GameManager.state == GameManager.State.PLAYING and not GameManager.is_paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Runs one command line. Public so tests can drive the console without any UI.
func execute(line: String) -> String:
	var parts: PackedStringArray = line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var name: String = parts[0].to_lower()
	if not _commands.has(name):
		return "unknown command '%s' - type help" % name
	var args: PackedStringArray = parts.slice(1)
	var handler: Callable = _commands[name]["handler"]
	return str(handler.call(args))


func log_line(text: String) -> void:
	if _output == null or text == "":
		return
	_output.append_text(text + "\n")
	if _output.get_line_count() > OUTPUT_LIMIT:
		_output.remove_paragraph(0)


# Private: commands

func _register_commands() -> void:
	_add("help", "[command]", "List commands, or explain one.", _cmd_help)
	_add("give", "<amount>", "Add currency.", _cmd_give)
	_add("wave", "<index>", "Jump to a wave (1-based).", _cmd_wave)
	_add("kill_all", "", "Kill every living enemy.", _cmd_kill_all)
	_add("spawn", "<enemy_id> [count]", "Spawn enemies in front of the player.", _cmd_spawn)
	_add("drop", "[utility_id]", "Have the crowd throw a gadget at the player.", _cmd_drop)
	_add("upgrade", "<upgrade_id> [stacks]", "Grant an upgrade to the player.", _cmd_upgrade)
	_add("upgrades", "", "List owned bonuses, as the O panel shows them.", _cmd_upgrades)
	_add("clear_upgrades", "", "Drop every owned bonus.", _cmd_clear_upgrades)
	_add("heal", "[amount]", "Heal the player, or full heal.", _cmd_heal)
	_add("god", "[on|off]", "Toggle player invulnerability.", _cmd_god)
	_add("tp", "<x> <y> <z>", "Teleport the player.", _cmd_teleport)
	_add("timescale", "<value>", "Set Engine.time_scale.", _cmd_timescale)
	_add("balance", "", "Reload the balance resources from disk.", _cmd_balance)
	_add("shop", "", "Open the shop screen right now.", _cmd_shop)
	_add("stats", "", "Wave, enemies, currency, fps.", _cmd_stats)
	_add("clear", "", "Clear the console output.", _cmd_clear)
	_add("quit", "", "Quit the game.", _cmd_quit)


func _add(name: String, args: String, help: String, handler: Callable) -> void:
	_commands[name] = {"args": args, "help": help, "handler": handler}


func _cmd_help(args: PackedStringArray) -> String:
	if args.size() > 0:
		var name: String = args[0].to_lower()
		if not _commands.has(name):
			return "unknown command '%s'" % name
		return "%s %s - %s" % [name, _commands[name]["args"], _commands[name]["help"]]
	var lines: PackedStringArray = PackedStringArray()
	var names: Array = _commands.keys()
	names.sort()
	for name: String in names:
		lines.append("  %s %s" % [name, _commands[name]["args"]])
	return "commands:\n" + "\n".join(lines)


func _cmd_give(args: PackedStringArray) -> String:
	if args.is_empty():
		return "give <amount>"
	EconomyManager.currency += int(args[0])
	return "currency: %d" % EconomyManager.currency


func _cmd_wave(args: PackedStringArray) -> String:
	if args.is_empty():
		return "wave <index>"
	var target: int = clampi(int(args[0]), 1, WaveManager.waves.size())
	# start_next_wave() advances from current_index, so land one short of target.
	WaveManager.current_index = target - 2
	if not WaveManager.start_next_wave():
		return "could not start wave %d" % target
	return "started wave %d" % target


func _cmd_kill_all(_args: PackedStringArray) -> String:
	var killed: int = 0
	for node: Node in _tree().get_nodes_in_group(&"enemy"):
		var health: HealthComponent = node.get(&"health") as HealthComponent
		if health == null or health.is_dead:
			continue
		health.apply_damage(health.current_health + 1.0, _player())
		killed += 1
	return "killed %d" % killed


func _cmd_spawn(args: PackedStringArray) -> String:
	if args.is_empty():
		return "spawn <enemy_id> [count]"
	var path: String = "res://data/enemies/%s.tres" % args[0].to_lower()
	if not ResourceLoader.exists(path):
		return "no enemy data at %s" % path
	var data := load(path) as EnemyData
	var player: Node3D = _player()
	if player == null:
		return "no player in the scene"
	var count: int = int(args[1]) if args.size() > 1 else 1
	var spawned: int = 0
	for index: int in maxi(count, 1):
		var offset := Vector3(float(index % 4) * 2.0 - 3.0, 0.0, -6.0 - float(index / 4) * 2.0)
		if WaveManager.spawn_summoned(data, player.global_position + offset) != null:
			spawned += 1
	return "spawned %d %s" % [spawned, data.id]


## Tira un gadget desde arriba, como lo va a hacer el publico. Sin argumento
## elige uno de los tres al azar, que es como se ve en partida.
##
## Es la unica forma de ver caer un drop sin esperar al director: el arco, el
## aterrizaje y el levantarlo son tres cosas que solo se juzgan mirandolas.
func _cmd_drop(args: PackedStringArray) -> String:
	var player := _player() as Player
	if player == null or player.utility == null:
		return "no player in the scene"

	var slot: int = -1
	if args.is_empty():
		slot = randi() % UtilityComponent.SLOT_COUNT
	else:
		slot = player.utility.find_slot(StringName(args[0].to_lower()))
		if slot < 0:
			return "no utility slot for '%s'" % args[0]
	var data: UtilityData = player.utility.get_slot_data(slot)
	if data == null:
		return "slot %d has no utility" % (slot + 1)

	var pickup := ObjectPool.acquire(CROWD_DROP_SCENE) as CrowdDropPickup
	if pickup == null:
		return "crowd_drop_pickup.tscn is not a CrowdDropPickup"
	# Un asiento imaginario: lejos, arriba y en una direccion al azar, para que el
	# arco se parezca al que va a salir de la tribuna de verdad.
	var angle: float = randf() * TAU
	var from: Vector3 = player.global_position 		+ Vector3(cos(angle) * 22.0, 12.0, sin(angle) * 22.0)
	var landing: Vector3 = player.global_position 		+ Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
	pickup.throw_from_stands(from, CrowdDropPickup.arc_to(from, landing, 1.6), data)
	return "the crowd throws a %s" % data.display_name


func _cmd_upgrade(args: PackedStringArray) -> String:
	if args.is_empty():
		return "upgrade <upgrade_id> [stacks]"
	var path: String = "res://data/upgrades/%s.tres" % args[0].to_lower()
	if not ResourceLoader.exists(path):
		return "no upgrade at %s" % path
	var data := load(path) as UpgradeData
	var weapon_id: StringName = _equipped_weapon_id()
	if data.category == UpgradeData.Category.WEAPON and weapon_id == &"":
		return "'%s' is a weapon upgrade and no weapon is equipped" % data.id
	var granted: int = 0
	for _i: int in maxi(int(args[1]) if args.size() > 1 else 1, 1):
		if UpgradeManager.add_upgrade(data, weapon_id if data.category == UpgradeData.Category.WEAPON else &""):
			granted += 1
	return "granted %s x%d" % [data.id, granted]


func _cmd_upgrades(_args: PackedStringArray) -> String:
	var entries: Array[Dictionary] = UpgradeManager.get_owned_entries()
	if entries.is_empty():
		return "no bonuses"
	var lines: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		var data: UpgradeData = entry["data"]
		var scope: String = "" if entry["weapon_id"] == &"" else " (%s)" % entry["weapon_id"]
		lines.append("  [%s] %s x%d%s" % [
			UpgradeData.Category.keys()[data.category], data.id, entry["stacks"], scope])
	return "\n".join(lines)


func _cmd_clear_upgrades(_args: PackedStringArray) -> String:
	UpgradeManager.reset()
	return "cleared"


func _cmd_heal(args: PackedStringArray) -> String:
	var player: Node3D = _player()
	if player == null:
		return "no player in the scene"
	var health: HealthComponent = player.get(&"health") as HealthComponent
	if health == null:
		return "player has no health component"
	var amount: float = float(args[0]) if args.size() > 0 else health.max_health
	health.heal(amount)
	return "health: %0.0f/%0.0f" % [health.current_health, health.max_health]


func _cmd_god(args: PackedStringArray) -> String:
	var player: Node3D = _player()
	if player == null:
		return "no player in the scene"
	var health: HealthComponent = player.get(&"health") as HealthComponent
	if health == null:
		return "player has no health component"
	_god_mode = args[0].to_lower() == "on" if args.size() > 0 else not _god_mode
	health.is_invulnerable = _god_mode
	return "god mode %s" % ("on" if _god_mode else "off")


func _cmd_teleport(args: PackedStringArray) -> String:
	if args.size() < 3:
		return "tp <x> <y> <z>"
	var player: Node3D = _player()
	if player == null:
		return "no player in the scene"
	player.global_position = Vector3(float(args[0]), float(args[1]), float(args[2]))
	return "moved to %v" % player.global_position


func _cmd_timescale(args: PackedStringArray) -> String:
	if args.is_empty():
		return "timescale <value>"
	Engine.time_scale = clampf(float(args[0]), 0.05, 8.0)
	return "time_scale: %0.2f" % Engine.time_scale


func _cmd_balance(_args: PackedStringArray) -> String:
	if not Engine.has_singleton(&"BalanceHub") and get_node_or_null(^"/root/BalanceHub") == null:
		return "BalanceHub is not running"
	var hub: Node = get_node(^"/root/BalanceHub")
	for path: String in hub.call(&"_watched_files"):
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return "balance reloaded"


## Straight to the shop, without clearing a wave first - the between-round screen
## is where half the balance questions live.
func _cmd_shop(_args: PackedStringArray) -> String:
	var screen: Node = _tree().root.find_child("ShopScreen", true, false)
	if screen == null or not screen.has_method(&"open"):
		return "no shop screen in the scene"
	GameManager.state = GameManager.State.SHOPPING
	screen.call(&"open", WaveManager.get_last_breakdown(),
		maxi(WaveManager.current_index + 1, 1), WaveManager.get_wave_duration())
	return "shop opened"


func _cmd_stats(_args: PackedStringArray) -> String:
	return "wave %d/%d | enemies %d | currency %d | fps %d" % [
		WaveManager.current_index + 1, WaveManager.waves.size(),
		WaveManager.get_alive_count(), EconomyManager.currency,
		Engine.get_frames_per_second()]


func _cmd_clear(_args: PackedStringArray) -> String:
	_output.clear()
	return ""


func _cmd_quit(_args: PackedStringArray) -> String:
	_tree().quit()
	return "bye"


# Private: helpers

func _tree() -> SceneTree:
	return get_tree()


func _player() -> Node3D:
	return _tree().get_first_node_in_group(&"player") as Node3D


func _equipped_weapon_id() -> StringName:
	var player: Node3D = _player()
	if player == null:
		return &""
	var holder := player.get(&"weapon_holder") as WeaponHolder
	if holder == null or holder.current == null or holder.current.data == null:
		return &""
	return holder.current.data.id


# Private: UI

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.anchor_bottom = OPEN_HEIGHT
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := ColorRect.new()
	background.color = Color(Tokens.VOID, 0.92)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, Tokens.PANEL_PADDING)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Tokens.ROW_GAP)
	margin.add_child(column)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	_output.bbcode_enabled = false
	_output.add_theme_color_override("default_color", Tokens.TEXT)
	column.add_child(_output)

	_input = LineEdit.new()
	_input.placeholder_text = "type help"
	_input.caret_blink = true
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_gui_input)
	column.add_child(_input)

	log_line("MAYHEM dev console. 'help' lists commands.")


func _on_submitted(line: String) -> void:
	if line.strip_edges() == "":
		return
	log_line("> %s" % line)
	log_line(execute(line))
	_push_history(line)
	_input.clear()


## Up/Down walk the history, Tab completes the command name.
func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_UP:
			_recall(1)
		KEY_DOWN:
			_recall(-1)
		KEY_TAB:
			_complete()
		_:
			return
	_input.accept_event()


func _push_history(line: String) -> void:
	_history.insert(0, line)
	if _history.size() > HISTORY_LIMIT:
		_history.remove_at(_history.size() - 1)
	_history_index = -1


func _recall(direction: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + direction, -1, _history.size() - 1)
	_input.text = "" if _history_index < 0 else _history[_history_index]
	_input.caret_column = _input.text.length()


func _complete() -> void:
	var prefix: String = _input.text.strip_edges()
	if prefix == "":
		return
	var matches: PackedStringArray = PackedStringArray()
	for name: String in _commands.keys():
		if name.begins_with(prefix):
			matches.append(name)
	if matches.size() == 1:
		_input.text = "%s " % matches[0]
		_input.caret_column = _input.text.length()
	elif matches.size() > 1:
		matches.sort()
		log_line("  ".join(matches))
