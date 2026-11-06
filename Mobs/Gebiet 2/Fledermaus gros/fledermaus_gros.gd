extends CharacterBody2D

# Fliegender Mob (Gebiet 2). Nutzer-Wunsch: gleicher Aufwach-
# Mechanismus wie beim Schatten Mutant (siehe Mobs/Gebiet 2/schatten
# mutant/schatten_mutant.gd): SLEEP zeigt "Hängen" in Dauerschleife,
# bis der Spieler (oder PlayerSummon) in die WakeArea kommt - dann
# spielt "schlüpfen" einmal, danach ist sie wach.
#
# Anders als der Schatten Mutant fliegt sie danach aber frei in x
# UND y direkt auf ihr Ziel zu (keine Schwerkraft, kein Boden-Check).
# Berührt sie dabei den Spieler/das Summon, macht sie Schaden und
# fliegt danach kurz in die Gegenrichtung weg (RETREAT), bevor sie
# wieder zurück zum Ziel fliegt (CHASE) - so gibt's keinen
# Dauerschaden bei direktem Kontakt.
#
# Sprites sind nach RECHTS gezeichnet (genau wie beim Schatten
# Mutant, anders als beim normalen Skelett) - deshalb NICHT spiegeln
# beim Blick nach rechts, SPIEGELN beim Blick nach links (siehe
# _update_facing()).


enum State {
	SLEEP,
	AWAKE,
	CHASE,
	RETREAT,
	HURT,
	DEATH
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2
@export var damage: int = 1
@export var move_speed: float = 60.0


# ============================================================
# FLUGVERHALTEN (natürliches Verfolgen)
# ============================================================

# Nutzer-Wunsch: nicht mehr stur in gerader Linie auf den Spieler
# zufliegen, sondern natürlich: weich beschleunigen/bremsen, flattern,
# auf Abstand kreisen und dann im Bogen herabstoßen (Sturzflug). Wände
# und Boden erkennt sie über Sichtstrahlen (Raycasts) - dafür braucht
# der Raum KEINE extra Node.

@export_group("Flugverhalten")

# Wie schnell sie ihre Geschwindigkeit an die Wunschrichtung angleicht
# (Pixel/s²). Niedriger = träger, weitere Kurven.
@export var beschleunigung: float = 220.0

# Flattern: Auf-und-Ab-Bewegung beim Fliegen.
@export var flatter_hoehe: float = 14.0
@export var flatter_tempo: float = 6.0

# Kreisen: Punkt schräg über dem Spieler, an dem sie lauert.
@export var kreis_abstand_x: float = 46.0
@export var kreis_hoehe: float = 38.0
# So weit "eiert" der Lauerpunkt hin und her (wirkt lebendiger).
@export var kreis_wackeln: float = 12.0
# Zufällige Lauerzeit, bevor sie zustößt (Sekunden).
@export var kreis_zeit_min: float = 1.2
@export var kreis_zeit_max: float = 2.4

# Sturzflug auf die Position, an der der Spieler beim Start stand.
@export var sturz_tempo: float = 120.0
@export var sturz_beschleunigung: float = 420.0
# Zielt etwas vor den Spieler (in seine Laufrichtung). 0 = genau drauf.
@export var sturz_vorhalt: float = 0.15
# Sturzflug endet spätestens nach dieser Zeit (Sekunden).
@export var sturz_max_zeit: float = 1.1
# Nach dem Sturz kurz wieder hochziehen, bevor sie neu kreist.
@export var hochziehen_zeit: float = 0.5

# Hindernisse: Länge der Sichtstrahlen und wie stark sie ausweicht.
@export var strahl_laenge: float = 28.0
@export var ausweich_staerke: float = 1.6
# Mindestabstand zum Boden (außer im Sturzflug).
@export var boden_abstand: float = 22.0
# Physik-Ebenen, die als Wand/Boden gelten (Standard: Ebene 1 = Tiles).
@export_flags_2d_physics var hindernis_maske: int = 1


# ============================================================
# RÜCKZUG NACH TREFFER
# ============================================================

@export_group("Rückzug nach Treffer")

# Nutzer-Wunsch: nach einem Treffer fliegt sie kurz in die
# Gegenrichtung weg, bevor sie wieder zum Ziel zurückfliegt.
@export var retreat_speed: float = 90.0
@export var retreat_time: float = 0.6


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

@export var hurt_time: float = 0.3

# Trefferblitz: so lange bleibt sie voll hell ...
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

@export var death_delete_time: float = 1.0


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

@export var anim_sleep: StringName = &"Hängen"
@export var anim_awake: StringName = &"schlüpfen"
@export var anim_fly: StringName = &"Fliegen"
@export var anim_hurt: StringName = &"Hittet"
@export var anim_death: StringName = &"Tot"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionPolygon2D = $CollisionPolygon2D

# Verursacht Schaden am Spieler oder PlayerSummon bei Berührung.
@onready var attack_hitbox: Area2D = $AttackHitbox

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt die Fledermaus durch Spieler oder PlayerSummon einmalig auf.
@onready var wake_area: Area2D = $WakeArea

# Nutzer-Wunsch: statt stur geradeaus aufs Ziel zuzufliegen, sucht
# sie sich per Godot-Pfadsuche (NavigationAgent2D) einen Weg um
# Hindernisse/Plattformen herum - genau wie das "Pathing" in Spielen
# wie Hollow Knight. Dafür braucht JEDER Raum, in dem sie vorkommt,
# einmalig eine eigene NavigationRegion2D mit gebackenem
# NavigationPolygon (siehe Hinweis unten bei _process_chase()) - ohne
# das fällt sie automatisch auf die alte gerade Linie zurück.
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

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

var can_take_damage: bool = false
var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null
var _flash_tween: Tween = null

# Feste Richtung + Restzeit für den Rückzug nach einem Treffer
# (siehe _start_retreat_after_hit() / _process_retreat()).
var _retreat_direction: Vector2 = Vector2.ZERO
var _retreat_time_left: float = 0.0

# Flugverhalten (siehe _process_chase()).
enum Flug { KREISEN, STURZ, HOCHZIEHEN }
var _flug: Flug = Flug.KREISEN
var _flug_zeit: float = 0.0
var _flug_zeit_ziel: float = 0.0
var _flatter_t: float = 0.0
var _kreis_seite: float = 1.0
var _sturz_ziel: Vector2 = Vector2.ZERO
var _letzte_ziel_pos: Vector2 = Vector2.ZERO


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

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_hurt, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_sleep, true)
	_set_animation_loop(anim_fly, true)

	state = State.SLEEP
	awakened = false

	can_take_damage = false

	if _has_animation(anim_sleep):
		sprite.play(anim_sleep)
	else:
		awakened = true
		can_take_damage = true
		_enter_chase()

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

	_find_player_if_missing()
	_refresh_target()
	_check_player_attack_overlap()
	_check_contact_damage()

	match state:
		State.SLEEP:
			velocity = Vector2.ZERO

		State.AWAKE:
			velocity = Vector2.ZERO

		State.CHASE:
			_process_chase(delta)

		State.RETREAT:
			_process_retreat(delta)

		State.HURT:
			velocity = Vector2.ZERO

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


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
		nearest_distance = global_position.distance_to(
			player.global_position
		)

	for summon_node: Node in get_tree().get_nodes_in_group(
		summon_group
	):
		if not summon_node is Node2D:
			continue

		var summon := summon_node as Node2D

		if not _node_is_available_target(summon):
			continue

		var summon_distance: float = global_position.distance_to(
			summon.global_position
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
# VERFOLGUNG (FLIEGEN)
# ============================================================

func _enter_chase() -> void:
	if dead:
		return

	state = State.CHASE

	_starte_kreisen()
	_flatter_t = randf() * TAU

	_play_animation(anim_fly)


func _process_chase(delta: float) -> void:
	if _is_rooted():
		velocity = Vector2.ZERO
		return

	if not _target_is_available():
		velocity = velocity.move_toward(Vector2.ZERO, beschleunigung * delta)
		_play_animation(anim_fly)
		return

	_flug_zeit += delta
	_flatter_t += delta * flatter_tempo

	var ziel_pos: Vector2 = current_target.global_position
	# Laufrichtung des Ziels grob schätzen (für den Vorhalt im Sturzflug)
	if _letzte_ziel_pos == Vector2.ZERO:
		_letzte_ziel_pos = ziel_pos
	var ziel_tempo: Vector2 = (ziel_pos - _letzte_ziel_pos) / max(delta, 0.001)
	_letzte_ziel_pos = ziel_pos

	var wunsch: Vector2 = Vector2.ZERO
	var tempo: float = move_speed
	var accel: float = beschleunigung

	match _flug:
		Flug.KREISEN:
			# Lauerpunkt schräg über dem Spieler, leicht eiernd
			var punkt: Vector2 = ziel_pos + Vector2(
				_kreis_seite * kreis_abstand_x + sin(_flug_zeit * 1.3) * kreis_wackeln,
				-kreis_hoehe + cos(_flug_zeit * 0.9) * kreis_wackeln * 0.5
			)
			wunsch = _weg_zu(punkt)
			# in der Nähe des Punktes langsamer werden (kein Zappeln)
			tempo = move_speed * clamp(wunsch.length() / 24.0, 0.25, 1.0)

			if _flug_zeit >= _flug_zeit_ziel and _sicht_frei(ziel_pos):
				_flug = Flug.STURZ
				_flug_zeit = 0.0
				_sturz_ziel = ziel_pos + ziel_tempo * sturz_vorhalt

		Flug.STURZ:
			wunsch = _sturz_ziel - global_position
			tempo = sturz_tempo
			accel = sturz_beschleunigung
			if wunsch.length() < 6.0 or _flug_zeit >= sturz_max_zeit:
				_starte_hochziehen()

		Flug.HOCHZIEHEN:
			# im Bogen weg vom Ziel und nach oben
			wunsch = Vector2(_kreis_seite, -1.2)
			if _flug_zeit >= hochziehen_zeit:
				_starte_kreisen()

	var richtung: Vector2 = wunsch.normalized() if wunsch.length() > 0.5 else Vector2.ZERO
	richtung = _mit_ausweichen(richtung, _flug != Flug.STURZ)

	var soll: Vector2 = richtung * tempo * _get_speed_multiplier()
	# Flattern nur beim Kreisen/Hochziehen, im Sturz fliegt sie straff
	if _flug != Flug.STURZ:
		soll.y += cos(_flatter_t) * flatter_hoehe * flatter_tempo * 0.5

	velocity = velocity.move_toward(soll, accel * delta)

	_update_facing(velocity.x)
	_play_animation(anim_fly)


func _starte_kreisen() -> void:
	_flug = Flug.KREISEN
	_flug_zeit = 0.0
	_flug_zeit_ziel = randf_range(
		min(kreis_zeit_min, kreis_zeit_max),
		max(kreis_zeit_min, kreis_zeit_max)
	)
	# Seite wählen, auf der sie gerade ist (kein Durchqueren des Spielers)
	if _target_is_available():
		var dx: float = global_position.x - current_target.global_position.x
		_kreis_seite = 1.0 if dx >= 0.0 else -1.0


func _starte_hochziehen() -> void:
	_flug = Flug.HOCHZIEHEN
	_flug_zeit = 0.0
	# zur anderen Seite weiterziehen -> fliegt im Bogen über den Spieler
	_kreis_seite = 1.0 if velocity.x >= 0.0 else -1.0


# Richtung zu einem Punkt - nutzt die Pfadsuche, falls im Raum eine
# NavigationRegion2D gebacken ist und eine Wand im Weg ist (siehe
# _next_chase_step()), sonst direkt. Die Sichtstrahlen in
# _mit_ausweichen() kümmern sich dann um Wände.
func _weg_zu(punkt: Vector2) -> Vector2:
	if nav_agent != null and not _sicht_frei(punkt):
		nav_agent.target_position = punkt
		var naechster: Vector2 = nav_agent.get_next_path_position()
		var weg: Vector2 = naechster - global_position
		if weg.length() >= 1.0:
			return weg
	return punkt - global_position


# Sichtstrahl von der Fledermaus zu einem Punkt: true = keine Wand dazwischen.
func _sicht_frei(punkt: Vector2) -> bool:
	return _strahl(global_position, punkt).is_empty()


func _strahl(von: Vector2, nach: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(von, nach, hindernis_maske)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	# Spieler/Summons sind keine Hindernisse
	if not hit.is_empty() and _is_player_or_summon(hit.collider):
		return {}
	return hit


# Hindernisvermeidung per Sichtstrahlen: geradeaus und schräg links/
# rechts der Flugrichtung, dazu nach unten (Bodenabstand). Trifft ein
# Strahl, wird die Richtung von der Wand weggedrückt (Wand-Normale).
func _mit_ausweichen(richtung: Vector2, boden_halten: bool) -> Vector2:
	var basis: Vector2 = richtung
	if basis.length() < 0.1:
		basis = velocity.normalized() if velocity.length() > 1.0 else Vector2.ZERO

	var druck: Vector2 = Vector2.ZERO

	if basis != Vector2.ZERO:
		for winkel in [0.0, 0.6, -0.6]:
			var d: Vector2 = basis.rotated(winkel)
			var hit: Dictionary = _strahl(global_position, global_position + d * strahl_laenge)
			if hit.is_empty():
				continue
			var abstand: float = global_position.distance_to(hit.position)
			var naehe: float = 1.0 - clamp(abstand / strahl_laenge, 0.0, 1.0)
			druck += (hit.normal as Vector2) * naehe * ausweich_staerke

	if boden_halten:
		var unten: Dictionary = _strahl(global_position, global_position + Vector2.DOWN * boden_abstand)
		if not unten.is_empty():
			var naehe_b: float = 1.0 - clamp(global_position.distance_to(unten.position) / boden_abstand, 0.0, 1.0)
			druck += Vector2.UP * naehe_b * ausweich_staerke

	var neu: Vector2 = richtung + druck
	return neu.normalized() if neu.length() > 0.05 else richtung


# Liefert den Vektor zum nächsten Schritt Richtung Ziel - über die
# Godot-Pfadsuche (NavigationAgent2D), falls im aktuellen Raum eine
# NavigationRegion2D mit gebackenem NavigationPolygon liegt (dann
# fliegt sie in mehreren Etappen um Plattformen/Wände herum, genau
# wie gewünscht). GIBT ES noch keine NavigationRegion2D im Raum,
# liefert die Pfadsuche keinen brauchbaren Weg (naechster Punkt liegt
# praktisch auf ihrer eigenen Position) - dann fällt das hier
# automatisch auf die alte gerade Linie direkt zum Ziel zurück, damit
# sie in noch nicht eingerichteten Räumen nicht einfach stehen bleibt.
#
# EINMALIGES SETUP PRO RAUM (im Godot-Editor, nicht per Code):
#   1. In der Raum-Szene eine "NavigationRegion2D"-Node hinzufügen.
#   2. Im Inspector ein neues "NavigationPolygon" zuweisen.
#   3. Oben in der 2D-Ansicht auf "Bake NavigationPolygon" klicken -
#      Godot erkennt die Kollisionen von TileMap/Plattformen
#      automatisch und schneidet sie aus der begehbaren Fläche raus.
func _next_chase_step() -> Vector2:
	nav_agent.target_position = current_target.global_position

	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - global_position

	if to_next.length() < 1.0:
		return current_target.global_position - global_position

	return to_next


# ============================================================
# RÜCKZUG NACH TREFFER
# ============================================================

func _start_retreat_after_hit() -> void:
	if dead:
		return

	state = State.RETREAT

	var away: Vector2 = Vector2.ZERO

	if _target_is_available():
		away = global_position - current_target.global_position

	if away.length() < 0.5:
		away = Vector2(-1.0 if facing_right else 1.0, 0.0)
	else:
		away = away.normalized()

	# leicht nach oben ziehen, wirkt wie Wegflattern statt Wegrutschen
	_retreat_direction = (away + Vector2(0, -0.6)).normalized()
	_retreat_time_left = max(retreat_time, 0.01)

	_play_animation(anim_fly)


func _process_retreat(delta: float) -> void:
	if _is_rooted():
		velocity = Vector2.ZERO
		return

	# Nutzer-Wunsch "natürlich fliegen": auch der Rückzug lenkt weich
	# und weicht Wänden/Boden aus, statt hart in eine Wand zu fliegen.
	var richtung: Vector2 = _mit_ausweichen(_retreat_direction, true)
	velocity = velocity.move_toward(
		richtung * retreat_speed * _get_speed_multiplier(),
		beschleunigung * 2.0 * delta
	)

	# Nutzer-Wunsch: sie soll sich beim Rückzug auch in die
	# Flugrichtung drehen, nicht nur beim Verfolgen.
	_update_facing(velocity.x)

	_retreat_time_left -= delta

	if _retreat_time_left <= 0.0:
		_enter_chase()


# ============================================================
# SCHADEN AN SPIELER/SUMMON BEI BERÜHRUNG
# ============================================================

func _check_contact_damage() -> void:
	if dead:
		return

	if state != State.CHASE:
		return

	for body: Node in attack_hitbox.get_overlapping_bodies():
		if not _is_player_or_summon(body):
			continue

		_deal_contact_damage(body)
		return

	for area: Area2D in attack_hitbox.get_overlapping_areas():
		var target: Node = _get_player_or_summon_from_area(area)

		if target == null:
			continue

		_deal_contact_damage(target)
		return


func _deal_contact_damage(target: Node) -> void:
	if target.has_method("take_damage"):
		target.take_damage(
			damage,
			global_position
		)

	_start_retreat_after_hit()


# ============================================================
# SPIELERANGRIFFE ERKENNEN (SCHADEN AN DER FLEDERMAUS)
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

	if invincible:
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

	if invincible:
		return

	hp -= amount

	EnemySoundManager.play(&"skelette", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	# Trefferblitz bei jedem Treffer.
	_flash_white()

	# Die "Hittet"-Animation unterbricht nur, solange sie gerade
	# fliegt (CHASE/RETREAT) - nicht während Aufwachen oder Tod.
	if state == State.CHASE or state == State.RETREAT:
		_start_hurt()


func _start_hurt() -> void:
	if dead:
		return

	state = State.HURT
	invincible = true

	velocity = Vector2.ZERO

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
	can_take_damage = true

	_enter_chase()


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
	var wake_target: Node = _get_player_or_summon_from_area(area)

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

	# Ab jetzt dauerhaft aktiviert - kann während der Schlüpf-
	# Animation aber noch keinen Schaden nehmen (gleiches Muster
	# wie beim Schatten Mutant während seiner Aufwach-Animation).
	awakened = true

	can_take_damage = false

	var direction: Vector2 = (
		wake_target.global_position - global_position
	)

	if abs(direction.x) > 0.5:
		_update_facing(direction.x)

	if _has_animation(anim_awake):
		_play_animation_force(anim_awake)
	else:
		can_take_damage = true
		_enter_chase()


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
		can_take_damage = true

		_enter_chase()
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		queue_free()


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
	invincible = false
	damage_hit_locked = true

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
# eingefroren werden darf.
func is_animation_freeze_safe() -> bool:
	return state == State.CHASE or state == State.RETREAT


# ============================================================
# BLICKRICHTUNG
# ============================================================

# x_direction: die x-Komponente der aktuellen Flugrichtung. Sehr
# kleine Werte (fast senkrechter Flug) werden ignoriert, damit die
# Blickrichtung nicht bei jedem Frame hin- und herflackert.
func _update_facing(x_direction: float) -> void:
	if abs(x_direction) < 0.05:
		return

	# WICHTIG: KEIN "schon facing_right, also nichts zu tun"-Abbruch
	# hier - facing_right startet als false, was zufällig mit "schaut
	# nach links" übereinstimmt, obwohl sprite.flip_h anfangs noch
	# gar nicht gesetzt wurde. Ein Abbruch bei Gleichstand hat genau
	# deshalb das allererste Spiegeln nach links verschluckt. Deshalb
	# hier IMMER flip_h/Hitbox neu setzen, genau wie beim Schatten
	# Mutant (siehe schatten_mutant.gd _set_facing()).
	facing_right = x_direction > 0.0

	# Sprites sind nach rechts gezeichnet - deshalb NICHT spiegeln
	# beim Blick nach rechts, SPIEGELN beim Blick nach links.
	sprite.flip_h = not facing_right

	attack_hitbox.scale.x = (
		1.0 if facing_right else -1.0
	)


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
