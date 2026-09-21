extends Area2D

@export var speed: float = 150.0
@export var damage: int = 1
@export var lifetime: float = 4.0
@export var player_group: StringName = &"player"

@export var anim_spawn: StringName = &"Spawn"
@export var anim_fly: StringName = &"Fly"
@export var anim_hit: StringName = &"Hit"

@export var sprite_points_right: bool = true

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var target: Node2D = null
var direction: Vector2 = Vector2.LEFT
var active: bool = false
var dying: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite.animation_finished.connect(_on_animation_finished)

	monitoring = true
	monitorable = true

	sprite.play(anim_spawn)

	await get_tree().create_timer(lifetime).timeout

	if is_instance_valid(self):
		queue_free()


func setup(new_target: Node2D, new_damage: int) -> void:
	target = new_target
	damage = new_damage


func _physics_process(delta: float) -> void:
	if not active:
		return

	if dying:
		return

	global_position += direction * speed * delta


func _on_animation_finished() -> void:
	if sprite.animation == anim_spawn:
		if target != null and is_instance_valid(target):
			direction = (target.global_position - global_position).normalized()

		if direction != Vector2.ZERO:
			if sprite_points_right:
				rotation = direction.angle()
			else:
				rotation = direction.angle() + PI

		active = true
		sprite.play(anim_fly)
		return

	if sprite.animation == anim_hit:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if dying:
		return

	if body.is_in_group(player_group):
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position)

	_die()


func _die() -> void:
	dying = true
	active = false
	monitoring = false
	sprite.play(anim_hit)
