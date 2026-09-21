extends Area2D

@export var damage: int = 1
@export var player_group: StringName = &"player"

@export var anim_name: StringName = &"FirePillar"

@export var damage_start_frame: int = 8
@export var damage_end_frame: int = 13

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var hit_done: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)

	monitoring = true
	monitorable = true

	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)


func setup(new_damage: int) -> void:
	damage = new_damage


func _on_frame_changed() -> void:
	var f: int = sprite.frame

	if f < damage_start_frame:
		return

	if f > damage_end_frame:
		return

	if hit_done:
		return

	for body in get_overlapping_bodies():
		if body.is_in_group(player_group):
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position)

			hit_done = true
			return


func _on_body_entered(body: Node) -> void:
	if hit_done:
		return

	var f: int = sprite.frame

	if f < damage_start_frame or f > damage_end_frame:
		return

	if body.is_in_group(player_group):
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position)

		hit_done = true


func _on_animation_finished() -> void:
	queue_free()
