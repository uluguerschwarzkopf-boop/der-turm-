extends Node2D

@export var damage: int = 1
@export var cooldown: float = 1.5
@export var damage_start_frame: int = 2
@export var damage_end_frame: int = 3
@export var player_group: StringName = &"player"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var damage_area: Area2D = $DamageArea

var active: bool = false
var can_trigger: bool = true
var hit_player: bool = false


func _ready() -> void:
	detection_area.body_entered.connect(_on_detection_body_entered)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)

	damage_area.monitoring = false
	damage_area.monitorable = true

	sprite.play("idle")


func _on_detection_body_entered(body: Node) -> void:
	if not body.is_in_group(player_group):
		return

	if not can_trigger:
		return

	_trigger()


func _trigger() -> void:
	can_trigger = false
	active = true
	hit_player = false
	sprite.play("attack")


func _on_frame_changed() -> void:
	if not active:
		return

	if sprite.animation != "attack":
		return

	var damage_on := sprite.frame >= damage_start_frame and sprite.frame <= damage_end_frame
	damage_area.monitoring = damage_on

	if damage_on and not hit_player:
		for body in damage_area.get_overlapping_bodies():
			if body.is_in_group(player_group):
				if body.has_method("take_damage"):
					body.take_damage(damage, global_position)
				hit_player = true
				break


func _on_animation_finished() -> void:
	if sprite.animation != "attack":
		return

	active = false
	damage_area.monitoring = false
	sprite.play("idle")

	await get_tree().create_timer(cooldown).timeout
	can_trigger = true
