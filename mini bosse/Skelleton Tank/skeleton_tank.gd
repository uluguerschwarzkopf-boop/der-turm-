extends CharacterBody2D


signal miniboss_died
signal boss_started


enum State {
	SLEEP,
	AWAKE,
	IDLE,
	WALK,
	ATTACK,
	BLOCK,
	BLOCK_HIT,
	HURT,
	DEATH
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 12
@export var damage: int = 2

@export var move_speed: float = 28.0
@export var gravity: float = 900.0

@export_flags_2d_physics
var world_collision_mask: int = 1


# ============================================================
# REICHWEITEN
# ============================================================

@export_group("Reichweiten")

# Miniboss verfolgt den Spieler unbegrenzt weit (bis zum Rand
# des Raums / bis eine Wand blockiert) - kein chase_range mehr.
@export var attack_range: float = 55.0


# ============================================================
# ANGRIFF
# ============================================================

@export_group("Angriff")

@export var attack_cooldown: float = 0.9

@export var attack_damage_start_frame: int = 10
@export var attack_damage_end_frame: int = 12

@export var after_attack_idle_time: float = 0.55


# ============================================================
# BLOCK
# ============================================================

@export_group("Block")

# Nach so vielen Treffern von vorne beginnt der Block.
@export_range(1, 20, 1)
var front_hits_before_block: int = 2

# An:
# Während BLOCK und BLOCK_HIT wird überhaupt kein Schaden
# angenommen, egal aus welcher Richtung.
#
# Aus:
# Nur Treffer von vorne werden geblockt.
# Treffer von hinten verursachen weiterhin Schaden.
@export var block_all_damage: bool = true


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

# Verhindert mehrfachen Schaden durch dieselbe aktive Hitbox.
@export var hit_lock_time: float = 0.18

# Weißer Blitz bei einem Treffer während ATTACK.
@export var attack_hit_flash_time: float = 0.07


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

@export var anim_block: StringName = &"Block"
@export var anim_block_hit: StringName = &"Block_Hittet"

@export var anim_death: StringName = &"Death"

@export var anim_hurt_1: StringName = &"Hittet_1"
@export var anim_hurt_2: StringName = &"Hittet_2"
@export var anim_hurt_3: StringName = &"Hittet_3"

@export var anim_idle: StringName = &"Idle"
@export var anim_walk: StringName = &"Walk"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Diese Area verursacht Schaden am Spieler.
@onready var attack_hitbox: Area2D = $AttackHitbox

# Diese Area empfängt die Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

@onready var wake_area: Area2D = $WakeArea

@onready var shield_area: Area2D = (
	get_node_or_null("ShieldArea") as Area2D
)

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

var can_take_damage: bool = false
var can_attack: bool = true
var dead: bool = false

var attack_hit_done: bool = false
var hurt_index: int = 0

var hit_lock: bool = false
var front_hit_count: int = 0
var block_resume_frame: int = 0

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null


# ============================================================
# START
# ============================================================

func _ready() -> void:
	hp = max_health

	add_to_group("enemy")

	collision_mask = world_collision_mask

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

	if not wake_area.area_entered.is_connected(
		_on_wake_area_area_entered
	):
		wake_area.area_entered.connect(
			_on_wake_area_area_entered
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

	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true

	wake_area.monitoring = true
	wake_area.monitorable = true

	hurtbox.monitoring = true
	hurtbox.monitorable = true

	if shield_area != null:
		shield_area.monitoring = true
		shield_area.monitorable = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_attack, false)
	_set_animation_loop(anim_block, false)
	_set_animation_loop(anim_block_hit, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_hurt_1, false)
	_set_animation_loop(anim_hurt_2, false)
	_set_animation_loop(anim_hurt_3, false)

	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)

	state = State.SLEEP
	can_take_damage = false
	can_attack = true

	if _has_animation(anim_awake):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()

	await get_tree().physics_frame

	_check_initial_wake_overlap()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	if dead:
		return

	var old_x: float = global_position.x
	var boss_wants_to_move: bool = (
		state == State.WALK
	)

	_find_player_if_missing()
	_refresh_current_target()

	# Funktioniert jetzt auch während ATTACK.
	_check_player_attack()

	_apply_gravity(delta)

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

		State.IDLE:
			_chase_logic()

		State.WALK:
			_chase_logic()

		State.ATTACK:
			velocity.x = 0
			_check_attack_damage()

		State.BLOCK:
			velocity.x = 0

		State.BLOCK_HIT:
			velocity.x = 0

		State.HURT:
			velocity.x = 0

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()

	# Verhindert horizontales Verschieben während Animationen.
	if not boss_wants_to_move:
		global_position.x = old_x
		velocity.x = 0


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

	# Beim Summon darf nur die echte Hurtbox als Ziel gelten.
	if area.name != &"Hurtbox":
		return null

	var current: Node = area.get_parent()

	while current != null:
		if _is_valid_target(current):
			return current as Node2D

		current = current.get_parent()

	return null


func _find_summon() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(summon_group):
		if node is Node2D and _is_valid_target(node as Node2D):
			return node as Node2D

	return null


# Wichtig: Der Miniboss verfolgt sein Ziel über den GANZEN Raum,
# nicht nur innerhalb der WakeArea. Die WakeArea dient nur noch
# dazu, ihn initial aufzuwecken (siehe _on_wake_area_*) - danach
# wird hier direkt anhand von player/_find_summon() weiter
# verfolgt, unabhängig davon, ob das Ziel noch überlappt.
func _refresh_current_target() -> void:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	if _is_valid_target(player):
		nearest_target = player
		nearest_distance = global_position.distance_to(
			player.global_position
		)

	var summon: Node2D = _find_summon()

	if _is_valid_target(summon):
		var summon_distance: float = global_position.distance_to(
			summon.global_position
		)

		if summon_distance < nearest_distance:
			nearest_target = summon
			nearest_distance = summon_distance

	current_target = nearest_target


func _target_is_available() -> bool:
	return _is_valid_target(current_target)


# ============================================================
# VERFOLGUNG
# ============================================================

func _chase_logic() -> void:
	if not _target_is_available():
		_play_idle()
		return

	var dx: float = (
		current_target.global_position.x
		- global_position.x
	)

	var dist: float = abs(dx)
	var dir: float = sign(dx)

	if dir != 0:
		_set_facing(dir)

	if dist <= attack_range and can_attack:
		_start_attack()
		return

	# Festgewurzelt (Ranken): darf sich nicht wegbewegen,
	# kann aber weiterhin angreifen (siehe Zweig oben).
	if _is_rooted():
		_play_idle()
		return

	_walk(dir)


func _walk(dir: float) -> void:
	if dir == 0:
		_play_idle()
		return

	state = State.WALK
	velocity.x = dir * move_speed * _get_speed_multiplier()

	# Während des Festhaltens (Ranken) hält enemy_spell_effects.gd
	# die Animation exakt auf dem eingefrorenen Frame fest - hier
	# NICHT auf Walk umschalten, sonst geht der gehaltene Frame
	# verloren.
	if _is_rooted():
		return

	if sprite.animation != anim_walk:
		sprite.play(anim_walk)


func _play_idle() -> void:
	if dead:
		return

	state = State.IDLE
	velocity.x = 0

	# Siehe Kommentar in _walk() - beim Festhalten nicht auf
	# Idle umschalten, sonst geht der gehaltene Frame verloren.
	if _is_rooted():
		return

	if sprite.animation != anim_idle:
		sprite.play(anim_idle)


# ============================================================
# ANGRIFF
# ============================================================

func _start_attack() -> void:
	if dead:
		return

	if not can_attack:
		return

	if state == State.ATTACK:
		return

	state = State.ATTACK

	can_attack = false
	attack_hit_done = false

	velocity.x = 0

	_play_animation_force(anim_attack)


func _on_frame_changed() -> void:
	if state == State.ATTACK:
		_check_attack_damage()


func _check_attack_damage() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	if sprite.animation != anim_attack:
		return

	if attack_hit_done:
		return

	if sprite.frame < attack_damage_start_frame:
		return

	if sprite.frame > attack_damage_end_frame:
		return

	attack_hit_done = true

	# Spieler wird wie bisher über seinen PhysicsBody getroffen.
	for body: Node in attack_hitbox.get_overlapping_bodies():
		if not body.is_in_group(player_group):
			continue

		if body.has_method("take_damage"):
			body.take_damage(
				damage,
				global_position
			)

		return

	# Das Summon besitzt keinen normalen Body-Collision-Layer.
	# Deshalb wird ausschließlich seine echte Hurtbox getroffen.
	for area: Area2D in attack_hitbox.get_overlapping_areas():
		var summon_target: Node2D = _target_from_area(area)

		if summon_target == null:
			continue

		if not summon_target.is_in_group(summon_group):
			continue

		if summon_target.has_method("take_damage"):
			summon_target.take_damage(
				damage,
				global_position
			)

		return


# ============================================================
# BLOCK
# ============================================================

func _start_block() -> void:
	if dead:
		return

	state = State.BLOCK

	can_attack = false
	front_hit_count = 0

	velocity.x = 0

	_play_animation_force(anim_block)


func _block_hit() -> void:
	if state != State.BLOCK:
		return

	block_resume_frame = sprite.frame

	state = State.BLOCK_HIT
	velocity.x = 0

	_play_animation_force(anim_block_hit)


func _is_hit_blocked(
	attack_position: Vector2
) -> bool:
	if state != State.BLOCK and state != State.BLOCK_HIT:
		return false

	if block_all_damage:
		return true

	return _is_front(attack_position)


# ============================================================
# SPIELERANGRIFFE PRÜFEN
# ============================================================

func _check_player_attack() -> void:
	if dead:
		return

	if not can_take_damage:
		return

	if hit_lock:
		return

	for area: Area2D in hurtbox.get_overlapping_areas():
		_try_player_attack(area)

		if hit_lock:
			return


func _try_player_attack(area: Area2D) -> void:
	if dead:
		return

	if hit_lock:
		return

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

	var attack_position: Vector2 = area.global_position
	var front_hit: bool = _is_front(attack_position)

	hit_lock = true

	# ========================================================
	# WÄHREND EINES ANGRIFFS
	# ========================================================
	# Schaden wird genommen und der weiße Blitz abgespielt.
	# Der Angriff wird aber niemals durch Block oder Hurt
	# unterbrochen.
	if state == State.ATTACK:
		_apply_damage(
			amount,
			false
		)

		_release_hit_lock_later()
		return

	# ========================================================
	# BEREITS IM BLOCK
	# ========================================================

	if state == State.BLOCK:
		if _is_hit_blocked(attack_position):
			_block_hit()
		else:
			_apply_damage(
				amount,
				true
			)

		_release_hit_lock_later()
		return

	if state == State.BLOCK_HIT:
		if not _is_hit_blocked(attack_position):
			_apply_damage(
				amount,
				true
			)

		_release_hit_lock_later()
		return

	# ========================================================
	# NORMALER ZUSTAND
	# ========================================================

	if front_hit:
		front_hit_count += 1
	else:
		front_hit_count = 0

	# Der Treffer, der den Block auslöst,
	# verursacht keinen Schaden.
	if (
		front_hit
		and front_hit_count >= front_hits_before_block
	):
		_start_block()

		_release_hit_lock_later()
		return

	_apply_damage(
		amount,
		true
	)

	_release_hit_lock_later()


func _release_hit_lock_later() -> void:
	var tree := get_tree()

	if tree == null:
		hit_lock = false
		return

	await tree.create_timer(
		max(hit_lock_time, 0.01)
	).timeout

	if is_inside_tree():
		hit_lock = false


# ============================================================
# DIREKTER SCHADEN DURCH ZAUBER UND PROJEKTILE
# ============================================================

func take_damage(
	amount: int,
	from_position: Vector2 = Vector2.ZERO
) -> void:
	if dead:
		return

	if amount <= 0:
		return

	if not can_take_damage:
		return

	if hit_lock:
		return

	hit_lock = true

	# Bei vorhandener Trefferposition kann vorne/hinten
	# unterschieden werden.
	if state == State.BLOCK or state == State.BLOCK_HIT:
		var blocked: bool = block_all_damage

		if not blocked and from_position != Vector2.ZERO:
			blocked = _is_front(from_position)

		if blocked:
			if state == State.BLOCK:
				_block_hit()

			_release_hit_lock_later()
			return

	_apply_damage(
		amount,
		from_position != Vector2.ZERO
	)

	_release_hit_lock_later()


# ============================================================
# SCHADEN ANWENDEN
# ============================================================

func _apply_damage(
	amount: int,
	_allow_hurt_animation: bool
) -> void:
	if dead:
		return

	if amount <= 0:
		return

	hp -= amount

	# Nutzer-Wunsch: Gegner-Sound-Bank (siehe Game/enemy_sound_
	# manager.gd) - Kategorie "mini_boss".
	EnemySoundManager.play(&"mini_boss", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	# Während des Angriffs:
	# Schaden zählt, aber der Angriff wird nicht unterbrochen.
	if state == State.ATTACK:
		_flash_white()
		return

	# Bei einem Treffer von hinten während Block:
	# Block wird durch Hurt unterbrochen.
	if (
		state == State.BLOCK
		or state == State.BLOCK_HIT
	):
		if _allow_hurt_animation:
			_play_hurt()

		return

	_play_hurt()


# ============================================================
# HURT
# ============================================================

func _play_hurt() -> void:
	if dead:
		return

	state = State.HURT

	can_attack = false
	velocity.x = 0

	if hurt_index == 0:
		_play_animation_force(anim_hurt_1)
	elif hurt_index == 1:
		_play_animation_force(anim_hurt_2)
	else:
		_play_animation_force(anim_hurt_3)

	hurt_index += 1

	if hurt_index > 2:
		hurt_index = 0


# ============================================================
# KOMPLETT WEISSER TREFFERBLITZ
# ============================================================

func _setup_hit_flash_shader() -> void:
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
# ANIMATIONSENDE
# ============================================================

func _on_animation_finished() -> void:
	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
	):
		can_take_damage = true
		can_attack = true

		boss_started.emit()

		_play_idle()
		return

	if (
		state == State.ATTACK
		and sprite.animation == anim_attack
	):
		_play_idle()

		await get_tree().create_timer(
			max(after_attack_idle_time, 0.01)
		).timeout

		await get_tree().create_timer(
			max(attack_cooldown, 0.01)
		).timeout

		if dead:
			return

		can_attack = true
		state = State.WALK

		sprite.play(anim_walk)
		return

	if (
		state == State.BLOCK
		and sprite.animation == anim_block
	):
		can_attack = true
		_play_idle()
		return

	if (
		state == State.BLOCK_HIT
		and sprite.animation == anim_block_hit
	):
		state = State.BLOCK

		sprite.play(anim_block)

		var frame_count: int = (
			sprite.sprite_frames.get_frame_count(
				anim_block
			)
		)

		sprite.frame = clamp(
			block_resume_frame,
			0,
			max(frame_count - 1, 0)
		)

		return

	if state == State.HURT:
		if dead:
			return

		can_attack = true
		state = State.WALK

		sprite.play(anim_walk)
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		sprite.pause()

		sprite.frame = (
			sprite.sprite_frames.get_frame_count(
				anim_death
			)
			- 1
		)

		return


# ============================================================
# AUFWACHEN
# ============================================================

# Prüft NUR die tatsächliche physische Überlappung mit der
# WakeArea (nicht den ganzen Raum) - der Miniboss soll erst
# erwachen, wenn der Spieler wirklich in die Aufwach-Zone
# kommt, nicht schon beim Betreten des Raums.
func _find_target_in_wake_area() -> Node2D:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	for body: Node2D in wake_area.get_overlapping_bodies():
		if not _is_valid_target(body):
			continue

		var distance: float = global_position.distance_to(
			body.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = body

	for area: Area2D in wake_area.get_overlapping_areas():
		var possible_target: Node2D = _target_from_area(area)

		if not _is_valid_target(possible_target):
			continue

		var distance: float = global_position.distance_to(
			possible_target.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = possible_target

	return nearest_target


func _check_initial_wake_overlap() -> void:
	if state != State.SLEEP:
		return

	var target: Node2D = _find_target_in_wake_area()

	if target != null:
		current_target = target
		_wake_up_for_target(target)


func _on_wake_area_body_entered(body: Node) -> void:
	if not _is_valid_target(body):
		return

	if body.is_in_group(player_group):
		player = body as Node2D

	_refresh_current_target()

	var target := body as Node2D

	if current_target != null:
		target = current_target

	_wake_up_for_target(target)


func _on_wake_area_area_entered(area: Area2D) -> void:
	var target: Node2D = _target_from_area(area)

	if target == null:
		return

	_refresh_current_target()

	if current_target != null:
		target = current_target

	_wake_up_for_target(target)


func _wake_up_for_target(target: Node2D) -> void:
	if not _is_valid_target(target):
		return

	current_target = target

	if state != State.SLEEP:
		return

	state = State.AWAKE

	can_take_damage = false
	can_attack = false

	velocity.x = 0

	var direction: float = sign(
		current_target.global_position.x
		- global_position.x
	)

	if direction != 0.0:
		_set_facing(direction)

	_play_animation_force(anim_awake)


# ============================================================
# TOD
# ============================================================

func _die() -> void:
	if dead:
		return

	dead = true
	state = State.DEATH

	# Nutzer-Wunsch: Gegner-Sound-Bank (siehe Game/enemy_sound_
	# manager.gd) - Kategorie "mini_boss".
	EnemySoundManager.play(&"mini_boss", &"death", global_position)

	can_take_damage = false
	can_attack = false

	attack_hit_done = true
	hit_lock = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	attack_hitbox.monitoring = false
	wake_area.monitoring = false
	hurtbox.monitoring = false

	if shield_area != null:
		shield_area.monitoring = false

	collision_layer = 0
	collision_mask = 0

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	_play_animation_force(anim_death)

	miniboss_died.emit()


# ============================================================
# RICHTUNG
# ============================================================

func _is_front(position: Vector2) -> bool:
	if facing_right:
		return position.x > global_position.x

	return position.x < global_position.x


func _set_facing(dir: float) -> void:
	if dir > 0:
		facing_right = true
	elif dir < 0:
		facing_right = false
	else:
		return

	sprite.flip_h = facing_right

	attack_hitbox.scale.x = (
		-1.0 if facing_right else 1.0
	)

	if shield_area != null:
		shield_area.scale.x = (
			-1.0 if facing_right else 1.0
		)


# ============================================================
# SCHWERKRAFT
# ============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	elif velocity.y > 0:
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
	# Nur in Idle/Walk einfrieren - NICHT während Attack, Block,
	# Hurt, Death oder Awake.
	return state == State.IDLE or state == State.WALK


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


func _play_animation_force(
	animation_name: StringName
) -> void:
	if not _has_animation(animation_name):
		push_warning(
			"Miniboss: Animation fehlt: "
			+ str(animation_name)
		)
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
