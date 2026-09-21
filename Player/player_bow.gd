extends Node

signal bow_changed(unlocked: bool)
signal arrows_changed(current_arrows: int, max_arrows: int)
signal cooldown_changed(time_left: float, active: bool)

@export var max_arrows: int = 99
@export var start_arrows: int = 0

@export var shoot_cooldown: float = 10.0
@export var shoot_anim: StringName = &"bow_shoot"
@export var shoot_spawn_frame: int = 11

@export var arrow_scene: PackedScene

var bow_unlocked: bool = false
var current_arrows: int = 0
var cooldown_left: float = 0.0
var shooting: bool = false

var player: CharacterBody2D
var sprite: AnimatedSprite2D
var arrow_spawn: Marker2D


func _ready() -> void:
	player = get_parent().get_parent() as CharacterBody2D
	sprite = player.get_node_or_null("AnimatedSprite2D")
	arrow_spawn = player.get_node_or_null("ArrowSpawn")

	if get_node_or_null("/root/RunState") != null:
		bow_unlocked = RunState.bow_unlocked
		current_arrows = RunState.current_arrows
	else:
		current_arrows = clamp(start_arrows, 0, max_arrows)

	bow_changed.emit(bow_unlocked)
	arrows_changed.emit(current_arrows, max_arrows)
	cooldown_changed.emit(0.0, false)


func _process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= delta
		cooldown_left = max(cooldown_left, 0.0)
		cooldown_changed.emit(cooldown_left, cooldown_left > 0.0)


func unlock_bow() -> bool:
	if bow_unlocked:
		return false

	bow_unlocked = true

	if get_node_or_null("/root/RunState") != null:
		RunState.bow_unlocked = true

	bow_changed.emit(true)
	return true


func add_arrows(amount: int = 5) -> bool:
	if amount <= 0:
		return false

	if current_arrows >= max_arrows:
		arrows_changed.emit(current_arrows, max_arrows)
		return false

	current_arrows += amount
	current_arrows = clamp(current_arrows, 0, max_arrows)

	if get_node_or_null("/root/RunState") != null:
		RunState.current_arrows = current_arrows

	arrows_changed.emit(current_arrows, max_arrows)
	return true


func shoot(facing_right: bool) -> bool:
	if not bow_unlocked:
		return false

	if current_arrows <= 0:
		return false

	if cooldown_left > 0.0:
		cooldown_changed.emit(cooldown_left, true)
		return false

	if shooting:
		return false

	if arrow_scene == null:
		push_warning("PlayerBow: arrow_scene fehlt im Inspector.")
		return false

	if arrow_spawn == null:
		push_warning("PlayerBow: ArrowSpawn Marker fehlt.")
		return false

	shooting = true
	await _shoot_sequence(facing_right)
	shooting = false

	return true


func _shoot_sequence(facing_right: bool) -> void:
	if sprite and sprite.sprite_frames.has_animation(shoot_anim):
		sprite.play(shoot_anim)

		while sprite.animation == shoot_anim and sprite.frame < shoot_spawn_frame:
			await get_tree().process_frame

	_spawn_arrow(facing_right)

	current_arrows -= 1
	current_arrows = max(current_arrows, 0)

	if get_node_or_null("/root/RunState") != null:
		RunState.current_arrows = current_arrows

	arrows_changed.emit(current_arrows, max_arrows)

	cooldown_left = shoot_cooldown
	cooldown_changed.emit(cooldown_left, true)


func _spawn_arrow(facing_right: bool) -> void:
	var arrow = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)

	var offset := arrow_spawn.position

	if facing_right:
		offset.x = abs(offset.x)
	else:
		offset.x = -abs(offset.x)

	arrow.global_position = player.global_position + offset

	var dir := 1 if facing_right else -1

	if arrow.has_method("setup"):
		arrow.setup(dir, player)
