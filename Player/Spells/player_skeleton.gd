extends CharacterBody2D

signal summon_died
signal enemy_target_changed(target: Node2D)

enum State {
	SPAWN,
	IDLE,
	FOLLOW_PLAYER,
	CHASE_ENEMY,
	ATTACK,
	TELEPORT_OUT,
	TELEPORT_IN,
	DEATH
}

@export_group("General")
@export var max_health: int = 4
@export var damage: int = 1
@export var move_speed: float = 55.0
@export var gravity: float = 900.0
@export_flags_2d_physics var world_collision_mask: int = 1

@export_group("Follow Player")
@export var follow_distance: float = 32.0
@export var follow_start_distance: float = 55.0
@export var teleport_distance: float = 260.0
@export var teleport_vertical_distance: float = 110.0
@export var player_side_offset: Vector2 = Vector2(30, 0)

@export_group("Enemy Detection")
@export var enemy_group: StringName = &"enemy"
@export var target_refresh_time: float = 0.15
@export var maximum_target_distance: float = 190.0

@export_group("Attack")
@export var attack_range: float = 25.0
@export var attack_cooldown: float = 0.75
@export var attack_active_start_frame: int = 3
@export var attack_active_end_frame: int = 5
@export var attack_hit_active_time: float = 0.08

@export_group("Damage Feedback")
@export var hit_flash_time: float = 0.07

@export_group("Ground Check")
@export var edge_check_x: float = 10.0
@export var edge_check_y: float = 28.0

@export_group("Groups")
@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"
@export var player_attack_group: StringName = &"player_attack"

@export_group("Animations")
@export var anim_spawn: StringName = &"Spawn"
@export var anim_idle: StringName = &"Idle"
@export var anim_walk: StringName = &"Walk"
@export var anim_attack: StringName = &"Attack"
@export var anim_teleport_out: StringName = &"Teleport_Out"
@export var anim_teleport_in: StringName = &"Teleport_In"
@export var anim_death: StringName = &"Death"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var detection_area: Area2D = $DetectionArea
@onready var ground_ray: RayCast2D = $GroundRay

var state: State = State.SPAWN
var owner_player: Node2D = null
var summon_manager: Node = null
var current_target: Node2D = null

var hp: int = 0
var facing_right: bool = true
var can_act: bool = false
var can_attack: bool = true
var dead: bool = false
var attack_finishing: bool = false
var attack_damage_window_used: bool = false
var attack_generation: int = 0
var target_refresh_timer: float = 0.0

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null


func _ready() -> void:
	hp = max_health

	# Der Summon liegt auf der Welt-Schicht, damit Gegner ihn
	# wie ein festes Hindernis erkennen und an ihm stoppen.
	# Der Spieler kann dank der Collision Exception trotzdem
	# weiterhin vollständig durch den Summon hindurchlaufen.
	collision_layer = world_collision_mask
	collision_mask = world_collision_mask
	call_deferred("_apply_player_collision_exception")

	if not is_in_group(summon_group):
		add_to_group(summon_group)

	_setup_areas()
	_setup_animations()
	_setup_hit_flash_shader()

	sprite.frame_changed.connect(_on_sprite_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)

	state = State.SPAWN
	can_act = false
	_set_attack_active(false)

	if _has_animation(anim_spawn):
		_play_animation_force(anim_spawn)
	else:
		_finish_spawn()


func setup_summon(
	new_player: Node2D,
	new_summon_manager: Node
) -> void:
	owner_player = new_player
	summon_manager = new_summon_manager
	call_deferred("_apply_player_collision_exception")


func restore_summon_state(
	saved_health: int,
	from_room_change: bool = true
) -> void:
	hp = clamp(saved_health, 1, max_health)

	if not from_room_change:
		return

	can_act = false
	velocity = Vector2.ZERO
	state = State.TELEPORT_IN

	if _has_animation(anim_teleport_in):
		_play_animation_force(anim_teleport_in)
	else:
		_finish_teleport_in()


func get_current_health() -> int:
	return hp


func _physics_process(delta: float) -> void:
	if dead:
		return

	_find_player_if_missing()
	_apply_gravity(delta)
	_recover_finished_attack()

	if not can_act:
		velocity.x = 0
		move_and_slide()
		return

	if _should_teleport_to_player():
		_start_teleport()
		move_and_slide()
		return

	target_refresh_timer -= delta

	if target_refresh_timer <= 0.0:
		target_refresh_timer = target_refresh_time
		_refresh_enemy_target()

	match state:
		State.IDLE:
			_process_idle()
		State.FOLLOW_PLAYER:
			_process_follow_player()
		State.CHASE_ENEMY:
			_process_chase_enemy()
		State.ATTACK, State.SPAWN, State.TELEPORT_OUT, State.TELEPORT_IN:
			velocity.x = 0
		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()

	if _is_standing_on_enemy():
		teleport_to_player()


func _recover_finished_attack() -> void:
	if (
		state == State.ATTACK
		and not attack_finishing
		and sprite.animation == anim_attack
		and not sprite.is_playing()
	):
		_finish_attack()


func _find_player_if_missing() -> void:
	if owner_player != null and is_instance_valid(owner_player):
		return

	owner_player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D


func _player_is_valid() -> bool:
	_find_player_if_missing()

	return (
		owner_player != null
		and is_instance_valid(owner_player)
	)


func _apply_player_collision_exception() -> void:
	_find_player_if_missing()

	if not _player_is_valid():
		return

	if owner_player is PhysicsBody2D:
		var player_body := owner_player as PhysicsBody2D
		add_collision_exception_with(player_body)
		player_body.add_collision_exception_with(self)


func _refresh_enemy_target() -> void:
	if dead or not can_act:
		return

	if not _player_is_valid():
		_set_target(null)
		return

	var nearest_enemy: Node2D = null
	var nearest_player_distance: float = INF

	for body: Node2D in detection_area.get_overlapping_bodies():
		if not _is_valid_enemy(body):
			continue

		var summon_distance: float = global_position.distance_to(
			body.global_position
		)

		if summon_distance > maximum_target_distance:
			continue

		var player_distance: float = owner_player.global_position.distance_to(
			body.global_position
		)

		if player_distance < nearest_player_distance:
			nearest_player_distance = player_distance
			nearest_enemy = body

	for area: Area2D in detection_area.get_overlapping_areas():
		var possible_enemy: Node = area

		if not possible_enemy.is_in_group(enemy_group):
			possible_enemy = area.get_parent()

		if not possible_enemy is Node2D:
			continue

		var enemy_node := possible_enemy as Node2D

		if not _is_valid_enemy(enemy_node):
			continue

		var summon_distance: float = global_position.distance_to(
			enemy_node.global_position
		)

		if summon_distance > maximum_target_distance:
			continue

		var player_distance: float = owner_player.global_position.distance_to(
			enemy_node.global_position
		)

		if player_distance < nearest_player_distance:
			nearest_player_distance = player_distance
			nearest_enemy = enemy_node

	_set_target(nearest_enemy)


func _is_valid_enemy(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if not node.is_in_group(enemy_group):
		return false

	if "dead" in node and bool(node.dead):
		return false

	return true


func _target_is_valid(target: Node2D) -> bool:
	return _is_valid_enemy(target)


func _target_is_inside_detection(target: Node2D) -> bool:
	if not _target_is_valid(target):
		return false

	return global_position.distance_to(
		target.global_position
	) <= maximum_target_distance


func _set_target(new_target: Node2D) -> void:
	if current_target == new_target:
		return

	current_target = new_target
	enemy_target_changed.emit(current_target)


func _process_idle() -> void:
	velocity.x = 0

	if _target_is_valid(current_target):
		state = State.CHASE_ENEMY
	elif _should_follow_player():
		state = State.FOLLOW_PLAYER
	else:
		_play_animation(anim_idle)


func _enter_idle() -> void:
	if dead:
		return

	state = State.IDLE
	velocity.x = 0
	_set_attack_active(false)
	_play_animation(anim_idle)


func _process_follow_player() -> void:
	if _target_is_valid(current_target):
		state = State.CHASE_ENEMY
		return

	if not _player_is_valid():
		_enter_idle()
		return

	var dx: float = owner_player.global_position.x - global_position.x

	if abs(dx) <= follow_distance:
		_enter_idle()
		return

	var direction: float = sign(dx)

	if direction == 0.0 or not _has_ground_in_direction(direction):
		_enter_idle()
		return

	_set_facing(direction)
	velocity.x = direction * move_speed
	_play_animation(anim_walk)


func _should_follow_player() -> bool:
	if not _player_is_valid():
		return false

	return abs(
		owner_player.global_position.x - global_position.x
	) > follow_start_distance


func _process_chase_enemy() -> void:
	if not _target_is_valid(current_target):
		_set_target(null)

		if _should_follow_player():
			state = State.FOLLOW_PLAYER
		else:
			_enter_idle()

		return

	var dx: float = current_target.global_position.x - global_position.x
	var distance: float = abs(dx)
	var direction: float = sign(dx)

	if direction != 0.0:
		_set_facing(direction)

	if distance <= attack_range:
		if can_attack:
			_start_attack()
		else:
			velocity.x = 0
			_play_animation(anim_idle)
		return

	if direction == 0.0 or not _has_ground_in_direction(direction):
		velocity.x = 0
		_play_animation(anim_idle)
		return

	velocity.x = direction * move_speed
	_play_animation(anim_walk)


func _start_attack() -> void:
	if dead or not can_act or not can_attack:
		return

	state = State.ATTACK
	can_attack = false
	attack_finishing = false
	attack_damage_window_used = false
	attack_generation += 1
	velocity.x = 0

	if _target_is_valid(current_target):
		_set_facing(sign(
			current_target.global_position.x - global_position.x
		))

	_set_attack_active(false)

	if _has_animation(anim_attack):
		_play_animation_force(anim_attack)
	else:
		_finish_attack()


func _on_sprite_frame_changed() -> void:
	if state != State.ATTACK or sprite.animation != anim_attack:
		return

	if attack_damage_window_used:
		return

	if sprite.frame < attack_active_start_frame:
		return

	if sprite.frame > attack_active_end_frame:
		return

	attack_damage_window_used = true
	_activate_attack_hit_window(attack_generation)


func _activate_attack_hit_window(
	generation: int
) -> void:
	_set_attack_active(true)

	await get_tree().create_timer(
		max(attack_hit_active_time, 0.01)
	).timeout

	if generation != attack_generation:
		return

	_set_attack_active(false)


func _set_attack_active(active: bool) -> void:
	attack_hitbox.set_meta("active", active)
	attack_hitbox.set_meta("damage", damage)


func _finish_attack() -> void:
	if dead or attack_finishing:
		return

	attack_finishing = true
	attack_generation += 1
	_set_attack_active(false)

	if not _target_is_valid(current_target):
		_set_target(null)

	_enter_idle()

	await get_tree().create_timer(
		max(attack_cooldown, 0.01)
	).timeout

	if dead:
		return

	can_attack = true
	attack_finishing = false
	_refresh_enemy_target()


func _should_teleport_to_player() -> bool:
	if not _player_is_valid():
		return false

	if state in [
		State.SPAWN,
		State.TELEPORT_OUT,
		State.TELEPORT_IN,
		State.DEATH
	]:
		return false

	var difference: Vector2 = (
		owner_player.global_position - global_position
	)

	return (
		abs(difference.x) >= teleport_distance
		or abs(difference.y) >= teleport_vertical_distance
	)


# ============================================================
# STECKENBLEIBEN AUF GEGNERN VERHINDERN
# ============================================================

# Der Summon läuft auf der Welt-Kollisionsschicht (siehe _ready()),
# damit Gegner ihn als festes Hindernis erkennen und an ihm stoppen -
# dadurch kann er aber selbst auf einem Gegner "landen" (z.B. direkt
# nach dem Teleportieren neben den Spieler, oder wenn ein Gegner
# unter ihm durchläuft/springt). Steht er oben auf einem Gegner,
# soll er sich einfach wieder zum Spieler zurückteleportieren, statt
# sichtbar auf dem Gegner "festzukleben".
func _is_standing_on_enemy() -> bool:
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if collider == null or not collider is Node:
			continue

		# Nur von oben ("wir stehen drauf") zählt - seitliche
		# Berührungen mit einem Gegner (z.B. nebeneinander stehen/
		# aneinander vorbeidrücken) sollen keinen Teleport auslösen.
		if collision.get_normal().y > -0.5:
			continue

		if _is_valid_enemy(collider as Node):
			return true

	return false


func teleport_to_player() -> void:
	if dead or not _player_is_valid():
		return

	if state in [State.TELEPORT_OUT, State.TELEPORT_IN]:
		return

	_start_teleport()


func _start_teleport() -> void:
	can_act = false
	velocity = Vector2.ZERO
	attack_generation += 1
	_set_attack_active(false)
	_set_target(null)
	state = State.TELEPORT_OUT

	if _has_animation(anim_teleport_out):
		_play_animation_force(anim_teleport_out)
	else:
		_finish_teleport_out()


func _finish_teleport_out() -> void:
	if not _player_is_valid():
		can_act = true
		_enter_idle()
		return

	global_position = _get_player_side_position()
	state = State.TELEPORT_IN

	if _has_animation(anim_teleport_in):
		_play_animation_force(anim_teleport_in)
	else:
		_finish_teleport_in()


func _finish_teleport_in() -> void:
	can_act = true
	_enter_idle()


func _get_player_side_position() -> Vector2:
	var offset: Vector2 = player_side_offset

	if "facing_right" in owner_player:
		offset.x = (
			-abs(player_side_offset.x)
			if bool(owner_player.facing_right)
			else abs(player_side_offset.x)
		)

	return owner_player.global_position + offset


func take_damage(
	amount: int,
	_from_position: Vector2 = Vector2.ZERO
) -> void:
	if dead or amount <= 0:
		return

	if state in [
		State.SPAWN,
		State.TELEPORT_OUT,
		State.TELEPORT_IN
	]:
		return

	hp -= amount

	if get_node_or_null("/root/RunState") != null:
		RunState.save_summon_data(true, hp)

	if hp <= 0:
		_die()
		return

	_flash_white()


func _setup_hit_flash_shader() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(
		mix(source.rgb, vec3(1.0), flash_amount),
		source.a
	);
}
"""

	hit_flash_material = ShaderMaterial.new()
	hit_flash_material.shader = shader
	hit_flash_material.set_shader_parameter(
		"flash_amount",
		0.0
	)
	sprite.material = hit_flash_material


func _flash_white() -> void:
	flash_generation += 1
	var generation: int = flash_generation

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		1.0
	)

	await get_tree().create_timer(
		max(hit_flash_time, 0.01)
	).timeout

	if generation == flash_generation:
		hit_flash_material.set_shader_parameter(
			"flash_amount",
			0.0
		)


func _die() -> void:
	if dead:
		return

	dead = true
	state = State.DEATH
	can_act = false
	can_attack = false
	velocity = Vector2.ZERO

	attack_generation += 1
	_set_attack_active(false)
	hurtbox.monitoring = false
	detection_area.monitoring = false
	attack_hitbox.monitoring = false
	body_shape.set_deferred("disabled", true)

	if (
		summon_manager != null
		and is_instance_valid(summon_manager)
		and summon_manager.has_method("unregister_summon")
	):
		summon_manager.unregister_summon(self, true)

	summon_died.emit()

	if _has_animation(anim_death):
		_play_animation_force(anim_death)
	else:
		queue_free()


func _on_animation_finished() -> void:
	if state == State.SPAWN and sprite.animation == anim_spawn:
		_finish_spawn()
	elif state == State.ATTACK and sprite.animation == anim_attack:
		_finish_attack()
	elif (
		state == State.TELEPORT_OUT
		and sprite.animation == anim_teleport_out
	):
		_finish_teleport_out()
	elif (
		state == State.TELEPORT_IN
		and sprite.animation == anim_teleport_in
	):
		_finish_teleport_in()
	elif state == State.DEATH and sprite.animation == anim_death:
		queue_free()


func _finish_spawn() -> void:
	can_act = true
	_enter_idle()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0


func _has_ground_in_direction(direction: float) -> bool:
	ground_ray.position.x = edge_check_x * sign(direction)
	ground_ray.target_position = Vector2(0, edge_check_y)
	ground_ray.force_raycast_update()
	return ground_ray.is_colliding()


func _set_facing(direction: float) -> void:
	if direction > 0.0:
		facing_right = true
	elif direction < 0.0:
		facing_right = false
	else:
		return

	# Original artwork faces left.
	sprite.flip_h = facing_right
	attack_hitbox.scale.x = (
		-1.0 if facing_right else 1.0
	)


func _setup_areas() -> void:
	hurtbox.monitoring = true
	hurtbox.monitorable = true
	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true
	detection_area.monitoring = true
	detection_area.monitorable = true
	ground_ray.enabled = true

	if not attack_hitbox.is_in_group(player_attack_group):
		attack_hitbox.add_to_group(player_attack_group)

	_set_attack_active(false)


func _setup_animations() -> void:
	for animation in [
		anim_spawn,
		anim_attack,
		anim_teleport_out,
		anim_teleport_in,
		anim_death
	]:
		_set_animation_loop(animation, false)

	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)


func _has_animation(animation_name: StringName) -> bool:
	return (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(animation_name)
	)


func _play_animation(animation_name: StringName) -> void:
	if (
		_has_animation(animation_name)
		and sprite.animation != animation_name
	):
		sprite.play(animation_name)


func _play_animation_force(animation_name: StringName) -> void:
	if _has_animation(animation_name):
		sprite.play(animation_name)
		sprite.frame = 0


func _set_animation_loop(
	animation_name: StringName,
	should_loop: bool
) -> void:
	if _has_animation(animation_name):
		sprite.sprite_frames.set_animation_loop(
			animation_name,
			should_loop
		)
