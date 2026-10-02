extends CharacterBody2D

# Basiert auf Mobs/Gebiet 2/Ratte/ratte.gd (gleiches Zustands-System:
# SLEEP -> AWAKE -> IDLE/WALK/ATTACK/DEATH), aber als Fernkampf-Mob
# (Nutzer-Wunsch) mit drei Ergänzungen:
#
# 1. Der Angriff ("Attack"-Animation, Spuck-Pose) schießt ab einem
#    bestimmten Frame (siehe spit_frame) einen Spinnenwebenball
#    (spinnen_weben_ball.gd) vom ShootPoint aus in Blickrichtung,
#    statt wie bei den Nahkampf-Mobs direkt über eine Angriffs-Hitbox
#    zu treffen.
# 2. Statt der üblichen kurzen "hittet"-Reaktion springt sie bei
#    einem Treffer mit der "Wegspringen"-Animation vom Ziel weg -
#    ein echter Sprung mit Schwerkraft: Luft-Frames 3-6 (siehe
#    wegspring_airborne_start_frame/end_frame), die Frames davor/
#    danach sind Absprung/Landung und bewegen sie nicht. Danach
#    greift sie wieder normal an.
# 3. Die "aufwachen"-Animation zeigt sie, wie sie aus einem Ei
#    schlüpft - im letzten Frame ist laut Artwork nur noch die
#    zerbrochene Schale zu sehen (keine Spinne mehr gezeichnet).
#    Deshalb friert DIESE Instanz beim Ende der Animation dauerhaft
#    auf dem letzten Frame ein (reine Deko, keine Kollision/Logik
#    mehr) und spawnt am "Spinnenspawn"-Marker eine NEUE, bereits
#    wache Instanz derselben Szene - die ist ab dann die eigentlich
#    aktive Spinne (siehe _hatch_into_new_spider()).
# 4. Zusätzlicher zweiter Angriffstyp (Nutzer-Wunsch, siehe Export-
#    Gruppe "Nahkampfangriff"): ein Nahkampf-Biss mit eigener
#    "Nahkampf angriff"-Animation + eigener Angriffs-Hitbox
#    (Attack_Hitbox). Ob er auslöst, bestimmt nicht ein numerischer
#    Wert wie attack_range, sondern die FORM der "Nahkampfangriff
#    Area" (steht das Ziel darin, greift sie im Nahkampf an - hat
#    Vorrang vor dem Spucken). Eigener Cooldown, eigener Schaden,
#    einmalige Schadensprüfung exakt auf melee_active_frame.


enum State {
	SLEEP,
	AWAKE,
	IDLE,
	WALK,
	ATTACK,
	NAHKAMPF,
	WEGSPRINGEN,
	DEATH,
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2

@export var move_speed: float = 40.0
@export var gravity: float = 900.0


# ============================================================
# REICHWEITEN
# ============================================================

@export_group("Reichweiten")

# Innerhalb dieser Entfernung verfolgt die Spinne das Ziel.
@export var chase_range: float = 160.0

# Innerhalb dieser Entfernung bleibt sie stehen und spuckt.
@export var attack_range: float = 140.0


# ============================================================
# ANGRIFF
# ============================================================

@export_group("Angriff")

@export var attack_cooldown: float = 1.4

# Godot zählt Frames ab 0. Ab diesem Frame der "Attack"-Animation
# wird der Spinnenwebenball abgeschossen (einmalig).
@export var spit_frame: int = 4


# ============================================================
# PROJEKTIL
# ============================================================

@export_group("Projektil")

@export var web_ball_scene: PackedScene

@export var web_ball_speed: float = 160.0
@export var web_ball_damage: int = 1

# Nutzer-Wunsch: trifft der Ball den Spieler, wird er für diese Zeit
# (Sekunden) eingesponnen - komplett bewegungs- und angriffsunfähig
# (siehe Player/player.gd -> start_web_wrap() und
# spinnen_weben_ball.gd -> _hit_target()).
@export var web_wrap_duration: float = 2.0

@export var shoot_point_offset_x: float = 15.0
@export var shoot_point_offset_y: float = -10.0


# ============================================================
# NAHKAMPFANGRIFF
# ============================================================

@export_group("Nahkampfangriff")

# Nutzer-Wunsch: zweiter Angriffstyp - greift zusätzlich zum Spucken
# im Nahkampf an (eigene "Nahkampf angriff"-Animation + eigene
# Angriffs-Hitbox), wenn das Ziel innerhalb der "Nahkampfangriff Area"
# steht (siehe melee_range_area unten - die FORM dieser Area im
# Editor bestimmt die Reichweite, kein numerischer Wert wie bei
# attack_range). Hat Vorrang vor dem Spucken, wenn beides gleichzeitig
# zutrifft (siehe _try_start_attack_if_in_range()).
@export var melee_damage: int = 1

# Eigener Cooldown, unabhängig vom Spucken-Cooldown oben (Nutzer-
# Wunsch) - nach einem Biss kann sie also trotzdem sofort wieder
# spucken (und umgekehrt), falls beide Reichweiten passen.
@export var melee_attack_cooldown: float = 1.2

# Godot zählt Frames ab 0. Genau auf diesem Frame der "Nahkampf
# angriff"-Animation wird EINMALIG geprüft, ob das Ziel in der
# Angriffs-Hitbox steht (Nutzer-Wunsch: exakt dieser eine Frame, nicht
# durchgehend wie bei der Ratte).
@export var melee_active_frame: int = 5

@export var anim_melee_attack: StringName = &"Nahkampf angriff"


# ============================================================
# WEGSPRINGEN
# ============================================================

@export_group("Wegspringen")

# Senkrechter Sprung-Impuls, der einmalig gesetzt wird, sobald die
# Wegspringen-Animation den Luft-Start-Frame erreicht.
@export var wegspring_jump_speed: float = 180.0

# Waagrechte Geschwindigkeit vom Ziel weg, während sie in der Luft ist.
@export var wegspring_horizontal_speed: float = 90.0

# Frame-Bereich (inklusive), in dem die Spinne laut Animation in der
# Luft ist - nur in diesem Bereich wirken Sprung-Impuls und
# waagrechte Bewegung. Davor = Absprung, danach = Landung (beides
# bewegt sie nicht zusätzlich, die Animation läuft einfach durch).
@export var wegspring_airborne_start_frame: int = 3
@export var wegspring_airborne_end_frame: int = 6

# Verhindert, dass der Wegsprung sie über eine Kante schubst - nutzt
# dieselbe Abgrundprüfung wie beim normalen Laufen.
@export var wegspring_respect_edges: bool = true


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

# Trefferblitz: so lange bleibt sie voll hell ...
@export var attack_hit_flash_time: float = 0.07
# ... und blendet dann so lange weich aus.
@export var hit_flash_fade_time: float = 0.16
# Farbe des Blitzes: kaltes, leicht milchiges Weiß.
@export var hit_flash_color: Color = Color(0.82, 0.9, 1.0)
# Gleicht die Abdunklung durch den dunklen Raum (CanvasModulate) aus.
@export var hit_flash_boost: float = 5.0

# Verhindert mehrfachen Schaden durch dieselbe aktive Hitbox.
@export var damage_hit_lock_time: float = 0.12


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

# Nutzer-Wunsch (wie bei der Ratte): der Leichnam bleibt
# standardmäßig für immer auf dem letzten Frame der Tot-Animation
# liegen. Nur wenn hier eingeschaltet, wird sie zusätzlich
# "death_delete_time" Sekunden NACH Ende der Animation entfernt.
@export var delete_after_death: bool = false
@export var death_delete_time: float = 1.2


# ============================================================
# SCHLÜPFEN
# ============================================================

@export_group("Schlüpfen")

# Nutzer-Wunsch: die neue Spinne soll schon etwas VOR dem letzten
# Frame der aufwachen-Animation spawnen, nicht erst wenn sie komplett
# zu Ende gelaufen ist. 1 = ein Frame früher, 0 = exakt beim letzten
# Frame, usw. (siehe _on_frame_changed()).
@export var hatch_frame_offset: int = 1

# Pfad zur eigenen Szene - wird NICHT als PackedScene-Resource
# eingebunden (eine Szene darf sich nicht selbst als Resource
# referenzieren), sondern erst zur Laufzeit per load() geladen, wenn
# die Aufwach-Animation zu Ende ist (siehe _spawn_new_spider()).
@export var hatched_spider_scene_path: String = (
	"res://Mobs/Gebiet 2/Spinne gros/spinne_gros.tscn"
)


# ============================================================
# ABGRUNDPRÜFUNG
# ============================================================

@export_group("Abgrundprüfung")

@export var edge_check_x: float = 10.0
@export var edge_check_y: float = 28.0
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
@export var anim_attack: StringName = &"Attack"
@export var anim_wegspringen: StringName = &"Wegspringen"
@export var anim_death: StringName = &"tot"

# Es gibt keine eigene Steh-still-Animation - "laufen" wird auch
# fürs Stehenbleiben benutzt (wie bei der Ratte).
@export var anim_idle: StringName = &"laufen"
@export var anim_walk: StringName = &"laufen"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt die Spinne durch Spieler oder PlayerSummon einmalig auf.
@onready var wake_area: Area2D = $WakeArea

@onready var ground_ray: RayCast2D = $RayCast2D

# Abschusspunkt für den Spinnenwebenball.
@onready var shoot_point: Marker2D = $ShootPoint

# Nahkampfangriff (Nutzer-Wunsch): eigene Angriffs-Hitbox (Schaden,
# siehe _damage_melee_target_if_inside()) und eigene Area, deren FORM
# die Auslöse-Reichweite bestimmt (siehe _target_is_in_melee_range()).
@onready var melee_hitbox: Area2D = $Attack_Hitbox
@onready var melee_range_area: Area2D = $"Nahkampfangriff Area"

# Spawnpunkt für die neue, bereits wache Spinne nach dem Schlüpfen
# (siehe Export-Gruppe "Schlüpfen").
@onready var spinnenspawn: Marker2D = $Spinnenspawn

# Optional: Node "enemy_spell_effects" (Freeze/Root/Slow durch
# Spieler-Zauber). Kann null sein, falls die Gegner-Szene den Node
# (noch) nicht besitzt - dann wirken einfach keine Effekte.
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
var shot_done: bool = false

var can_melee_attack: bool = true
var melee_damage_done: bool = false

var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false
var can_take_damage: bool = false

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null
var _flash_tween: Tween = null

# Gesperrte Wegsprung-Richtung + ob der Sprung-Impuls für den
# aktuellen Wegsprung schon gesetzt wurde (siehe _process_wegspringen()).
var _wegspring_direction: float = 0.0
var _wegspring_jump_applied: bool = false

# Wird von _spawn_new_spider() VOR dem Hinzufügen zum Baum auf true
# gesetzt, wenn diese Instanz die "neu geschlüpfte" Spinne ist - dann
# überspringt _ready() die SLEEP/Aufwach-Phase komplett und ist
# sofort einsatzbereit (siehe unten).
var _spawned_already_awake: bool = false

# Wird true, sobald diese Instanz nach dem Schlüpfen zur reinen Deko
# (zerbrochene Eierschale) eingefroren ist - dann läuft keinerlei
# Logik mehr (siehe _physics_process()).
var _is_husk: bool = false


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

	# Nahkampfangriff (Nutzer-Wunsch): melee_range_area muss monitoren,
	# damit overlaps_body()/overlaps_area() in
	# _target_is_in_melee_range() überhaupt etwas liefert. melee_hitbox
	# genauso wie Ratte.attack_hitbox (monitoring UND monitorable true).
	melee_range_area.monitoring = true
	melee_range_area.monitorable = true

	melee_hitbox.monitoring = true
	melee_hitbox.monitorable = true

	ground_ray.enabled = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_attack, false)
	_set_animation_loop(anim_melee_attack, false)
	_set_animation_loop(anim_wegspringen, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_sleep, true)
	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)

	if _spawned_already_awake:
		# Direkt als bereits wache, einsatzbereite Spinne starten -
		# keine SLEEP/Schlüpf-Phase (siehe _spawn_new_spider()).
		state = State.IDLE
		awakened = true
		can_take_damage = true
		can_attack = true
		_decide_next_state()
		return

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

	# Prüft, ob Spieler oder PlayerSummon beim Szenenstart bereits
	# innerhalb der WakeArea stehen.
	await get_tree().physics_frame

	_check_initial_wake_overlap()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	if dead:
		return

	if _is_husk:
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

		State.ATTACK:
			velocity.x = 0

		State.NAHKAMPF:
			velocity.x = 0

		State.WEGSPRINGEN:
			_process_wegspringen()

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


# ============================================================
# SPIELER-KOLLISION AUSSCHALTEN
# ============================================================

# Der Spieler soll durch die Spinne hindurchlaufen können, genau wie
# bei den anderen Gebiet-2-Mobs (siehe ratte.gd/schatten_mutant.gd).
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

	# Angriff, Nahkampfangriff, Wegspringen und Tod dürfen nicht
	# erzwungen wechseln.
	if (
		state == State.ATTACK
		or state == State.NAHKAMPF
		or state == State.WEGSPRINGEN
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

	# Ziel innerhalb der Angriffsreichweite hat immer Vorrang - auch
	# bei Richtung 0.0 (Ziel genau auf der Spinne), siehe
	# _try_start_attack_if_in_range().
	if _try_start_attack_if_in_range():
		return

	var distance: float = _distance_to_target()
	var direction: float = _direction_to_target()

	if distance > chase_range:
		_enter_idle()
		return

	if direction != 0.0:
		_set_facing(direction)

	_enter_walk()


func _try_start_attack_if_in_range() -> bool:
	if dead:
		return false

	if not _target_is_available():
		return false

	# Nahkampf hat Vorrang vor dem Spucken, wenn das Ziel in BEIDEN
	# Reichweiten gleichzeitig steht (Nutzer-Wunsch: Nahkampf greift,
	# wenn das Ziel in der "Nahkampfangriff Area" steht).
	if _try_start_melee_attack_if_in_range():
		return true

	if not can_attack:
		return false

	# BUGFIX (Nutzer-Report: "macht nur einmal eine Nahkampfattacke"):
	# läuft gerade ein Nahkampfangriff (state == NAHKAMPF), darf hier
	# NICHT trotzdem _start_attack() aufgerufen werden - sonst würde das
	# die noch laufende Nahkampf-Animation mitten drin durch die Spuck-
	# Animation ersetzen, OHNE den Nahkampfangriff sauber abzubrechen
	# (can_melee_attack bliebe z.B. falsch gesetzt). Da hier `false`
	# zurückgegeben wird, fällt _decide_next_state() dann sauber auf
	# Verfolgen/Idle durch, bis der Nahkampfangriff von selbst fertig
	# ist (siehe _finish_melee_attack()).
	if state == State.NAHKAMPF:
		return false

	if _distance_to_target() > attack_range:
		return false

	_start_attack()
	return true


# Siehe Export-Gruppe "Nahkampfangriff" - melee_range_area (nicht ein
# numerischer Wert) bestimmt hier die Reichweite, deren FORM also
# direkt im Editor einstellbar ist.
func _try_start_melee_attack_if_in_range() -> bool:
	if dead:
		return false

	if not can_melee_attack:
		return false

	# Siehe Kommentar in _try_start_attack_if_in_range() oben - genau
	# dasselbe Problem, nur umgekehrt: ein laufender Spuck-Angriff darf
	# hier nicht mitten drin durch den Nahkampfangriff ersetzt werden.
	if state == State.ATTACK:
		return false

	if not _target_is_in_melee_range():
		return false

	_start_melee_attack()
	return true


func _target_is_in_melee_range() -> bool:
	if not _target_is_available():
		return false

	if melee_range_area != null:
		if (
			current_target is PhysicsBody2D
			and melee_range_area.overlaps_body(current_target)
		):
			return true

		# Das PlayerSkeleton hat absichtlich collision_layer = 0 (siehe
		# ratte.gd) - deshalb zusätzlich über die Hurtbox-Area prüfen.
		var target_hurtbox := current_target.get_node_or_null(
			"Hurtbox"
		) as Area2D

		if (
			target_hurtbox != null
			and melee_range_area.overlaps_area(target_hurtbox)
		):
			return true

	# Nutzer-Wunsch: steht der Spieler (weil er durch sie hindurchlaufen
	# kann) direkt in ihrer eigenen Hurtbox - auch außerhalb der
	# "Nahkampfangriff Area" -, soll trotzdem der Nahkampfangriff
	# auslösen, statt dass sie einfach nichts tut (siehe
	# _target_overlaps_hurtbox() weiter unten).
	if _target_overlaps_hurtbox():
		return true

	return false


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

		var summon_hurtbox := summon.get_node_or_null(
			"Hurtbox"
		) as Area2D

		if summon_hurtbox != null:
			var summon_hurtbox_layer: int = (
				summon_hurtbox.collision_layer
			)

			if summon_hurtbox_layer != 0:
				wake_area.collision_mask |= summon_hurtbox_layer

			if (
				state == State.SLEEP
				and wake_area.overlaps_area(summon_hurtbox)
			):
				_wake_up_for_target(summon)

		var summon_distance: float = abs(
			summon.global_position.x - global_position.x
		)

		if summon_distance < nearest_distance:
			nearest_distance = summon_distance
			nearest_target = summon

	current_target = nearest_target


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
		return

	if _try_start_attack_if_in_range():
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

	if _try_start_attack_if_in_range():
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

	if _try_start_attack_if_in_range():
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

	if _is_rooted():
		_enter_idle()
		return

	if not _has_ground_in_direction(direction):
		_enter_idle()
		return

	state = State.WALK
	velocity.x = direction * move_speed * _get_speed_multiplier()

	_play_animation(anim_walk)


# ============================================================
# ANGRIFF (SPUCKEN)
# ============================================================

func _start_attack() -> void:
	if dead:
		return

	if not awakened:
		return

	if not can_attack:
		return

	if state == State.ATTACK or state == State.NAHKAMPF:
		return

	state = State.ATTACK

	can_attack = false
	shot_done = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	_play_animation_force(anim_attack)


func _on_frame_changed() -> void:
	if dead:
		return

	if (
		state == State.ATTACK
		and sprite.animation == anim_attack
		and not shot_done
		and sprite.frame >= spit_frame
	):
		shot_done = true
		_shoot_web_ball()
		return

	# Nutzer-Wunsch: NUR auf genau melee_active_frame einmalig prüfen
	# (nicht durchgehend wie bei der Ratte), siehe
	# _damage_melee_target_if_inside().
	if (
		state == State.NAHKAMPF
		and sprite.animation == anim_melee_attack
		and not melee_damage_done
		and sprite.frame == melee_active_frame
	):
		_damage_melee_target_if_inside()
		return

	# Nutzer-Wunsch: die neue Spinne soll einen Frame früher spawnen,
	# statt erst zu warten, bis die komplette aufwachen-Animation
	# (inkl. letztem Frame) durchgelaufen ist - siehe hatch_frame_offset
	# und _hatch_into_new_spider(). _hatch_into_new_spider() ist gegen
	# Doppelaufruf abgesichert (_is_husk-Check), die gleiche Prüfung in
	# _on_animation_finished() bleibt als Sicherheitsnetz bestehen.
	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
		and not _is_husk
	):
		var frame_count: int = sprite.sprite_frames.get_frame_count(
			anim_awake
		)
		var trigger_frame: int = max(
			frame_count - 1 - hatch_frame_offset,
			0
		)

		if sprite.frame >= trigger_frame:
			_hatch_into_new_spider()


func _shoot_web_ball() -> void:
	if dead:
		return

	if web_ball_scene == null:
		push_warning(
			"Spinne Gros: Spinnenwebenball-Szene fehlt im Inspector "
			+ "(web_ball_scene)."
		)
		return

	var tree := get_tree()

	if tree == null or tree.current_scene == null:
		return

	var ball: Node = web_ball_scene.instantiate()

	if ball == null:
		return

	if "damage" in ball:
		ball.set("damage", web_ball_damage)

	if "speed" in ball:
		ball.set("speed", web_ball_speed)

	if "web_wrap_duration" in ball:
		ball.set("web_wrap_duration", web_wrap_duration)

	tree.current_scene.add_child(ball)

	if ball is Node2D:
		(ball as Node2D).global_position = (
			shoot_point.global_position
		)

	var direction: float = (
		1.0 if facing_right else -1.0
	)

	if ball.has_method("setup"):
		ball.setup(
			direction,
			self
		)


# Wird von Player/enemy_spell_effects.gd aufgerufen, sobald ein
# laufender Angriff hier durch den Parry-Skill des Spielers
# unterbrochen wurde (gleiches Muster wie bei ratte.gd).
func interrupt_current_action() -> void:
	if dead:
		return

	if state == State.ATTACK:
		_cancel_attack()
		_decide_next_state()
		return

	if state == State.NAHKAMPF:
		_cancel_melee_attack()
		_decide_next_state()
		return


# Bricht einen laufenden Angriff sauber ab (z.B. weil sie mitten im
# Spucken getroffen wurde und wegspringt, siehe take_damage()) -
# WICHTIG: can_attack muss hier sofort wieder true werden, sonst
# bliebe sie für immer gesperrt, weil der normale Cooldown-Timer in
# _finish_attack() dann nie läuft.
func _cancel_attack() -> void:
	can_attack = true
	shot_done = true


func _finish_attack() -> void:
	if dead:
		return

	if not shot_done:
		shot_done = true
		_shoot_web_ball()

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

	# BUGFIX (Nutzer-Report: "macht nur einmal eine Nahkampfattacke"):
	# ist inzwischen (während der Abklingzeit) schon ein Nahkampfangriff
	# aktiv geworden, darf dieser verspätete Aufruf ihn NICHT per
	# _enter_idle()/_enter_walk() mitten drin unterbrechen - einfach
	# can_attack aktualisiert lassen und nichts weiter tun, der
	# Nahkampfangriff entscheidet über seinen eigenen
	# _finish_melee_attack()-Zyklus selbst weiter.
	if state != State.NAHKAMPF:
		_decide_next_state()


# ============================================================
# NAHKAMPFANGRIFF
# ============================================================

func _start_melee_attack() -> void:
	if dead:
		return

	if not awakened:
		return

	if not can_melee_attack:
		return

	if state == State.NAHKAMPF or state == State.ATTACK:
		return

	state = State.NAHKAMPF

	can_melee_attack = false
	melee_damage_done = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	_play_animation_force(anim_melee_attack)


# Nutzer-Wunsch: NUR auf genau melee_active_frame wird einmalig
# geprüft (siehe _on_frame_changed()), nicht durchgehend wie beim
# Dash-Angriff der Ratte.
func _damage_melee_target_if_inside() -> void:
	if dead:
		return

	if melee_hitbox == null:
		return

	for body: Node in melee_hitbox.get_overlapping_bodies():
		if not _is_player_or_summon(body):
			continue

		if body.has_method("take_damage"):
			body.take_damage(
				melee_damage,
				global_position
			)

		melee_damage_done = true
		return

	# Das PlayerSkeleton hat absichtlich collision_layer = 0 (siehe
	# ratte.gd) - deshalb zusätzlich über die Hurtbox-Area prüfen.
	for area: Area2D in melee_hitbox.get_overlapping_areas():
		var damage_target: Node = _get_player_or_summon_from_area(
			area
		)

		if damage_target == null:
			continue

		if damage_target.has_method("take_damage"):
			damage_target.take_damage(
				melee_damage,
				global_position
			)

		melee_damage_done = true
		return


# Bricht einen laufenden Nahkampfangriff sauber ab (z.B. weil sie
# mitten im Biss getroffen wurde und wegspringt, siehe take_damage())
# - WICHTIG: can_melee_attack muss hier sofort wieder true werden,
# sonst bliebe sie für immer gesperrt, weil der normale Cooldown-
# Timer in _finish_melee_attack() dann nie läuft.
func _cancel_melee_attack() -> void:
	can_melee_attack = true
	melee_damage_done = true


func _finish_melee_attack() -> void:
	if dead:
		return

	melee_damage_done = true

	_decide_next_state()

	var tree := get_tree()

	if tree == null:
		can_melee_attack = true
		return

	await tree.create_timer(
		max(melee_attack_cooldown, 0.01)
	).timeout

	if dead:
		return

	can_melee_attack = true

	# Siehe Kommentar in _finish_attack() oben - genau dasselbe,
	# umgekehrt: ist inzwischen schon wieder ein Spuck-Angriff aktiv
	# geworden, nicht mitten drin unterbrechen.
	if state != State.ATTACK:
		_decide_next_state()


# ============================================================
# SPIELER STEHT IN DER HITBOX
# ============================================================

# Nutzer-Wunsch: der Spieler kann durch die Spinne hindurchlaufen
# (siehe _apply_player_collision_exception()) und sich deshalb genau
# in ihre Hurtbox stellen. Steht er dort - auch wenn er (noch) nicht
# in der "Nahkampfangriff Area" steht - soll sie trotzdem ganz normal
# ihren Nahkampfangriff machen, statt einfach nichts zu tun. Siehe
# Verwendung in _target_is_in_melee_range() oben.
func _target_overlaps_hurtbox() -> bool:
	if hurtbox == null:
		return false

	if not _target_is_available():
		return false

	if (
		current_target is PhysicsBody2D
		and hurtbox.overlaps_body(current_target)
	):
		return true

	# Das PlayerSkeleton hat absichtlich collision_layer = 0 (siehe
	# ratte.gd) - deshalb zusätzlich über die Hurtbox-Area prüfen.
	var target_hurtbox := current_target.get_node_or_null(
		"Hurtbox"
	) as Area2D

	if (
		target_hurtbox != null
		and hurtbox.overlaps_area(target_hurtbox)
	):
		return true

	return false


# Bricht einen gerade laufenden Angriff (Spucken ODER Nahkampf) sauber
# ab - wird von take_damage() benutzt, bevor sie wegspringt.
func _cancel_current_attack_if_any() -> void:
	if state == State.ATTACK:
		_cancel_attack()
	elif state == State.NAHKAMPF:
		_cancel_melee_attack()


# ============================================================
# WEGSPRINGEN (TREFFER-REAKTION)
# ============================================================

func _start_wegspring() -> void:
	if dead:
		return

	state = State.WEGSPRINGEN
	invincible = true

	velocity.x = 0
	_wegspring_jump_applied = false

	var direction_to_target: float = _direction_to_target()
	var retreat_direction: float

	if direction_to_target != 0.0:
		retreat_direction = -direction_to_target
	else:
		retreat_direction = -1.0 if facing_right else 1.0

	_wegspring_direction = retreat_direction

	_play_animation_force(anim_wegspringen)

	# BUGFIX (Nutzer-Report: "bekommt keinen Schaden mehr nachdem ich
	# sie 1 angreif"): vorher hing das Verlassen von WEGSPRINGEN (und
	# damit invincible = false) ausschließlich am animation_finished-
	# Signal in _on_animation_finished() - lief das aus irgendeinem
	# Grund nicht genau wie erwartet, blieb sie für immer in
	# WEGSPRINGEN + invincible = true stecken und hat nie wieder
	# Schaden genommen. Jetzt läuft der Ausstieg zusätzlich über einen
	# Timer (Animationslänge, siehe _get_wegspring_duration()) - genau
	# wie bei der Hurt-Animation der anderen Mobs. _finish_wegspring()
	# ist gegen Doppelaufruf abgesichert, das Signal bleibt also
	# zusätzlich als zweiter, sofortiger Auslöser bestehen.
	var tree := get_tree()

	if tree == null:
		_finish_wegspring()
		return

	await tree.create_timer(
		max(_get_wegspring_duration(), 0.01)
	).timeout

	if dead:
		return

	_finish_wegspring()


func _finish_wegspring() -> void:
	if dead:
		return

	if state != State.WEGSPRINGEN:
		return

	invincible = false

	_decide_next_state()


# Länge der Wegspringen-Animation in Sekunden (Frame-Anzahl / Fps aus
# der SpriteFrames-Resource) - dient als Sicherheitsnetz-Timer in
# _start_wegspring(), falls das animation_finished-Signal ausbleibt.
func _get_wegspring_duration() -> float:
	if sprite == null or sprite.sprite_frames == null:
		return 1.0

	if not sprite.sprite_frames.has_animation(anim_wegspringen):
		return 1.0

	var frame_count: int = sprite.sprite_frames.get_frame_count(
		anim_wegspringen
	)
	var fps: float = sprite.sprite_frames.get_animation_speed(
		anim_wegspringen
	)

	if fps <= 0.0:
		return 1.0

	return float(frame_count) / fps


func _process_wegspringen() -> void:
	if (
		sprite.frame < wegspring_airborne_start_frame
		or sprite.frame > wegspring_airborne_end_frame
	):
		velocity.x = 0
		return

	if not _wegspring_jump_applied:
		velocity.y = -wegspring_jump_speed
		_wegspring_jump_applied = true

	if _is_rooted():
		velocity.x = 0
		return

	if (
		wegspring_respect_edges
		and not _has_ground_in_direction(_wegspring_direction)
	):
		velocity.x = 0
		return

	velocity.x = (
		_wegspring_direction
		* wegspring_horizontal_speed
		* _get_speed_multiplier()
	)


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
		_hatch_into_new_spider()
		return

	if (
		state == State.ATTACK
		and sprite.animation == anim_attack
	):
		_finish_attack()
		return

	if (
		state == State.NAHKAMPF
		and sprite.animation == anim_melee_attack
	):
		_finish_melee_attack()
		return

	if (
		state == State.WEGSPRINGEN
		and sprite.animation == anim_wegspringen
	):
		# Normalerweise hier schon fertig (siehe _finish_wegspring()) -
		# der Timer in _start_wegspring() ist nur noch das
		# Sicherheitsnetz, falls dieses Signal mal ausbleibt.
		_finish_wegspring()
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		_finish_death()


# ============================================================
# AUFWACHEN / SCHLÜPFEN
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

	# Die Spinne gilt ab jetzt dauerhaft als aktiviert. Sie kann aber
	# während der Schlüpf-Animation noch keinen Schaden nehmen.
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
		# Kein Schlüpf-Artwork vorhanden - keine neue Instanz spawnen,
		# einfach direkt selbst aktiv werden.
		can_take_damage = true
		can_attack = true
		_decide_next_state()


# Nutzer-Wunsch: Die "aufwachen"-Animation zeigt die Spinne, wie sie
# aus einem Ei schlüpft - im letzten Frame ist laut Artwork nur noch
# die zerbrochene Schale zu sehen (die Spinne selbst ist dort bewusst
# nicht mehr gezeichnet). AnimatedSprite2D hält automatisch auf
# diesem letzten Frame an (loopt nicht), DIESE Instanz wird also ganz
# von selbst zur Deko - hier wird nur noch ihre Logik/Kollision
# abgeschaltet und am Spinnenspawn-Marker die neue, aktive Spinne
# gespawnt.
func _hatch_into_new_spider() -> void:
	# Gegen Doppelaufruf abgesichert - wird sowohl per Frame-Trigger
	# (siehe _on_frame_changed(), hatch_frame_offset) als auch als
	# Sicherheitsnetz von _on_animation_finished() aufgerufen.
	if _is_husk:
		return

	_is_husk = true

	can_take_damage = false
	can_attack = false
	can_melee_attack = false

	wake_area.monitoring = false
	hurtbox.monitoring = false
	melee_range_area.monitoring = false
	melee_hitbox.monitoring = false

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	_spawn_new_spider()


func _spawn_new_spider() -> void:
	var tree := get_tree()

	if tree == null or tree.current_scene == null:
		return

	if hatched_spider_scene_path.is_empty():
		push_warning(
			"Spinne Gros: hatched_spider_scene_path ist leer."
		)
		return

	if not ResourceLoader.exists(hatched_spider_scene_path):
		push_warning(
			"Spinne Gros: Szene für die geschlüpfte Spinne fehlt: "
			+ hatched_spider_scene_path
		)
		return

	var scene: PackedScene = load(
		hatched_spider_scene_path
	) as PackedScene

	if scene == null:
		return

	var new_spider: Node = scene.instantiate()

	if new_spider == null:
		return

	if "_spawned_already_awake" in new_spider:
		new_spider.set("_spawned_already_awake", true)

	var spawn_position: Vector2 = global_position

	if spinnenspawn != null and is_instance_valid(spinnenspawn):
		spawn_position = spinnenspawn.global_position

	if new_spider is Node2D:
		(new_spider as Node2D).global_position = spawn_position

	tree.current_scene.add_child(new_spider)


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

	if (
		invincible
		and state != State.ATTACK
		and state != State.NAHKAMPF
	):
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


# ============================================================
# SCHADEN
# ============================================================

func take_damage(
	amount: int,
	_from_position: Vector2 = Vector2.ZERO
) -> void:
	if dead:
		return

	if _is_husk:
		return

	if amount <= 0:
		return

	if not can_take_damage:
		return

	if (
		invincible
		and state != State.ATTACK
		and state != State.NAHKAMPF
	):
		return

	hp -= amount

	EnemySoundManager.play(&"skelette", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	# Trefferblitz bei jedem Treffer (auch während eines Angriffs).
	_flash_white()

	# Nutzer-Wunsch: statt der üblichen "hittet"-Animation springt sie
	# bei jedem Treffer weg - auch mitten im Spucken oder im Nahkampf-
	# Biss (der jeweilige Angriff wird dann sauber abgebrochen, siehe
	# _cancel_current_attack_if_any() bei "ZU NAH DRAN" weiter unten).
	_cancel_current_attack_if_any()

	_start_wegspring()


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

	RunState.add_enemy_kill(1, global_position)

	can_take_damage = false
	can_attack = false

	invincible = false
	damage_hit_locked = true
	shot_done = true
	melee_damage_done = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	wake_area.monitoring = false
	hurtbox.monitoring = false
	melee_range_area.monitoring = false
	melee_hitbox.monitoring = false

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	if _has_animation(anim_death):
		_play_animation_force(anim_death)
	else:
		queue_free()


# Der letzte Frame der Tot-Animation zeigt den liegenden Leichnam -
# AnimatedSprite2D hält (weil die Animation nicht loopt) automatisch
# auf diesem letzten Frame an. Standardmäßig bleibt sie einfach so
# liegen (delete_after_death = false) - nur wenn eingeschaltet, wird
# sie "death_delete_time" Sekunden NACH Ende der Animation entfernt.
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


# Wird von enemy_spell_effects.gd abgefragt, um zu wissen, ob die
# Animation gerade gefahrlos eingefroren werden darf.
func is_animation_freeze_safe() -> bool:
	return state == State.IDLE or state == State.WALK


func _set_facing(direction: float) -> void:
	if direction > 0.0:
		facing_right = true
	elif direction < 0.0:
		facing_right = false
	else:
		return

	# ANNAHME (bitte in Godot testen): wie bei Ratte/Schatten Mutant
	# gehe ich davon aus, dass die Sprites nach rechts gezeichnet sind
	# - deshalb hier NICHT spiegeln wenn sie nach rechts schaut,
	# SPIEGELN wenn sie nach links schaut. Falls es verkehrt rum ist,
	# einfach Bescheid geben, dann wird's getauscht.
	sprite.flip_h = not facing_right

	if facing_right:
		shoot_point.position.x = abs(shoot_point_offset_x)
	else:
		shoot_point.position.x = -abs(shoot_point_offset_x)

	shoot_point.position.y = shoot_point_offset_y

	# Nahkampf-Hitbox und -Reichweiten-Area mit umdrehen (genau wie
	# attack_hitbox bei der Ratte) - beide Nodes müssen also auf der
	# "rechten" Seite modelliert sein (Spiegelung über scale.x = -1).
	melee_hitbox.scale.x = 1.0 if facing_right else -1.0
	melee_range_area.scale.x = 1.0 if facing_right else -1.0


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
