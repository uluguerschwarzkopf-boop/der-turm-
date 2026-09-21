extends Area2D


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export_group("Blitz")

@export var speed: float = 600.0
@export var damage: int = 1
@export var lifetime: float = 2.0

@export_group("Treffer")

@export var enemy_group: StringName = &"enemy"

@export_range(1, 20, 1)
var maximum_enemy_hits: int = 1

@export var destroy_on_world_collision: bool = true

@export_group("Animationen")

@export var anim_spawn: StringName = &"Spawn"
@export var anim_fly: StringName = &"Fly"
@export var anim_hit: StringName = &"Hit"

# Dein Blitz ist nach LINKS gepixelt.
# Deshalb muss dieser Wert im Inspector AUS sein.
@export var sprite_points_right: bool = false


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# ============================================================
# STATUS
# ============================================================

var direction: Vector2 = Vector2.RIGHT

var active: bool = false
var dying: bool = false

var owner_player: Node = null

var enemy_hits: int = 0
var already_hit_enemies: Array[int] = []


# ============================================================
# START
# ============================================================

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

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
# SETUP
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
	if not active or dying:
		return

	global_position += direction * speed * delta


# ============================================================
# ANIMATIONEN
# ============================================================

func _play_spawn_animation() -> void:
	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_spawn)
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
		and sprite.sprite_frames.has_animation(anim_fly)
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

	# Die Animation ist nach links gepixelt.
	if sprite_points_right:
		sprite.rotation = direction.angle()
	else:
		sprite.rotation = direction.angle() + PI


# ============================================================
# TREFFER
# ============================================================

func _on_body_entered(body: Node) -> void:
	if dying:
		return

	if body == owner_player:
		return

	if body.is_in_group(enemy_group):
		_hit_enemy(body)
		return

	if destroy_on_world_collision:
		_die()


func _hit_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	var enemy_id: int = enemy.get_instance_id()

	if already_hit_enemies.has(enemy_id):
		return

	already_hit_enemies.append(enemy_id)

	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	# Bewusst KEIN Extra-Effekt (kein Paralyse-Tint, keine
	# pausierte Animation etc.) - der Blitz soll sich beim Treffer
	# genau wie der Feuerball verhalten: nur Schaden, sonst nichts.

	enemy_hits += 1

	if enemy_hits >= maximum_enemy_hits:
		_die()


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
		and sprite.sprite_frames.has_animation(anim_hit)
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
