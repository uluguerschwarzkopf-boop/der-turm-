extends CharacterBody2D


enum State {
	SLEEP,
	AWAKE,
	DASH,
	PAUSE,
	DEATH
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2
@export var contact_damage: int = 1

@export var gravity: float = 900.0


# ============================================================
# AUFWACHEN
# ============================================================

@export_group("Aufwachen")

# Wahrscheinlichkeit, dass der Busch überhaupt aufwacht, sobald
# der Spieler zum ERSTEN Mal in die WakeArea kommt. Dieser Wurf
# passiert nur EIN EINZIGES MAL im gesamten Leben dieses Mobs -
# schlägt er fehl, bleibt der Busch für immer ein "Blindgänger"
# (eingefroren auf Awake-Frame 1) und wacht nie wieder auf, auch
# wenn der Spieler später erneut in die WakeArea läuft.
@export_range(0.0, 1.0, 0.01) var wake_chance: float = 0.3


# ============================================================
# DASH
# ============================================================

@export_group("Dash")

@export var dash_speed: float = 220.0

# Die ersten X Frames (0-basiert, also 0 = Frame 1, 1 = Frame 2, ...)
# der Dash-Animation sind reiner Vorlauf: Der Busch bewegt sich noch
# NICHT und macht auch noch keinen Schaden. Erst danach beginnt die
# eigentliche Dash-Bewegung.
@export var dash_windup_frame_count: int = 2

# Bei genau diesem Frame der Dash-Animation wird die Attack Hitbox
# ausgewertet und macht einmalig (pro Dash) contact_damage Schaden,
# falls der Spieler gerade drin steht - siehe _on_frame_changed()
# und skeleton.gd (attack_damage_frame, gleiches Muster).
@export var dash_attack_frame: int = 6

# Wie viele Pixel der Busch pro Dash höchstens zurücklegt. Ist
# diese Strecke erreicht, bleibt er stehen (velocity.x = 0) -
# die Dash-Animation läuft aber ganz normal zu Ende, es wird
# also nicht mittendrin abgebrochen. Unabhängig von dash_speed
# einstellbar, damit man kurze, knackige Dashs machen kann, ohne
# gleich auch das Lauftempo während des Dashs ändern zu müssen.
@export var dash_distance: float = 40.0

# Ab diesem Frame (0-basiert) beginnt die Dash-Animation in der
# Luft zu loopen (Frames dash_loop_frame_start..dash_loop_frame_end),
# solange der Busch nicht auf dem Boden steht.
@export var dash_loop_frame_start: int = 9
@export var dash_loop_frame_end: int = 12

# Frame, ab dem die Dash-Animation ganz normal weiterläuft, sobald
# der Busch nach dem Loopen wieder Boden unter den Füßen hat.
@export var dash_loop_resume_frame: int = 13


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

# Weißer Trefferblitz, wenn der Busch Schaden nimmt. Unterbricht
# NICHT den laufenden Dash oder die Pause.
@export var hit_flash_time: float = 0.08


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

# Fallback-Löschzeit, falls das Ende der Death-Animation aus
# irgendeinem Grund nicht sauber erkannt wird (siehe skeleton.gd -
# selbes Sicherheitsmuster).
@export var death_delete_time: float = 1.2


# ============================================================
# GRUPPEN
# ============================================================

@export_group("Gruppen")

@export var player_group: StringName = &"player"
@export var player_attack_group: StringName = &"player_attack"


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var anim_awake: StringName = &"Awake"
@export var anim_dash: StringName = &"Dash"
@export var anim_pause: StringName = &"Pause"
@export var anim_death: StringName = &"Death"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Allgemeiner Körperkontakt: berührt der Spieler den Busch
# irgendwann während des Dashs (nach dem Vorlauf), gibt's Schaden -
# unabhängig vom Angriffs-Frame. Die passgenau geformte
# "Attack Hitbox" (unten) macht ZUSÄTZLICH ab dash_attack_frame
# Schaden (z.B. der Biss am Ende) - beide teilen sich aber den
# selben Ein-Treffer-pro-Dash-Flag (_dash_damage_dealt), es gibt
# also trotzdem nur 1 Treffer pro Dash, egal welche der beiden
# zuerst greift.
@onready var contact_hitbox: Area2D = $AttackHitbox

# Macht ab dash_attack_frame Schaden, falls der Spieler drin
# steht (siehe _check_dash_attack_hitbox()).
@onready var attack_hitbox: Area2D = $"Attack Hitbox"

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt den Busch (einmalig verwürfelt) durch den Spieler.
@onready var wake_area: Area2D = $WakeArea

# Verlässt der Spieler diesen (größeren) Bereich, setzt sich der
# Busch sofort zurück (volles Leben, Schlaf-Zustand).
@onready var chase_area: Area2D = $"Chase Area"

@onready var ground_ray: RayCast2D = $RayCast2D


# ============================================================
# STATUS
# ============================================================

var state: State = State.SLEEP
var player: Node2D = null

var hp: int = 0
var facing_right: bool = false

# Der 30%-Würfel wird nur EIN EINZIGES MAL im Leben des Mobs
# ausgeführt (siehe Kommentar bei wake_chance oben).
var _wake_roll_done: bool = false
var _wake_roll_passed: bool = false

var can_take_damage: bool = false

var _dash_damage_dealt: bool = false
var _dash_was_airborne: bool = false
var _dash_start_x: float = 0.0
var _dash_direction: float = 0.0
var _dash_distance_reached: bool = false

var dead: bool = false
var _death_pending_ground: bool = false

var damage_hit_locked: bool = false

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

	_apply_player_collision_exception()

	if not wake_area.body_entered.is_connected(
		_on_wake_area_body_entered
	):
		wake_area.body_entered.connect(
			_on_wake_area_body_entered
		)

	if not chase_area.body_exited.is_connected(
		_on_chase_area_body_exited
	):
		chase_area.body_exited.connect(
			_on_chase_area_body_exited
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

	chase_area.monitoring = true
	chase_area.monitorable = true

	hurtbox.monitoring = true
	hurtbox.monitorable = true

	contact_hitbox.monitoring = true
	contact_hitbox.monitorable = true

	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true

	ground_ray.enabled = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_dash, false)
	_set_animation_loop(anim_pause, false)
	_set_animation_loop(anim_death, false)

	_enter_sleep()

	# Prüft, ob der Spieler beim Szenenstart bereits innerhalb
	# der WakeArea steht.
	await get_tree().physics_frame

	_check_initial_wake_overlap()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)

	if dead:
		if _death_pending_ground:
			if is_on_floor():
				_death_pending_ground = false
				_play_death()
		else:
			# Die Death-Animation läuft bereits (oder wurde schon
			# gespielt) - die Collision-Shape ist jetzt deaktiviert
			# (siehe _play_death()), es gibt also keinen Boden mehr,
			# der die Fallgeschwindigkeit stoppen könnte. Ohne dieses
			# Zurücksetzen würde die Schwerkraft Frame für Frame
			# weiter aufaddieren und der Busch würde immer schneller
			# durch die Welt nach unten fallen/fliegen.
			velocity = Vector2.ZERO

		move_and_slide()
		return

	_find_player_if_missing()
	_check_player_attack_overlap()

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

		State.DASH:
			_process_dash()

		State.PAUSE:
			velocity.x = 0

		State.DEATH:
			velocity.x = 0

	move_and_slide()


func _find_player_if_missing() -> void:
	if player != null and is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D

	_apply_player_collision_exception()


# Der Busch soll den Spieler NIEMALS körperlich blockieren - ein
# Busch hält einen normalerweise nicht auf. Schaden kommt weiterhin
# ausschließlich über die AttackHitbox (Area2D), die davon nicht
# betroffen ist. Deshalb hier eine gezielte Kollisions-Ausnahme
# zwischen genau diesem Mob und dem Spieler, statt über die
# Physik-Layer zu gehen (die auch den Boden/Wände betreffen würden).
func _apply_player_collision_exception() -> void:
	if player == null or not is_instance_valid(player):
		return

	if not (player is PhysicsBody2D):
		return

	add_collision_exception_with(player)


# ============================================================
# SCHLAF / AUFWACHEN
# ============================================================

func _enter_sleep() -> void:
	state = State.SLEEP

	can_take_damage = false
	velocity = Vector2.ZERO

	_reset_hit_flash()

	if _has_animation(anim_awake):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()


func _check_initial_wake_overlap() -> void:
	if state != State.SLEEP:
		return

	for body: Node in wake_area.get_overlapping_bodies():
		if body.is_in_group(player_group):
			_on_wake_area_body_entered(body)
			return


func _on_wake_area_body_entered(body: Node) -> void:
	if dead:
		return

	if not body.is_in_group(player_group):
		return

	if state != State.SLEEP:
		return

	player = body as Node2D

	if not _wake_roll_done:
		_wake_roll_done = true
		_wake_roll_passed = randf() <= wake_chance

		if not _wake_roll_passed:
			# Für immer ein Blindgänger - bleibt auf Awake-Frame 1
			# eingefroren stehen, siehe Kommentar bei wake_chance.
			return

	if not _wake_roll_passed:
		return

	_wake_up()


func _wake_up() -> void:
	if dead:
		return

	state = State.AWAKE

	can_take_damage = false
	velocity.x = 0

	var direction: float = _direction_to_player()

	if direction != 0.0:
		_set_facing(direction)

	if _has_animation(anim_awake):
		_play_animation_force(anim_awake)
	else:
		can_take_damage = true
		_start_dash()


# ============================================================
# DASH
# ============================================================

func _start_dash() -> void:
	if dead:
		return

	state = State.DASH

	can_take_damage = true
	_dash_damage_dealt = false
	_dash_was_airborne = false
	_dash_distance_reached = false
	_dash_start_x = global_position.x

	var direction: float = _direction_to_player()

	if direction != 0.0:
		_set_facing(direction)

	_dash_direction = (
		1.0 if facing_right else -1.0
	)

	# Bewegung startet noch NICHT hier - erst ab
	# dash_windup_frame_count (siehe _update_dash_movement()).
	velocity.x = 0

	_play_animation_force(anim_dash)


func _process_dash() -> void:
	# Kehrt der Busch nach dem Luft-Loop wieder auf den Boden
	# zurück ODER dasht er gegen eine Wand, läuft die Animation
	# ab genau dem festgelegten Frame ganz normal weiter (siehe
	# _on_frame_changed()). Die Wand zählt hier bewusst genauso
	# wie der Boden, sonst könnte der Busch mitten in der Luft
	# vor einer Wand im 9-12-Loop hängen bleiben.
	if _dash_was_airborne and (is_on_floor() or is_on_wall()):
		_dash_was_airborne = false
		sprite.frame = dash_loop_resume_frame

	_update_dash_movement()
	_check_dash_distance()
	_check_dash_contact_damage()
	_check_dash_attack_hitbox()


func _update_dash_movement() -> void:
	if _dash_distance_reached:
		velocity.x = 0
		return

	# Die ersten dash_windup_frame_count Frames sind reiner Vorlauf
	# - der Busch steht noch still (siehe Kommentar bei
	# dash_windup_frame_count oben).
	if sprite.frame < dash_windup_frame_count:
		velocity.x = 0
		return

	velocity.x = _dash_direction * dash_speed


func _check_dash_distance() -> void:
	if _dash_distance_reached:
		return

	var traveled: float = absf(
		global_position.x - _dash_start_x
	)

	if traveled < dash_distance:
		return

	_dash_distance_reached = true

	# Nur die Bewegung stoppen - die Dash-Animation läuft trotzdem
	# ganz normal (inkl. Luft-Loop/Wand-Logik) bis zum Ende weiter.
	velocity.x = 0


# Ursprüngliche Anforderung: Berührt der Spieler den Busch
# IRGENDWANN während des Dashs (nach dem Vorlauf), kriegt er
# Schaden - unabhängig von der Attack Hitbox weiter unten. Läuft
# deshalb JEDEN Physik-Frame, nicht nur ab einem bestimmten Frame.
func _check_dash_contact_damage() -> void:
	if _dash_damage_dealt:
		return

	# Während des Vorlaufs (siehe dash_windup_frame_count) macht
	# der Busch noch generell keinen Schaden.
	if sprite.frame < dash_windup_frame_count:
		return

	for body: Node in contact_hitbox.get_overlapping_bodies():
		if not body.is_in_group(player_group):
			continue

		if body.has_method("take_damage"):
			body.take_damage(
				contact_damage,
				global_position
			)

		_dash_damage_dealt = true
		return


# Ab dash_attack_frame wird JEDEN Physik-Frame geprüft, ob der
# Spieler gerade in der Attack Hitbox steht - nicht nur genau in
# dem einen Frame-Moment. Der Busch bewegt sich während des Dashs
# ja weiter, deshalb würde eine reine Einmal-Prüfung GENAU bei
# Frame 6 den Treffer fast immer verpassen (Spieler war zu dem
# exakten Zeitpunkt noch nicht oder schon nicht mehr drin - er
# "dasht durch", ohne dass es zählt). Ab Frame 6 "aktiv" heißt
# also: von da an dauerhaft scharf, bis es einmal trifft.
func _check_dash_attack_hitbox() -> void:
	if _dash_damage_dealt:
		return

	if sprite.frame < dash_attack_frame:
		return

	_deal_dash_attack_damage()


func _deal_dash_attack_damage() -> void:
	if dead:
		return

	if _dash_damage_dealt:
		return

	for body: Node in attack_hitbox.get_overlapping_bodies():
		if not body.is_in_group(player_group):
			continue

		if body.has_method("take_damage"):
			body.take_damage(
				contact_damage,
				global_position
			)

		_dash_damage_dealt = true
		return


func _on_frame_changed() -> void:
	if dead:
		return

	if state != State.DASH:
		return

	if sprite.animation != anim_dash:
		return

	# In der Luft zwischen den festgelegten Frames loopen, bis
	# wieder Boden unter den Füßen ist (siehe _process_dash()).
	if (
		sprite.frame > dash_loop_frame_end
		and not is_on_floor()
	):
		_dash_was_airborne = true
		sprite.frame = dash_loop_frame_start


# ============================================================
# PAUSE
# ============================================================

func _start_pause() -> void:
	if dead:
		return

	state = State.PAUSE
	velocity.x = 0

	_play_animation_force(anim_pause)


# ============================================================
# ANIMATIONSENDE
# ============================================================

func _on_animation_finished() -> void:
	if dead:
		if state == State.DEATH and sprite.animation == anim_death:
			queue_free()

		return

	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
	):
		can_take_damage = true
		_start_dash()
		return

	if (
		state == State.DASH
		and sprite.animation == anim_dash
	):
		_start_pause()
		return

	if (
		state == State.PAUSE
		and sprite.animation == anim_pause
	):
		_start_dash()
		return


# ============================================================
# ZURÜCKSETZEN (SPIELER VERLÄSST DIE CHASE AREA)
# ============================================================

func _on_chase_area_body_exited(body: Node) -> void:
	if dead:
		return

	if not body.is_in_group(player_group):
		return

	hp = max_health

	_dash_damage_dealt = false
	_dash_was_airborne = false

	_enter_sleep()


# ============================================================
# SPIELERANGRIFFE ERKENNEN
# ============================================================

func _on_hurtbox_area_entered(area: Area2D) -> void:
	_try_take_player_attack_damage(area)


# Zusätzlich zum area_entered-Signal jeden Physik-Frame prüfen:
# Überlappt die Angriffs-Hitbox des Spielers die Hurtbox bereits,
# BEVOR sie "aktiv" (meta("active")) wird, feuert area_entered gar
# nicht erneut - ohne diese Dauerprüfung würden solche Treffer
# komplett verloren gehen (siehe skeleton.gd, selbes Muster).
func _check_player_attack_overlap() -> void:
	if dead:
		return

	if hurtbox == null:
		return

	for area: Area2D in hurtbox.get_overlapping_areas():
		_try_take_player_attack_damage(area)


func _try_take_player_attack_damage(area: Area2D) -> void:
	if dead:
		return

	if damage_hit_locked:
		return

	if not can_take_damage:
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

	await tree.create_timer(0.12).timeout

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

	hp -= amount

	if hp <= 0:
		_die()
		return

	# Nutzer-Wunsch: Schaden unterbricht weder Dash noch Pause -
	# nur ein weißer Blitz, sonst läuft alles unverändert weiter.
	_flash_white()


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
		max(hit_flash_time, 0.01)
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

	can_take_damage = false
	damage_hit_locked = true

	wake_area.monitoring = false
	chase_area.monitoring = false
	hurtbox.monitoring = false
	contact_hitbox.monitoring = false
	attack_hitbox.monitoring = false

	velocity.x = 0

	# Nutzer-Wunsch: Die Death-Animation darf nicht in der Luft
	# abgespielt werden - hängt der Busch gerade in der Luft
	# (z.B. mitten im Dash-Sprung), warten wir erst, bis er wieder
	# Boden unter den Füßen hat (siehe _physics_process()).
	if is_on_floor():
		_play_death()
	else:
		_death_pending_ground = true


func _play_death() -> void:
	state = State.DEATH

	# Zählt für die Statistik UND lässt (falls schon ein Skill-Pfad
	# gewählt wurde) einen kleinen Pixel von hier zum XP-Ring im HUD
	# fliegen - siehe RunState.add_enemy_kill()/add_skill_path_xp().
	RunState.add_enemy_kill(1, global_position)

	_reset_hit_flash()

	velocity = Vector2.ZERO

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	if not _has_animation(anim_death):
		queue_free()
		return

	_play_animation_force(anim_death)

	var tree := get_tree()

	if tree == null:
		return

	# Sicherheits-Fallback, falls animation_finished aus irgendeinem
	# Grund nicht feuert (siehe _on_animation_finished()). Wichtig:
	# NIEMALS kürzer als die tatsächliche Death-Animation selbst,
	# sonst wird queue_free() aufgerufen, bevor sie fertig
	# abgespielt hat, und sie bricht mittendrin ab. Deshalb hier
	# immer das Längere von death_delete_time und der echten
	# Animationsdauer (+ kleiner Puffer) nehmen.
	var death_anim_duration: float = _get_animation_duration(
		anim_death
	)

	var fallback_delete_time: float = max(
		death_delete_time,
		death_anim_duration + 0.2
	)

	await tree.create_timer(
		max(fallback_delete_time, 0.01)
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


func _direction_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0

	return sign(
		player.global_position.x - global_position.x
	)


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


# ============================================================
# ANIMATIONSHILFEN
# ============================================================

func _has_animation(animation_name: StringName) -> bool:
	if sprite == null:
		return false

	if sprite.sprite_frames == null:
		return false

	return sprite.sprite_frames.has_animation(
		animation_name
	)


# Tatsächliche Abspieldauer (in Sekunden) einer Animation, aus
# Frame-Anzahl und Abspielgeschwindigkeit in der SpriteFrames-
# Resource berechnet - siehe _play_death().
func _get_animation_duration(animation_name: StringName) -> float:
	if not _has_animation(animation_name):
		return 0.0

	var frame_count: int = sprite.sprite_frames.get_frame_count(
		animation_name
	)

	var speed: float = sprite.sprite_frames.get_animation_speed(
		animation_name
	)

	if speed <= 0.0:
		return 0.0

	return float(frame_count) / speed


func _play_animation_force(animation_name: StringName) -> void:
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
