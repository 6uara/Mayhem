class_name CoopPanel
extends Control
## Opens a coop session or joins a friend's, and shows who is in the lobby.
##
## Built as a panel on the main menu rather than a separate screen, for the same
## reason the settings screen is shared with the pause menu: one place where a
## session is set up, so there is one behaviour to get right.
##
## Rows are generated from the roster rather than authored. The lobby is one
## name deep the moment it opens and four later, and an authored list has to
## fake both states.

signal closed()

## Localhost is the default because the first thing anyone does is run two
## copies on one machine to see if it works at all.
const DEFAULT_ADDRESS: String = "127.0.0.1"

@onready var _setup: VBoxContainer = $Panel/Margin/Layout/Setup
@onready var _lobby: VBoxContainer = $Panel/Margin/Layout/Lobby
@onready var _name_edit: LineEdit = $Panel/Margin/Layout/Setup/NameRow/NameEdit
@onready var _address_edit: LineEdit = $Panel/Margin/Layout/Setup/AddressRow/AddressEdit
@onready var _host_button: Button = $Panel/Margin/Layout/Setup/Buttons/HostButton
@onready var _join_button: Button = $Panel/Margin/Layout/Setup/Buttons/JoinButton
@onready var _roster: VBoxContainer = $Panel/Margin/Layout/Lobby/Roster
@onready var _start_button: Button = $Panel/Margin/Layout/Lobby/StartButton
@onready var _leave_button: Button = $Panel/Margin/Layout/Lobby/LeaveButton
@onready var _status: Label = $Panel/Margin/Layout/Status
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_back_button.pressed.connect(close)

	NetworkManager.roster_changed.connect(_refresh)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.host_disconnected.connect(_on_host_disconnected)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	if _address_edit.text.strip_edges().is_empty():
		_address_edit.text = DEFAULT_ADDRESS
	if _name_edit.text.strip_edges().is_empty():
		_name_edit.text = "Jugador"
	_refresh()
	visible = true
	_host_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# Private

func _on_host_pressed() -> void:
	var error: Error = NetworkManager.host_session(_name_edit.text)
	if error != OK:
		_set_status("No se pudo abrir el puerto %d. Puede estar en uso."
			% NetworkManager.DEFAULT_PORT, Tokens.ENEMY)
		return
	_set_status("Partida abierta. Pasales esta direccion: %s" % _local_address(),
		Tokens.PLAYER)
	_refresh()


func _on_join_pressed() -> void:
	var address: String = _address_edit.text.strip_edges()
	if address.is_empty():
		_set_status("Escribi la direccion del host.", Tokens.ENEMY)
		return
	_set_status("Conectando a %s..." % address, Tokens.PLAYER)
	var error: Error = NetworkManager.join_session(address, _name_edit.text)
	if error != OK:
		# join_failed carries the readable reason; this only covers the case
		# where the address itself was rejected before a socket was opened.
		_refresh()


func _on_start_pressed() -> void:
	GameManager.start_coop_run()


func _on_leave_pressed() -> void:
	NetworkManager.leave_session()
	_set_status("Saliste de la partida.", Tokens.MUTED)
	_refresh()


func _on_join_failed(reason: String) -> void:
	_set_status(reason, Tokens.ENEMY)
	_refresh()


func _on_host_disconnected() -> void:
	_set_status("El host cerro la partida.", Tokens.ENEMY)
	_refresh()


## The lobby and the setup form are the same panel in two states - being in a
## session is the only thing that decides which one you see.
func _refresh() -> void:
	var online: bool = NetworkManager.is_online()
	_setup.visible = not online
	_lobby.visible = online
	if online:
		# Only the host can pull everyone into the arena; a client waits.
		_start_button.visible = NetworkManager.is_host()
		_rebuild_roster()


func _rebuild_roster() -> void:
	for child: Node in _roster.get_children():
		child.queue_free()

	for peer_id: int in NetworkManager.get_peer_ids():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var who := Label.new()
		who.theme_type_variation = &"HUDLabel"
		who.text = NetworkManager.get_player_name(peer_id)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)

		var tag := Label.new()
		tag.theme_type_variation = &"HUDLabel"
		if peer_id == NetworkManager.SERVER_ID:
			tag.text = "HOST"
			tag.add_theme_color_override("font_color", Tokens.PLAYER)
		elif peer_id == NetworkManager.local_id():
			tag.text = "VOS"
			tag.add_theme_color_override("font_color", Tokens.REWARD)
		row.add_child(tag)

		_roster.add_child(row)

	var free_slots: int = NetworkManager.MAX_PLAYERS - NetworkManager.get_peer_ids().size()
	for _i: int in free_slots:
		var empty := Label.new()
		empty.theme_type_variation = &"HUDLabel"
		empty.text = "- libre -"
		empty.add_theme_color_override("font_color", Tokens.MUTED)
		_roster.add_child(empty)


func _set_status(message: String, color: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", color)


## The address a friend on the same network types in. Loopback is filtered out
## because "127.0.0.1" is exactly the one address that cannot work for them.
func _local_address() -> String:
	for address: String in IP.get_local_addresses():
		if address.begins_with("127.") or address.contains(":"):
			continue
		return address
	return DEFAULT_ADDRESS
