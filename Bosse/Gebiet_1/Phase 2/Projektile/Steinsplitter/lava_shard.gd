extends Area2D

@export var speed: float = 260.0
@export var damage: int = 1
@export var lifetime: float = 3.0
@export var player_group: StringName = &"player"

@export var anim_fly: StringName = &"loop"
@export var anim_hit: StringName = &"impact"

@export var sprite_points_right: bool = true

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var direction: Vector2 = Vector2.RIGHT
var active: bool = false
var dying: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	monitoring = true
	monitorable = true

	if sprite != null:
		sprite.animation_finished.connect(_on_animation_finished)

		if sprite.sprite_frames.has_animation(anim_fly):
			sprite.play(anim_fly)

	active = true

	await get_tree().create_timer(lifetime).timeout

	if is_instance_valid(self):
		queue_free()


func setup(new_direction: Vector2, new_damage: int = -1, new_speed: float = -1.0) -> void:
	direction = new_direction.normalized()

	if new_damage >= 0:
		damage = new_damage

	if new_speed > 0:
		speed = new_speed

	if direction != Vector2.ZERO:
		if sprite_points_right:
			rotation = direction.angle()
		else:
			rotation = direction.angle() + PI


func _physics_process(delta: float) -> void:
	if not active:
		return

	if dying:
		return

	global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if dying:
		return

	if body.is_in_group(player_group):
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position)

	_die()
	return


func _die() -> void:
	dying = true
	active = false
	monitoring = false

	if sprite != null and sprite.sprite_frames.has_animation(anim_hit):
		sprite.play(anim_hit)
	else:
		queue_free()


func _on_animation_finished() -> void:
	if sprite.animation == anim_hit:
		queue_free()
