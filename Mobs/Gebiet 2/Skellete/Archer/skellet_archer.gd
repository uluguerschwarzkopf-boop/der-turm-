extends CharacterBody2D

# Skellet Archer (Gebiet 2).
# Basiert auf Mobs/Gebiet 2/Skellete/krieger skellet/krieger_skellet.gd
# (Schlafen/Aufwachen, Liege-Animation, Spieler läuft durch ihn
# hindurch, Zurücksetzen ohne Ziel, Trefferblitz, Leiche bleibt
# liegen, Gold-Drop über den GoldDrop-Node) und für das Verhalten
# auf Mobs/Gebiet 1/Skellete/Archer/skeleton_archer.gd (bleibt
# stehen, schießt, flieht wenn man zu nah kommt).
#
# Nutzer-Wunsch: die Reichweiten kommen aus Areas, die im Editor
# gezogen werden (nicht aus festen Zahlen):
# - "AttackRange"      -> Ziel drin + Nahkampf bereit: Nahkampf.
# - "Schussreichweite" -> Ziel drin + Schuss bereit: schießen.
# - "Fliehen"          -> Ziel drin: von ihm weglaufen.
# Reihenfolge (Nutzer-Entscheidung): Nahkampf > Schuss > Fliehen.
# Ist der Schuss bereit, schießt er also zuerst und läuft erst
# danach weg (wie beim alten Archer).
#
# Ist das Ziel nicht mehr in der Schussreichweite, legt er sich
# wieder hin und setzt sich zurück (wie Krieger/Schatten Mutant).


enum State {
	SLEEP,
	AWAKE,
	IDLE,
	WALK,
	ATTACK,
	HURT,
	DEATH,
	RESET
}

const ATTACK_MELEE: int = 1
const ATTACK_RANGED: int = 2


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2

# Geschwindigkeit beim Weglaufen (Fliehen).
@export var move_speed: float = 45.0

# Nutzer-Korrektur: während der Schuss im Cooldown ist, läuft er vom
# Spieler weg - aber nur bis so viele Pixel vor dem Rand der
# Schussreichweite (Breite wird aus der Area gelesen), damit er nicht
# aus der Reichweite rennt.
@export var kite_edge_margin: float = 30.0

# Nutzer-Wunsch: ist der Spieler aus der Schussreichweite raus, läuft
# er hinterher - bis er wieder so viele Pixel innerhalb der Reichweite
# ist. Muss KLEINER sein als kite_edge_margin, sonst zappelt er.
@export var follow_stop_margin: float = 15.0
@export var follow_speed: float = 45.0

# Es gibt keine eigene Steh-Animation (anim_idle = "laufen"). Damit er
# im Stehen nicht "auf der Stelle läuft", wird "laufen" beim Stehen
# auf diesem Frame angehalten. Aus = laufen spielt auch im Stehen.
@export var idle_freeze_walk_frame: bool = true
@export var idle_still_frame: int = 0
@export var gravity: float = 900.0

# Hitbox-Form und ShootPoint zeigen im Editor nach rechts (+X),
# deshalb gehen wir davon aus, dass die Sprites nach RECHTS
# gezeichnet sind. Falls nicht, hier umschalten.
@export var sprite_faces_right: bool = true


# ============================================================
# NAHKAMPF
# ============================================================

@export_group("Nahkampf")

@export var anim_melee: StringName = &"Nahkampf_Angriff"
@export var melee_damage: int = 1
# Nutzer-Wunsch: Schaden auf Frame 7 (Godot zählt ab 0).
@export var melee_damage_frame: int = 7
@export var melee_cooldown: float = 0.7


# ============================================================
# FERNKAMPF
# ============================================================

@export_group("Fernkampf")

@export var anim_shoot: StringName = &"Fernkampf_Angriff"
# Nutzer-Wunsch: Pfeil spawnt auf Frame 9 (Godot zählt ab 0).
@export var shoot_frame: int = 9
@export var shoot_cooldown: float = 2.0

# Pfeil-Szene (arrow_skellet_archer.tscn). Geschwindigkeit, Schaden
# und Lebensdauer werden in DER Pfeil-Szene im Inspektor eingestellt.
@export var arrow_scene: PackedScene

# Nutzer-Wunsch: kann er nicht weiter fliehen (Wand, Abgrund, Ranken),
# schießt er die ganze Zeit. Dann gilt statt shoot_cooldown dieser
# Cooldown (0 = Pfeil auf Pfeil, die Schuss-Animation selbst dauert
# schon ca. 2 s), und er schießt auch, wenn das Ziel gerade nicht in
# der Schussreichweite-Area ist (z.B. springt).
@export var cornered_shoot_cooldown: float = 0.0


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
@export var hit_flash_boost: float = 5.0

# Verhindert mehrfachen Schaden durch dieselbe aktive Hitbox.
@export var damage_hit_lock_time: float = 0.12


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

# Nutzer-Wunsch (wie Krieger/Spinne): die Leiche bleibt standardmäßig
# für immer auf dem letzten Frame der Tot-Animation liegen. Nur wenn
# eingeschaltet, wird sie "death_delete_time" Sekunden NACH Ende der
# Animation entfernt.
@export var delete_after_death: bool = false
@export var death_delete_time: float = 1.2


# ============================================================
# ZURÜCKSETZEN
# ============================================================

@export_group("Zurücksetzen")

# Nutzer-Korrektur: er hat sich nach dem Schießen sofort wieder
# hingelegt. Ursache: das Zurücksetzen hing an der Schussreichweite-
# Area - die ist nur 29 px hoch, ein Sprung (oder kurz raus) hat
# also schon gereicht, und die Wartezeit war 0. Jetzt eigene, viel
# größere Reichweite (nur waagerechter Abstand, Höhe egal) plus
# Wartezeit. Schießen geht weiterhin nur in der Schussreichweite.

# Ist das Ziel waagerecht weiter weg als das ...
@export var reset_distance: float = 400.0
# ... und zwar so viele Sekunden am Stück, legt er sich wieder hin
# (Aufwach-Animation rückwärts) und hat wieder volle Leben.
@export var reset_after_idle_time: float = 2.0


# ============================================================
# ABGRUNDPRÜFUNG
# ============================================================

@export_group("Abgrundprüfung")

@export var edge_check_x: float = 10.0
@export var edge_check_y: float = 28.0

# Strahl startet etwas oberhalb der Füße, sonst steckt er im Boden
# und erkennt nichts (siehe schatten_mutant.gd).
@export var edge_check_start_height: float = 8.0

# So viele Pixel vor ihm wird beim Fliehen auf eine Wand geprüft.
@export var wall_check_distance: float = 2.0


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
# auch fürs Stehen benutzt (wie beim Krieger). Kommt eine Idle-
# Animation dazu, hier eintragen.
@export var anim_idle: StringName = &"laufen"
@export var anim_walk: StringName = &"laufen"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

# Nahkampf-Schaden (Form "Nahkampf_Angriff").
@onready var attack_hitbox: Area2D = $AttackHitbox

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt ihn durch Spieler oder PlayerSummon einmalig auf.
@onready var wake_area: Area2D = $WakeArea

# Reichweiten-Areas (Nutzer-Wunsch, im Editor gezogen).
@onready var attack_range_area: Area2D = $AttackRange
@onready var flee_area: Area2D = $Fliehen
@onready var shoot_range_area: Area2D = $Schussreichweite

@onready var shoot_point: Marker2D = $ShootPoint

@onready var ground_ray: RayCast2D = $RayCast2D

# Optional: Freeze/Root/Slow durch Spieler-Zauber.
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
var facing_right: bool = true

var awakened: bool = false

var can_melee: bool = true
var can_shoot: bool = true

# Gerade laufender Angriff (ATTACK_MELEE / ATTACK_RANGED).
var _current_attack: int = ATTACK_MELEE
# Nahkampf-Schaden bzw. Pfeil für den laufenden Angriff erledigt.
var attack_action_done: bool = false

# Wird bei jedem Angriffsstart erhöht. Der Sicherheits-Timer beendet
# den Angriff nur, wenn noch DERSELBE Angriff läuft.
var _attack_generation: int = 0

var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false
var can_take_damage: bool = false

var hit_flash_material: ShaderMaterial = null
var _flash_tween: Tween = null

# Wie lange schon kein Ziel in der Schussreichweite war.
var _idle_no_target_time: float = 0.0

# Zeitpunkt, an dem der letzte Schuss-Angriff zu Ende war (für
# cornered_shoot_cooldown).
var _last_shot_finished_msec: int = -1000000

# ShootPoint-Position aus dem Editor (zeigt nach rechts). Beim
# Umdrehen wird nur X gespiegelt.
var _shoot_point_base: Vector2 = Vector2.ZERO


# ============================================================
# START
# ============================================================

func _ready() -> void:
	hp = max_health

	add_to_group("enemy")

	_shoot_point_base = shoot_point.position
	_shoot_point_base.x = abs(_shoot_point_base.x)

	# Blickrichtung aus dem Editor übernehmen (flip_h am Sprite).
	facing_right = sprite.flip_h != sprite_faces_right
	_apply_facing_visuals()

	_setup_hit_flash_shader()

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D

	_apply_player_collision_exception()

	if not wake_area.body_entered.is_connected(_on_wake_area_body_entered):
		wake_area.body_entered.connect(_on_wake_area_body_entered)

	if not wake_area.area_entered.is_connected(_on_wake_area_area_entered):
		wake_area.area_entered.connect(_on_wake_area_area_entered)

	if not hurtbox.area_entered.is_connected(_on_hurtbox_area_entered):
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)

	if not sprite.animation_finished.is_connected(_on_animation_finished):
		sprite.animation_finished.connect(_on_animation_finished)

	for area: Area2D in [
		wake_area,
		hurtbox,
		attack_hitbox,
		attack_range_area,
		flee_area,
		shoot_range_area
	]:
		area.monitoring = true
		area.monitorable = true

	ground_ray.enabled = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_melee, false)
	_set_animation_loop(anim_shoot, false)
	_set_animation_loop(anim_hurt, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_sleep, true)
	_set_animation_loop(anim_idle, true)
	_set_animation_loop(anim_walk, true)

	state = State.SLEEP
	awakened = false

	can_take_damage = false
	can_melee = true
	can_shoot = true

	if _has_animation(anim_sleep):
		sprite.play(anim_sleep)
	elif _has_animation(anim_awake):
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()
	else:
		awakened = true
		can_take_damage = true
		_enter_idle()

	if arrow_scene == null:
		push_warning("Skellet Archer: Arrow Scene fehlt im Inspektor.")

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

	match state:
		State.IDLE, State.WALK:
			# Wie beim alten Archer: in Idle/Walk wird jeden Frame
			# neu entschieden (Nahkampf > Schuss > Fliehen > Stehen).
			_process_archer(delta)

		State.DEATH:
			velocity = Vector2.ZERO

		_:
			velocity.x = 0

	move_and_slide()


# ============================================================
# SPIELER-KOLLISION AUSSCHALTEN
# ============================================================

# Wie bei allen Gebiet-2-Mobs: der Spieler läuft durch ihn hindurch.
# Treffer laufen weiterhin über die Areas.
func _apply_player_collision_exception() -> void:
	if player == null or not is_instance_valid(player):
		return

	if not (player is PhysicsBody2D):
		return

	add_collision_exception_with(player)


# ============================================================
# ARCHER-LOGIK
# ============================================================

func _process_archer(delta: float) -> void:
	if not awakened:
		return

	# Zurücksetzen nur, wenn das Ziel weit weg ist (reset_distance),
	# nicht schon beim Verlassen der Schussreichweite.
	if (
		not _target_is_available()
		or _horizontal_distance_to_target() > reset_distance
	):
		_enter_idle()
		_accumulate_idle_reset_timer(delta)
		return

	_idle_no_target_time = 0.0

	var direction_to_target: float = _direction_to_target()

	# 1. Nahkampf: Ziel in der AttackRange und Nahkampf bereit.
	if can_melee and _area_has_target(attack_range_area):
		_start_attack(ATTACK_MELEE)
		return

	# 2. Schuss: Ziel in der Schussreichweite und Schuss bereit.
	# Nutzer-Entscheidung: hat Vorrang vor dem Fliehen.
	if (
		can_shoot
		and arrow_scene != null
		and _area_has_target(shoot_range_area)
	):
		_start_attack(ATTACK_RANGED)
		return

	# 3. Fliehen: Ziel ist zu nah -> in die Gegenrichtung laufen.
	if _area_has_target(flee_area) and direction_to_target != 0.0:
		_flee(-direction_to_target, direction_to_target)
		return

	# 4. Nutzer-Korrektur: NICHT mehr zum Ziel hinlaufen, sondern
	# weglaufen, solange der Schuss im Cooldown ist - aber nur bis kurz
	# vor den Rand der Schussreichweite (kite_edge_margin), damit er
	# nicht aus der Reichweite rennt. Sobald der Schuss bereit ist,
	# greift oben Punkt 2 (stehen bleiben, umdrehen, schießen).
	var kite_distance: float = (
		_get_area_half_width(shoot_range_area) - kite_edge_margin
	)

	var distance: float = _horizontal_distance_to_target()

	if direction_to_target != 0.0 and distance < kite_distance:
		_flee(-direction_to_target, direction_to_target)
		return

	# 5. Nutzer-Wunsch: ist das Ziel (fast) aus der Schussreichweite
	# raus, läuft er wieder hinterher, damit der Abstand nicht zu groß
	# wird. Er stoppt follow_stop_margin px innerhalb der Reichweite.
	# Zwischen diesem Punkt und kite_distance steht er still - dieser
	# Puffer verhindert das Hin- und Herzappeln zwischen Weglaufen
	# und Hinterherlaufen (follow_stop_margin < kite_edge_margin).
	var follow_distance: float = (
		_get_area_half_width(shoot_range_area) - follow_stop_margin
	)

	# Absicherung, falls die Margins im Inspektor vertauscht werden:
	# immer mindestens 5 px Stehbereich zwischen beiden Grenzen.
	follow_distance = max(follow_distance, kite_distance + 5.0)

	if direction_to_target != 0.0 and distance > follow_distance:
		_follow(direction_to_target)
		return

	_enter_idle()
	_set_facing(direction_to_target)


func _follow(direction: float) -> void:
	# Ranken, Abgrund oder Wand: stehen bleiben und Ziel anschauen.
	if (
		_is_rooted()
		or not _has_ground_in_direction(direction)
		or _is_wall_in_direction(direction)
	):
		_enter_idle()
		_set_facing(direction)
		return

	state = State.WALK
	velocity.x = direction * follow_speed * _get_speed_multiplier()

	_set_facing(direction)

	_play_animation(anim_walk)


# Halbe Breite einer Reichweiten-Area (+ Versatz der Form), gelesen
# aus ihren RectangleShape2D - wächst also mit, wenn die Area im
# Editor geändert wird.
func _get_area_half_width(area: Area2D) -> float:
	var half_width: float = 0.0

	for child: Node in area.get_children():
		var shape_node := child as CollisionShape2D

		if shape_node == null or shape_node.shape == null:
			continue

		var rect := shape_node.shape as RectangleShape2D

		if rect == null:
			continue

		half_width = max(
			half_width,
			abs(shape_node.position.x) + rect.size.x * 0.5
		)

	return half_width


func _flee(flee_direction: float, direction_to_target: float) -> void:
	# Festgewurzelt (Ranken), Abgrund oder Wand: stehen bleiben und
	# das Ziel anschauen, statt hängen zu bleiben oder abzustürzen.
	if (
		_is_rooted()
		or not _has_ground_in_direction(flee_direction)
		or _is_wall_in_direction(flee_direction)
	):
		_enter_idle()
		_set_facing(direction_to_target)

		# Nutzer-Wunsch: steht er mit dem Rücken an der Wand (oder am
		# Abgrund / festgewurzelt) und kann nicht weiter fliehen,
		# schießt er die ganze Zeit (mit cornered_shoot_cooldown statt
		# shoot_cooldown).
		if arrow_scene != null and _cornered_shot_ready():
			_start_attack(ATTACK_RANGED)

		return

	state = State.WALK
	velocity.x = flee_direction * move_speed * _get_speed_multiplier()

	# Wie beim alten Archer: beim Weglaufen schaut er in die
	# Laufrichtung.
	_set_facing(flee_direction)

	_play_animation(anim_walk)


func _enter_idle() -> void:
	if dead:
		return

	state = State.IDLE
	velocity.x = 0

	if not (idle_freeze_walk_frame and anim_idle == anim_walk):
		_play_animation(anim_idle)
		return

	# Nutzer-Korrektur: im Stehen nicht "auf der Stelle laufen" -
	# "laufen" auf idle_still_frame anhalten. Wird jeden Frame
	# aufgerufen, fängt also auch ein Fortsetzen durch Zauber-Effekte ab.
	if not _has_animation(anim_idle):
		return

	if sprite.animation != anim_idle:
		sprite.play(anim_idle)

	var still_frame: int = clampi(
		idle_still_frame,
		0,
		sprite.sprite_frames.get_frame_count(anim_idle) - 1
	)

	if sprite.is_playing() or sprite.frame != still_frame:
		sprite.frame = still_frame
		sprite.pause()


func _accumulate_idle_reset_timer(delta: float) -> void:
	if not _has_animation(anim_awake):
		return

	_idle_no_target_time += delta

	if _idle_no_target_time >= reset_after_idle_time:
		_start_reset()


# ============================================================
# ZIELE
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

	for summon_node: Node in get_tree().get_nodes_in_group(summon_group):
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


# Beschworene Skelette haben collision_layer = 0 am Körper und sind
# nur über ihre Hurtbox erkennbar -> deren Layer in alle eigenen
# Areas aufnehmen.
func _include_summon_hurtbox_collision(summon: Node2D) -> void:
	var summon_hurtbox := summon.get_node_or_null("Hurtbox") as Area2D

	if summon_hurtbox == null:
		return

	var summon_hurtbox_layer: int = summon_hurtbox.collision_layer

	if summon_hurtbox_layer != 0:
		for area: Area2D in [
			attack_hitbox,
			wake_area,
			attack_range_area,
			flee_area,
			shoot_range_area
		]:
			area.collision_mask |= summon_hurtbox_layer

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


func _horizontal_distance_to_target() -> float:
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


# Steht das aktuelle Ziel in dieser Area? Spieler über seinen
# Körper, beschworene Skelette über ihre Hurtbox.
func _area_has_target(area: Area2D) -> bool:
	if area == null:
		return false

	if not _target_is_available():
		return false

	if (
		current_target is PhysicsBody2D
		and area.overlaps_body(current_target)
	):
		return true

	var target_hurtbox := current_target.get_node_or_null(
		"Hurtbox"
	) as Area2D

	if target_hurtbox != null and area.overlaps_area(target_hurtbox):
		return true

	return false


func _is_player_or_summon(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	return (
		node.is_in_group(player_group)
		or node.is_in_group(summon_group)
	)


func _get_player_or_summon_from_area(area: Area2D) -> Node:
	if _is_player_or_summon(area):
		return area

	var parent: Node = area.get_parent()

	if _is_player_or_summon(parent):
		return parent

	return null


# ============================================================
# ANGRIFF (NAHKAMPF + SCHUSS)
# ============================================================

func _get_attack_anim(attack: int) -> StringName:
	return anim_melee if attack == ATTACK_MELEE else anim_shoot


func _start_attack(attack: int) -> void:
	if dead or not awakened:
		return

	if state == State.ATTACK:
		return

	var anim: StringName = _get_attack_anim(attack)

	if not _has_animation(anim):
		return

	state = State.ATTACK

	_current_attack = attack
	_attack_generation += 1
	attack_action_done = false

	if attack == ATTACK_MELEE:
		can_melee = false
	else:
		can_shoot = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	_play_animation_force(anim)

	_end_attack_by_timer_fallback(_attack_generation)


# Robustheit: Angriffsende nicht nur über animation_finished, sondern
# zusätzlich per Timer aus Frameanzahl / FPS absichern.
func _end_attack_by_timer_fallback(generation: int) -> void:
	var anim: StringName = _get_attack_anim(_current_attack)

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

	_finish_attack(true)


func _on_frame_changed() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	if sprite.animation != _get_attack_anim(_current_attack):
		return

	if attack_action_done:
		return

	if _current_attack == ATTACK_MELEE:
		# Nutzer-Wunsch: Schaden auf melee_damage_frame.
		if sprite.frame >= melee_damage_frame:
			attack_action_done = true
			_damage_target_if_inside()
	else:
		# Nutzer-Wunsch: Pfeil auf shoot_frame am ShootPoint.
		if sprite.frame >= shoot_frame:
			attack_action_done = true
			_shoot_arrow()


func _damage_target_if_inside() -> void:
	if dead:
		return

	for body: Node in attack_hitbox.get_overlapping_bodies():
		if not _is_player_or_summon(body):
			continue

		if body.has_method("take_damage"):
			body.take_damage(melee_damage, global_position)

		return

	# Das PlayerSkeleton hat absichtlich collision_layer = 0.
	# Deshalb wird es über seine Hurtbox-Area getroffen.
	for area: Area2D in attack_hitbox.get_overlapping_areas():
		var damage_target: Node = _get_player_or_summon_from_area(area)

		if damage_target == null:
			continue

		if damage_target.has_method("take_damage"):
			damage_target.take_damage(melee_damage, global_position)

		return


func _shoot_arrow() -> void:
	if dead:
		return

	if arrow_scene == null:
		push_warning("Skellet Archer: Arrow Scene fehlt im Inspektor.")
		return

	var tree := get_tree()

	if tree == null or tree.current_scene == null:
		return

	var arrow: Node = arrow_scene.instantiate()

	if arrow == null:
		return

	# Gleich wie beim alten Archer: der Pfeil hängt an der Raum-Szene,
	# nicht am Archer - sonst würde er beim Umdrehen/Tod mitwandern.
	tree.current_scene.add_child(arrow)

	if arrow is Node2D:
		(arrow as Node2D).global_position = shoot_point.global_position

	var direction: float = 1.0 if facing_right else -1.0

	if arrow.has_method("setup"):
		arrow.setup(direction, self)


# Wird von Player/enemy_spell_effects.gd aufgerufen, sobald ein
# laufender Angriff durch den Parry-Skill unterbrochen wurde.
func interrupt_current_action() -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	# Pariert = kein Pfeil mehr nachschießen.
	attack_action_done = true
	_finish_attack(false)


func _finish_attack(shoot_if_missed: bool) -> void:
	if dead:
		return

	if state != State.ATTACK:
		return

	# Falls der Schuss-Frame übersprungen wurde (z.B. Ruckler), den
	# Pfeil wie beim alten Archer am Ende noch abfeuern.
	if (
		shoot_if_missed
		and _current_attack == ATTACK_RANGED
		and not attack_action_done
	):
		attack_action_done = true
		_shoot_arrow()

	attack_action_done = true

	var finished_attack: int = _current_attack

	if finished_attack == ATTACK_RANGED:
		_last_shot_finished_msec = Time.get_ticks_msec()

	# Zurück nach Idle - _process_archer() entscheidet ab dem
	# nächsten Physik-Frame neu (Fliehen, Stehen, ...).
	_enter_idle()

	_start_cooldown(finished_attack)


# Getrennte Cooldowns (Nutzer-Wunsch): Nahkampf und Schuss sperren
# sich nicht gegenseitig.
func _start_cooldown(attack: int) -> void:
	var cooldown: float = (
		melee_cooldown if attack == ATTACK_MELEE else shoot_cooldown
	)

	var tree := get_tree()

	if tree == null:
		_set_attack_ready(attack)
		return

	await tree.create_timer(max(cooldown, 0.01)).timeout

	if dead or not is_inside_tree():
		return

	_set_attack_ready(attack)


func _set_attack_ready(attack: int) -> void:
	if attack == ATTACK_MELEE:
		can_melee = true
	else:
		can_shoot = true


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

		_enter_idle()
		return

	if (
		state == State.RESET
		and sprite.animation == anim_awake
	):
		_finish_reset()
		return

	if (
		state == State.ATTACK
		and sprite.animation == _get_attack_anim(_current_attack)
	):
		_finish_attack(true)
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
		var wake_target: Node = _get_player_or_summon_from_area(area)

		if wake_target is Node2D:
			_wake_up_for_target(wake_target as Node2D)
			return


func _on_wake_area_body_entered(body: Node) -> void:
	if not _is_player_or_summon(body):
		return

	_wake_up_for_target(body as Node2D)


func _on_wake_area_area_entered(area: Area2D) -> void:
	var wake_target: Node = _get_player_or_summon_from_area(area)

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

	# Während der Aufwach-Animation nimmt er noch keinen Schaden
	# (wie beim Krieger).
	awakened = true
	can_take_damage = false

	velocity.x = 0

	var direction: float = _direction_to_target()

	if direction != 0.0:
		_set_facing(direction)

	if _has_animation(anim_awake):
		_play_animation_force(anim_awake)
	else:
		can_take_damage = true
		_enter_idle()


# ============================================================
# ZURÜCKSETZEN (LEGT SICH WIEDER HIN)
# ============================================================

# Aufwach-Animation einmal RÜCKWÄRTS, bis er wieder liegt.
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

	sprite.play(anim_awake, -1.0, true)


func _finish_reset() -> void:
	if dead:
		return

	hp = max_health

	state = State.SLEEP
	awakened = false

	can_take_damage = false
	can_melee = true
	can_shoot = true

	attack_action_done = false
	invincible = false
	damage_hit_locked = false

	_idle_no_target_time = 0.0

	_reset_hit_flash()

	if _has_animation(anim_sleep):
		sprite.play(anim_sleep)
	else:
		sprite.play(anim_awake)
		sprite.frame = 0
		sprite.pause()

	# Steht noch jemand in der WakeArea, sofort wieder aufwachen.
	_check_initial_wake_overlap()


# ============================================================
# SPIELERANGRIFFE ERKENNEN
# ============================================================

func _on_hurtbox_area_entered(area: Area2D) -> void:
	_try_take_player_attack_damage(area)


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
		attack_damage = int(area.get_meta("damage"))

	damage_hit_locked = true

	take_damage(attack_damage)

	_release_damage_hit_lock_later()


func _release_damage_hit_lock_later() -> void:
	var tree := get_tree()

	if tree == null:
		damage_hit_locked = false
		return

	await tree.create_timer(max(damage_hit_lock_time, 0.01)).timeout

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

	_flash_white()

	# Wie beim Krieger: "hittet" unterbricht nur Laufen/Stehen.
	# Angriffe laufen weiter, er blitzt nur weiß auf.
	if state != State.IDLE and state != State.WALK:
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

	await tree.create_timer(max(hurt_time, 0.01)).timeout

	if dead or not is_inside_tree():
		return

	_finish_hurt()


func _finish_hurt() -> void:
	if dead:
		return

	if state != State.HURT:
		invincible = false
		return

	awakened = true
	invincible = false
	can_take_damage = true

	_enter_idle()


# ============================================================
# TREFFERBLITZ
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

	hit_flash_material.set_shader_parameter("flash_amount", 0.0)
	hit_flash_material.set_shader_parameter(
		"flash_color",
		Vector3(hit_flash_color.r, hit_flash_color.g, hit_flash_color.b)
	)
	hit_flash_material.set_shader_parameter("flash_boost", hit_flash_boost)

	sprite.material = hit_flash_material


func _flash_white() -> void:
	if hit_flash_material == null:
		return

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

	hit_flash_material.set_shader_parameter("flash_amount", value)


func _reset_hit_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	_set_flash_amount(0.0)


# ============================================================
# TOD
# ============================================================

func _die() -> void:
	if dead:
		return

	dead = true
	state = State.DEATH

	EnemySoundManager.play(&"skelette", &"death", global_position)

	# Zählt für die Statistik und lässt den XP-Pixel fliegen.
	RunState.add_enemy_kill(1, global_position)

	can_take_damage = false
	can_melee = false
	can_shoot = false

	invincible = false
	damage_hit_locked = true
	attack_action_done = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	# set_deferred statt direkt setzen: _die() kann mitten in einem
	# Physik-Signal laufen (z.B. hurtbox.area_entered).
	for area: Area2D in [
		wake_area,
		hurtbox,
		attack_hitbox,
		attack_range_area,
		flee_area,
		shoot_range_area
	]:
		area.set_deferred("monitoring", false)

	if body_shape != null:
		body_shape.set_deferred("disabled", true)

	if _has_animation(anim_death):
		_play_animation_force(anim_death)
	else:
		queue_free()


# Der letzte Frame der Tot-Animation zeigt die liegende Leiche -
# AnimatedSprite2D hält (Loop ist in _ready() aus) automatisch dort
# an. Standardmäßig bleibt sie liegen (delete_after_death = false).
func _finish_death() -> void:
	if not delete_after_death:
		return

	var tree := get_tree()

	if tree == null:
		if is_instance_valid(self):
			queue_free()
		return

	await tree.create_timer(max(death_delete_time, 0.01)).timeout

	if is_instance_valid(self):
		queue_free()


# ============================================================
# SCHWERKRAFT, RICHTUNG, BODEN
# ============================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0


func _set_facing(direction: float) -> void:
	if direction > 0.0:
		facing_right = true
	elif direction < 0.0:
		facing_right = false
	else:
		return

	_apply_facing_visuals()


# Spiegelt Sprite, Nahkampf-Hitbox und ShootPoint. Die Reichweiten-
# Areas (AttackRange, Fliehen, Schussreichweite) sind mittig und
# symmetrisch und müssen nicht gespiegelt werden.
func _apply_facing_visuals() -> void:
	sprite.flip_h = facing_right != sprite_faces_right

	var side: float = 1.0 if facing_right else -1.0

	attack_hitbox.scale.x = side

	shoot_point.position = Vector2(
		_shoot_point_base.x * side,
		_shoot_point_base.y
	)


func _has_ground_in_direction(direction: float) -> bool:
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


# Steht direkt in Fluchtrichtung eine Wand? test_move prüft, ob der
# Körper ein paar Pixel weiter anstoßen würde. Das klappt auch im
# Stehen (is_on_wall() wäre im Stehen false und würde flackern).
# Der Spieler zählt nicht (Kollisions-Ausnahme).
func _is_wall_in_direction(direction: float) -> bool:
	if direction == 0.0:
		return false

	return test_move(
		global_transform,
		Vector2(sign(direction) * wall_check_distance, 0.0)
	)


func _cornered_shot_ready() -> bool:
	if can_shoot:
		return true

	var since_last_shot: float = (
		Time.get_ticks_msec() - _last_shot_finished_msec
	) / 1000.0

	return since_last_shot >= cornered_shoot_cooldown


# ============================================================
# ZAUBER-EFFEKTE (FREEZE / ROOT / SLOW)
# ============================================================

func _is_rooted() -> bool:
	return spell_effects != null and spell_effects.is_rooted()


func _get_speed_multiplier() -> float:
	if spell_effects == null:
		return 1.0

	return spell_effects.get_speed_multiplier()


# Während eines Angriffs NICHT einfrieren, sonst würde der
# Schaden-/Schuss-Frame nie erreicht.
func is_animation_freeze_safe() -> bool:
	return state == State.IDLE or state == State.WALK


# ============================================================
# ANIMATIONSHILFEN
# ============================================================

func _has_animation(animation_name: StringName) -> bool:
	if sprite == null:
		return false

	if sprite.sprite_frames == null:
		return false

	return sprite.sprite_frames.has_animation(animation_name)


func _play_animation(animation_name: StringName) -> void:
	if not _has_animation(animation_name):
		return

	if _is_rooted():
		return

	if sprite.animation != animation_name:
		sprite.play(animation_name)
		return

	# "laufen" ist im Stehen angehalten (siehe _enter_idle()) - beim
	# Loslaufen wieder fortsetzen. (Festgewurzelt wurde oben schon
	# abgefangen, Lähmung stoppt _physics_process ganz.)
	if (
		animation_name == anim_walk
		and state == State.WALK
		and not sprite.is_playing()
	):
		sprite.play(animation_name)


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

	sprite.sprite_frames.set_animation_loop(animation_name, should_loop)
