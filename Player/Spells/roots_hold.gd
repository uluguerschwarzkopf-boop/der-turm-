extends Node2D


# ============================================================
# ZEITEN
# ============================================================

@export_group("Zeiten")

# Wie lange die Ranken nach der Grow-Animation stehen bleiben.
@export var hold_duration: float = 2.0

# Sicherheitszeit, falls eine Animation falsch eingestellt ist.
@export var maximum_lifetime: float = 6.0


# ============================================================
# POSITION
# ============================================================

@export_group("Position")

# Wenn aktiviert, folgt die Animation horizontal dem Gegner.
@export var follow_enemy_x: bool = true

# Wenn aktiviert, folgt sie auch vertikal.
# Für Bodenranken normalerweise ausgeschaltet lassen.
@export var follow_enemy_y: bool = false

# Zusätzlicher Versatz zum Gegner.
@export var follow_offset: Vector2 = Vector2.ZERO


# ============================================================
# DARSTELLUNG
# ============================================================

@export_group("Darstellung")

# Die Ranken können leicht transparent dargestellt werden,
# damit der Gegner weiterhin sichtbar bleibt.
@export_range(0.0, 1.0, 0.01)
var effect_opacity: float = 0.88


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var grow_animation: StringName = &"Grow"
@export var hold_animation: StringName = &"Hold"
@export var disappear_animation: StringName = &"Disappear"


# ============================================================
# FESTHALTEN
# ============================================================

@export_group("Festhalten")

# Hier enemy_spell_effects.gd hineinziehen.
@export var enemy_spell_effects_script: Script


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
)

@onready var collision_shape: CollisionShape2D = (
	get_node_or_null("CollisionShape2D") as CollisionShape2D
)


# ============================================================
# STATUS
# ============================================================

var target_enemy: Node2D = null
var owner_player: Node = null

var disappearing: bool = false
var finished: bool = false
var sequence_started: bool = false


# ============================================================
# START
# ============================================================

func _ready() -> void:
	if sprite != null:
		sprite.modulate.a = effect_opacity

		if not sprite.animation_finished.is_connected(
			_on_animation_finished
		):
			sprite.animation_finished.connect(
				_on_animation_finished
			)

	# Die Hold-Szene verursacht vorerst keinen eigenen Schaden.
	if collision_shape != null:
		collision_shape.disabled = true

	_start_lifetime_timer()

	# setup() wird normalerweise direkt nach dem Erzeugen
	# aufgerufen. Wir starten sicherheitshalber verzögert.
	call_deferred("_start_sequence")


# ============================================================
# SETUP
# ============================================================

func setup(
	enemy: Node,
	new_owner_player: Node = null
) -> void:
	if enemy is Node2D:
		target_enemy = enemy as Node2D

	owner_player = new_owner_player

	_apply_root_to_enemy()


# ============================================================
# ZIEL FOLGEN
# ============================================================

func _process(_delta: float) -> void:
	if finished:
		return

	if target_enemy == null:
		return

	if not is_instance_valid(target_enemy):
		_start_disappear()
		return

	if follow_enemy_x:
		global_position.x = (
			target_enemy.global_position.x
			+ follow_offset.x
		)

	if follow_enemy_y:
		global_position.y = (
			target_enemy.global_position.y
			+ follow_offset.y
		)


# ============================================================
# ANIMATIONSABLAUF
# ============================================================

func _start_sequence() -> void:
	if sequence_started or finished:
		return

	sequence_started = true

	if sprite == null:
		_start_hold_phase()
		return

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			grow_animation
		)
	):
		sprite.play(grow_animation)
		return

	_start_hold_phase()


func _start_hold_phase() -> void:
	if finished or disappearing:
		return

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			hold_animation
		)
	):
		sprite.play(hold_animation)

	var tree := get_tree()

	if tree == null:
		_finish()
		return

	await tree.create_timer(
		max(hold_duration, 0.01)
	).timeout

	if not is_inside_tree():
		return

	if finished or disappearing:
		return

	_start_disappear()


func _start_disappear() -> void:
	if disappearing or finished:
		return

	disappearing = true

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			disappear_animation
		)
	):
		sprite.play(disappear_animation)
		return

	_finish()


func _on_animation_finished() -> void:
	if sprite == null:
		return

	if sprite.animation == grow_animation:
		_start_hold_phase()
		return

	if sprite.animation == disappear_animation:
		_finish()


func _finish() -> void:
	if finished:
		return

	finished = true
	disappearing = true

	_cancel_root_on_enemy()

	queue_free()


# ============================================================
# FESTHALTEN
# ============================================================

func _apply_root_to_enemy() -> void:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return

	var effects: Node = target_enemy.get_node_or_null(
		"enemy_spell_effects"
	)

	if effects == null:
		if enemy_spell_effects_script == null:
			push_warning(
				"RootsHold: EnemySpellEffects-Script fehlt im Inspector."
			)
			return

		effects = Node.new()
		effects.name = "enemy_spell_effects"
		effects.set_script(enemy_spell_effects_script)

		target_enemy.add_child(effects)

	if not effects.has_method("apply_root"):
		return

	var safety_duration: float = 4.0
	var config: Node = _get_player_spell_effects()

	if config != null:
		safety_duration = config.root_safety_duration

	effects.apply_root(safety_duration)


func _cancel_root_on_enemy() -> void:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return

	var effects: Node = target_enemy.get_node_or_null(
		"enemy_spell_effects"
	)

	if effects != null and effects.has_method("cancel_root"):
		effects.cancel_root()


func _get_player_spell_effects() -> Node:
	if owner_player == null or not is_instance_valid(owner_player):
		return null

	return owner_player.get_node_or_null(
		"Scripts/PlayerSpellEffects"
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
		_finish()
