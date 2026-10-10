extends Node2D

@export var idle_animation: StringName = &"idle"
@export var entry_animation: StringName = &"Eintrittsanimation"
@export var fallback_animation_time: float = 0.8

func _ready() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(idle_animation):
		sprite.play(idle_animation)


func get_spawn_position() -> Vector2:
	var marker := get_node_or_null("Marker2D") as Marker2D

	if marker == null:
		return global_position

	return marker.global_position


func play_entry_animation() -> void:
	# Nutzer-Wunsch: "Door Close"-Sound aus der Sound-Bank des Spielers
	# (siehe Player/player_sound_manager.gd), genau in dem Moment, in
	# dem die Tür beim Betreten eines Raums hinter dem Spieler zugeht -
	# wird von Levels/room_manager.gd -> _enter_at_normal_spawn() bei
	# JEDEM normalen Raumeintritt über eine SpawnDoor aufgerufen, ganz
	# unabhängig davon, ob diese Tür überhaupt eine Animation hat.
	_play_door_close_sound()

	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	if sprite == null:
		await get_tree().create_timer(fallback_animation_time).timeout
		return

	if sprite.sprite_frames == null:
		await get_tree().create_timer(fallback_animation_time).timeout
		return

	if not sprite.sprite_frames.has_animation(entry_animation):
		await get_tree().create_timer(fallback_animation_time).timeout
		return

	sprite.stop()
	sprite.frame = 0
	sprite.play(entry_animation)

	await get_tree().create_timer(fallback_animation_time).timeout

	if sprite.sprite_frames.has_animation(idle_animation):
		sprite.play(idle_animation)


# Sucht den Spieler und dessen SoundManager (siehe Player/player.tscn ->
# Scripts/SoundManager) und spielt darüber "Door Close" ab - tut bewusst
# nichts (kein Fehler), falls Spieler/SoundManager gerade fehlen oder es
# noch keinen "Door Close"-Eintrag in der Sound Bank gibt.
func _play_door_close_sound() -> void:
	var player := get_tree().get_first_node_in_group(&"player")

	if player == null:
		return

	var sound_manager := player.get_node_or_null("Scripts/SoundManager")

	if sound_manager != null and sound_manager.has_method("play"):
		sound_manager.play(&"Door Close")
