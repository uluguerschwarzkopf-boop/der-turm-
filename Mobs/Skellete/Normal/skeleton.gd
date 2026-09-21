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

# Innerhalb dieser Entfernung verfolgt das Skelett den Spieler.
@export var chase_range: float = 140.0

# Innerhalb dieser Entfernung greift es an.
@export var attack_range: float = 24.0


# ============================================================
# ANGRIFF
# ============================================================

@export_group("Angriff")

@export var attack_cooldown: float = 0.7

# Godot zählt Frames ab 0.
@export var attack_damage_frame: int = 5


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

@export var hurt_time: float = 0.35

# Weißer Trefferblitz während eines laufenden Angriffs.
@export var attack_hit_flash_time: float = 0.07

# Verhindert mehrfachen Schaden durch dieselbe aktive Hitbox.
@export var damage_hit_lock_time: float = 0.12


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

@export var death_delete_time: float = 1.2


# ============================================================
# ABGRUNDPRÜFUNG
# ============================================================

@export_group("Abgrundprüfung")

@export var edge_check_x: float = 10.0
@export var edge_check_y: float = 28.0

# Der Strahl darf NICHT auf Fußhöhe (y = 0) starten, weil er dort
# direkt in der Boden-Collision-Shape steckt - RayCast2D erkennt
# per Default keine Treffer, wenn der Startpunkt schon innerhalb
# einer Shape liegt (hit_from_inside = false). Deshalb starten wir
# etwas oberhalb der Füße (außerhalb des Bodens) und verlängern die
# Zielweite entsprechend, damit die effektive Reichweite unter den
# Füßen gleich bleibt.
@export var edge_check_start_height: float = 8.0


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

# Verursacht Schaden am Spieler oder PlayerSummon.
@onready var attack_hitbox: Area2D = $AttackHitbox

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt das Skelett durch Spieler oder PlayerSummon einmalig auf.
@onready var wake_area: Area2D = $WakeArea

@onready var ground_ray: RayCast2D = $RayCast2D

# Optional: Node "enemy_spell_effects" (Freeze/Root/Slow durch
# Spieler-Zauber). Kann null sein, falls die Gegner-Szene den
# Node (noch) nicht besitzt - dann wirken einfach keine Effekte.
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

var awakened: bool = false

var can_attack: bool = true
var attack_damage_done: bool = false

var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false
var can_take_damage: bool = false

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null

# Nur zum Testen: merkt sich den letzten Idle-Grund,
# damit wir nicht jeden Frame spammen, sondern nur bei
# Änderungen printen.
var _debug_last_idle_reason: String = ""
var _debug_last_ground_check_print_ms: int = 0


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

	if not wake_area.area_entered.is_connected(
		_on_wake_area_area_entered
	):
		wake_area.area_entered.connect(
			_on_wake_area_area_entered
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

	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true

	ground_ray.enabled = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_attack, false)
	_set_animation_loop(anim_hurt, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)

	state = State.SLEEP
	awakened = false

	can_take_damage = false
	can_attack = true

	if _has_animation(anim_awake):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()
	else:
		awakened = true
		can_take_damage = true
		can_attack = true
		_decide_next_state()

	# Prüft, ob Spieler oder PlayerSummon beim Szenenstart
	# bereits innerhalb der WakeArea stehen.
	await get_tree().physics_frame

	_check_initial_wake_overlap()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	if dead:
		return

	_find_player_if_missing()
	_refresh_target()
	_check_player_attack_overlap()
	_apply_gravity(delta)

	# Sicherheitsmechanismus:
	# Falls Awake, Idle oder Walk unerwartet keine Animation
	# mehr abspielen, wird der korrekte Zustand neu bestimmt.
	_recover_stopped_animation()

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

		State.IDLE:
			_process_idle()

		State.WALK:
			_process_walk()

		State.ATTACK:
			velocity.x = 0

		State.HURT:
			velocity.x = 0

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


# ============================================================
# SICHERHEITSWIEDERHERSTELLUNG
# ============================================================

func _recover_stopped_animation() -> void:
	if not awakened:
		return

	if dead:
		return

	# Angriff, Hurt und Tod dürfen nicht erzwungen wechseln.
	if (
		state == State.ATTACK
		or state == State.HURT
		or state == State.DEATH
	):
		return

	if sprite == null:
		return

	if sprite.is_playing():
		return

	_decide_next_state()


# ============================================================
# ZENTRALE ZUSTANDSENTSCHEIDUNG
# ============================================================

func _decide_next_state() -> void:
	if dead:
		return

	if not awakened:
		return

	_refresh_target()

	if not _target_is_available():
		_enter_idle()
		return

	var distance: float = _distance_to_target()
	var direction: float = _direction_to_target()

	if distance > chase_range:
		_enter_idle()
		return

	if direction != 0.0:
		_set_facing(direction)

	if distance <= attack_range and can_attack:
		_start_attack()
		return

	_enter_walk()


# ============================================================
# ZIELE SUCHEN
# ============================================================

func _find_player_if_missing() -> void:
	if player != null and is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D


func _refresh_target() -> void:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	if _node_is_available_target(player):
		nearest_target = player
		nearest_distance = abs(
			player.global_position.x - global_position.x
		)

	for summon_node: Node in get_tree().get_nodes_in_group(
		summon_group
	):
		if not summon_node is Node2D:
			continue

		var summon := summon_node as Node2D

		if not _node_is_available_target(summon):
			continue

		_include_summon_hurtbox_collision(summon)

		var summon_distance: float = abs(
			summon.global_position.x - global_position.x
		)

		if summon_distance < nearest_distance:
			nearest_distance = summon_distance
			nearest_target = summon

	current_target = nearest_target


func _include_summon_hurtbox_collision(
	summon: Node2D
) -> void:
	var summon_hurtbox := summon.get_node_or_null(
		"Hurtbox"
	) as Area2D

	if summon_hurtbox == null:
		return

	var summon_hurtbox_layer: int = (
		summon_hurtbox.collision_layer
	)

	if summon_hurtbox_layer != 0:
		attack_hitbox.collision_mask |= summon_hurtbox_layer
		wake_area.collision_mask |= summon_hurtbox_layer

	if (
		state == State.SLEEP
		and wake_area.overlaps_area(summon_hurtbox)
	):
		_wake_up_for_target(summon)


func _node_is_available_target(node: Node2D) -> bool:
	if node == null:
		return false

	if not is_instance_valid(node):
		return false

	if not node.visible:
		return false

	if "dead" in node and bool(node.dead):
		return false

	return true


func _target_is_available() -> bool:
	return _node_is_available_target(current_target)


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
# IDLE
# ============================================================

func _process_idle() -> void:
	velocity.x = 0

	_refresh_target()

	if not _target_is_available():
		_play_animation(anim_idle)
		return

	var distance: float = _distance_to_target()

	if distance > chase_range:
		_play_animation(anim_idle)
		return

	_decide_next_state()


func _enter_idle() -> void:
	if dead:
		return

	state = State.IDLE
	velocity.x = 0

	_play_animation(anim_idle)


# ============================================================
# LAUFEN
# ============================================================

func _process_walk() -> void:
	_refresh_target()

	if not _target_is_available():
		_enter_idle()
		return

	var distance: float = _distance_to_target()

	if distance > chase_range:
		_enter_idle()
		return

	var direction: float = _direction_to_target()

	if direction == 0.0:
		_enter_idle()
		return

	_set_facing(direction)

	if distance <= attack_range and can_attack:
		_start_attack()
		return

	if _is_rooted():
		_enter_idle()
		return

	if not _has_ground_in_direction(direction):
		_enter_idle()
		return

	state = State.WALK
	velocity.x = direction * move_speed * _get_speed_multiplier()

	_play_animation(anim_walk)


func _enter_walk() -> void:
	if dead:
		return

	if not awakened:
		return

	_refresh_target()

	if not _target_is_available():
		_debug_log_idle_reason("kein Ziel verfügbar (tot/unsichtbar/ungültig)")
		_enter_idle()
		return

	var distance: float = _distance_to_target()

	if distance > chase_range:
		_debug_log_idle_reason(
			"Distanz > chase_range (%.1f > %.1f)" % [distance, chase_range]
		)
		_enter_idle()
		return

	var direction: float = _direction_to_target()

	if direction == 0.0:
		_debug_log_idle_reason("Richtung ist 0 (exakt gleiche X-Position wie Ziel)")
		_enter_idle()
		return

	if _is_rooted():
		_debug_log_idle_reason("festgewurzelt (Ranken) - kann sich nicht bewegen")
		_enter_idle()
		return

	if not _has_ground_in_direction(direction):
		_debug_log_idle_reason(
			"kein Boden in Laufrichtung (Kante/Abgrund)"
		)
		_enter_idle()
		return

	_debug_log_idle_reason("")

	state = State.WALK

	_set_facing(direction)
	_play_animation(anim_walk)


# ============================================================
# DEBUG: WARUM BLEIBT DAS SKELETT IM IDLE?
# ============================================================

# Nur zum Testen. Printet nur, wenn sich der Grund ändert,
# damit die Konsole nicht mit hunderten gleichen Zeilen pro
# Sekunde vollläuft (falls das jeden Frame erneut passiert).
func _debug_log_idle_reason(reason: String) -> void:
	if reason == _debug_last_idle_reason:
		return

	_debug_last_idle_reason = reason

	if reason == "":
		print(
			"Skeleton DEBUG (", name, "): Grund behoben, läuft/greift jetzt normal an."
		)
		return

	print(
		"Skeleton DEBUG (", name, "): Kann nicht laufen -> ", reason
	)


# ============================================================
# ANGRIFF
# ============================================================

func _start_attack() -> void:
	if dead:
		return

	if not awakened:
		return

	if not can_attack:
		return

	if state == State.ATTACK:
		return

	state = State.ATTACK

	can_attack = false
	attack_damage_done = false

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

	if attack_damage_done:
		return

	if sprite.frame >= attack_damage_frame:
		attack_damage_done = true
		_damage_target_if_inside()


func _damage_target_if_inside() -> void:
	if dead:
		return

	for body: Node in attack_hitbox.get_overlapping_bodies():
		if not _is_player_or_summon(body):
			continue

		if body.has_method("take_damage"):
			body.take_damage(
				damage,
				global_position
			)

		return

	# Das PlayerSkeleton hat absichtlich collision_layer = 0.
	# Deshalb wird es über seine Hurtbox-Area getroffen.
	for area: Area2D in attack_hitbox.get_overlapping_areas():
		var damage_target: Node = _get_player_or_summon_from_area(
			area
		)

		if damage_target == null:
			continue

		if damage_target.has_method("take_damage"):
			damage_target.take_damage(
				damage,
				global_position
			)

		return


func _is_player_or_summon(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	return (
		node.is_in_group(player_group)
		or node.is_in_group(summon_group)
	)


func _get_player_or_summon_from_area(
	area: Area2D
) -> Node:
	if _is_player_or_summon(area):
		return area

	var parent: Node = area.get_parent()

	if _is_player_or_summon(parent):
		return parent

	return null


# Wird von Player/enemy_spell_effects.gd aufgerufen, sobald ein
# laufender Angriff hier durch den Parry-Skill des Spielers (siehe
# Player/player.gd _trigger_parry()) unterbrochen wurde - Nutzer-
# Wunsch: die Angriffsanimation soll dann NICHT einfach zu Ende
# laufen, sondern sofort zu dem übergehen, was als Nächstes ansteht
# (laufen, erneut angreifen, ...). Bricht den Angriff deshalb genau
# so ab, wie er auch normalerweise (über _on_animation_finished())
# enden würde - nur früher, ohne erst auf das tatsächliche Ende der
# (durch den Parry-Freeze unterbrochenen) Animation zu warten.
func interrupt_current_action() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	_finish_attack()


func _finish_attack() -> void:
	if dead:
		return

	attack_damage_done = true

	# Nach dem Angriff sofort neu entscheiden.
	_decide_next_state()

	var tree := get_tree()

	if tree == null:
		can_attack = true
		return

	await tree.create_timer(
		max(attack_cooldown, 0.01)
	).timeout

	if dead:
		return

	can_attack = true

	# Nach Ablauf des Cooldowns erneut prüfen.
	_decide_next_state()


# ============================================================
# ANIMATIONSENDE
# ============================================================

func _on_animation_finished() -> void:
	if dead and state != State.DEATH:
		return

	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
	):
		awakened = true
		can_take_damage = true
		can_attack = true

		# Nicht mehr pauschal Idle:
		# Sofort Walk, Attack oder Idle bestimmen.
		_decide_next_state()
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

	for body: Node in wake_area.get_overlapping_bodies():
		if _is_player_or_summon(body):
			_wake_up_for_target(body as Node2D)
			return

	for area: Area2D in wake_area.get_overlapping_areas():
		var wake_target: Node = _get_player_or_summon_from_area(
			area
		)

		if wake_target is Node2D:
			_wake_up_for_target(wake_target as Node2D)
			return


func _on_wake_area_body_entered(body: Node) -> void:
	if not _is_player_or_summon(body):
		return

	_wake_up_for_target(body as Node2D)


func _on_wake_area_area_entered(area: Area2D) -> void:
	var wake_target: Node = _get_player_or_summon_from_area(
		area
	)

	if not wake_target is Node2D:
		return

	_wake_up_for_target(wake_target as Node2D)


func _wake_up_for_target(wake_target: Node2D) -> void:
	if wake_target == null:
		return

	if wake_target.is_in_group(player_group):
		player = wake_target

	current_target = wake_target

	if awakened:
		return

	if state != State.SLEEP:
		return

	state = State.AWAKE

	# Das Skelett gilt ab jetzt dauerhaft als aktiviert.
	# Es kann aber während Awake noch keinen Schaden nehmen.
	awakened = true

	can_take_damage = false
	can_attack = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	if _has_animation(anim_awake):
		_play_animation_force(anim_awake)
	else:
		can_take_damage = true
		can_attack = true
		_decide_next_state()


# ============================================================
# SPIELERANGRIFFE ERKENNEN
# ============================================================

func _on_hurtbox_area_entered(
	area: Area2D
) -> void:
	_try_take_player_attack_damage(area)


func _check_player_attack_overlap() -> void:
	if dead:
		return

	if hurtbox == null:
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

	damage_hit_locked = true

	take_damage(attack_damage)

	_release_damage_hit_lock_later()


func _release_damage_hit_lock_later() -> void:
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

	# Während des Angriffs:
	# Schaden zählt, Angriff läuft vollständig weiter.
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

	awakened = true
	invincible = false
	can_take_damage = true

	# Nach Hurt ebenfalls nicht pauschal Idle.
	_decide_next_state()


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
	can_attack = false

	invincible = false
	damage_hit_locked = true
	attack_damage_done = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	wake_area.monitoring = false
	hurtbox.monitoring = false
	attack_hitbox.monitoring = false

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
# ZAUBER-EFFEKTE (FREEZE / ROOT / SLOW)
# ============================================================

func _is_rooted() -> bool:
	return spell_effects != null and spell_effects.is_rooted()


func _get_speed_multiplier() -> float:
	if spell_effects == null:
		return 1.0

	return spell_effects.get_speed_multiplier()


# Wird von enemy_spell_effects.gd abgefragt (z.B. beim
# Festhalten durch Ranken), um zu wissen, ob die Animation
# gerade gefahrlos eingefroren werden darf. Während eines
# laufenden Angriffs NICHT - sonst könnte der Schaden-Frame
# nie erreicht werden oder für immer aktiv bleiben.
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

	attack_hitbox.scale.x = (
		-1.0 if facing_right else 1.0
	)


func _has_ground_in_direction(
	direction: float
) -> bool:
	if direction == 0.0:
		return true

	# Start-Punkt: etwas ÜBER den Füßen, damit er außerhalb der
	# Boden-Collision-Shape liegt (siehe edge_check_start_height).
	ground_ray.position = Vector2(
		edge_check_x * sign(direction),
		-edge_check_start_height
	)

	# Zielweite entsprechend verlängert, damit der Strahl trotzdem
	# edge_check_y weit UNTER die Füße reicht.
	ground_ray.target_position = Vector2(
		0.0,
		edge_check_y + edge_check_start_height
	)

	ground_ray.force_raycast_update()

	var colliding: bool = ground_ray.is_colliding()

	if not colliding:
		var now_ms: int = Time.get_ticks_msec()

		if now_ms - _debug_last_ground_check_print_ms > 1000:
			_debug_last_ground_check_print_ms = now_ms

			print(
				"Skeleton DEBUG (", name, ") RayCast: KEIN Treffer",
				" | ray.position (lokal): ", ground_ray.position,
				" | ray.global_position: ", ground_ray.global_position,
				" | ray.target_position: ", ground_ray.target_position,
				" | ray.collision_mask: ", ground_ray.collision_mask,
				" | ray.enabled: ", ground_ray.enabled,
				" | ray.collide_with_bodies: ", ground_ray.collide_with_bodies,
				" | ray.collide_with_areas: ", ground_ray.collide_with_areas,
				" | skeleton.global_position: ", global_position
			)

	return colliding


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
	# Frame verloren. _play_animation_force() (Attack/Hurt/Death)
	# ist davon bewusst NICHT betroffen.
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
