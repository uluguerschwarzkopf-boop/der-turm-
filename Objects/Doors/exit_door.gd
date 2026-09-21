extends Node2D

@export var idle_animation: StringName = &"idle"
@export var exit_animation: StringName = &"Ausgangsanimation"
@export var fallback_animation_time: float = 0.8

@onready var area: Area2D = $Area2D

var already_used: bool = false


func _ready() -> void:
	if area == null:
		push_error("ExitDoor: Area2D fehlt.")
		return

	area.monitoring = true
	area.monitorable = true

	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)

	var sprite := get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(idle_animation)
	):
		sprite.play(idle_animation)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if already_used:
		return

	already_used = true

	# Nutzer-Wunsch: "Door Open"-Sound aus der Sound-Bank des Spielers
	# (siehe Player/player_sound_manager.gd), genau in dem Moment, in
	# dem der Spieler die Exit-Tür berührt und den Raum verlässt.
	var sound_manager := body.get_node_or_null("Scripts/SoundManager")

	if sound_manager != null and sound_manager.has_method("play"):
		sound_manager.play(&"Door Open")

	if area != null:
		area.set_deferred("monitoring", false)

	var room_manager := get_tree().get_first_node_in_group(
		"room_manager"
	)

	if room_manager == null:
		push_error(
			"ExitDoor: Kein RoomManager in der Gruppe 'room_manager' gefunden."
		)
		restore_door()
		return

	if not room_manager.has_method("request_room_exit"):
		push_error(
			"ExitDoor: RoomManager besitzt request_room_exit() nicht."
		)
		restore_door()
		return

	print(
		"ExitDoor ruft RoomManager auf in: ",
		get_tree().current_scene.scene_file_path
	)

	room_manager.call_deferred("request_room_exit")


func play_exit_animation() -> void:
	var sprite := get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if (
		sprite == null
		or sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(exit_animation)
	):
		await _wait_safely(fallback_animation_time)
		return

	sprite.stop()
	sprite.frame = 0
	sprite.play(exit_animation)

	await _wait_safely(fallback_animation_time)


func restore_door() -> void:
	already_used = false

	if area != null and is_instance_valid(area):
		area.set_deferred("monitoring", true)

	var sprite := get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(idle_animation)
	):
		sprite.play(idle_animation)


func _wait_safely(wait_time: float) -> void:
	if not is_inside_tree():
		return

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(wait_time, 0.001)
	).timeout
