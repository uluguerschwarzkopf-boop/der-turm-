extends CharacterBody2D

# Krieger Skellet (Gebiet 2).
# Basiert auf Mobs/Gebiet 2/schatten mutant/schatten_mutant.gd
# (gleiches Zustands-System: SLEEP -> AWAKE -> IDLE/WALK/ATTACK/
# HURT/DEATH, Liege-Animation, Spieler läuft durch ihn hindurch,
# Zurücksetzen ohne Ziel, Gold-Drop über den GoldDrop-Node).
#
# Nutzer-Wunsch: ZWEI Angriffe. Bei jedem Angriff wird zufällig
# Attacke 1 oder Attacke 2 gewählt (attack_1_chance). Jede Attacke
# hat ihre eigene Area2D ("AttackHitbox" / "AttackHitbox2"), eigene
# Animation, eigenen Schaden, Treffer-Frame, Cooldown und Reichweite.
#
# Die nächste Attacke wird VORHER ausgelost (siehe _roll_next_attack()),
# nicht erst im Moment des Angriffs: so läuft er so weit heran, wie
# GENAU diese Attacke reicht. Würde erst beim Angriff gelost, käme
# die Attacke mit der kürzeren Reichweite kaum noch vor (er würde
# schon bei der größeren Reichweite stehen bleiben) bzw. er würde
# ins Leere schlagen.


enum State {
	SLEEP,
	AWAKE,
	IDLE,
	WALK,
	TURN,
	ATTACK,
	HURT,
	DEATH,
	RESET
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2

@export var move_speed: float = 45.0
@export var gravity: float = 900.0

# Nutzer-Bestätigung: die Krieger-Sprites sind nach RECHTS gezeichnet.
# Falls sich das mal ändert, hier umschalten statt Code anzufassen.
@export var sprite_faces_right: bool = true


# ============================================================
# REICHWEITEN
# ============================================================

@export_group("Reichweiten")

# Innerhalb dieser Entfernung verfolgt er den Spieler.
@export var chase_range: float = 140.0


# ============================================================
# ANGRIFFSAUSWAHL
# ============================================================

@export_group("Angriffsauswahl")

# Nutzer-Wunsch: Wahrscheinlichkeit für Attacke 1 (0.5 = 50/50).
# 1.0 = immer Attacke 1, 0.0 = immer Attacke 2.
@export_range(0.0, 1.0, 0.05) var attack_1_chance: float = 0.5


# ============================================================
# ATTACKE 1
# ============================================================

@export_group("Attacke 1")

@export var anim_attack_1: StringName = &"Attack"
@export var attack_1_damage: int = 1
# Godot zählt Frames ab 0.
@export var attack_1_damage_frame: int = 7
# Wartezeit nach Attacke 1, bevor er wieder angreifen darf.
@export var attack_1_cooldown: float = 0.7
# Ab dieser Entfernung (nur X) startet er Attacke 1. Passend zur
# Form "Attack 1" in AttackHitbox einstellen.
@export var attack_1_range: float = 24.0


# ============================================================
# ATTACKE 2
# ============================================================

@export_group("Attacke 2")

@export var anim_attack_2: StringName = &"Attacke 2"
@export var attack_2_damage: int = 1
# Godot zählt Frames ab 0.
@export var attack_2_damage_frame: int = 3
# Wartezeit nach Attacke 2, bevor er wieder angreifen darf.
@export var attack_2_cooldown: float = 0.7
# Ab dieser Entfernung (nur X) startet er Attacke 2. Die Form
# "Attack 2" reicht weiter nach vorne (Stich), deshalb Standard
# etwas größer als bei Attacke 1.
@export var attack_2_range: float = 34.0


# ============================================================
# ANGRIFF ALLGEMEIN
# ============================================================

@export_group("Angriff allgemein")

# Sicherheitsnetz: so viele Sekunden zusätzlich zur rechnerischen
# Animationsdauer (Frames / FPS), danach wird der Angriff auch ohne
# animation_finished beendet - sonst könnte er für immer im
# Angriff hängen bleiben.
@export var attack_end_safety_margin: float = 0.25


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

@export var hurt_time: float = 0.35

# Trefferblitz: so lange bleibt er voll hell ...
@export var attack_hit_flash_time: float = 0.05
# ... und blendet dann so lange weich aus.
@export var hit_flash_fade_time: float = 0.16
# Farbe des Blitzes: kaltes, leicht milchiges Weiß.
@export var hit_flash_color: Color = Color(0.82, 0.9, 1.0)
# Gleicht die Abdunklung durch den dunklen Raum (CanvasModulate) aus.
# Ohne das wäre der Blitz nur ein dunkles Grau. Höher = greller.
@export var hit_flash_boost: float = 5.0

# Verhindert mehrfachen Schaden durch dieselbe aktive Hitbox.
@export var damage_hit_lock_time: float = 0.12


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

# Nutzer-Wunsch (wie bei der Spinne gros): die Leiche bleibt
# standardmäßig für immer auf dem letzten Frame der Tot-Animation
# liegen. Nur wenn hier eingeschaltet, wird sie zusätzlich
# "death_delete_time" Sekunden NACH Ende der Animation entfernt.
@export var delete_after_death: bool = false
@export var death_delete_time: float = 1.2


# ============================================================
# KOPF BEIM TOD
# ============================================================

@export_group("Kopf beim Tod")

# Nutzer-Wunsch: Stirbt er auf einer Plattform, fällt der Kopf mit
# Schwerkraft herunter und rollt ein kleines Stück weg. Vorher war
# der Kopf in die Tot-Animation gemalt und landete immer ca. 20 px
# daneben auf Fußhöhe - an einer Plattformkante also in der Luft.
# Die Tot-Animation nutzt deshalb "tot-Sheet ohne Kopf.png"; ab
# head_detach_frame übernimmt ein echter Schädel (fallender_kopf.gd).
@export var head_enabled: bool = true
@export var head_texture: Texture2D
# Ab diesem Frame der Tot-Animation fliegt der Kopf (Frame 2 = dort
# löst er sich im Original-Sheet).
@export var head_detach_frame: int = 2
# Startpunkt des Schädels relativ zu den Füßen (bei Blick nach rechts,
# wird beim Blick nach links gespiegelt).
@export var head_start_offset: Vector2 = Vector2(16.5, -22.5)
# Abwurf: x = nach vorne, y = negativ heißt nach oben.
@export var head_throw_velocity: Vector2 = Vector2(30.0, -25.0)
@export var head_gravity: float = 320.0
# 0 = kein Abprallen, 1 = springt genauso hoch zurück.
@export var head_bounce: float = 0.3
# Höher = rollt kürzer.
@export var head_roll_friction: float = 40.0
# Drehung in der Luft (Bogenmaß pro Sekunde).
@export var head_spin: float = 6.0


# ============================================================
# ZURÜCKSETZEN
# ============================================================

@export_group("Zurücksetzen")

# Nutzer-Wunsch: verliert er den Spieler aus den Augen (kein Ziel
# in Reichweite), legt er sich wieder hin - dafür spielt die
# Aufwach-Animation einmal rückwärts, bis er wieder in der
# Liege-Animation ist, und sein Leben wird komplett zurückgesetzt
# (siehe _start_reset() / _finish_reset()). 0 = sofort, ohne vorher
# noch auf der Stelle zu laufen/stehen.
@export var reset_after_idle_time: float = 0.0


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

@export var anim_sleep: StringName = &"rumliegen"
@export var anim_awake: StringName = &"aufwachen"
@export var anim_death: StringName = &"tot"
@export var anim_hurt: StringName = &"hittet"

# Es gibt (noch) keine eigene Steh-still-Animation - "laufen" wird
# auch fürs Stehenbleiben nach dem Aufwachen benutzt (Bewegung
# steht dann einfach still, während "laufen" weiter angezeigt wird).
# Falls noch eine eigene Idle-Animation dazukommt, hier einfach im
# Inspektor eintragen.
@export var anim_idle: StringName = &"laufen"
@export var anim_walk: StringName = &"laufen"

# Optionale Umdreh-Animation (wie beim Schatten Mutant). Der Krieger
# hat (noch) keine - dann dreht er sich einfach sofort um. Wird
# später eine gezeichnet, hier den Namen eintragen.
@export var anim_turn: StringName = &"umdrehen"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Verursacht Schaden am Spieler oder PlayerSummon.
# Attacke 1 -> AttackHitbox (Form "Attack 1"),
# Attacke 2 -> AttackHitbox2 (Form "Attack 2").
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_hitbox_2: Area2D = $AttackHitbox2

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt den Krieger durch Spieler oder PlayerSummon einmalig auf.
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

# Die als Nächstes geplante Attacke (1 oder 2), siehe
# _roll_next_attack(), und die gerade laufende Attacke.
var _next_attack: int = 1
var _current_attack: int = 1

# Wird bei jedem Angriffsstart erhöht. Der Sicherheits-Timer beendet
# den Angriff nur, wenn noch DERSELBE Angriff läuft.
var _attack_generation: int = 0

var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false
var can_take_damage: bool = false
var _head_spawned: bool = false

const FALLENDER_KOPF := preload("res://Mobs/Gebiet 2/Skellete/krieger skellet/fallender_kopf.gd")

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null
var _flash_tween: Tween = null

# Ziel-Blickrichtung, die nach Ende der "umdrehen"-Animation
# übernommen wird (siehe _turn_to_face()).
var _pending_facing_right: bool = false

# Wie lange (in Sekunden) schon kein Ziel in Reichweite war,
# während er im Idle steht (siehe _process_idle() / _start_reset()).
var _idle_no_target_time: float = 0.0


# ============================================================
# START
# ============================================================

func _ready() -> void:
	hp = max_health

	add_to_group("enemy")

	# Blickrichtung aus dem Editor übernehmen (flip_h am Sprite), damit
	# Flag, Sprite und beide Angriffs-Areas von Anfang an zusammenpassen.
	facing_right = sprite.flip_h != sprite_faces_right
	_apply_facing_visuals()

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

	attack_hitbox_2.monitoring = true
	attack_hitbox_2.monitorable = true

	ground_ray.enabled = true

	_roll_next_attack()

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_attack_1, false)
	_set_animation_loop(anim_attack_2, false)
	_set_animation_loop(anim_hurt, false)
	_set_animation_loop(anim_death, false)
	_set_animation_loop(anim_turn, false)

	_set_animation_loop(anim_sleep, true)
	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)

	state = State.SLEEP
	awakened = false

	can_take_damage = false
	can_attack = true

	if _has_animation(anim_sleep):
		sprite.play(anim_sleep)
	elif _has_animation(anim_awake):
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
	# Falls Idle oder Walk unerwartet keine Animation mehr
	# abspielen, wird der korrekte Zustand neu bestimmt.
	_recover_stopped_animation()

	match state:
		State.SLEEP:
			velocity.x = 0

		State.AWAKE:
			velocity.x = 0

		State.IDLE:
			_process_idle(delta)

		State.WALK:
			_process_walk()

		State.TURN:
			velocity.x = 0

		State.ATTACK:
			velocity.x = 0

		State.HURT:
			velocity.x = 0

		State.DEATH:
			velocity = Vector2.ZERO

		State.RESET:
			velocity.x = 0

	move_and_slide()


# ============================================================
# SPIELER-KOLLISION AUSSCHALTEN
# ============================================================

# Nutzer-Wunsch (wie beim Schatten Mutant): der Spieler soll durch den Krieger
# hindurchlaufen können, genau wie beim Bush Mob (siehe
# Mobs/Gebiet 1/Hidden MOBs/Bush Mob/bush_mob.gd). Fügt eine reine
# Kollisions-Ausnahme zwischen genau diesem Mob und dem Spieler
# hinzu, statt über die Physik-Layer zu gehen (die auch den
# Boden/Wände betreffen würden) - Angriffs-/Hurtbox-Erkennung läuft
# weiterhin normal über die Areas, nur die reine Körper-Kollision
# (das gegenseitige Wegschieben) wird ausgeschaltet.
func _apply_player_collision_exception() -> void:
	if player == null or not is_instance_valid(player):
		return

	if not (player is PhysicsBody2D):
		return

	add_collision_exception_with(player)


# ============================================================
# SICHERHEITSWIEDERHERSTELLUNG
# ============================================================

func _recover_stopped_animation() -> void:
	if not awakened:
		return

	if dead:
		return

	# Angriff, Hurt, Tod, Umdrehen und Zurücksetzen dürfen nicht
	# erzwungen wechseln.
	if (
		state == State.ATTACK
		or state == State.HURT
		or state == State.DEATH
		or state == State.TURN
		or state == State.RESET
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
		if _turn_to_face(direction):
			return

	if _try_start_attack_if_in_range(distance):
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

	_apply_player_collision_exception()


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
		attack_hitbox_2.collision_mask |= summon_hurtbox_layer
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

func _process_idle(delta: float) -> void:
	velocity.x = 0

	_refresh_target()

	if not _target_is_available():
		_play_animation(anim_idle)
		_accumulate_idle_reset_timer(delta)
		return

	var distance: float = _distance_to_target()

	if distance > chase_range:
		_play_animation(anim_idle)
		_accumulate_idle_reset_timer(delta)
		return

	_idle_no_target_time = 0.0

	_decide_next_state()


# Nutzer-Wunsch: legt sich nach einer Weile ohne Ziel in Reichweite
# wieder hin und setzt sich zurück (siehe _start_reset()).
func _accumulate_idle_reset_timer(delta: float) -> void:
	if not _has_animation(anim_awake):
		return

	_idle_no_target_time += delta

	if _idle_no_target_time >= reset_after_idle_time:
		_start_reset()


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

	if _turn_to_face(direction):
		return

	if _try_start_attack_if_in_range(distance):
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

	if _is_rooted():
		_enter_idle()
		return

	if not _has_ground_in_direction(direction):
		_enter_idle()
		return

	state = State.WALK

	if _turn_to_face(direction):
		return

	_play_animation(anim_walk)


# ============================================================
# ANGRIFF
# ============================================================

# Nutzer-Wunsch: zufällig Attacke 1 oder 2 (attack_1_chance). Wird
# beim Start und nach jedem Angriff neu ausgelost, damit er bis zur
# Reichweite GENAU dieser Attacke heranläuft (siehe Kopfkommentar).
func _roll_next_attack() -> void:
	if randf() < attack_1_chance:
		_next_attack = 1
	else:
		_next_attack = 2

	# Fehlt die Animation einer Attacke, immer die andere nehmen,
	# damit er nicht ohne sichtbaren Angriff hängen bleibt.
	if _next_attack == 1 and not _has_animation(anim_attack_1):
		_next_attack = 2
	elif _next_attack == 2 and not _has_animation(anim_attack_2):
		_next_attack = 1


func _get_attack_range(attack: int) -> float:
	return attack_1_range if attack == 1 else attack_2_range


func _get_attack_anim(attack: int) -> StringName:
	return anim_attack_1 if attack == 1 else anim_attack_2


func _get_attack_damage(attack: int) -> int:
	return attack_1_damage if attack == 1 else attack_2_damage


func _get_attack_damage_frame(attack: int) -> int:
	return (
		attack_1_damage_frame if attack == 1
		else attack_2_damage_frame
	)


func _get_attack_cooldown(attack: int) -> float:
	return attack_1_cooldown if attack == 1 else attack_2_cooldown


func _get_attack_hitbox(attack: int) -> Area2D:
	return attack_hitbox if attack == 1 else attack_hitbox_2


# "Ziel in Reichweite" hat immer Vorrang vor Laufen (gleiches Muster
# wie bei den anderen Mobs). Gibt true zurück, wenn ein Angriff
# gestartet wurde.
func _try_start_attack_if_in_range(distance: float) -> bool:
	if not can_attack:
		return false

	if distance > _get_attack_range(_next_attack):
		return false

	_start_attack()

	return state == State.ATTACK


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

	_current_attack = _next_attack
	_attack_generation += 1

	can_attack = false
	attack_damage_done = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	_play_animation_force(_get_attack_anim(_current_attack))

	_end_attack_by_timer_fallback(_attack_generation)


# Robustheit: Angriffsende nicht nur über animation_finished, sondern
# zusätzlich per Timer aus Frameanzahl / FPS absichern, sonst kann er
# dauerhaft im ATTACK-State hängen bleiben (und wäre dann auch nie
# mehr "hittet"-bar).
func _end_attack_by_timer_fallback(generation: int) -> void:
	var anim: StringName = _get_attack_anim(_current_attack)

	if not _has_animation(anim):
		_finish_attack()
		return

	var frame_count: int = sprite.sprite_frames.get_frame_count(anim)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim)
	var speed: float = abs(fps * sprite.speed_scale)

	if speed <= 0.0:
		speed = 1.0

	var duration: float = (
		float(frame_count) / speed
		+ max(attack_end_safety_margin, 0.0)
	)

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(max(duration, 0.05)).timeout

	if not is_inside_tree() or dead:
		return

	if state != State.ATTACK:
		return

	if generation != _attack_generation:
		return

	_finish_attack()


func _on_frame_changed() -> void:
	if dead:
		_check_head_detach()
		return

	if state != State.ATTACK:
		return

	if sprite.animation != _get_attack_anim(_current_attack):
		return

	if attack_damage_done:
		return

	if sprite.frame >= _get_attack_damage_frame(_current_attack):
		attack_damage_done = true
		_damage_target_if_inside()


# Schaden nur über die Area der GERADE laufenden Attacke.
func _damage_target_if_inside() -> void:
	if dead:
		return

	var hitbox: Area2D = _get_attack_hitbox(_current_attack)
	var hit_damage: int = _get_attack_damage(_current_attack)

	if hitbox == null:
		return

	for body: Node in hitbox.get_overlapping_bodies():
		if not _is_player_or_summon(body):
			continue

		if body.has_method("take_damage"):
			body.take_damage(
				hit_damage,
				global_position
			)

		return

	# Das PlayerSkeleton hat absichtlich collision_layer = 0.
	# Deshalb wird es über seine Hurtbox-Area getroffen.
	for area: Area2D in hitbox.get_overlapping_areas():
		var damage_target: Node = _get_player_or_summon_from_area(
			area
		)

		if damage_target == null:
			continue

		if damage_target.has_method("take_damage"):
			damage_target.take_damage(
				hit_damage,
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
# laufender Angriff hier durch den Parry-Skill des Spielers
# unterbrochen wurde (siehe skeleton.gd interrupt_current_action(),
# gleiches Muster).
func interrupt_current_action() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	_finish_attack()


func _finish_attack() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	attack_damage_done = true

	# Cooldown der gerade beendeten Attacke. Er gilt für BEIDE
	# Attacken, sonst würde er direkt nach Attacke 1 ohne Pause
	# Attacke 2 machen.
	var cooldown: float = _get_attack_cooldown(_current_attack)

	_roll_next_attack()

	# State verlassen, bevor neu entschieden wird (can_attack ist
	# noch false, also startet hier kein neuer Angriff).
	state = State.IDLE

	# Nach dem Angriff sofort neu entscheiden.
	_decide_next_state()

	var tree := get_tree()

	if tree == null:
		can_attack = true
		return

	await tree.create_timer(
		max(cooldown, 0.01)
	).timeout

	if dead or not is_inside_tree():
		return

	can_attack = true

	# Nach Ablauf des Cooldowns erneut prüfen - aber nicht mitten in
	# Hurt/Umdrehen/Zurücksetzen/Schlafen reinfunken.
	if state == State.IDLE or state == State.WALK:
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

		# Sofort Walk, Attack oder Idle bestimmen.
		_decide_next_state()
		return

	if (
		state == State.RESET
		and sprite.animation == anim_awake
	):
		_finish_reset()
		return

	if (
		state == State.TURN
		and sprite.animation == anim_turn
	):
		facing_right = _pending_facing_right
		_apply_facing_visuals()

		_decide_next_state()
		return

	if (
		state == State.ATTACK
		and sprite.animation == _get_attack_anim(_current_attack)
	):
		_finish_attack()
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		_finish_death()


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
		_apply_player_collision_exception()

	current_target = wake_target

	if awakened:
		return

	if state != State.SLEEP:
		return

	state = State.AWAKE

	# Der Krieger gilt ab jetzt dauerhaft als aktiviert.
	# Er kann aber während der Aufwach-Animation noch keinen
	# Schaden nehmen (Nutzer-Wunsch).
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
# ZURÜCKSETZEN (LEGT SICH WIEDER HIN)
# ============================================================

# Nutzer-Wunsch: hat er zu lange kein Ziel in Reichweite (siehe
# _accumulate_idle_reset_timer()), legt er sich wieder hin - dafür
# spielt die Aufwach-Animation einmal RÜCKWÄRTS (letztes Frame bis
# Frame 0), bis er wieder in der "rumliegen"-Pose ist.
func _start_reset() -> void:
	if dead:
		return

	if state != State.IDLE:
		return

	if not _has_animation(anim_awake):
		return

	state = State.RESET
	velocity.x = 0

	_idle_no_target_time = 0.0

	can_take_damage = false
	can_attack = false

	# custom_speed = -1.0 und from_end = true: die Animation startet
	# beim letzten Frame und läuft rückwärts bis Frame 0.
	sprite.play(anim_awake, -1.0, true)


func _finish_reset() -> void:
	if dead:
		return

	# Komplett zurücksetzen - Nutzer-Wunsch: "alle Leben wieder voll".
	hp = max_health

	state = State.SLEEP
	awakened = false

	can_take_damage = false
	can_attack = true

	attack_damage_done = false
	invincible = false
	damage_hit_locked = false

	_idle_no_target_time = 0.0

	_roll_next_attack()

	_reset_hit_flash()

	if _has_animation(anim_sleep):
		sprite.play(anim_sleep)
	else:
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()


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

	EnemySoundManager.play(&"skelette", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	# Trefferblitz bei jedem Treffer (vorher nur waehrend eines Angriffs).
	_flash_white()

	# Nutzer-Wunsch: die "hittet"-Animation soll NUR unterbrechen,
	# wenn gerade die Lauf-Animation läuft (Idle zeigt ja ebenfalls
	# "laufen", siehe anim_idle). Läuft gerade irgendeine andere
	# Animation (z.B. Attack), wird diese NICHT unterbrochen -
	# stattdessen blitzt er nur kurz weiß auf, die laufende
	# Animation spielt normal weiter.
	if sprite.animation != anim_walk and sprite.animation != anim_idle:
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
uniform vec3 flash_color = vec3(0.82, 0.9, 1.0);
uniform float flash_boost = 5.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	vec3 final_color = mix(
		source.rgb,
		flash_color * flash_boost,
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
	hit_flash_material.set_shader_parameter(
		"flash_color",
		Vector3(hit_flash_color.r, hit_flash_color.g, hit_flash_color.b)
	)
	hit_flash_material.set_shader_parameter(
		"flash_boost",
		hit_flash_boost
	)

	sprite.material = hit_flash_material


func _flash_white() -> void:
	if hit_flash_material == null:
		return

	flash_generation += 1

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	_set_flash_amount(1.0)

	_flash_tween = create_tween()
	_flash_tween.tween_interval(max(attack_hit_flash_time, 0.01))
	_flash_tween.tween_method(
		_set_flash_amount,
		1.0,
		0.0,
		max(hit_flash_fade_time, 0.01)
	)


func _set_flash_amount(value: float) -> void:
	if hit_flash_material == null:
		return

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		value
	)


func _reset_hit_flash() -> void:
	flash_generation += 1

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

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

	EnemySoundManager.play(&"skelette", &"death", global_position)

	# Zählt für die Statistik UND lässt (falls schon ein Skill-Pfad
	# gewählt wurde) einen kleinen Pixel von hier zum XP-Ring im HUD
	# fliegen (siehe RunState.add_enemy_kill()).
	RunState.add_enemy_kill(1, global_position)

	can_take_damage = false
	can_attack = false

	invincible = false
	damage_hit_locked = true
	attack_damage_done = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	# set_deferred statt direkt setzen: _die() kann mitten in einem
	# Physik-Signal laufen (z.B. hurtbox.area_entered), dort darf
	# monitoring nicht direkt geändert werden (Fehler "Function
	# blocked during in/out signal" - beim Schatten Mutant noch offen).
	wake_area.set_deferred("monitoring", false)
	hurtbox.set_deferred("monitoring", false)
	attack_hitbox.set_deferred("monitoring", false)
	attack_hitbox_2.set_deferred("monitoring", false)

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	if _has_animation(anim_death):
		_play_animation_force(anim_death)
	else:
		queue_free()


# Der letzte Frame der Tot-Animation zeigt die liegende Leiche -
# AnimatedSprite2D hält (Loop ist in _ready() ausgeschaltet)
# automatisch auf diesem letzten Frame an. Standardmäßig bleibt sie
# einfach so liegen (delete_after_death = false), wie bei der Spinne.
# _physics_process() bricht bei dead sofort ab, die Leiche bewegt
# sich also nicht mehr; alle Areas und die Körper-Kollision sind
# in _die() schon aus.
# Sobald die Tot-Animation den Frame erreicht, in dem sich der Kopf löst,
# übernimmt ein echter Schädel (siehe Exporte "Kopf beim Tod").
func _check_head_detach() -> void:
	if _head_spawned or not head_enabled or head_texture == null:
		return
	if sprite.animation != anim_death or sprite.frame < head_detach_frame:
		return
	_head_spawned = true

	# Die Grafik ist nach rechts gezeichnet, der Kopf fliegt nach vorne.
	var dir: float = 1.0 if facing_right else -1.0
	var head: Node2D = FALLENDER_KOPF.new()
	head.texture = head_texture
	head.flip_h = sprite.flip_h
	head.velocity = Vector2(head_throw_velocity.x * dir, head_throw_velocity.y)
	head.gravity = head_gravity
	head.bounce = head_bounce
	head.roll_friction = head_roll_friction
	head.spin = head_spin
	head.z_index = sprite.z_index
	add_child(head)
	# Eigene Position unabhängig von der Leiche.
	head.top_level = true
	head.global_position = global_position + Vector2(head_start_offset.x * dir, head_start_offset.y)


func _finish_death() -> void:
	if not delete_after_death:
		return

	var tree := get_tree()

	if tree == null:
		if is_instance_valid(self):
			queue_free()
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


# Wird von enemy_spell_effects.gd abgefragt (z.B. beim Festhalten
# durch Ranken), um zu wissen, ob die Animation gerade gefahrlos
# eingefroren werden darf. Während eines laufenden Angriffs NICHT -
# sonst könnte der Schaden-Frame nie erreicht werden.
func is_animation_freeze_safe() -> bool:
	return state == State.IDLE or state == State.WALK


func _set_facing(direction: float) -> void:
	if direction > 0.0:
		facing_right = true
	elif direction < 0.0:
		facing_right = false
	else:
		return

	_apply_facing_visuals()


# Spiegelt Sprite und BEIDE Angriffs-Areas passend zu facing_right.
func _apply_facing_visuals() -> void:
	# Nutzer-Bestätigung: Krieger-Sprites sind nach rechts gezeichnet
	# -> nur spiegeln, wenn er nach links schaut (über
	# sprite_faces_right umschaltbar).
	sprite.flip_h = facing_right != sprite_faces_right

	# Die Formen "Attack 1" / "Attack 2" sind im Editor nach rechts
	# (+X) gebaut -> nach links schauen = Area spiegeln.
	var hitbox_scale_x: float = 1.0 if facing_right else -1.0

	attack_hitbox.scale.x = hitbox_scale_x
	attack_hitbox_2.scale.x = hitbox_scale_x


# Wie _set_facing(), aber für Idle/Walk gedacht: falls sich die
# Blickrichtung dabei wirklich ändert und die "umdrehen"-Animation
# existiert (Nutzer-Wunsch), wird zuerst diese Animation einmal
# abgespielt. Sprite-Spiegelung (flip_h) und Hitbox-Spiegelung
# werden dann erst übernommen, wenn die Animation fertig ist (siehe
# _on_animation_finished()), damit die Umdreh-Animation in ihrer
# eigenen Zeichenrichtung gezeigt wird und nicht sofort schon
# mitgespiegelt wirkt. Gibt true zurück, wenn eine Umdreh-Animation
# gestartet wurde - der Aufrufer muss dann sofort abbrechen (return),
# damit er nicht direkt danach die laufen/idle-Animation drüberspielt.
func _turn_to_face(direction: float) -> bool:
	var new_facing_right: bool

	if direction > 0.0:
		new_facing_right = true
	elif direction < 0.0:
		new_facing_right = false
	else:
		return false

	if new_facing_right == facing_right:
		return false

	if not _should_play_turn_animation():
		_set_facing(direction)
		return false

	_pending_facing_right = new_facing_right
	state = State.TURN
	velocity.x = 0

	_play_animation_force(anim_turn)

	return true


func _should_play_turn_animation() -> bool:
	if dead:
		return false

	if not awakened:
		return false

	if state != State.IDLE and state != State.WALK:
		return false

	return _has_animation(anim_turn)


func _has_ground_in_direction(
	direction: float
) -> bool:
	if direction == 0.0:
		return true

	ground_ray.position = Vector2(
		edge_check_x * sign(direction),
		-edge_check_start_height
	)

	ground_ray.target_position = Vector2(
		0.0,
		edge_check_y + edge_check_start_height
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
