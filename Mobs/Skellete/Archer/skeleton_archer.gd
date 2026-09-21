extends CharacterBody2D


enum State {
	SLEEP,
	AWAKE,
	IDLE,
	WALK,
	ATTACK,
	HURT,
	DEATH
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2
@export var damage: int = 1

@export var move_speed: float = 45.0
@export var gravity: float = 900.0


# ============================================================
# REICHWEITEN
# ============================================================

@export_group("Reichweiten")

@export var shoot_range: float = 180.0

# Ist das aktuelle Ziel näher als dieser Wert,
# läuft der Archer von ihm weg.
@export var keep_distance: float = 90.0


# ============================================================
# SCHUSS
# ============================================================

@export_group("Schuss")

@export var shoot_cooldown: float = 2.0
@export var shoot_frame: int = 4

@export var shoot_point_offset_x: float = 8.0
@export var shoot_point_offset_y: float = -6.0

@export var arrow_scene: PackedScene


# ============================================================
# ABGRUNDPRÜFUNG
# ============================================================

@export_group("Abgrundprüfung")

@export var edge_check_x: float = 10.0
@export var edge_check_y: float = 28.0


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

@export var hurt_time: float = 0.35
@export var attack_hit_flash_time: float = 0.07
@export var damage_hit_lock_time: float = 0.12


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

@export var death_delete_time: float = 1.2


# ============================================================
# GRUPPEN
# ============================================================

@export_group("Gruppen")

@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"
@export var player_attack_group: StringName = &"player_attack"


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var anim_attack: StringName = &"Attack"
@export var anim_awake: StringName = &"Awake"
@export var anim_death: StringName = &"Death"
@export var anim_hurt: StringName = &"Hittet"
@export var anim_idle: StringName = &"Idle"
@export var anim_walk: StringName = &"Walk"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var wake_area: Area2D = $WakeArea
@onready var hurtbox: Area2D = $Hurtbox
@onready var shoot_point: Marker2D = $ShootPoint
@onready var ground_ray: RayCast2D = $RayCast2D

# Zauber-Effekte (Einfrieren, Festhalten, Verlangsamen) - siehe
# enemy_spell_effects.gd. Wird von den Zauber-Scripts des
# Spielers automatisch erzeugt, falls noch nicht vorhanden.
@onready var spell_effects: Node = get_node_or_null(
	"enemy_spell_effects"
)


# ============================================================
# STATUS
# ============================================================

var state: State = State.SLEEP
var player: Node2D = null
var current_target: Node2D = null

var hp: int = 0
var facing_right: bool = false

var target_in_wake_area: bool = false

var can_shoot: bool = true
var shot_done: bool = false

var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false
var can_take_damage: bool = false

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null


# ============================================================
# START
# ============================================================

func _ready() -> void:
	hp = max_health

	add_to_group("enemy")

	_setup_hit_flash_shader()

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D

	if not wake_area.body_entered.is_connected(
		_on_wake_area_body_entered
	):
		wake_area.body_entered.connect(
			_on_wake_area_body_entered
		)

	if not wake_area.body_exited.is_connected(
		_on_wake_area_body_exited
	):
		wake_area.body_exited.connect(
			_on_wake_area_body_exited
		)

	if not wake_area.area_entered.is_connected(
		_on_wake_area_area_entered
	):
		wake_area.area_entered.connect(
			_on_wake_area_area_entered
		)

	if not wake_area.area_exited.is_connected(
		_on_wake_area_area_exited
	):
		wake_area.area_exited.connect(
			_on_wake_area_area_exited
		)

	if not hurtbox.area_entered.is_connected(
		_on_hurtbox_area_entered
	):
		hurtbox.area_entered.connect(
			_on_hurtbox_area_entered
		)

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

	wake_area.monitoring = true
	wake_area.monitorable = true

	hurtbox.monitoring = true
	hurtbox.monitorable = true

	ground_ray.enabled = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_attack, false)
	_set_animation_loop(anim_hurt, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)

	_set_facing(-1.0)

	state = State.SLEEP
	can_take_damage = false
	can_shoot = true

	if _has_animation(anim_awake):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()
	else:
		can_take_damage = true
		_enter_idle()

	await get_tree().physics_frame

	_check_initial_wake_overlap()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	if dead:
		return

	_find_player_if_missing()
	_refresh_current_target()
	_check_player_attack_overlap()
	_apply_gravity(delta)

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

		State.IDLE:
			_process_archer()

		State.WALK:
			_process_archer()

		State.ATTACK:
			velocity.x = 0

		State.HURT:
			velocity.x = 0

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


# ============================================================
# ZIEL SUCHEN
# ============================================================

func _find_player_if_missing() -> void:
	if player != null and is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D


func _is_valid_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if not node is Node2D:
		return false

	if (
		not node.is_in_group(player_group)
		and not node.is_in_group(summon_group)
	):
		return false

	if "dead" in node and bool(node.dead):
		return false

	if not (node as Node2D).visible:
		return false

	return true


func _target_from_area(area: Area2D) -> Node2D:
	if area == null or not is_instance_valid(area):
		return null

	if _is_valid_target(area):
		return area as Node2D

	var parent := area.get_parent()

	if _is_valid_target(parent):
		return parent as Node2D

	return null


func _refresh_current_target() -> void:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	for body: Node2D in wake_area.get_overlapping_bodies():
		if not _is_valid_target(body):
			continue

		var distance := global_position.distance_to(
			body.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = body

	for area: Area2D in wake_area.get_overlapping_areas():
		var possible_target := _target_from_area(area)

		if not _is_valid_target(possible_target):
			continue

		var distance := global_position.distance_to(
			possible_target.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = possible_target

	current_target = nearest_target
	target_in_wake_area = current_target != null


func _target_is_available() -> bool:
	return _is_valid_target(current_target)


func _distance_to_target() -> float:
	if not _target_is_available():
		return INF

	return abs(
		current_target.global_position.x
		- global_position.x
	)


func _direction_to_target() -> float:
	if not _target_is_available():
		return 0.0

	return sign(
		current_target.global_position.x
		- global_position.x
	)


# ============================================================
# ARCHER-LOGIK
# ============================================================

func _process_archer() -> void:
	if not _target_is_available():
		_enter_idle()
		return

	if not target_in_wake_area:
		_enter_idle()
		return

	var distance: float = _distance_to_target()
	var direction_to_target: float = _direction_to_target()

	if direction_to_target == 0.0:
		_enter_idle()
		return

	# Wenn geschossen werden kann und das Ziel
	# in Reichweite ist, zum Ziel drehen und angreifen.
	if can_shoot and distance <= shoot_range:
		_set_facing(direction_to_target)
		_start_attack()
		return

	# Ziel ist zu nah:
	# Archer läuft in die entgegengesetzte Richtung
	# und schaut nun auch in die Laufrichtung.
	if distance < keep_distance:
		# Festgewurzelt (Ranken): darf sich nicht wegbewegen,
		# kann aber weiterhin schießen (siehe Zweig oben).
		if _is_rooted():
			_enter_idle()
			_set_facing(direction_to_target)
			return

		var retreat_direction: float = -direction_to_target

		if _has_ground_in_direction(retreat_direction):
			_walk(retreat_direction)
		else:
			_enter_idle()
			_set_facing(direction_to_target)

		return

	# Cooldown läuft oder Ziel ist außerhalb der Schussweite.
	_enter_idle()
	_set_facing(direction_to_target)


func _walk(direction: float) -> void:
	if direction == 0.0:
		_enter_idle()
		return

	state = State.WALK
	velocity.x = direction * move_speed * _get_speed_multiplier()

	# Wichtig:
	# Der Archer schaut jetzt in die Richtung,
	# in die er tatsächlich wegläuft.
	_set_facing(direction)

	_play_animation(anim_walk)


func _enter_idle() -> void:
	if dead:
		return

	state = State.IDLE
	velocity.x = 0

	_play_animation(anim_idle)


# ============================================================
# ANGRIFF
# ============================================================

func _start_attack() -> void:
	if dead:
		return

	if not can_shoot:
		return

	if state == State.ATTACK:
		return

	state = State.ATTACK

	can_shoot = false
	shot_done = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	_play_animation_force(anim_attack)


func _on_frame_changed() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	if sprite.animation != anim_attack:
		return

	if shot_done:
		return

	if sprite.frame >= shoot_frame:
		shot_done = true
		_shoot_arrow()


func _shoot_arrow() -> void:
	if dead:
		return

	if arrow_scene == null:
		push_warning(
			"Archer: Arrow Scene fehlt im Inspector."
		)
		return

	var tree := get_tree()

	if tree == null or tree.current_scene == null:
		return

	var arrow: Node = arrow_scene.instantiate()

	if arrow == null:
		return

	tree.current_scene.add_child(arrow)

	if arrow is Node2D:
		(arrow as Node2D).global_position = (
			shoot_point.global_position
		)

	var direction: float = (
		1.0 if facing_right else -1.0
	)

	if arrow.has_method("setup"):
		arrow.setup(
			direction,
			self
		)


func _finish_attack() -> void:
	if dead:
		return

	if not shot_done:
		shot_done = true
		_shoot_arrow()

	_enter_idle()

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(shoot_cooldown, 0.01)
	).timeout

	if dead:
		return

	can_shoot = true


# ============================================================
# ANIMATIONSENDE
# ============================================================

func _on_animation_finished() -> void:
	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
	):
		can_take_damage = true
		can_shoot = true

		_enter_idle()
		return

	if (
		state == State.ATTACK
		and sprite.animation == anim_attack
	):
		_finish_attack()
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		queue_free()


# ============================================================
# AUFWACHEN
# ============================================================

func _check_initial_wake_overlap() -> void:
	if state != State.SLEEP:
		return

	_refresh_current_target()

	if current_target != null:
		_wake_up_for_target(current_target)


func _on_wake_area_body_entered(body: Node) -> void:
	if not _is_valid_target(body):
		return

	if body.is_in_group(player_group):
		player = body as Node2D

	_refresh_current_target()
	_wake_up_for_target(body as Node2D)


func _on_wake_area_body_exited(body: Node) -> void:
	if not _is_valid_target(body):
		return

	_refresh_current_target()

	if state == State.IDLE or state == State.WALK:
		_process_archer()


func _on_wake_area_area_entered(area: Area2D) -> void:
	var target := _target_from_area(area)

	if not _is_valid_target(target):
		return

	_refresh_current_target()
	_wake_up_for_target(target)


func _on_wake_area_area_exited(area: Area2D) -> void:
	var target := _target_from_area(area)

	if target == null:
		return

	_refresh_current_target()

	if state == State.IDLE or state == State.WALK:
		_process_archer()


func _wake_up_for_target(target: Node2D) -> void:
	if not _is_valid_target(target):
		return

	current_target = target
	target_in_wake_area = true

	if state != State.SLEEP:
		return

	state = State.AWAKE

	can_take_damage = false
	can_shoot = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	if _has_animation(anim_awake):
		_play_animation_force(anim_awake)
	else:
		can_take_damage = true
		can_shoot = true
		_enter_idle()


# ============================================================
# SPIELERANGRIFFE
# ============================================================

func _on_hurtbox_area_entered(
	area: Area2D
) -> void:
	_try_take_player_attack_damage(area)


func _check_player_attack_overlap() -> void:
	if dead:
		return

	for area: Area2D in hurtbox.get_overlapping_areas():
		_try_take_player_attack_damage(area)


func _try_take_player_attack_damage(
	area: Area2D
) -> void:
	if dead:
		return

	if damage_hit_locked:
		return

	if not can_take_damage:
		return

	if invincible and state != State.ATTACK:
		return

	if not area.is_in_group(player_attack_group):
		return

	if not area.has_meta("active"):
		return

	if area.get_meta("active") != true:
		return

	var attack_damage: int = 1

	if area.has_meta("damage"):
		attack_damage = int(
			area.get_meta("damage")
		)

	_start_damage_hit_lock()
	take_damage(attack_damage)


func _start_damage_hit_lock() -> void:
	damage_hit_locked = true

	var tree := get_tree()

	if tree == null:
		damage_hit_locked = false
		return

	await tree.create_timer(
		max(damage_hit_lock_time, 0.01)
	).timeout

	if is_inside_tree():
		damage_hit_locked = false


# ============================================================
# SCHADEN
# ============================================================

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

	if invincible and state != State.ATTACK:
		return

	hp -= amount

	# Nutzer-Wunsch: Gegner-Sound-Bank (siehe Game/enemy_sound_
	# manager.gd) - Kategorie "skelette".
	EnemySoundManager.play(&"skelette", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	# Während des Schusses:
	# Schaden zählt, aber Schuss und Animation laufen weiter.
	if state == State.ATTACK:
		_flash_white()
		return

	_start_hurt()


func _start_hurt() -> void:
	if dead:
		return

	state = State.HURT
	invincible = true

	velocity.x = 0

	if _has_animation(anim_hurt):
		_play_animation_force(anim_hurt)

	var tree := get_tree()

	if tree == null:
		_finish_hurt()
		return

	await tree.create_timer(
		max(hurt_time, 0.01)
	).timeout

	if dead:
		return

	_finish_hurt()


func _finish_hurt() -> void:
	if dead:
		return

	invincible = false
	_enter_idle()


# ============================================================
# KOMPLETT WEISSER TREFFERBLITZ
# ============================================================

func _setup_hit_flash_shader() -> void:
	var flash_shader := Shader.new()

	flash_shader.code = """
shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	vec3 result = mix(
		source.rgb,
		vec3(1.0, 1.0, 1.0),
		flash_amount
	);

	COLOR = vec4(
		result,
		source.a
	);
}
"""

	hit_flash_material = ShaderMaterial.new()
	hit_flash_material.shader = flash_shader

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		0.0
	)

	sprite.material = hit_flash_material


func _flash_white() -> void:
	if hit_flash_material == null:
		return

	flash_generation += 1

	var this_generation: int = flash_generation

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		1.0
	)

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(attack_hit_flash_time, 0.01)
	).timeout

	if this_generation != flash_generation:
		return

	if hit_flash_material == null:
		return

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		0.0
	)


func _reset_hit_flash() -> void:
	flash_generation += 1

	if hit_flash_material != null:
		hit_flash_material.set_shader_parameter(
			"flash_amount",
			0.0
		)


# ============================================================
# TOD
# ============================================================

func _die() -> void:
	if dead:
		return

	dead = true
	state = State.DEATH

	# Nutzer-Wunsch: Gegner-Sound-Bank (siehe Game/enemy_sound_
	# manager.gd) - Kategorie "skelette".
	EnemySoundManager.play(&"skelette", &"death", global_position)

	# Zählt für die Statistik UND lässt (falls schon ein Skill-Pfad
	# gewählt wurde) einen kleinen Pixel von hier zum XP-Ring im HUD
	# fliegen, der ihn erst bei Ankunft ein Stück weiterfüllt - siehe
	# RunState.add_enemy_kill()/add_skill_path_xp().
	RunState.add_enemy_kill(1, global_position)

	can_take_damage = false
	can_shoot = false

	invincible = false
	damage_hit_locked = true
	shot_done = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	wake_area.monitoring = false
	hurtbox.monitoring = false

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	if _has_animation(anim_death):
		_play_animation_force(anim_death)
	else:
		queue_free()
		return

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(death_delete_time, 0.01)
	).timeout

	if is_instance_valid(self):
		queue_free()


# ============================================================
# SCHWERKRAFT UND RICHTUNG
# ============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0


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
	# Nur in Idle/Walk einfrieren - NICHT während Attack, Hurt,
	# Death oder Awake. Sonst könnte z.B. die Todesanimation
	# hängen bleiben und der Gegner nie entfernt werden.
	return state == State.IDLE or state == State.WALK


func _set_facing(direction: float) -> void:
	if direction > 0.0:
		facing_right = true
	elif direction < 0.0:
		facing_right = false
	else:
		return

	sprite.flip_h = facing_right

	if facing_right:
		shoot_point.position.x = abs(
			shoot_point_offset_x
		)
	else:
		shoot_point.position.x = -abs(
			shoot_point_offset_x
		)

	shoot_point.position.y = shoot_point_offset_y


func _has_ground_in_direction(
	direction: float
) -> bool:
	if direction == 0.0:
		return true

	ground_ray.position.x = (
		edge_check_x * sign(direction)
	)

	ground_ray.target_position = Vector2(
		0.0,
		edge_check_y
	)

	ground_ray.force_raycast_update()

	return ground_ray.is_colliding()


# ============================================================
# ANIMATIONSHILFEN
# ============================================================

func _has_animation(
	animation_name: StringName
) -> bool:
	if sprite == null:
		return false

	if sprite.sprite_frames == null:
		return false

	return sprite.sprite_frames.has_animation(
		animation_name
	)


func _play_animation(
	animation_name: StringName
) -> void:
	if not _has_animation(animation_name):
		return

	# Während des Festhaltens (Ranken) hält enemy_spell_effects.gd
	# die Animation exakt auf dem eingefrorenen Frame fest - hier
	# NICHT auf Idle/Walk umschalten, sonst geht der gehaltene
	# Frame verloren. _play_animation_force() (Attack/Hurt/Death/
	# Awake) ist davon bewusst NICHT betroffen.
	if _is_rooted():
		return

	if sprite.animation != animation_name:
		sprite.play(animation_name)


func _play_animation_force(
	animation_name: StringName
) -> void:
	if not _has_animation(animation_name):
		return

	sprite.play(animation_name)
	sprite.frame = 0


func _set_animation_loop(
	animation_name: StringName,
	should_loop: bool
) -> void:
	if not _has_animation(animation_name):
		return

	sprite.sprite_frames.set_animation_loop(
		animation_name,
		should_loop
	)
