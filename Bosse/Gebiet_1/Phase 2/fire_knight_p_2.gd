extends CharacterBody2D

signal boss_started
signal phase_2_finished
signal summon_started
signal summon_ended
signal cutscene_started
signal cutscene_finished

enum State {
	SLEEP,
	AWAKE,
	WALK,
	ATTACK_1,
	ATTACK_2,
	SUMMON,
	BEAM,
	HURT,
	DEATH
}

@export var max_health: int = 80
@export var damage: int = 1

@export var move_speed: float = 42.0
@export var gravity: float = 900.0
@export var world_collision_mask: int = 1

@export_group("Ranges")
# Boss verfolgt den Spieler/Summon unbegrenzt weit (bis zum
# Rand des Raums / bis eine Wand blockiert) - kein chase_range
# mehr als Obergrenze für Ziel-Auswahl oder Bewegung.
@export var attack_1_range: float = 65.0
@export var attack_2_range: float = 95.0
@export var summon_range: float = 260.0
@export var beam_range: float = 320.0

@export_group("Timings")
@export var attack_run_pause_time: float = 0.9
@export var attack_cooldown: float = 0.4
@export var summon_loop_time: float = 1.3
@export var summon_cooldown: float = 0.6
@export var hit_lock_time: float = 0.18
@export var attack_hit_flash_time: float = 0.07

@export_group("Healing")
@export var heal_health_percent: float = 0.30
@export var heal_only_once: bool = true
@export var heal_amount: int = 5
@export var heal_step_delay: float = 0.25

@export_group("Attack 1 Frames")
@export var attack_1_hitbox_1_start: int = 8
@export var attack_1_hitbox_1_end: int = 9
@export var attack_1_hitbox_2_start: int = 17
@export var attack_1_hitbox_2_end: int = 20

@export_group("Attack 2 Frames")
@export var attack_2_hitbox_1_start: int = 8
@export var attack_2_hitbox_1_end: int = 9
@export var attack_2_hitbox_2_start: int = 12
@export var attack_2_hitbox_2_end: int = 13
@export var attack_2_hitbox_3_start: int = 18
@export var attack_2_hitbox_3_end: int = 19

@export_group("Death Cutscene")
@export var death_reflect_time: float = 1.5
@export var white_fade_time: float = 3.0

@export_group("Projectile Scenes")
@export var meteor_scene: PackedScene
@export var lava_shard_scene: PackedScene
@export var orbit_fireball_scene: PackedScene

@export_group("Projectile Damage")
@export var meteor_damage: int = 3
@export var lava_shard_damage: int = 1
@export var orbit_fireball_damage: int = 1

@export_group("Meteor Settings")
@export var meteor_spawn_offset: Vector2 = Vector2(0, -180)

@export_group("Lava Shard Settings")
@export var lava_shard_count: int = 20
@export var lava_shard_delay: float = 0.06
@export var lava_shard_speed: float = 340.0
@export var lava_shard_spawn_offset: Vector2 = Vector2(160, -160)
@export var lava_shard_random_offset: float = 18.0
@export var lava_shards_always_left_of_player: bool = true

@export_group("Orbit Fireball Settings")
@export var orbit_fireball_spawn_offset: Vector2 = Vector2(-120, -120)
@export var orbit_fireball_speed: float = 180.0

@export_group("Groups")
@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"
@export var player_attack_group: StringName = &"player_attack"
@export var enemy_hurtbox_group: StringName = &"enemy_hurtbox"

@export_group("Animations")
@export var anim_walk: StringName = &"Walk"
@export var anim_awake: StringName = &"Awake"
@export var anim_attack_1: StringName = &"Attack_1"
@export var anim_attack_2: StringName = &"Attack_2"
@export var anim_summon_start: StringName = &"Summon_Start"
@export var anim_summon_loop: StringName = &"Summon_Loop"
@export var anim_summon_end: StringName = &"Summon_End"

# Diese drei früheren Beam-Animationen werden jetzt für die Heilung verwendet.
@export var anim_beam_start: StringName = &"Beam_start"
@export var anim_beam_loop: StringName = &"Beam_loop"
@export var anim_beam_end: StringName = &"Beam_end"

@export var anim_death: StringName = &"Death_P2"
@export var anim_hurt_1: StringName = &"Hittet_1"
@export var anim_hurt_2: StringName = &"Hittet_2"
@export var anim_hurt_3: StringName = &"Hittet_3"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var wake_area: Area2D = $WakeArea
@onready var hurtbox: Area2D = $Hurtbox

@onready var attack_1_hitbox_1: Area2D = get_node_or_null(
	"AttackHitbox1_Frame8"
) as Area2D

@onready var attack_1_hitbox_2: Area2D = get_node_or_null(
	"AttackHitbox1_Frame17_20"
) as Area2D

@onready var attack_2_hitbox_1: Area2D = get_node_or_null(
	"AttackHitbox2_Frame8"
) as Area2D

@onready var attack_2_hitbox_2: Area2D = get_node_or_null(
	"AttackHitbox2_Frame12"
) as Area2D

@onready var attack_2_hitbox_3: Area2D = get_node_or_null(
	"AttackHitbox2_Frame18"
) as Area2D

@onready var cutscene: Node = get_node_or_null("Cutscene")

# Zauber-Effekte (Einfrieren, Festhalten, Verlangsamen) - siehe
# enemy_spell_effects.gd. Wird von den Zauber-Scripts des
# Spielers automatisch erzeugt, falls noch nicht vorhanden.
@onready var spell_effects: Node = get_node_or_null(
	"enemy_spell_effects"
)

var state: State = State.SLEEP
var player: Node2D = null
var current_target: Node2D = null

var hp: int = 80
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

# Der alte Beam-Status wird jetzt für die einmalige Heilung verwendet.
var heal_used: bool = false

var death_sequence_started: bool = false

var pattern_index: int = 0

var pattern: Array[String] = [
	"MELEE",
	"RANGED",
	"MELEE",
	"RANGED",
	"METEOR",
	"MELEE",
	"RANGED"
]

var attack_1_hit_1_done: bool = false
var attack_1_hit_2_done: bool = false

var attack_2_hit_1_done: bool = false
var attack_2_hit_2_done: bool = false
var attack_2_hit_3_done: bool = false

var current_summon_action: String = "ORBIT"

var flash_layer: CanvasLayer = null
var flash_rect: ColorRect = null


func _ready() -> void:
	hp = max_health

	_setup_attack_flash_shader()

	add_to_group("enemy")
	add_to_group("boss")

	if hurtbox != null:
		hurtbox.add_to_group(enemy_hurtbox_group)

	collision_mask = world_collision_mask

	randomize()

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D

	if wake_area != null:
		if not wake_area.body_entered.is_connected(
			_on_wake_area_body_entered
		):
			wake_area.body_entered.connect(
				_on_wake_area_body_entered
			)

		if not wake_area.area_entered.is_connected(
			_on_wake_area_area_entered
		):
			wake_area.area_entered.connect(
				_on_wake_area_area_entered
			)

	if sprite != null:
		if not sprite.frame_changed.is_connected(
			_on_frame_changed
		):
			sprite.frame_changed.connect(
				_on_frame_changed
			)

		if not sprite.animation_finished.is_connected(
			_on_animation_finished
		):
			sprite.animation_finished.connect(
				_on_animation_finished
			)

	_set_area_ready(wake_area)
	_set_area_ready(hurtbox)

	_set_area_ready(attack_1_hitbox_1)
	_set_area_ready(attack_1_hitbox_2)

	_set_area_ready(attack_2_hitbox_1)
	_set_area_ready(attack_2_hitbox_2)
	_set_area_ready(attack_2_hitbox_3)

	_set_loop(anim_awake, false)
	_set_loop(anim_attack_1, false)
	_set_loop(anim_attack_2, false)

	_set_loop(anim_summon_start, false)
	_set_loop(anim_summon_end, false)

	_set_loop(anim_beam_start, false)
	_set_loop(anim_beam_end, false)

	_set_loop(anim_hurt_1, false)
	_set_loop(anim_hurt_2, false)
	_set_loop(anim_hurt_3, false)

	_set_loop(anim_death, false)

	_set_loop(anim_walk, true)
	_set_loop(anim_summon_loop, true)
	_set_loop(anim_beam_loop, true)

	_create_flash_rect()

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_awake)
	):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()

	state = State.SLEEP

	can_take_damage = false
	can_attack = true
	animation_locked = false
	sequence_running = false

	await get_tree().physics_frame

	_check_wake_area_start()


func _physics_process(delta: float) -> void:
	if dead:
		return

	_check_player_attack()
	_apply_gravity(delta)

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(
			player_group
		) as Node2D

	_refresh_current_target()

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

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

		State.BEAM:
			velocity.x = 0

		State.HURT:
			velocity.x = 0

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


func _set_area_ready(area: Area2D) -> void:
	if area == null:
		return

	area.monitoring = true
	area.monitorable = true


func _check_wake_area_start() -> void:
	if state != State.SLEEP:
		return

	if wake_area == null:
		return

	for body in wake_area.get_overlapping_bodies():
		if body.is_in_group(player_group):
			_on_wake_area_body_entered(body)
			return

	for area: Area2D in wake_area.get_overlapping_areas():
		var summon_target: Node2D = _get_summon_from_hurtbox(area)

		if summon_target != null:
			_on_wake_area_area_entered(area)
			return


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


func _set_summons_visible(should_be_visible: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group(summon_group):
		if node is CanvasItem:
			(node as CanvasItem).visible = should_be_visible


func _chase_logic() -> void:
	if animation_locked or sequence_running:
		velocity.x = 0
		return

	if not _target_is_valid(current_target):
		velocity.x = 0
		return

	var dx: float = (
		current_target.global_position.x
		- global_position.x
	)

	var dist: float = abs(dx)
	var dir: float = sign(dx)

	if dir != 0:
		_set_facing(dir)

	if _should_force_heal() and dist <= beam_range:
		_start_heal()
		return

	if can_attack:
		if (
			dist <= attack_1_range
			or dist <= attack_2_range
			or dist <= summon_range
		):
			_start_next_pattern_action(dist)
			return

	# Festgewurzelt (Ranken): darf sich nicht wegbewegen,
	# kann aber weiterhin angreifen (siehe Zweig oben).
	if _is_rooted():
		velocity.x = 0
		return

	_walk(dir)


func _should_force_heal() -> bool:
	if animation_locked or sequence_running:
		return false

	if not can_attack:
		return false

	if heal_only_once and heal_used:
		return false

	if hp >= max_health:
		return false

	var percent: float = (
		float(hp)
		/ float(max_health)
	)

	return percent <= heal_health_percent


func _start_next_pattern_action(_dist: float) -> void:
	if animation_locked or sequence_running:
		return

	var action: String = pattern[pattern_index]

	pattern_index += 1

	if pattern_index >= pattern.size():
		pattern_index = 0

	if action == "MELEE":
		_start_random_melee_attack()
		return

	if action == "RANGED":
		_start_random_ranged_summon()
		return

	if action == "METEOR":
		current_summon_action = "METEOR"
		_start_summon()
		return

	_start_random_melee_attack()


func _start_random_melee_attack() -> void:
	if animation_locked or sequence_running:
		return

	var choice: int = randi_range(1, 2)

	if choice == 1:
		_start_attack_1()
	else:
		_start_attack_2()


func _start_random_ranged_summon() -> void:
	if animation_locked or sequence_running:
		return

	var choice: int = randi_range(1, 2)

	if choice == 1:
		current_summon_action = "LAVA_SHARDS"
	else:
		current_summon_action = "ORBIT"

	_start_summon()


func _walk(dir: float) -> void:
	if animation_locked or sequence_running:
		velocity.x = 0
		return

	if dir == 0:
		velocity.x = 0
		return

	state = State.WALK
	velocity.x = dir * move_speed * _get_speed_multiplier()

	_play_anim(anim_walk)


func _play_anim(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning(
			"FireKnightP2: Animation fehlt: "
			+ str(anim_name)
		)
		return

	# Während des Festhaltens (Ranken) hält enemy_spell_effects.gd
	# die Animation exakt auf dem eingefrorenen Frame fest - hier
	# NICHT umschalten, sonst geht der gehaltene Frame verloren.
	# _play_anim_force() (Attack/Awake/Hurt/Summon/Beam/Death) ist
	# davon bewusst NICHT betroffen.
	if _is_rooted():
		return

	if sprite.animation != anim_name:
		sprite.play(anim_name)


func _play_anim_force(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning(
			"FireKnightP2: Animation fehlt: "
			+ str(anim_name)
		)
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

	attack_2_hit_1_done = false
	attack_2_hit_2_done = false
	attack_2_hit_3_done = false

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


func _start_heal() -> void:
	if animation_locked or sequence_running or dead:
		return

	animation_locked = true
	sequence_running = true

	state = State.BEAM
	can_attack = false
	heal_used = true
	velocity.x = 0

	_play_anim_force(anim_beam_start)


func _on_frame_changed() -> void:
	if state == State.ATTACK_1:
		_update_attack_1_damage()

	if state == State.ATTACK_2:
		_update_attack_2_damage()


func _update_attack_1_damage() -> void:
	if sprite == null:
		return

	if sprite.animation != anim_attack_1:
		return

	var current_frame: int = sprite.frame

	if (
		not attack_1_hit_1_done
		and current_frame >= attack_1_hitbox_1_start
		and current_frame <= attack_1_hitbox_1_end
	):
		attack_1_hit_1_done = true
		_damage_player_in_area(
			attack_1_hitbox_1
		)

	if (
		not attack_1_hit_2_done
		and current_frame >= attack_1_hitbox_2_start
		and current_frame <= attack_1_hitbox_2_end
	):
		attack_1_hit_2_done = true
		_damage_player_in_area(
			attack_1_hitbox_2
		)


func _update_attack_2_damage() -> void:
	if sprite == null:
		return

	if sprite.animation != anim_attack_2:
		return

	var current_frame: int = sprite.frame

	if (
		not attack_2_hit_1_done
		and current_frame >= attack_2_hitbox_1_start
		and current_frame <= attack_2_hitbox_1_end
	):
		attack_2_hit_1_done = true
		_damage_player_in_area(
			attack_2_hitbox_1
		)

	if (
		not attack_2_hit_2_done
		and current_frame >= attack_2_hitbox_2_start
		and current_frame <= attack_2_hitbox_2_end
	):
		attack_2_hit_2_done = true
		_damage_player_in_area(
			attack_2_hitbox_2
		)

	if (
		not attack_2_hit_3_done
		and current_frame >= attack_2_hitbox_3_start
		and current_frame <= attack_2_hitbox_3_end
	):
		attack_2_hit_3_done = true
		_damage_player_in_area(
			attack_2_hitbox_3
		)


func _damage_player_in_area(area: Area2D) -> void:
	if area == null:
		push_warning(
			"FireKnightP2: Attack-Hitbox fehlt."
		)
		return

	for body in area.get_overlapping_bodies():
		if body.is_in_group(player_group):
			if body.has_method("take_damage"):
				body.take_damage(
					damage,
					global_position
				)

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

	if hurtbox == null:
		return

	if (
		state != State.WALK
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
		amount = int(
			area.get_meta("damage")
		)

	hit_lock = true

	_take_damage(amount)

	await get_tree().create_timer(
		hit_lock_time
	).timeout

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
		and state != State.ATTACK_1
		and state != State.ATTACK_2
	):
		return

	hit_lock = true

	_take_damage(amount)

	await get_tree().create_timer(
		hit_lock_time
	).timeout

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
	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
	):
		can_take_damage = true
		can_attack = true
		animation_locked = false
		sequence_running = false

		boss_started.emit()

		state = State.WALK
		_play_anim(anim_walk)
		return

	if (
		state == State.ATTACK_1
		and sprite.animation == anim_attack_1
	):
		await _after_attack()
		return

	if (
		state == State.ATTACK_2
		and sprite.animation == anim_attack_2
	):
		await _after_attack()
		return

	if (
		state == State.SUMMON
		and sprite.animation == anim_summon_start
	):
		_play_anim_force(anim_summon_loop)

		await _do_summon_attack()

		await get_tree().create_timer(
			summon_loop_time
		).timeout

		if dead:
			return

		_play_anim_force(anim_summon_end)
		return

	if (
		state == State.SUMMON
		and sprite.animation == anim_summon_end
	):
		summon_ended.emit()

		await _after_attack()
		return

	# HEILUNG:
	# Nach Beam_start wird die Loop gestartet.
	# Während der Loop steigt HP fünfmal um jeweils 1.
	if (
		state == State.BEAM
		and sprite.animation == anim_beam_start
	):
		_play_anim_force(anim_beam_loop)

		await _heal_during_loop()

		if dead:
			return

		_play_anim_force(anim_beam_end)
		return

	if (
		state == State.BEAM
		and sprite.animation == anim_beam_end
	):
		await _after_attack()
		return

	if state == State.HURT:
		if dead:
			return

		await _after_attack()
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		if not death_sequence_started:
			death_sequence_started = true

			await _play_death_finish_sequence()

		return


func _heal_during_loop() -> void:
	var healed: int = 0

	while healed < heal_amount:
		if dead:
			return

		if hp >= max_health:
			break

		await get_tree().create_timer(
			heal_step_delay
		).timeout

		if dead:
			return

		hp = min(
			hp + 1,
			max_health
		)

		healed += 1

		print(
			"Boss heilt +1 HP. Aktuelle HP: ",
			hp,
			"/",
			max_health
		)


func _do_summon_attack() -> void:
	if current_summon_action == "METEOR":
		_spawn_meteor()
		return

	if current_summon_action == "LAVA_SHARDS":
		await _spawn_lava_shards()
		return

	_spawn_orbit_fireball()


func _spawn_meteor() -> void:
	if meteor_scene == null:
		push_warning(
			"FireKnightP2: Meteor Scene fehlt im Inspector."
		)
		return

	var obj = meteor_scene.instantiate()

	get_tree().current_scene.add_child(obj)

	obj.global_position = (
		_get_player_position()
		+ meteor_spawn_offset
	)

	if obj.has_method("setup"):
		obj.setup(
			player,
			meteor_damage
		)


func _spawn_lava_shards() -> void:
	if lava_shard_scene == null:
		push_warning(
			"FireKnightP2: Lava Shard Scene fehlt im Inspector."
		)
		return

	for i in lava_shard_count:
		if dead:
			return

		if player == null or not is_instance_valid(player):
			player = get_tree().get_first_node_in_group(
				player_group
			) as Node2D

		if player == null:
			return

		var side: float = -1.0

		if not lava_shards_always_left_of_player:
			side = 1.0

			if (
				player.global_position.x
				< global_position.x
			):
				side = -1.0

		var random_offset := Vector2(
			randf_range(
				-lava_shard_random_offset,
				lava_shard_random_offset
			),
			randf_range(
				-lava_shard_random_offset,
				lava_shard_random_offset
			)
		)

		var spawn_pos: Vector2 = (
			player.global_position
			+ Vector2(
				lava_shard_spawn_offset.x * side,
				lava_shard_spawn_offset.y
			)
			+ random_offset
		)

		var target_pos: Vector2 = (
			player.global_position
		)

		var dir: Vector2 = (
			target_pos - spawn_pos
		).normalized()

		var obj = lava_shard_scene.instantiate()

		get_tree().current_scene.add_child(obj)

		obj.global_position = spawn_pos

		if obj.has_method("setup"):
			obj.setup(
				dir,
				lava_shard_damage,
				lava_shard_speed
			)

		await get_tree().create_timer(
			lava_shard_delay
		).timeout


func _spawn_orbit_fireball() -> void:
	if orbit_fireball_scene == null:
		push_warning(
			"FireKnightP2: Orbit Fireball Scene fehlt im Inspector."
		)
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(
			player_group
		) as Node2D

	var obj = orbit_fireball_scene.instantiate()

	get_tree().current_scene.add_child(obj)

	obj.global_position = (
		_get_player_position()
		+ orbit_fireball_spawn_offset
	)

	if obj.has_method("setup"):
		obj.setup(
			player,
			orbit_fireball_damage,
			orbit_fireball_speed
		)


func _get_player_position() -> Vector2:
	if player != null and is_instance_valid(player):
		return player.global_position

	return global_position


func _after_attack() -> void:
	if dead:
		return

	state = State.WALK

	_play_anim(anim_walk)

	animation_locked = false
	sequence_running = false

	can_attack = false

	await get_tree().create_timer(
		attack_run_pause_time
	).timeout

	await get_tree().create_timer(
		attack_cooldown
	).timeout

	if dead:
		return

	can_attack = true

	if state == State.WALK:
		_play_anim(anim_walk)


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

	if wake_area != null:
		wake_area.monitoring = false

	if hurtbox != null:
		hurtbox.monitoring = false

	if attack_1_hitbox_1 != null:
		attack_1_hitbox_1.monitoring = false

	if attack_1_hitbox_2 != null:
		attack_1_hitbox_2.monitoring = false

	if attack_2_hitbox_1 != null:
		attack_2_hitbox_1.monitoring = false

	if attack_2_hitbox_2 != null:
		attack_2_hitbox_2.monitoring = false

	if attack_2_hitbox_3 != null:
		attack_2_hitbox_3.monitoring = false

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	# Summon während der Todes-Cutscene ausblenden.
	_set_summons_visible(false)

	# Eigenes Boss-Signal bleibt erhalten.
	cutscene_started.emit()

	# Allgemeiner CutsceneManager blendet das HUD aus.
	if get_node_or_null("/root/CutsceneManager") != null:
		CutsceneManager.begin_cutscene()
	else:
		push_warning(
			"Boss: CutsceneManager wurde nicht als Autoload gefunden."
		)

	if (
		cutscene != null
		and cutscene.has_method("play_death_cutscene")
	):
		cutscene.play_death_cutscene(self)

	attack_flash_generation += 1

	if attack_flash_material != null:
		attack_flash_material.set_shader_parameter(
			"flash_amount",
			0.0
		)

	_play_anim_force(anim_death)


func _play_death_finish_sequence() -> void:
	await get_tree().create_timer(
		death_reflect_time
	).timeout

	if flash_rect != null:
		var tween := create_tween()

		tween.tween_property(
			flash_rect,
			"color",
			Color(1, 1, 1, 1),
			white_fade_time
		)

		await tween.finished

	phase_2_finished.emit()
	cutscene_finished.emit()

	# Summon nach Abschluss der Cutscene wieder einblenden.
	_set_summons_visible(true)

	# Gibt das HUD nach Abschluss wieder frei.
	if get_node_or_null("/root/CutsceneManager") != null:
		CutsceneManager.end_cutscene()


func _create_flash_rect() -> void:
	flash_layer = CanvasLayer.new()
	flash_layer.layer = 1000

	add_child(flash_layer)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)

	flash_rect.set_anchors_preset(
		Control.PRESET_FULL_RECT
	)

	flash_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	flash_layer.add_child(flash_rect)


func _set_loop(
	anim_name: StringName,
	loop_value: bool
) -> void:
	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_name)
	):
		sprite.sprite_frames.set_animation_loop(
			anim_name,
			loop_value
		)


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
	# Nur während des normalen Laufens einfrieren - NICHT während
	# Attack, Summon, Beam/Heilung, Hurt, Death oder Awake.
	return state == State.WALK


func _set_facing(dir: float) -> void:
	if dir > 0:
		facing_right = true
	elif dir < 0:
		facing_right = false

	if sprite != null:
		sprite.flip_h = facing_right

	var flip_value := (
		-1 if facing_right else 1
	)

	if attack_1_hitbox_1 != null:
		attack_1_hitbox_1.scale.x = flip_value

	if attack_1_hitbox_2 != null:
		attack_1_hitbox_2.scale.x = flip_value

	if attack_2_hitbox_1 != null:
		attack_2_hitbox_1.scale.x = flip_value

	if attack_2_hitbox_2 != null:
		attack_2_hitbox_2.scale.x = flip_value

	if attack_2_hitbox_3 != null:
		attack_2_hitbox_3.scale.x = flip_value
