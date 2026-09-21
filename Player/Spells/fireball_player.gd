extends Area2D


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export_group("Fireball")

@export var speed: float = 220.0
@export var damage: int = 1
@export var lifetime: float = 4.0


@export_group("Treffer")

@export var enemy_group: StringName = &"enemy"

# Wenn aktiviert, verschwindet der Feuerball beim Kontakt
# mit Wänden, Böden und anderen PhysicsBody2D-Nodes.
@export var destroy_on_world_collision: bool = true


@export_group("Animationen")

@export var anim_spawn: StringName = &"Spawn"
@export var anim_fly: StringName = &"Fly"
@export var anim_hit: StringName = &"Hit"

@export var sprite_points_right: bool = true


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var collision_shape: CollisionShape2D = (
	$CollisionShape2D
)


# ============================================================
# STATUS
# ============================================================

var direction: Vector2 = Vector2.RIGHT

var active: bool = false
var dying: bool = false

var owner_player: Node = null


# ============================================================
# START
# ============================================================

func _ready() -> void:
	if not body_entered.is_connected(
		_on_body_entered
	):
		body_entered.connect(
			_on_body_entered
		)

	if not sprite.animation_finished.is_connected(
		_on_animation_finished
	):
		sprite.animation_finished.connect(
			_on_animation_finished
		)

	monitoring = true
	monitorable = true

	if collision_shape != null:
		collision_shape.disabled = false

	_play_spawn_animation()
	_start_lifetime_timer()


# ============================================================
# EINRICHTUNG DURCH SPELLMANAGER
# ============================================================

func setup(
	new_direction: Vector2,
	new_owner: Node = null
) -> void:
	owner_player = new_owner

	if new_direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	else:
		direction = new_direction.normalized()

	_update_visual_direction()


# ============================================================
# BEWEGUNG
# ============================================================

func _physics_process(delta: float) -> void:
	if not active:
		return

	if dying:
		return

	global_position += direction * speed * delta


# ============================================================
# ANIMATIONEN
# ============================================================

func _play_spawn_animation() -> void:
	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			anim_spawn
		)
	):
		sprite.play(anim_spawn)
		return

	_start_flying()


func _start_flying() -> void:
	if dying:
		return

	active = true

	_update_visual_direction()

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			anim_fly
		)
	):
		sprite.play(anim_fly)


func _on_animation_finished() -> void:
	if dying:
		if sprite.animation == anim_hit:
			queue_free()

		return

	if sprite.animation == anim_spawn:
		_start_flying()


func _update_visual_direction() -> void:
	if direction == Vector2.ZERO:
		return

	if sprite_points_right:
		rotation = direction.angle()
	else:
		rotation = direction.angle() + PI


# ============================================================
# TREFFER
# ============================================================

func _on_body_entered(body: Node) -> void:
	if dying:
		return

	if body == owner_player:
		return

	# Gegner werden nur über ihren echten CharacterBody2D
	# getroffen, nicht über WakeArea oder AttackHitbox.
	if body.is_in_group(enemy_group):
		_damage_enemy(body)
		_die()
		return

	# Wände, Boden und andere feste Körper.
	if destroy_on_world_collision:
		_die()


func _damage_enemy(enemy: Node) -> void:
	if enemy == null:
		return

	if not is_instance_valid(enemy):
		return

	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)


# ============================================================
# ZERSTÖRUNG
# ============================================================

func _die() -> void:
	if dying:
		return

	dying = true
	active = false

	monitoring = false
	monitorable = false

	if collision_shape != null:
		collision_shape.set_deferred(
			"disabled",
			true
		)

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			anim_hit
		)
	):
		sprite.play(anim_hit)
		return

	queue_free()


func _start_lifetime_timer() -> void:
	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(lifetime, 0.05)
	).timeout

	if is_instance_valid(self):
		queue_free()
