extends CharacterBody2D

signal boss_started
signal phase_1_finished
signal summon_started
signal summon_ended

enum State {
	SLEEP,
	AWAKE,
	IDLE,
	WALK,
	ATTACK_1,
	ATTACK_2,
	SUMMON,
	HURT,
	DEATH
}

@export var max_health: int = 60
@export var damage: int = 1

@export var move_speed: float = 38.0
@export var gravity: float = 900.0
@export var world_collision_mask: int = 1

# Boss verfolgt den Spieler/Summon unbegrenzt weit (bis zum
# Rand des Raums / bis eine Wand blockiert) - kein chase_range
# mehr als Obergrenze für Ziel-Auswahl oder Bewegung.
@export var attack_1_range: float = 55.0
@export var attack_2_range: float = 100.0

@export var attack_cooldown: float = 0.9
@export var after_attack_idle_time: float = 0.45

@export var summon_loop_time: float = 1.5
@export var summon_cooldown: float = 0.6

@export_group("Fireballs")
@export var fireball_scene: PackedScene
@export var fireball_damage: int = 1
@export var fireballs_above_50: int = 2
@export var fireballs_below_50: int = 3
@export var fireball_spawn_radius_x: float = 100.0
@export var fireball_spawn_min_y: float = -100.0
@export var fireball_spawn_max_y: float = -45.0
@export var fireball_delay_between: float = 0.25

@export_group("Air Explosion")
@export var air_explosion_scene: PackedScene
@export var air_explosion_damage: int = 1
@export var explosion_count: int = 9
@export var explosion_batch_size: int = 3
@export var explosion_batch_delay: float = 0.35
@export var explosion_random_offset_x: float = 90.0
@export var explosion_random_offset_y: float = 45.0
@export var explosion_height_offset: float = -24.0

@export_group("Fire Pillars")
@export var fire_pillar_scene: PackedScene
@export var fire_pillar_damage: int = 1
@export var pillar_count: int = 6
@export var pillar_batch_size: int = 2
@export var pillar_batch_delay: float = 0.35
@export var pillar_random_offset_x: float = 70.0
@export var pillar_y_offset: float = 0.0

@export_group("Attack 1 Frames")
@export var attack_1_hitbox_1_start: int = 4
@export var attack_1_hitbox_1_end: int = 6
@export var attack_1_hitbox_2_start: int = 10
@export var attack_1_hitbox_2_end: int = 12

@export_group("Attack 2 Frames")
@export var attack_2_damage_start_frame: int = 5
@export var attack_2_damage_end_frame: int = 11

@export var hit_lock_time: float = 0.18
@export var attack_hit_flash_time: float = 0.07

@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"
@export var player_attack_group: StringName = &"player_attack"

@export var anim_idle: StringName = &"Idle"
@export var anim_walk: StringName = &"Walk"
@export var anim_awake: StringName = &"Awake"
@export var anim_attack_1: StringName = &"Attack_1"
@export var anim_attack_2: StringName = &"Attack_2"
@export var anim_summon_start: StringName = &"Summon_Start"
@export var anim_summon_loop: StringName = &"Summon_Loop"
@export var anim_summon_end: StringName = &"Summon_End"
@export var anim_death: StringName = &"Death_P1"
@export var anim_hurt_1: StringName = &"Hittet_1"
@export var anim_hurt_2: StringName = &"Hittet_2"
@export var anim_hurt_3: StringName = &"Hittet_3"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var wake_area: Area2D = $WakeArea
@onready var hurtbox: Area2D = $Hurtbox
@onready var attack_hitbox_1: Area2D = $AttackHitbox1
@onready var attack_hitbox_2: Area2D = $AttackHitbox2
@onready var flame_breath_hitbox: Area2D = $FlameBreathHitbox

# Zauber-Effekte (Einfrieren, Festhalten, Verlangsamen) - siehe
# enemy_spell_effects.gd. Wird von den Zauber-Scripts des
# Spielers automatisch erzeugt, falls noch nicht vorhanden.
@onready var spell_effects: Node = get_node_or_null(
	"enemy_spell_effects"
)

var state: State = State.SLEEP
var player: Node2D = null
var current_target: Node2D = null

var hp: int = 60
var facing_right: bool = false
var dead: bool = false
var can_take_damage: bool = false
var can_attack: bool = true

var animation_locked: bool = false
var sequence_running: bool = false

var hit_lock: bool = false
var hurt_index: int = 0

var attack_flash_generation: int = 0
var attack_flash_material: ShaderMaterial = null

var pattern_index: int = 0
var pattern: Array[String] = [
	"MELEE",
	"MELEE",
	"SUMMON",
	"MELEE",
	"SUMMON",
	"SUMMON"
]

var attack_1_hit_1_done: bool = false
var attack_1_hit_2_done: bool = false
var attack_2_hit_done: bool = false


func _ready() -> void:
	hp = max_health

	_setup_attack_flash_shader()

	add_to_group("enemy")
	add_to_group("boss")

	collision_mask = world_collision_mask
	randomize()

	player = get_tree().get_first_node_in_group(player_group) as Node2D

	if not wake_area.body_entered.is_connected(_on_wake_area_body_entered):
		wake_area.body_entered.connect(_on_wake_area_body_entered)

	if not wake_area.area_entered.is_connected(_on_wake_area_area_entered):
		wake_area.area_entered.connect(_on_wake_area_area_entered)

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)

	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)

	wake_area.monitoring = true
	hurtbox.monitoring = true
	attack_hitbox_1.monitoring = true
	attack_hitbox_2.monitoring = true
	flame_breath_hitbox.monitoring = true

	wake_area.monitorable = true
	hurtbox.monitorable = true
	attack_hitbox_1.monitorable = true
	attack_hitbox_2.monitorable = true
	flame_breath_hitbox.monitorable = true

	_set_loop(anim_awake, false)
	_set_loop(anim_attack_1, false)
	_set_loop(anim_attack_2, false)
	_set_loop(anim_summon_start, false)
	_set_loop(anim_summon_end, false)
	_set_loop(anim_hurt_1, false)
	_set_loop(anim_hurt_2, false)
	_set_loop(anim_hurt_3, false)
	_set_loop(anim_death, false)

	_set_loop(anim_walk, true)
	_set_loop(anim_summon_loop, true)

	if sprite.sprite_frames.has_animation(anim_awake):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()

	state = State.SLEEP
	can_take_damage = false
	can_attack = true
	animation_locked = false
	sequence_running = false

	call_deferred("_check_initial_wake_overlap")


func _physics_process(delta: float) -> void:
	if dead:
		return

	_check_player_attack()
	_apply_gravity(delta)

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(player_group) as Node2D

	_refresh_current_target()

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

		State.IDLE:
			_chase_logic()

		State.WALK:
			_chase_logic()

		State.ATTACK_1:
			velocity.x = 0
			_update_attack_1_damage()

		State.ATTACK_2:
			velocity.x = 0
			_update_attack_2_damage()

		State.SUMMON:
			velocity.x = 0

		State.HURT:
			velocity.x = 0

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


func _target_is_valid(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if (
		not target.is_in_group(player_group)
		and not target.is_in_group(summon_group)
	):
		return false

	if "dead" in target and bool(target.dead):
		return false

	if not target.visible:
		return false

	return true


func _find_summon() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(summon_group):
		if node is Node2D and _target_is_valid(node as Node2D):
			return node as Node2D

	return null


func _refresh_current_target() -> void:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	if _target_is_valid(player):
		var player_distance: float = global_position.distance_to(
			player.global_position
		)

		nearest_target = player
		nearest_distance = player_distance

	var summon: Node2D = _find_summon()

	if _target_is_valid(summon):
		var summon_distance: float = global_position.distance_to(
			summon.global_position
		)

		if summon_distance < nearest_distance:
			nearest_target = summon
			nearest_distance = summon_distance

	current_target = nearest_target


func _get_summon_from_hurtbox(area: Area2D) -> Node2D:
	if area == null or not is_instance_valid(area):
		return null

	if area.name != &"Hurtbox":
		return null

	var current: Node = area.get_parent()

	while current != null:
		if (
			current is Node2D
			and current.is_in_group(summon_group)
		):
			return current as Node2D

		current = current.get_parent()

	return null


func _chase_logic() -> void:
	if animation_locked or sequence_running:
		velocity.x = 0
		return

	if not _target_is_valid(current_target):
		_stop_moving()
		return

	var dx: float = current_target.global_position.x - global_position.x
	var dist: float = abs(dx)
	var dir: float = sign(dx)

	if dir != 0:
		_set_facing(dir)

	if can_attack and dist <= attack_2_range:
		_start_next_pattern_action(dist)
		return

	# Festgewurzelt (Ranken): darf sich nicht wegbewegen,
	# kann aber weiterhin angreifen (siehe Zweig oben).
	if _is_rooted():
		_stop_moving()
		return

	_walk(dir)


func _start_next_pattern_action(dist: float) -> void:
	if animation_locked or sequence_running or dead:
		return

	var action: String = pattern[pattern_index]

	pattern_index += 1

	if pattern_index >= pattern.size():
		pattern_index = 0

	if action == "SUMMON":
		_start_summon()
		return

	_start_random_melee_attack(dist)


func _start_random_melee_attack(_dist: float) -> void:
	if animation_locked or sequence_running or dead:
		return

	var choice: int = randi_range(1, 2)

	if choice == 1:
		_start_attack_1()
	else:
		_start_attack_2()


func _walk(dir: float) -> void:
	if animation_locked or sequence_running:
		velocity.x = 0
		return

	if dir == 0:
		_stop_moving()
		return

	state = State.WALK
	velocity.x = dir * move_speed * _get_speed_multiplier()

	_play_anim(anim_walk)


func _stop_moving() -> void:
	if animation_locked or sequence_running:
		velocity.x = 0
		return

	state = State.IDLE
	velocity.x = 0


func _play_anim(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning("FireKnightP1: Animation fehlt: " + str(anim_name))
		return

	# Während des Festhaltens (Ranken) hält enemy_spell_effects.gd
	# die Animation exakt auf dem eingefrorenen Frame fest - hier
	# NICHT umschalten, sonst geht der gehaltene Frame verloren.
	# _play_anim_force() (Attack/Awake/Hurt/Summon/Death) ist
	# davon bewusst NICHT betroffen.
	if _is_rooted():
		return

	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)


func _play_anim_force(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning("FireKnightP1: Animation fehlt: " + str(anim_name))
		return

	sprite.play(anim_name)
	sprite.frame = 0


func _start_attack_1() -> void:
	if animation_locked or sequence_running or dead:
		return

	animation_locked = true
	sequence_running = true

	state = State.ATTACK_1
	can_attack = false
	velocity.x = 0

	attack_1_hit_1_done = false
	attack_1_hit_2_done = false

	_play_anim_force(anim_attack_1)


func _start_attack_2() -> void:
	if animation_locked or sequence_running or dead:
		return

	animation_locked = true
	sequence_running = true

	state = State.ATTACK_2
	can_attack = false
	velocity.x = 0

	attack_2_hit_done = false

	_play_anim_force(anim_attack_2)


func _start_summon() -> void:
	if animation_locked or sequence_running or dead:
		return

	animation_locked = true
	sequence_running = true

	state = State.SUMMON
	can_attack = false
	velocity.x = 0

	summon_started.emit()

	_play_anim_force(anim_summon_start)


func _on_frame_changed() -> void:
	if state == State.ATTACK_1:
		_update_attack_1_damage()

	if state == State.ATTACK_2:
		_update_attack_2_damage()


func _update_attack_1_damage() -> void:
	if sprite.animation != anim_attack_1:
		return

	var current_frame: int = sprite.frame

	if (
		not attack_1_hit_1_done
		and current_frame >= attack_1_hitbox_1_start
		and current_frame <= attack_1_hitbox_1_end
	):
		attack_1_hit_1_done = true
		_damage_player_in_area(attack_hitbox_1)

	if (
		not attack_1_hit_2_done
		and current_frame >= attack_1_hitbox_2_start
		and current_frame <= attack_1_hitbox_2_end
	):
		attack_1_hit_2_done = true
		_damage_player_in_area(attack_hitbox_2)


func _update_attack_2_damage() -> void:
	if sprite.animation != anim_attack_2:
		return

	if attack_2_hit_done:
		return

	var current_frame: int = sprite.frame

	if (
		current_frame >= attack_2_damage_start_frame
		and current_frame <= attack_2_damage_end_frame
	):
		attack_2_hit_done = true
		_damage_player_in_area(flame_breath_hitbox)


func _damage_player_in_area(area: Area2D) -> void:
	if area == null:
		return

	for body in area.get_overlapping_bodies():
		if body.is_in_group(player_group):
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position)

			return

	for overlap_area: Area2D in area.get_overlapping_areas():
		var summon_target: Node2D = _get_summon_from_hurtbox(
			overlap_area
		)

		if summon_target == null:
			continue

		if summon_target.has_method("take_damage"):
			summon_target.take_damage(
				damage,
				global_position
			)

		return


func _check_player_attack() -> void:
	if dead:
		return

	if not can_take_damage:
		return

	if hit_lock:
		return

	if (
		state != State.WALK
		and state != State.IDLE
		and state != State.ATTACK_1
		and state != State.ATTACK_2
	):
		return

	for area in hurtbox.get_overlapping_areas():
		_try_player_attack(area)

		if hit_lock:
			return


func _try_player_attack(area: Area2D) -> void:
	if not area.is_in_group(player_attack_group):
		return

	if not area.has_meta("active"):
		return

	if area.get_meta("active") != true:
		return

	var amount: int = 1

	if area.has_meta("damage"):
		amount = int(area.get_meta("damage"))

	hit_lock = true
	_take_damage(amount)

	await get_tree().create_timer(hit_lock_time).timeout

	hit_lock = false


# _from_position wird hier nicht ausgewertet, muss die Funktion
# aber trotzdem annehmen: der Pfeil (Mobs/Skellete/Archer/arrow.gd)
# ruft take_damage() immer mit zwei Argumenten auf (Schaden +
# Trefferposition) - ohne diesen Parameter stürzte das Spiel ab,
# sobald der Boss mit dem Bogen getroffen wurde ("Expected 1
# argument(s)").
func take_damage(
	amount: int,
	_from_position: Vector2 = Vector2.ZERO
) -> void:
	if dead:
		return

	if amount <= 0:
		return

	if not can_take_damage:
		return

	if hit_lock:
		return

	if (
		state != State.WALK
		and state != State.IDLE
		and state != State.ATTACK_1
		and state != State.ATTACK_2
	):
		return

	hit_lock = true

	_take_damage(amount)

	await get_tree().create_timer(hit_lock_time).timeout

	if is_inside_tree():
		hit_lock = false


func _take_damage(amount: int) -> void:
	if dead:
		return

	if amount <= 0:
		return

	hp -= amount

	# Nutzer-Wunsch: Gegner-Sound-Bank (siehe Game/enemy_sound_
	# manager.gd) - Kategorie "boss".
	EnemySoundManager.play(&"boss", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	if (
		state == State.ATTACK_1
		or state == State.ATTACK_2
	):
		_flash_white_during_attack()
		return

	_play_hurt()


func _setup_attack_flash_shader() -> void:
	if sprite == null:
		return

	var flash_shader := Shader.new()

	flash_shader.code = """
shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	vec3 final_color = mix(
		source.rgb,
		vec3(1.0, 1.0, 1.0),
		flash_amount
	);

	COLOR = vec4(
		final_color,
		source.a
	);
}
"""

	attack_flash_material = ShaderMaterial.new()
	attack_flash_material.shader = flash_shader

	attack_flash_material.set_shader_parameter(
		"flash_amount",
		0.0
	)

	sprite.material = attack_flash_material


func _flash_white_during_attack() -> void:
	if attack_flash_material == null:
		return

	attack_flash_generation += 1

	var this_generation: int = attack_flash_generation

	attack_flash_material.set_shader_parameter(
		"flash_amount",
		1.0
	)

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(attack_hit_flash_time, 0.01)
	).timeout

	if this_generation != attack_flash_generation:
		return

	if attack_flash_material == null:
		return

	attack_flash_material.set_shader_parameter(
		"flash_amount",
		0.0
	)


func _play_hurt() -> void:
	if dead:
		return

	if animation_locked or sequence_running:
		return

	animation_locked = true
	sequence_running = true

	state = State.HURT
	can_attack = false
	velocity.x = 0

	if hurt_index == 0:
		_play_anim_force(anim_hurt_1)
	elif hurt_index == 1:
		_play_anim_force(anim_hurt_2)
	else:
		_play_anim_force(anim_hurt_3)

	hurt_index += 1

	if hurt_index > 2:
		hurt_index = 0


func _on_animation_finished() -> void:
	if state == State.AWAKE and sprite.animation == anim_awake:
		can_take_damage = true
		can_attack = true
		animation_locked = false
		sequence_running = false

		boss_started.emit()

		state = State.WALK
		_play_anim(anim_walk)
		return

	if state == State.ATTACK_1 and sprite.animation == anim_attack_1:
		await _after_attack()
		return

	if state == State.ATTACK_2 and sprite.animation == anim_attack_2:
		await _after_attack()
		return

	if state == State.SUMMON and sprite.animation == anim_summon_start:
		_play_anim_force(anim_summon_loop)

		await _do_summon_attack()
		await get_tree().create_timer(summon_loop_time).timeout

		if dead:
			return

		_play_anim_force(anim_summon_end)
		return

	if state == State.SUMMON and sprite.animation == anim_summon_end:
		summon_ended.emit()
		await _after_summon()
		return

	if state == State.HURT:
		if dead:
			return

		animation_locked = false
		sequence_running = false
		can_attack = true

		state = State.WALK
		_play_anim(anim_walk)
		return

	if state == State.DEATH and sprite.animation == anim_death:
		phase_1_finished.emit()
		return


func _do_summon_attack() -> void:
	if hp > max_health / 2:
		if randi_range(1, 2) == 1:
			await _summon_fireballs()
		else:
			await _summon_fire_pillars()
	else:
		if randi_range(1, 2) == 1:
			await _summon_fireballs()
		else:
			await _summon_air_explosions()


func _summon_fireballs() -> void:
	var count: int = fireballs_above_50

	if hp <= max_health / 2:
		count = fireballs_below_50

	for i in count:
		if player == null:
			return

		var spawn_pos: Vector2 = player.global_position

		spawn_pos.x += randf_range(
			-fireball_spawn_radius_x,
			fireball_spawn_radius_x
		)

		spawn_pos.y += randf_range(
			fireball_spawn_min_y,
			fireball_spawn_max_y
		)

		_spawn_fireball(spawn_pos)

		await get_tree().create_timer(
			fireball_delay_between
		).timeout


func _summon_fire_pillars() -> void:
	var spawned: int = 0

	while spawned < pillar_count:
		for i in pillar_batch_size:
			if spawned >= pillar_count:
				break

			if player == null:
				return

			var pos: Vector2 = player.global_position

			if i != 0:
				pos.x += randf_range(
					-pillar_random_offset_x,
					pillar_random_offset_x
				)

			pos.y += pillar_y_offset

			_spawn_fire_pillar(pos)
			spawned += 1

		await get_tree().create_timer(
			pillar_batch_delay
		).timeout


func _summon_air_explosions() -> void:
	var spawned: int = 0

	while spawned < explosion_count:
		for i in explosion_batch_size:
			if spawned >= explosion_count:
				break

			if player == null:
				return

			var pos: Vector2 = player.global_position
			pos.y += explosion_height_offset

			if i != 0:
				pos.x += randf_range(
					-explosion_random_offset_x,
					explosion_random_offset_x
				)

				pos.y += randf_range(
					-explosion_random_offset_y,
					explosion_random_offset_y
				)

			_spawn_air_explosion(pos)
			spawned += 1

		await get_tree().create_timer(
			explosion_batch_delay
		).timeout


func _spawn_fireball(pos: Vector2) -> void:
	if fireball_scene == null:
		push_warning("FireKnightP1: Fireball Scene fehlt im Inspector.")
		return

	var fireball = fireball_scene.instantiate()

	get_tree().current_scene.add_child(fireball)
	fireball.global_position = pos

	if fireball.has_method("setup"):
		fireball.setup(player, fireball_damage)


func _spawn_air_explosion(pos: Vector2) -> void:
	if air_explosion_scene == null:
		push_warning("FireKnightP1: Air Explosion Scene fehlt im Inspector.")
		return

	var explosion = air_explosion_scene.instantiate()

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos

	if explosion.has_method("setup"):
		explosion.setup(air_explosion_damage)


func _spawn_fire_pillar(pos: Vector2) -> void:
	if fire_pillar_scene == null:
		push_warning("FireKnightP1: Fire Pillar Scene fehlt im Inspector.")
		return

	var pillar = fire_pillar_scene.instantiate()

	get_tree().current_scene.add_child(pillar)
	pillar.global_position = pos

	if pillar.has_method("setup"):
		pillar.setup(fire_pillar_damage)


func _after_attack() -> void:
	if dead:
		return

	# Direkt nach der Attacke wieder laufen und verwundbar werden.
	state = State.WALK
	animation_locked = false
	sequence_running = false
	can_attack = false

	_play_anim(anim_walk)

	# Während dieser Zeiten läuft der Boss bereits weiter.
	await get_tree().create_timer(after_attack_idle_time).timeout
	await get_tree().create_timer(attack_cooldown).timeout

	if dead:
		return

	can_attack = true


func _after_summon() -> void:
	if dead:
		return

	# Direkt nach der Beschwörung wieder laufen und verwundbar werden.
	state = State.WALK
	animation_locked = false
	sequence_running = false
	can_attack = false

	_play_anim(anim_walk)

	# Während des Summon-Cooldowns läuft der Boss weiter.
	await get_tree().create_timer(summon_cooldown).timeout

	if dead:
		return

	can_attack = true


func _check_initial_wake_overlap() -> void:
	if state != State.SLEEP:
		return

	for body: Node in wake_area.get_overlapping_bodies():
		if body.is_in_group(player_group):
			_on_wake_area_body_entered(body)
			return

	for area: Area2D in wake_area.get_overlapping_areas():
		var summon_target: Node2D = _get_summon_from_hurtbox(area)

		if summon_target != null:
			_on_wake_area_area_entered(area)
			return


func _on_wake_area_body_entered(body: Node) -> void:
	if not body.is_in_group(player_group):
		return

	player = body as Node2D
	current_target = player

	_wake_up_for_target(current_target)


func _on_wake_area_area_entered(area: Area2D) -> void:
	var summon_target: Node2D = _get_summon_from_hurtbox(area)

	if summon_target == null:
		return

	current_target = summon_target

	_wake_up_for_target(current_target)


func _wake_up_for_target(target: Node2D) -> void:
	if not _target_is_valid(target):
		return

	if state == State.SLEEP:
		state = State.AWAKE
		can_take_damage = false
		can_attack = false
		animation_locked = true
		sequence_running = true
		velocity.x = 0

		var direction: float = sign(
			target.global_position.x
			- global_position.x
		)

		if direction != 0.0:
			_set_facing(direction)

		_play_anim_force(anim_awake)


func _die() -> void:
	if dead:
		return

	dead = true
	state = State.DEATH

	# Nutzer-Wunsch: Gegner-Sound-Bank (siehe Game/enemy_sound_
	# manager.gd) - Kategorie "boss".
	EnemySoundManager.play(&"boss", &"death", global_position)

	can_take_damage = false
	can_attack = false
	animation_locked = true
	sequence_running = true
	velocity = Vector2.ZERO

	wake_area.monitoring = false
	hurtbox.monitoring = false
	attack_hitbox_1.monitoring = false
	attack_hitbox_2.monitoring = false
	flame_breath_hitbox.monitoring = false

	if body_shape:
		body_shape.disabled = true

	attack_flash_generation += 1

	if attack_flash_material != null:
		attack_flash_material.set_shader_parameter(
			"flash_amount",
			0.0
		)

	_play_anim_force(anim_death)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		if velocity.y > 0:
			velocity.y = 0


# ============================================================
# ZAUBER-EFFEKTE
# ============================================================

func _is_rooted() -> bool:
	return spell_effects != null and spell_effects.is_rooted()


func _get_speed_multiplier() -> float:
	if spell_effects == null:
		return 1.0

	return spell_effects.get_speed_multiplier()


func is_animation_freeze_safe() -> bool:
	# Nur in Idle/Walk einfrieren - NICHT während Attack, Summon,
	# Hurt, Death oder Awake.
	return state == State.IDLE or state == State.WALK


func _set_facing(dir: float) -> void:
	if dir > 0:
		facing_right = true
	elif dir < 0:
		facing_right = false

	sprite.flip_h = facing_right

	attack_hitbox_1.scale.x = -1 if facing_right else 1
	attack_hitbox_2.scale.x = -1 if facing_right else 1
	flame_breath_hitbox.scale.x = -1 if facing_right else 1


func _set_loop(anim_name: StringName, loop_value: bool) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	if sprite.sprite_frames.has_animation(anim_name):
		sprite.sprite_frames.set_animation_loop(anim_name, loop_value)
