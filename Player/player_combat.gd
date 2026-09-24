extends Node

@export var damage: int = 1
@export var hitbox_active_time: float = 0.12

@export var attack_1_name: StringName = &"attack 1"
@export var attack_2_name: StringName = &"attack 2"

@export var attack_1_hit_delay: float = 0.22
@export var attack_2_hit_delay: float = 0.22

@export_group("Passiver Skill - Execution")

# Nutzer-Wunsch: sobald der passive Skill "execution" im Skill-Baum
# freigeschaltet ist (siehe Game/skill_tree_data.gd, id &"execution")
# UND beim Zuschlagen ein Gegner unter execution_hp_threshold in
# Reichweite steht (siehe _find_execution_target() unten), wird statt
# der normalen Attacke 1 automatisch diese Animation gespielt - kein
# eigener Skill-Slot, kein Tastendruck nötig, ersetzt einfach den
# ersten Schlag.
@export var execution_anim: StringName = &"execution"
@export_range(0.0, 1.0, 0.01) var execution_hp_threshold: float = 0.20

# WICHTIG: die normale AttackHitbox (Hitboxes/AttackHitbox im player.
# tscn) reicht in Blickrichtung bis zu ~36px weit - execution_range
# stand vorher auf 20, war also KLEINER als die normale Angriffs-
# Reichweite. Dadurch konnte ein Gegner schon unter der Trefferzone
# der normalen Attacke liegen, aber noch außerhalb der Execution-
# Prüfung - Execution hat dann nie ausgelöst, obwohl der Treffer
# trotzdem landete. Jetzt auf 40, damit Execution überall dort
# greift, wo auch ein normaler Schlag schon treffen würde.
@export var execution_range: float = 40.0

# Nutzer-Wunsch: die Hitbox (die NORMALE AttackHitbox - execution
# benutzt bewusst keine eigene, siehe attack() unten wo target_hitbox
# auf null bleibt) wird jetzt auf einem festen ANIMATIONS-FRAME
# aktiviert statt nach einer festen Zeit, genau wie bei Backstep/
# Ground Slam (siehe _wait_for_sprite_frame() unten).
@export var execution_hit_frame: int = 5

# Schaden für ALLE ANDEREN Gegner, die beim Execution-Schlag mit
# getroffen werden, aber selbst NICHT unter execution_hp_threshold
# stehen (Nutzer-Wunsch) - die werden nicht normal wie bei Attacke 1
# verletzt, sondern nur mit diesem (kleineren) Wert.
@export var execution_fallback_damage: int = 1

# Nutzer-Wunsch: fester (hoher) Schaden für den eigentlichen
# Execution-Kill, statt exakt das aktuelle Leben des Ziels zu
# berechnen - tötet dadurch zuverlässig jeden Gegner unter
# execution_hp_threshold, egal wie viel HP er gerade genau hat.
@export var execution_lethal_damage: int = 100

# Nutzer-Wunsch: Execution kostet jetzt Vigor, genau wie ein normaler
# aktiver Skill - reicht der aktuelle Vigor nicht, wird ganz normal
# Attacke 1 gespielt (kein Fehler, kein Soft-Lock).
@export var execution_vigor_cost: int = 30

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

# Eigene Hitbox für den Backstep-Skill (Pfad der Stärke) - siehe
# activate_backstep_hitbox() weiter unten, ausgelöst von Player/
# player.gd _on_backstep_frame_changed().
@onready var backstep_hitbox: Area2D = (
	$"../../Hitboxes/Backstep Hitbox"
)

# Nutzer-Wunsch: eigene Erkennungs-Shape für die Reichweiten-Prüfung
# VOR dem eigentlichen Backstep-Start (siehe find_backstep_target()
# weiter unten und Player/player.gd _try_start_backstep()) - liegt bei
# dir als CollisionShape2D unter Hitboxes/Backstep Hitbox/Reichweite
# (also INNERHALB derselben Area2D wie die eigentliche Treffer-Shape).
# Deshalb wird hier NICHT über Area2D.get_overlapping_bodies()
# geprüft (das würde die kurz-aktive Treffer-Shape und die
# Reichweiten-Shape vermischen UND bräuchte eine dauerhaft
# eingeschaltete Area2D) - stattdessen liest find_backstep_target()
# direkt die Shape-Geometrie aus und fragt die Physik-Engine damit
# gezielt ab (funktioniert unabhängig vom monitoring-Zustand der
# Area2D und unabhängig davon, ob noch weitere Shapes danebenliegen).
@onready var backstep_range_shape: CollisionShape2D = get_node_or_null(
	"../../Hitboxes/Backstep Hitbox/Reichweite"
) as CollisionShape2D

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

	backstep_hitbox.monitoring = false
	backstep_hitbox.monitorable = true
	backstep_hitbox.add_to_group("player_attack")
	backstep_hitbox.set_meta("active", false)
	backstep_hitbox.set_meta("damage", damage)


func attack() -> void:
	if player.is_rolling:
		return

	if attacking:
		if (
			sprite.animation == attack_1_name
			or sprite.animation == execution_anim
		):
			combo_requested = true
		return

	attacking = true
	combo_requested = false
	cancel_requested = false
	second_hit_cancel_window_open = false

	# Nutzer-Wunsch (Execution, passiver Skill - siehe Game/skill_tree_
	# data.gd id &"execution"): steht beim Zuschlagen ein freigeschal-
	# teter Execution-Gegner unter execution_hp_threshold in Reichweite,
	# wird automatisch die Execution-Animation statt der normalen
	# Attacke 1 gespielt. Der ERSTE Schlag läuft in beiden Fällen immer
	# vollständig durch, er kann nicht abgebrochen werden.
	#
	# WICHTIG (Nutzer-Wunsch: "unter 20 Prozent Leben"): das ist relativ
	# zu max_health, kein fester Wert - ein Gegner mit z.B. 4 oder 5
	# max_health kann das rechnerisch NIE erreichen, solange er noch
	# lebt (20% von 4 = 0.8, d.h. es müsste hp < 0.8 sein, also 0 -
	# aber bei hp <= 0 ist er schon tot). Zum Testen daher am besten
	# einen Gegner mit mindestens ~6-10 max_health nehmen und erst mit
	# normalen Treffern auf 1 HP runterschlagen, dann nochmal
	# angreifen.
	var execution_unlocked: bool = (
		get_node_or_null("/root/RunState") != null
		and RunState.has_unlocked_skill(&"execution")
	)
	var execution_target: Node = (
		_find_execution_target() if execution_unlocked else null
	)
	var execution_vigor_ok: bool = (
		execution_unlocked
		and RunState.current_vigor >= execution_vigor_cost
	)
	var is_execution: bool = (
		execution_unlocked and execution_vigor_ok and execution_target != null
	)

	# Debug-Ausgabe (Nutzer-Wunsch: "warum geht execution nicht") - nur
	# EINE Zeile pro Fehlschlag, damit man im Godot-Output-Panel sofort
	# sieht, an welcher der drei Bedingungen es hängt.
	if not is_execution:
		if not execution_unlocked:
			print(
				"Execution: Skill 'execution' ist im Skill-Baum noch "
				+ "nicht freigeschaltet."
			)
		elif not execution_vigor_ok:
			print(
				"Execution: nicht genug Vigor (",
				RunState.current_vigor,
				"/",
				execution_vigor_cost,
				" nötig)."
			)
		elif execution_target == null:
			print(
				"Execution: kein Gegner unter ",
				int(execution_hp_threshold * 100),
				"% Leben in Reichweite (",
				execution_range,
				"px) und Blickrichtung."
			)

	if is_execution:
		RunState.spend_vigor(execution_vigor_cost)
		sprite.play(execution_anim)
		_play_sound(&"skill_execution")
	else:
		sprite.play(attack_1_name)
		_play_sound(&"sword_hit_1")

	if is_execution:
		await _wait_for_sprite_frame(execution_anim, execution_hit_frame)
	else:
		await get_tree().create_timer(attack_1_hit_delay).timeout

	# target_hitbox bleibt null -> _activate_hitbox() benutzt die ganz
	# normale AttackHitbox (siehe Kommentar dort), execution_mode=true
	# sorgt nur dafür, dass _damage_body() weiter unten den Execution-
	# Schaden statt des normalen Schadens berechnet.
	await _activate_hitbox(-1, null, is_execution)

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


# Wartet, bis die AnimatedSprite2D-Animation "anim" (noch) läuft UND
# mindestens bei "target_frame" angekommen ist (Nutzer-Wunsch:
# Execution löst die Hitbox auf einem festen Frame aus, genau wie
# Backstep/Ground Slam). Bricht sofort ab, wenn die Animation
# zwischendurch wechselt oder der Sprite weg ist, damit hier nie
# etwas für immer hängen bleibt.
func _wait_for_sprite_frame(anim: StringName, target_frame: int) -> void:
	if sprite == null:
		return

	while (
		is_instance_valid(sprite)
		and sprite.animation == anim
		and sprite.frame < target_frame
	):
		await get_tree().process_frame


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
	target_hitbox: Area2D = null,
	execution_mode: bool = false
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
		_damage_body(body, applied_damage, execution_mode)

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


# Wie activate_hitbox_with_damage(), aber für die eigene Backstep-
# Hitbox (nicht die normale AttackHitbox) - siehe Player/player.gd
# _on_backstep_frame_changed().
func activate_backstep_hitbox(skill_damage: int) -> void:
	await _activate_hitbox(skill_damage, backstep_hitbox)


# ============================================================
# BACKSTEP - REICHWEITEN-PRÜFUNG (PFAD DER STÄRKE)
# ============================================================

# Nutzer-Wunsch: liefert den EINEN Gegner in der "Reichweite"-Fläche
# zurück (siehe backstep_range oben), wenn GENAU EINER drinsteht - bei
# keinem oder mehreren gleichzeitig (z.B. hintereinander aufgereiht)
# wird null zurückgegeben, siehe Player/player.gd
# _try_start_backstep(), das dann abbricht: "geht nur bei einzelnen
# Gegnern".
func find_backstep_target() -> Node:
	if backstep_range_shape == null or backstep_range_shape.shape == null:
		push_warning(
			"Backstep: 'Reichweite'-Shape fehlt oder hat keine Form "
			+ "unter Hitboxes/Backstep Hitbox/Reichweite (player.tscn)."
		)
		return null

	# Backstep Hitbox VOR der Abfrage auf die aktuelle Blickrichtung
	# ausrichten (dieselbe Funktion, die auch beim eigentlichen Treffer
	# benutzt wird) - "Reichweite" hängt darunter und wird dadurch
	# automatisch mitgespiegelt.
	_update_hitbox_side(backstep_hitbox)

	# player_combat.gd ist ein reines "Node" (kein Node2D) - get_world_2d()
	# gibt es deshalb nur auf dem Player selbst, nicht auf "self" hier.
	var space_state := player.get_world_2d().direct_space_state

	if space_state == null:
		return null

	var query := PhysicsShapeQueryParameters2D.new()

	query.shape = backstep_range_shape.shape
	query.transform = backstep_range_shape.global_transform
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]

	var results: Array[Dictionary] = space_state.intersect_shape(
		query,
		32
	)

	var found: Array = []

	for result in results:
		var body: Node = result.get("collider")

		if body == null or body == player:
			continue

		if not body.is_in_group(&"enemy"):
			continue

		if bool(body.get("dead")):
			continue

		# Nur Gegner IN Blickrichtung zählen - die Shape selbst deckt
		# bewusst beide Seiten ab, siehe _update_hitbox_side() oben für
		# die Spiegelung.
		var offset_x: float = (
			(body as Node2D).global_position.x - player.global_position.x
		)

		if player.facing_right and offset_x < 0:
			continue

		if not player.facing_right and offset_x > 0:
			continue

		if not found.has(body):
			found.append(body)

	if found.size() != 1:
		return null

	return found[0]


# ============================================================
# EXECUTION - ZIEL-SUCHE (PFAD DER STÄRKE)
# ============================================================

# WICHTIG (gefundener Grund für "geht bei 2-3 HP Gegnern nie"):
# execution_hp_threshold ist ein PROZENT-ANTEIL von max_health, kein
# fester Wert. Bei sehr niedrigem max_health (z.B. 2 oder 3) rundet
# "hp/max_health < threshold" rechnerisch auf 0 - der Gegner müsste
# also schon TOT sein, um noch als "unter der Schwelle" zu gelten,
# was nie passieren kann. Deshalb wird hier AUFGERUNDET (ceil) statt
# einfach das Verhältnis zu vergleichen: es gibt dadurch bei JEDEM
# max_health (auch 1, 2, 3...) immer mindestens einen HP-Wert, den
# der Gegner lebend erreichen kann, um zu qualifizieren. Beide Stellen
# unten (Ziel-Suche UND der eigentliche Treffer in _damage_body())
# benutzen bewusst genau diese eine Funktion, damit nie eine Stelle
# ein Ziel für gültig hält, das die andere ablehnt.
func _is_below_execution_threshold(hp: int, max_hp: int) -> bool:
	if max_hp <= 0:
		return false

	var cutoff_hp: int = int(ceil(float(max_hp) * execution_hp_threshold))

	return hp <= cutoff_hp


# Nutzer-Wunsch: sucht (in Blickrichtung, innerhalb execution_range)
# den nächsten Gegner unter execution_hp_threshold - wird VOR dem
# Abspielen der Angriffs-Animation aufgerufen (siehe attack() oben),
# weil zu dem Zeitpunkt noch feststehen muss, OB die Execution-
# Animation überhaupt gespielt wird (die normale AttackHitbox prüft
# erst viel später, mitten in der Animation, wer wirklich getroffen
# wird). Liefert null, wenn kein passender Gegner in Reichweite ist.
func _find_execution_target() -> Node:
	var best: Node = null
	var best_distance: float = INF

	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue

		if not (enemy is Node2D):
			continue

		if bool(enemy.get("dead")):
			continue

		var enemy_hp: Variant = enemy.get("hp")
		var enemy_max_hp: Variant = enemy.get("max_health")

		if not (enemy_hp is int and enemy_max_hp is int):
			continue

		if not _is_below_execution_threshold(enemy_hp, enemy_max_hp):
			continue

		var offset: Vector2 = (
			(enemy as Node2D).global_position - player.global_position
		)

		if player.facing_right and offset.x < 0:
			continue

		if not player.facing_right and offset.x > 0:
			continue

		var enemy_distance: float = abs(offset.x)

		if enemy_distance > execution_range:
			continue

		if enemy_distance < best_distance:
			best_distance = enemy_distance
			best = enemy

	return best


func _update_hitbox_side(target_hitbox: Area2D = null) -> void:
	var hitbox: Area2D = (
		attack_hitbox if target_hitbox == null else target_hitbox
	)

	if player.facing_right:
		hitbox.scale.x = 1
	else:
		hitbox.scale.x = -1


func _damage_body(
	body: Node,
	damage_amount: int,
	execution_mode: bool = false
) -> void:
	if body == player:
		return

	if not body.has_method("take_damage"):
		return

	var id: int = int(body.get_instance_id())

	if hit_targets.has(id):
		return

	hit_targets[id] = true

	var final_damage: int = damage_amount

	# Nutzer-Wunsch (Execution): pro getroffenem Gegner EINZELN
	# geprüft, unabhängig davon, welcher Gegner ursprünglich die
	# Execution-Animation ausgelöst hat (siehe _find_execution_target()
	# oben) - jeder Gegner unter execution_hp_threshold bekommt
	# execution_lethal_damage (Nutzer-Wunsch: fester hoher Wert statt
	# "genau sein aktuelles Leben" - das lief nicht immer sauber durch,
	# ein fester Überschuss-Schaden tötet zuverlässig über den ganz
	# normalen take_damage()/_die()-Weg, inklusive Kill-Zähler/Sound/
	# XP), alle anderen bekommen nur execution_fallback_damage statt
	# dem eigentlichen Schlag-Schaden.
	var is_execution_kill: bool = false

	if execution_mode:
		final_damage = execution_fallback_damage

		var body_hp: Variant = body.get("hp")
		var body_max_hp: Variant = body.get("max_health")

		if body_hp is int and body_max_hp is int:
			if _is_below_execution_threshold(body_hp, body_max_hp):
				final_damage = execution_lethal_damage
				is_execution_kill = true

	# WICHTIG (gefundener Grund für "execution killt nicht zuverlässig"
	# bei 5-10 HP Gegnern): jeder Gegner hat nach einem Treffer kurz
	# eigene Unverwundbarkeits-Frames (Skelett/Skelett-Bogenschütze:
	# "invincible" für hurt_time; Skelett-Tank/Fire Knight: "hit_lock"
	# für hit_lock_time), damit normale Treffer nicht mehrfach zählen.
	# Holt man mit einem normalen Schlag zuerst die HP runter und
	# folgt SOFORT mit Execution, kann die Execution noch in genau
	# diesem Fenster landen und wird dann komplett ignoriert - sieht
	# dann so aus, als würde Execution "manchmal einfach nichts tun".
	# Für den eigentlichen Execution-Kill (nicht den Fallback-Schaden
	# an anderen Gegnern) wird das hier gezielt aufgehoben, bevor der
	# Schaden angewendet wird - body.set() auf eine Property, die es
	# bei einem bestimmten Gegner-Typ gar nicht gibt, tut in Godot
	# einfach nichts, ist also für alle Gegner-Typen sicher.
	if is_execution_kill:
		body.set("invincible", false)
		body.set("hit_lock", false)

	body.take_damage(final_damage)
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
