extends CanvasLayer

signal cutscene_finished

@export var player_group: StringName = &"player"
@export var hud_group: StringName = &"hud"
@export var boss_bar_group: StringName = &"boss_bar"

@export var hide_player_during_cutscene: bool = true
@export var hide_hud_during_cutscene: bool = true
@export var hide_boss_bar_during_cutscene: bool = true
@export var show_ui_after_cutscene: bool = false

@export var camera_move_time: float = 0.65
@export var camera_return_time: float = 0.45
@export var zoom_margin: float = 1.15
@export var min_zoom: float = 1.0
@export var max_zoom: float = 3.0

@export var bar_height: float = 40.0
@export var bar_time: float = 0.35
@export var wait_after_death: float = 0.8

@onready var top_bar: ColorRect = $TopBar
@onready var bottom_bar: ColorRect = $BottomBar
@onready var cutscene_frame: CollisionShape2D = $"../CutsceneFrame/CollisionShape2D"

var camera: Camera2D = null
var old_camera_position: Vector2
var old_camera_zoom: Vector2
var old_camera_smoothing: bool = false
var player: Node = null


func _ready() -> void:
	_setup_bars()


func play_death_cutscene(boss: Node2D) -> void:
	_hide_cutscene_ui()

	player = get_tree().get_first_node_in_group(player_group)

	if player != null:
		if player.has_method("lock_control"):
			player.lock_control()

		if hide_player_during_cutscene:
			player.visible = false

	camera = get_viewport().get_camera_2d()

	if camera != null:
		old_camera_position = camera.global_position
		old_camera_zoom = camera.zoom
		old_camera_smoothing = camera.position_smoothing_enabled

		camera.position_smoothing_enabled = false

		var target_pos: Vector2 = _get_frame_center()
		var target_zoom: Vector2 = _get_frame_zoom()

		var cam_tween := create_tween()
		cam_tween.tween_property(camera, "global_position", target_pos, camera_move_time)
		cam_tween.parallel().tween_property(camera, "zoom", target_zoom, camera_move_time)

	_start_bars()

	await get_tree().create_timer(camera_move_time).timeout
	await _wait_for_boss_death_animation(boss)
	await get_tree().create_timer(wait_after_death).timeout

	await _return_camera()
	await _hide_bars()

	if player != null:
		if hide_player_during_cutscene:
			player.visible = true

		if player.has_method("unlock_control"):
			player.unlock_control()

	if show_ui_after_cutscene:
		_show_cutscene_ui()

	cutscene_finished.emit()


func _hide_cutscene_ui() -> void:
	if hide_hud_during_cutscene:
		for hud in get_tree().get_nodes_in_group(hud_group):
			if hud.has_method("hide_for_cutscene"):
				hud.hide_for_cutscene()
			else:
				hud.visible = false

	if hide_boss_bar_during_cutscene:
		for boss_bar in get_tree().get_nodes_in_group(boss_bar_group):
			boss_bar.visible = false


func _show_cutscene_ui() -> void:
	for hud in get_tree().get_nodes_in_group(hud_group):
		if hud.has_method("show_after_cutscene"):
			hud.show_after_cutscene()
		else:
			hud.visible = true

	for boss_bar in get_tree().get_nodes_in_group(boss_bar_group):
		boss_bar.visible = true


func _get_frame_center() -> Vector2:
	if cutscene_frame == null:
		return Vector2.ZERO

	return cutscene_frame.global_position


func _get_frame_zoom() -> Vector2:
	if cutscene_frame == null or cutscene_frame.shape == null:
		return Vector2(1.5, 1.5)

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var frame_size: Vector2 = Vector2(160, 120)

	if cutscene_frame.shape is RectangleShape2D:
		frame_size = (cutscene_frame.shape as RectangleShape2D).size

	frame_size *= zoom_margin

	var zoom_x: float = screen_size.x / frame_size.x
	var zoom_y: float = screen_size.y / frame_size.y
	var zoom_value: float = min(zoom_x, zoom_y)

	zoom_value = clamp(zoom_value, min_zoom, max_zoom)

	return Vector2(zoom_value, zoom_value)


func _wait_for_boss_death_animation(boss: Node2D) -> void:
	if boss == null:
		return

	var sprite := boss.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	if sprite == null:
		return

	if sprite.is_playing():
		await sprite.animation_finished


func _setup_bars() -> void:
	if top_bar == null or bottom_bar == null:
		return

	var screen_size := get_viewport().get_visible_rect().size

	top_bar.visible = false
	bottom_bar.visible = false

	top_bar.color = Color.BLACK
	bottom_bar.color = Color.BLACK

	top_bar.size = Vector2(screen_size.x, bar_height)
	bottom_bar.size = Vector2(screen_size.x, bar_height)

	top_bar.position = Vector2(0, -bar_height)
	bottom_bar.position = Vector2(0, screen_size.y)


func _start_bars() -> void:
	if top_bar == null or bottom_bar == null:
		return

	var screen_size := get_viewport().get_visible_rect().size

	top_bar.visible = true
	bottom_bar.visible = true

	top_bar.size = Vector2(screen_size.x, bar_height)
	bottom_bar.size = Vector2(screen_size.x, bar_height)

	var tween := create_tween()
	tween.tween_property(top_bar, "position:y", 0.0, bar_time)
	tween.parallel().tween_property(bottom_bar, "position:y", screen_size.y - bar_height, bar_time)


func _hide_bars() -> void:
	if top_bar == null or bottom_bar == null:
		return

	var screen_size := get_viewport().get_visible_rect().size

	var tween := create_tween()
	tween.tween_property(top_bar, "position:y", -bar_height, bar_time)
	tween.parallel().tween_property(bottom_bar, "position:y", screen_size.y, bar_time)

	await tween.finished

	top_bar.visible = false
	bottom_bar.visible = false


func _return_camera() -> void:
	if camera == null:
		return

	var tween := create_tween()
	tween.tween_property(camera, "global_position", old_camera_position, camera_return_time)
	tween.parallel().tween_property(camera, "zoom", old_camera_zoom, camera_return_time)

	await tween.finished

	camera.position_smoothing_enabled = old_camera_smoothing
