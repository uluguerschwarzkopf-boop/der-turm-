extends Node

@export var damage: int = 1
@export var hitbox_active_time: float = 0.12

@export var attack_1_name: StringName = &"attack 1"
@export var attack_2_name: StringName = &"attack 2"

@export var attack_1_hit_delay: float = 0.22
@export var attack_2_hit_delay: float = 0.22

@export var hitstop_duration: float = 0.08
@export var hitstop_time_scale: float = 0.15

@onready var player: CharacterBody2D = $"../.."
@onready var sprite: AnimatedSprite2D = $"../../AnimatedSprite2D"
@onready var attack_hitbox: Area2D = $"../../Hitboxes/AttackHitbox"

# Sound-Bank (Nutzer-Wunsch) - siehe Player/player_sound_manager.gd für
# die komplette Erklärung. "sword_hit_1"/"sword_hit_2" werden unten in
# attack() genau beim Start des jeweiligen Schlags ausgelöst.
@onready var sound_manager: Node = get_node_or_null(
	"../SoundManager"
)

# Eigene Hitbox für den Ground-Slam-Skill (Pfad der Stärke) - siehe
# activate_ground_slam_hitbox() weiter unten, ausgelöst von Player/
# player.gd _on_ground_slam_frame_changed().
@onready var ground_slam_hitbox: Area2D = (
	$"../../Hitboxes/Ground slam Hitbox"
)

var attacking: bool = false
var combo_requested: bool = false
var cancel_requested: bool = false
var second_hit_cancel_window_open: bool = false
var hit_targets: Dictionary = {}


func _ready() -> void:
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = true
	attack_hitbox.add_to_group("player_attack")
	attack_hitbox.set_meta("active", false)
	attack_hitbox.set_meta("damage", damage)

	ground_slam_hitbox.monitoring = false
	ground_slam_hitbox.monitorable = true
	ground_slam_hitbox.add_to_group("player_attack")
	ground_slam_hitbox.set_meta("active", false)
	ground_slam_hitbox.set_meta("damage", damage)


func attack() -> void:
	if player.is_rolling:
		return

	if attacking:
		if sprite.animation == attack_1_name:
			combo_requested = true
		return

	attacking = true
	combo_requested = false
	cancel_requested = false
	second_hit_cancel_window_open = false

	# Der erste Schlag läuft immer vollständig durch,
	# er kann nicht abgebrochen werden.
	sprite.play(attack_1_name)
	_play_sound(&"sword_hit_1")

	await get_tree().create_timer(attack_1_hit_delay).timeout
	await _activate_hitbox()

	await sprite.animation_finished

	if combo_requested:
		combo_requested = false

		sprite.play(attack_2_name)
		_play_sound(&"sword_hit_2")

		# Kurzes Zeitfenster ganz am Anfang des zweiten Schlags:
		# Hier kann man ihn noch abbrechen (z.B. versehentlicher
		# Doppelklick). Sobald der Schaden-Frame aktiviert wird
		# (_activate_hitbox), ist kein Abbruch mehr möglich -
		# der Treffer muss dann durchgezogen werden.
		second_hit_cancel_window_open = true

		await get_tree().create_timer(attack_2_hit_delay).timeout

		second_hit_cancel_window_open = false

		if cancel_requested:
			_end_attack()
			return

		await _activate_hitbox()

		await sprite.animation_finished

	_end_attack()


# ============================================================
# DOPPELSCHLAG ABBRECHEN
# ============================================================

# Nur ganz am ANFANG des zweiten Schlags kann noch abgebrochen
# werden (bevor der Schaden-Frame aktiviert wird).
func can_cancel_second_hit() -> bool:
	return (
		attacking
		and second_hit_cancel_window_open
	)


func cancel_attack() -> void:
	if not can_cancel_second_hit():
		return

	cancel_requested = true

	attack_hitbox.monitoring = false
	attack_hitbox.set_meta("active", false)


func _end_attack() -> void:
	attacking = false
	combo_requested = false
	cancel_requested = false
	second_hit_cancel_window_open = false


# damage_override < 0 bedeutet "normaler Angriffsschaden" (siehe
# damage-Export oben). target_hitbox erlaubt, dieselbe Aktivierungs-
# Logik (Seiten-Ausrichtung, aktiv schalten, Treffer-Check, wieder
# deaktivieren) auch für eine ANDERE Hitbox als die normale
# AttackHitbox zu benutzen (z.B. die Ground-Slam-Hitbox, siehe
# activate_ground_slam_hitbox() weiter unten). Aktive Skills, die
# dieselbe Hitbox wie die normalen Angriffe benutzen sollen (z.B.
# Charge Attack, siehe Player/player.gd), rufen stattdessen
# activate_hitbox_with_damage() weiter unten mit ihrem eigenen
# Schadenswert auf.
func _activate_hitbox(
	damage_override: int = -1,
	target_hitbox: Area2D = null
) -> void:
	var hitbox: Area2D = (
		attack_hitbox if target_hitbox == null else target_hitbox
	)
	var applied_damage: int = (
		damage if damage_override < 0 else damage_override
	)

	hit_targets.clear()

	_update_hitbox_side(hitbox)

	hitbox.set_meta("active", true)
	hitbox.set_meta("damage", applied_damage)
	hitbox.monitoring = true

	await get_tree().physics_frame

	for body in hitbox.get_overlapping_bodies():
		_damage_body(body, applied_damage)

	await get_tree().create_timer(hitbox_active_time).timeout

	hitbox.monitoring = false
	hitbox.set_meta("active", false)


# Öffentlicher Zugriff für aktive Skills (Pfad der Stärke), die auf
# EXAKT derselben Hitbox wie die normalen Nahkampf-Angriffe treffen
# sollen, aber mit einem eigenen, festen Schadenswert - z.B. Charge
# Attack: 3 Schaden statt des normalen Angriffsschadens, siehe
# Player/player.gd _on_charge_attack_frame_changed().
func activate_hitbox_with_damage(skill_damage: int) -> void:
	await _activate_hitbox(skill_damage)


# Wie activate_hitbox_with_damage(), aber für die eigene Ground-Slam-
# Hitbox (nicht die normale AttackHitbox) - siehe Player/player.gd
# _on_ground_slam_frame_changed().
func activate_ground_slam_hitbox(skill_damage: int) -> void:
	await _activate_hitbox(skill_damage, ground_slam_hitbox)


func _update_hitbox_side(target_hitbox: Area2D = null) -> void:
	var hitbox: Area2D = (
		attack_hitbox if target_hitbox == null else target_hitbox
	)

	if player.facing_right:
		hitbox.scale.x = 1
	else:
		hitbox.scale.x = -1


func _damage_body(body: Node, damage_amount: int) -> void:
	if body == player:
		return

	if not body.has_method("take_damage"):
		return

	var id: int = int(body.get_instance_id())

	if hit_targets.has(id):
		return

	hit_targets[id] = true

	body.take_damage(damage_amount)
	_do_hitstop()

	# Vigor (Ressource für aktive Skills, Pfad der Stärke) lädt sich
	# durch Nahkampf-Treffer auf - siehe RunState.add_vigor()/
	# VIGOR_PER_MELEE_HIT. Mit freigeschaltetem passiven Skill
	# "Bloodlust" gibt's pro Treffer zusätzlich VIGOR_BLOODLUST_BONUS
	# oben drauf.
	if get_node_or_null("/root/RunState") != null:
		var vigor_gain: int = RunState.VIGOR_PER_MELEE_HIT

		if RunState.has_unlocked_skill(&"bloodlust"):
			vigor_gain += RunState.VIGOR_BLOODLUST_BONUS

		RunState.add_vigor(vigor_gain)


func _do_hitstop() -> void:
	var hitstop := get_tree().current_scene.get_node_or_null("HitStop")

	if hitstop != null and hitstop.has_method("do_hitstop"):
		hitstop.do_hitstop(hitstop_duration, hitstop_time_scale)


# Sound-Bank (Nutzer-Wunsch) - siehe Player/player_sound_manager.gd.
# Bewusst defensiv (kein Fehler, wenn SoundManager fehlt oder die id
# noch keine Audiodatei im Inspector hat).
func _play_sound(id: StringName) -> void:
	if sound_manager != null and sound_manager.has_method("play"):
		sound_manager.play(id)
