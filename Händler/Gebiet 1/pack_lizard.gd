extends Node2D

@export var sleep_animation: StringName = &"Idle_Sleep"
@export var wake_animation: StringName = &"Wake_Look"
@export var sleep_loops_before_wake: int = 5

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var sleep_count: int = 0


func _ready() -> void:
	if sprite.sprite_frames == null:
		return

	if sprite.sprite_frames.has_animation(sleep_animation):
		sprite.sprite_frames.set_animation_loop(sleep_animation, false)

	if sprite.sprite_frames.has_animation(wake_animation):
		sprite.sprite_frames.set_animation_loop(wake_animation, false)

	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)

	sleep_count = 0
	sprite.play(sleep_animation)


func _on_animation_finished() -> void:
	if sprite.animation == sleep_animation:
		sleep_count += 1

		if sleep_count >= sleep_loops_before_wake:
			sleep_count = 0
			sprite.play(wake_animation)
		else:
			sprite.play(sleep_animation)

	elif sprite.animation == wake_animation:
		sprite.play(sleep_animation)
