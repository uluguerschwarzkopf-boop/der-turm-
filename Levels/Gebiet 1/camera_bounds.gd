extends Node2D

@export_group("Player Camera")
@export var player_group: StringName = &"player"
@export var keep_player_camera_active: bool = true

@export_group("Camera Limits")
@export var enable_limits: bool = true
@export var limit_margin_left: int = 0
@export var limit_margin_right: int = 0
@export var limit_margin_top: int = 0
@export var limit_margin_bottom: int = 0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var player: Node2D = null
var player_camera: Camera2D = null
var limits_applied: bool = false


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_find_player_camera()

	if player_camera == null:
		push_error("CameraBounds: Player-Camera2D wurde nicht gefunden.")
		return

	_activate_player_camera()
	_apply_camera_limits()


func _process(_delta: float) -> void:
	if not keep_player_camera_active:
		return

	if player_camera == null or not is_instance_valid(player_camera):
		_find_player_camera()

		if player_camera == null:
			return

		limits_applied = false

	if not player_camera.enabled:
		player_camera.enabled = true

	var active_camera: Camera2D = get_viewport().get_camera_2d()

	if active_camera != player_camera:
		player_camera.make_current()

	if not limits_applied:
		_apply_camera_limits()


func _find_player_camera() -> void:
	player = get_tree().get_first_node_in_group(player_group) as Node2D

	if player == null:
		push_error(
			"CameraBounds: Kein Player in der Gruppe '" +
			str(player_group) +
			"' gefunden."
		)
		return

	# Dein Szenenbaum:
	# Player
	# └── Camera2D
	player_camera = player.get_node_or_null("Camera2D") as Camera2D

	if player_camera == null:
		push_error(
			"CameraBounds: Die Node 'Player/Camera2D' wurde nicht gefunden."
		)


func _activate_player_camera() -> void:
	if player_camera == null:
		return

	player_camera.enabled = true
	player_camera.make_current()
	player_camera.reset_smoothing()

	print(
		"CameraBounds: Aktive Player-Kamera = ",
		player_camera.get_path()
	)

	print(
		"CameraBounds: Zoom der Player-Kamera = ",
		player_camera.zoom
	)


func _apply_camera_limits() -> void:
	if player_camera == null:
		return

	if not enable_limits:
		player_camera.limit_enabled = false
		player_camera.reset_smoothing()
		limits_applied = true
		return

	if collision_shape == null:
		push_error("CameraBounds: CollisionShape2D fehlt.")
		return

	var rectangle: RectangleShape2D = (
		collision_shape.shape as RectangleShape2D
	)

	if rectangle == null:
		push_error(
			"CameraBounds: CollisionShape2D braucht eine RectangleShape2D."
		)
		return

	var center: Vector2 = collision_shape.global_position

	var size: Vector2 = Vector2(
		rectangle.size.x * abs(collision_shape.global_scale.x),
		rectangle.size.y * abs(collision_shape.global_scale.y)
	)

	var half_size: Vector2 = size / 2.0

	player_camera.limit_left = roundi(
		center.x - half_size.x + limit_margin_left
	)

	player_camera.limit_right = roundi(
		center.x + half_size.x - limit_margin_right
	)

	player_camera.limit_top = roundi(
		center.y - half_size.y + limit_margin_top
	)

	player_camera.limit_bottom = roundi(
		center.y + half_size.y - limit_margin_bottom
	)

	player_camera.limit_enabled = true
	player_camera.reset_smoothing()

	limits_applied = true

	print(
		"CameraBounds: Limits gesetzt | Links: ",
		player_camera.limit_left,
		" | Rechts: ",
		player_camera.limit_right,
		" | Oben: ",
		player_camera.limit_top,
		" | Unten: ",
		player_camera.limit_bottom
	)


func reapply_camera_bounds() -> void:
	limits_applied = false

	_find_player_camera()

	if player_camera == null:
		return

	_activate_player_camera()
	_apply_camera_limits()
