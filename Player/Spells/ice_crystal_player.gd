extends Area2D


# ============================================================
# SIGNALE
# ============================================================

signal crystal_finished


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

# Schaden dieses Kristalls.
@export var damage: int = 1

# Gruppe aller Gegner, Bosse und Minibosse.
@export var enemy_group: StringName = &"enemy"

# Ein Gegner kann von einem Kristall nur einmal getroffen werden.
@export var one_hit_per_enemy: bool = true


# ============================================================
# ZEITEN
# ============================================================

@export_group("Zeiten")

# So lange bleibt der ausgewachsene Kristall stehen.
@export var active_time: float = 0.45

# Sicherheitsdauer, falls eine Animation nicht korrekt endet.
@export var maximum_lifetime: float = 3.0


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var spawn_animation: StringName = &"Spawn"
@export var active_animation: StringName = &"Active"
@export var break_animation: StringName = &"Break"


# ============================================================
# HITBOX
# ============================================================

@export_group("Hitbox")

# Ab diesem Spawn-Frame wird die Hitbox aktiviert.
# Godot zählt ab Frame 0.
@export_range(0, 100, 1)
var hitbox_activation_frame: int = 1


# ============================================================
# EINFRIEREN
# ============================================================

@export_group("Einfrieren")

# Hier enemy_spell_effects.gd hineinziehen.
@export var enemy_spell_effects_script: Script


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
)

@onready var collision_polygon: CollisionPolygon2D = (
	get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
)


# ============================================================
# STATUS
# ============================================================

var owner_player: Node = null

var breaking: bool = false
var hitbox_active: bool = false
var finished: bool = false

var already_hit_enemy_ids: Array[int] = []


# ============================================================
# START
# ============================================================

func _ready() -> void:
	monitoring = true
	monitorable = true

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if sprite != null:
		if not sprite.animation_finished.is_connected(
			_on_animation_finished
		):
			sprite.animation_finished.connect(
				_on_animation_finished
			)

	_disable_hitbox()
	_start_lifetime_timer()
	_play_spawn_animation()


# ============================================================
# SETUP DURCH DIE EISWELLE
# ============================================================

func setup(
	new_owner_player: Node,
	new_damage: int
) -> void:
	owner_player = new_owner_player
	damage = max(new_damage, 0)


# ============================================================
# ABLAUF
# ============================================================

func _physics_process(_delta: float) -> void:
	if breaking or finished:
		return

	if sprite == null:
		return

	if sprite.animation != spawn_animation:
		return

	if (
		not hitbox_active
		and sprite.frame >= hitbox_activation_frame
	):
		_enable_hitbox()


func _play_spawn_animation() -> void:
	if sprite == null:
		_enable_hitbox()
		_start_active_phase()
		return

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			spawn_animation
		)
	):
		sprite.play(spawn_animation)
		return

	_enable_hitbox()
	_start_active_phase()


func _start_active_phase() -> void:
	if breaking or finished:
		return

	_enable_hitbox()

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			active_animation
		)
	):
		sprite.play(active_animation)

	var tree := get_tree()

	if tree == null:
		_finish_crystal()
		return

	await tree.create_timer(
		max(active_time, 0.01)
	).timeout

	if not is_inside_tree():
		return

	if breaking or finished:
		return

	_start_break()


func _start_break() -> void:
	if breaking or finished:
		return

	breaking = true
	_disable_hitbox()

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			break_animation
		)
	):
		sprite.play(break_animation)
		return

	_finish_crystal()


func _on_animation_finished() -> void:
	if sprite == null:
		return

	if sprite.animation == spawn_animation:
		_start_active_phase()
		return

	if sprite.animation == break_animation:
		_finish_crystal()


func _finish_crystal() -> void:
	if finished:
		return

	finished = true
	breaking = true

	_disable_hitbox()

	crystal_finished.emit()
	queue_free()


# ============================================================
# TREFFER
# ============================================================

func _on_body_entered(body: Node) -> void:
	if breaking or finished:
		return

	if not hitbox_active:
		return

	if body == null:
		return

	if body == owner_player:
		return

	if not body.is_in_group(enemy_group):
		return

	var enemy_id: int = body.get_instance_id()

	if (
		one_hit_per_enemy
		and already_hit_enemy_ids.has(enemy_id)
	):
		return

	already_hit_enemy_ids.append(enemy_id)

	if body.has_method("take_damage"):
		body.take_damage(damage)

	if is_instance_valid(body):
		_apply_freeze_to_enemy(body)


# ============================================================
# EINFRIEREN
# ============================================================

func _apply_freeze_to_enemy(enemy: Node) -> void:
	var effects: Node = enemy.get_node_or_null(
		"enemy_spell_effects"
	)

	if effects == null:
		if enemy_spell_effects_script == null:
			push_warning(
				"IceCrystal: EnemySpellEffects-Script fehlt im Inspector."
			)
			return

		effects = Node.new()
		effects.name = "enemy_spell_effects"
		effects.set_script(enemy_spell_effects_script)

		enemy.add_child(effects)

	if not effects.has_method("apply_freeze"):
		return

	var config: Node = _get_player_spell_effects()

	var freeze_duration: float = 2.5
	var slow_multiplier: float = 0.35

	if config != null:
		freeze_duration = config.freeze_duration
		slow_multiplier = config.freeze_slow_multiplier

	effects.apply_freeze(
		freeze_duration,
		slow_multiplier
	)

	_spawn_ice_particles(enemy)


func _get_player_spell_effects() -> Node:
	if owner_player == null or not is_instance_valid(owner_player):
		return null

	return owner_player.get_node_or_null(
		"Scripts/PlayerSpellEffects"
	)


func _spawn_ice_particles(enemy: Node) -> void:
	if not enemy is Node2D:
		return

	var particles: Node = _get_player_spell_particles()

	if particles == null or not particles.has_method("spawn_ice_particles"):
		return

	particles.spawn_ice_particles(enemy as Node2D)


func _get_player_spell_particles() -> Node:
	if owner_player == null or not is_instance_valid(owner_player):
		return null

	return owner_player.get_node_or_null(
		"Scripts/PlayerSpellParticles"
	)


# ============================================================
# HITBOX
# ============================================================

func _enable_hitbox() -> void:
	if hitbox_active:
		return

	hitbox_active = true

	if collision_polygon != null:
		collision_polygon.set_deferred(
			"disabled",
			false
		)


func _disable_hitbox() -> void:
	hitbox_active = false

	if collision_polygon != null:
		collision_polygon.set_deferred(
			"disabled",
			true
		)


# ============================================================
# SICHERHEITSTIMER
# ============================================================

func _start_lifetime_timer() -> void:
	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(maximum_lifetime, 0.1)
	).timeout

	if is_instance_valid(self):
		_finish_crystal()
