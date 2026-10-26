extends Node

@export var damage: int = 1
@export var hitbox_active_time: float = 0.12

@export var attack_1_name: StringName = &"attack 1"
@export var attack_2_name: StringName = &"attack 2"

@export var attack_1_hit_delay: float = 0.22
@export var attack_2_hit_delay: float = 0.22

# Nutzer-Wunsch (neue Attack-1-Animation): die Hitbox von Attack 1 wird
# auf einem festen FRAME aktiv statt nach attack_1_hit_delay Sekunden.
# Frames zählen wie im SpriteFrames-Editor (erster Frame = 0).
# Aus = wieder die alte Zeit-Verzögerung (attack_1_hit_delay).
@export var attack_1_use_hit_frame: bool = true
@export var attack_1_hit_frame: int = 1

# Nutzer-Wunsch (neue Attack-2-Animation): wie bei Attack 1 auf festem
# Frame treffen (erster Frame = 0). Aus = alte Zeit-Verzögerung
# (attack_2_hit_delay).
@export var attack_2_use_hit_frame: bool = true
@export var attack_2_hit_frame: int = 2

# Nutzer-Wunsch: Attack 2 ist NICHT mehr abbrechbar (vorher konnte man
# den 2. Schlag ganz am Anfang durch Laufen/Springen abbrechen).
# An = altes Verhalten (abbrechbar bis zum Treffer-Frame).
@export var attack_2_cancelable: bool = false

# Läuft gerade der 2. Schlag (siehe is_uncancelable_attack()).
var _in_attack_2: bool = false


@export_group("Attack 3")

# Nutzer-Wunsch: dritter Schlag der Combo (attack 1 -> attack 2 ->
# Attack 3). Klickt man während Attack 2 nochmal, folgt Attack 3 -
# genau wie Attack 2 auf Attack 1 folgt. Aus = Combo endet nach
# Attack 2 (altes Verhalten).
@export var use_attack_3: bool = true

# Achtung: großes A und Leerzeichen, genau wie in den SpriteFrames.
@export var attack_3_name: StringName = &"Attack 3"

# Nutzer-Wunsch: Attack 3 macht 2 Schaden.
@export var attack_3_damage: int = 2

# Nutzer-Wunsch: Attack 3 gibt es nur, wenn attack 1 (oder Execution)
# UND attack 2 der aktuellen Combo je mindestens einen Gegner getroffen
# haben. Sonst endet die Combo nach attack 2. Aus = altes Verhalten
# (Attack 3 immer möglich).
@export var attack_3_requires_hits: bool = true

# Sound-ID aus der Sound-Bank (Player -> Scripts -> SoundManager). Es
# gibt noch keinen eigenen Sound für Attack 3 - legt man z.B.
# "sword_hit_3" in der Bank an, hier eintragen.
@export var attack_3_sound: StringName = &"sword_hit_1"

# Treffer-Frame (erster Frame = 0, wie im SpriteFrames-Editor).
# Aus = Zeit-Verzögerung attack_3_hit_delay statt Frame.
@export var attack_3_use_hit_frame: bool = true
@export var attack_3_hit_frame: int = 2
@export var attack_3_hit_delay: float = 0.22

# Wie Attack 2: standardmäßig NICHT abbrechbar (kein Laufen/Springen/
# Bogen). An = abbrechbar bis zum Treffer-Frame.
@export var attack_3_cancelable: bool = false

# Eigene Hitbox (Nutzer-Wunsch) - Pfad relativ zum Player.
@export var attack_3_hitbox_path: NodePath = ^"Hitboxes/Attack 3 Hitbox"

# Nutzer-Wunsch: bei Attack 3 ein kleiner Dash nach vorne (in
# Blickrichtung). Weite in Pixeln - Standard ca. 2 Schritte, also
# bewusst kurz (16 px = 1 Tile). 0 = kein Dash.
@export var attack_3_dash_distance: float = 16.0
# Tempo des Dashs in Pixeln pro Sekunde (Laufen = 160).
@export var attack_3_dash_speed: float = 140.0
# Ab diesem Frame der Attack-3-Animation startet der Dash (erster
# Frame = 0).
@export var attack_3_dash_start_frame: int = 1

# Treffer-Merker der aktuellen Combo (siehe attack_3_requires_hits).
var _attack_1_landed: bool = false
var _attack_2_landed: bool = false
# Hat die zuletzt aktivierte Hitbox einen Gegner getroffen?
var _last_hitbox_landed: bool = false
# Gegner, die beim Aktivieren der Hitbox noch lebten (Instanz-IDs).
var _alive_at_activation: Dictionary = {}
# Leben der Gegner beim Aktivieren der Hitbox (Instanz-ID -> hp).
var _hp_at_activation: Dictionary = {}

# Restweite des laufenden Attack-3-Dashs.
var _attack_3_dash_left: float = 0.0

# Läuft gerade der 3. Schlag.
var _in_attack_3: bool = false
var attack_3_hitbox: Area2D = null

@export_group("Attack up")

# Nutzer-Wunsch: Aufwärts-Schlag. W gedrückt halten + Schlag-Taste ->
# "Attack up" statt attack 1. Gehört NICHT zur 1-2-3-Combo und setzt
# die Combo zurück. Aus = W+Schlag macht ganz normal attack 1.
@export var use_attack_up: bool = true

# Achtung: großes A und Leerzeichen, genau wie in den SpriteFrames.
@export var attack_up_name: StringName = &"Attack up"

# Input-Action für "nach oben" (Projekteinstellungen -> Eingabe-
# belegung). Gibt es die Action (noch) nicht, wird stattdessen direkt
# die Taste attack_up_fallback_key geprüft - deshalb funktioniert W
# auch ohne Änderung an project.godot. W ist bisher keiner Action
# zugeordnet (Springen = Leertaste), also kein Konflikt.
@export var attack_up_action: StringName = &"attack_up"
@export var attack_up_fallback_key: Key = KEY_W

# An = Aufwärts-Schlag auch in der Luft.
@export var attack_up_in_air: bool = true

# Nutzer-Wunsch: in der Luft schränkt Attack up die Bewegung nicht ein -
# man fliegt mit normaler Luftsteuerung (Links/Rechts, gleiche
# Geschwindigkeit wie sonst) weiter, Sprungbogen und Schwerkraft bleiben
# unverändert. Aus = wie attack 1 waagrecht stehen bleiben und nur fallen.
# Am Boden bleibt Attack up immer stehen (auch nach dem Landen mitten in
# der Attacke).
@export var attack_up_air_keep_movement: bool = true

# Nur mit attack_up_air_keep_movement: darf man sich während der Attacke
# in der Luft umdrehen? Standard aus, damit Animation und Hitbox nicht
# umklappen (die Hitbox wird beim Treffer-Frame in Blickrichtung
# gespiegelt und dreht danach nicht mehr mit).
@export var attack_up_air_can_turn: bool = false

# Nutzer-Wunsch: wurde Attack up in der LUFT gestartet und man landet,
# während sie noch läuft, bricht Laufen (Links/Rechts) die Attacke ab
# dem Aufsetzen sofort ab -> normal weiter in run. Auch wenn man die
# Richtung beim Aufsetzen schon hält. Ohne Eingabe spielt die Animation
# wie bisher im Stehen zu Ende. Kam der Treffer-Frame noch nicht, gibt
# es einfach keinen Treffer. Attack up vom Boden aus ist davon nicht
# betroffen (bleibt durch Laufen nicht abbrechbar).
@export var attack_up_land_cancel_on_move: bool = true

# Wie oben, nur für Springen nach dem Aufsetzen.
@export var attack_up_land_cancel_on_jump: bool = true

@export var attack_up_damage: int = 1

# Treffer-Frame (erster Frame = 0, wie im SpriteFrames-Editor) - Frame,
# auf dem der Bogen über dem Kopf beginnt. Aus = Zeit-Verzögerung
# attack_up_hit_delay statt Frame.
@export var attack_up_use_hit_frame: bool = true
@export var attack_up_hit_frame: int = 1
@export var attack_up_hit_delay: float = 0.1

# Wie attack 1: standardmäßig NICHT abbrechbar (kein Laufen/Springen/
# Bogen). An = abbrechbar bis zum Treffer-Frame.
@export var attack_up_cancelable: bool = false

# Eigene Hitbox (Nutzer-Wunsch) - Pfad relativ zum Player.
@export var attack_up_hitbox_path: NodePath = ^"Hitboxes/Attack up Hitbox"

# Sound-ID aus der Sound-Bank (Player -> Scripts -> SoundManager), wie
# attack 1. Eigenen Sound in der Bank anlegen und hier eintragen.
@export var attack_up_sound: StringName = &"sword_hit_1"

# Läuft gerade der Aufwärts-Schlag.
var _in_attack_up: bool = false
# Wurde der laufende Attack up in der Luft gestartet (für den
# Lande-Abbruch, siehe attack_up_land_cancel_on_move).
var _attack_up_started_in_air: bool = false
# Zähler pro Attack up: ein abgebrochener Durchlauf (Coroutine wartet
# evtl. noch auf Frames) erkennt daran, dass er veraltet ist, und
# fasst danach nichts mehr an (keine Hitbox, kein _end_attack()).
var _attack_up_run_id: int = 0
var attack_up_hitbox: Area2D = null

@export_group("Air Attack")

# Nutzer-Wunsch: Schlag in der Luft. Linksklick (ohne W) in der Luft ->
# "Air Attack" statt attack 1. Einzelschlag, KEINE Combo, setzt die
# Boden-Combo zurück. W + Klick in der Luft bleibt Attack up. Am Boden
# gibt es die Air Attack nie. Kein Limit pro Sprung: ist die Animation
# fertig, kann man in der Luft sofort wieder schlagen.
# Aus = in der Luft wie bisher attack 1.
@export var use_air_attack: bool = true

# Achtung: großes A und Leerzeichen, genau wie in den SpriteFrames.
@export var air_attack_name: StringName = &"Air Attack"

@export var air_attack_damage: int = 1

# Nutzer-Wunsch: Hitbox ist über ein FENSTER aus Frames aktiv (erster
# Frame = 0): an beim Beginn von air_attack_hit_start_frame, aus beim
# Beginn des Frames NACH air_attack_hit_end_frame (Standard: an bei
# Frame 1, aus bei Frame 3). Jeder Gegner nimmt pro Schlag höchstens
# einmal Schaden, auch wenn er beide Frames in der Hitbox steht.
@export var air_attack_hit_start_frame: int = 1
@export var air_attack_hit_end_frame: int = 2

# Wie Attack up: standardmäßig NICHT abbrechbar (kein Laufen/Springen/
# Bogen in der Luft). An = abbrechbar bis zum Treffer-Frame.
@export var air_attack_cancelable: bool = false

# Eigene Hitbox (Nutzer-Wunsch) - Pfad relativ zum Player.
@export var air_attack_hitbox_path: NodePath = ^"Hitboxes/Air Attack Hitbox"

# Sound-ID aus der Sound-Bank (Player -> Scripts -> SoundManager), wie
# attack 1. Eigenen Sound in der Bank anlegen und hier eintragen.
@export var air_attack_sound: StringName = &"sword_hit_1"

# Wie attack_up_air_keep_movement: in der Luft mit normaler
# Luftsteuerung weiterfliegen, Sprungbogen und Schwerkraft bleiben
# unverändert. Aus = waagrecht stehen bleiben und nur fallen.
@export var air_attack_keep_movement: bool = true

# Darf man sich während der Air Attack umdrehen? Standard aus, damit
# Animation und Hitbox nicht umklappen. An = die Hitbox dreht während
# des Treffer-Fensters mit.
@export var air_attack_can_turn: bool = false

# Wie bei Attack up: landet man, während die Air Attack noch läuft,
# bricht Laufen (Links/Rechts) sie sofort ab (Hitbox aus). Ohne Eingabe
# spielt die Animation im Stehen zu Ende.
@export var air_attack_land_cancel_on_move: bool = true

# Wie oben, nur für Springen nach dem Aufsetzen.
@export var air_attack_land_cancel_on_jump: bool = true

# Läuft gerade die Air Attack.
var _in_air_attack: bool = false
# Zähler pro Air Attack, wie _attack_up_run_id: ein abgebrochener
# Durchlauf fasst danach nichts mehr an.
var _air_attack_run_id: int = 0
var air_attack_hitbox: Area2D = null

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

	# Attack-3-Hitbox (Nutzer-Wunsch) - gleich eingerichtet wie die
	# anderen, damit die Gegner-Hurtboxen sie als Spielerangriff
	# erkennen (Gruppe player_attack + meta active/damage).
	attack_3_hitbox = player.get_node_or_null(attack_3_hitbox_path) as Area2D

	if attack_3_hitbox != null:
		attack_3_hitbox.monitoring = false
		attack_3_hitbox.monitorable = true
		attack_3_hitbox.add_to_group("player_attack")
		attack_3_hitbox.set_meta("active", false)
		attack_3_hitbox.set_meta("damage", attack_3_damage)
	elif use_attack_3:
		push_warning("PlayerCombat: Attack 3 Hitbox nicht gefunden: %s" % attack_3_hitbox_path)

	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(attack_3_name):
		sprite.sprite_frames.set_animation_loop(attack_3_name, false)

	# Attack-up-Hitbox (Nutzer-Wunsch) - gleich eingerichtet wie Attack 3.
	attack_up_hitbox = player.get_node_or_null(attack_up_hitbox_path) as Area2D

	if attack_up_hitbox != null:
		attack_up_hitbox.monitoring = false
		attack_up_hitbox.monitorable = true
		attack_up_hitbox.add_to_group("player_attack")
		attack_up_hitbox.set_meta("active", false)
		attack_up_hitbox.set_meta("damage", attack_up_damage)
	elif use_attack_up:
		push_warning("PlayerCombat: Attack up Hitbox nicht gefunden: %s" % attack_up_hitbox_path)

	# Non-looping erzwingen, sonst kommt nie animation_finished.
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(attack_up_name):
		sprite.sprite_frames.set_animation_loop(attack_up_name, false)

	# Air-Attack-Hitbox (Nutzer-Wunsch) - gleich eingerichtet wie Attack up.
	air_attack_hitbox = player.get_node_or_null(air_attack_hitbox_path) as Area2D

	if air_attack_hitbox != null:
		air_attack_hitbox.monitoring = false
		air_attack_hitbox.monitorable = true
		air_attack_hitbox.add_to_group("player_attack")
		air_attack_hitbox.set_meta("active", false)
		air_attack_hitbox.set_meta("damage", air_attack_damage)
	elif use_air_attack:
		push_warning("PlayerCombat: Air Attack Hitbox nicht gefunden: %s" % air_attack_hitbox_path)

	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(air_attack_name):
		sprite.sprite_frames.set_animation_loop(air_attack_name, false)


func attack() -> void:
	if player.is_rolling:
		return

	if attacking:
		if (
			sprite.animation == attack_1_name
			or sprite.animation == execution_anim
			# Nutzer-Wunsch: Klick während Attack 2 -> Attack 3.
			or (sprite.animation == attack_2_name and _can_do_attack_3())
		):
			combo_requested = true
		return

	# Nutzer-Wunsch: W halten + Schlag -> Aufwärts-Schlag statt attack 1.
	if _wants_attack_up():
		await _attack_up()
		return

	# Nutzer-Wunsch: in der Luft (ohne W) -> Air Attack statt attack 1.
	if _wants_air_attack():
		await _air_attack()
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
	elif attack_1_use_hit_frame:
		await _wait_for_sprite_frame(attack_1_name, attack_1_hit_frame)
	else:
		await get_tree().create_timer(attack_1_hit_delay).timeout

	# target_hitbox bleibt null -> _activate_hitbox() benutzt die ganz
	# normale AttackHitbox (siehe Kommentar dort), execution_mode=true
	# sorgt nur dafür, dass _damage_body() weiter unten den Execution-
	# Schaden statt des normalen Schadens berechnet.
	await _activate_hitbox(-1, null, is_execution)

	# Neue Combo: Treffer-Merker neu setzen (Execution zählt wie
	# attack 1).
	_attack_1_landed = _last_hitbox_landed
	_attack_2_landed = false

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
		_in_attack_2 = true

		# Nutzer-Wunsch: nur offen, wenn Attack 2 abbrechbar sein soll.
		second_hit_cancel_window_open = attack_2_cancelable

		if attack_2_use_hit_frame:
			await _wait_for_sprite_frame(attack_2_name, attack_2_hit_frame)
		else:
			await get_tree().create_timer(attack_2_hit_delay).timeout

		second_hit_cancel_window_open = false

		if cancel_requested:
			_end_attack()
			return

		await _activate_hitbox()

		_attack_2_landed = _last_hitbox_landed

		await sprite.animation_finished

		# Nutzer-Wunsch: dritter Schlag, wenn während Attack 2
		# nochmal geklickt wurde.
		# Der Klick während attack 2 wird gepuffert (combo_requested);
		# erst hier, nach dem Treffer-Frame von attack 2, wird geprüft,
		# ob beide vorigen Schläge getroffen haben.
		if (
			combo_requested
			and _can_do_attack_3()
			and (
				not attack_3_requires_hits
				or (_attack_1_landed and _attack_2_landed)
			)
		):
			combo_requested = false

			_in_attack_2 = false
			_in_attack_3 = true
			_attack_3_dash_left = max(attack_3_dash_distance, 0.0)

			sprite.play(attack_3_name)
			_play_sound(attack_3_sound)

			second_hit_cancel_window_open = attack_3_cancelable

			if attack_3_use_hit_frame:
				await _wait_for_sprite_frame(attack_3_name, attack_3_hit_frame)
			else:
				await get_tree().create_timer(attack_3_hit_delay).timeout

			second_hit_cancel_window_open = false

			if cancel_requested:
				_end_attack()
				return

			await _activate_hitbox(attack_3_damage, attack_3_hitbox)

			await sprite.animation_finished

	_end_attack()


# Wird von player.gd jeden Physik-Frame während eines Angriffs
# abgefragt. Gibt die horizontale Geschwindigkeit für den Attack-3-
# Dash zurück (0 = stehen bleiben). Der Dash stoppt genau nach
# attack_3_dash_distance Pixeln.
func get_attack_dash_velocity(delta: float) -> float:
	if not attacking or not _in_attack_3:
		return 0.0

	if _attack_3_dash_left <= 0.0 or delta <= 0.0:
		return 0.0

	if sprite.animation != attack_3_name:
		return 0.0

	if sprite.frame < attack_3_dash_start_frame:
		return 0.0

	var step: float = min(attack_3_dash_speed * delta, _attack_3_dash_left)

	_attack_3_dash_left -= step

	var direction: float = 1.0 if player.facing_right else -1.0

	return direction * step / delta


# ============================================================
# ATTACK UP (AUFWÄRTS-SCHLAG)
# ============================================================

func _wants_attack_up() -> bool:
	if not use_attack_up or attack_up_hitbox == null:
		return false

	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(attack_up_name):
		return false

	if not attack_up_in_air and not player.is_on_floor():
		return false

	# Über die InputMap, damit eine spätere Tastenbelegung wirkt; ohne
	# Action direkt die Taste (Standard W).
	if InputMap.has_action(attack_up_action):
		return Input.is_action_pressed(attack_up_action)

	return Input.is_physical_key_pressed(attack_up_fallback_key)


# Wird von player.gd jeden Physik-Frame während eines Angriffs
# abgefragt: true = Attack up läuft in der Luft und die normale
# Luftsteuerung soll aktiv bleiben (siehe attack_up_air_keep_movement).
func is_attack_up_air_movement() -> bool:
	return (
		attacking
		and _in_attack_up
		and attack_up_air_keep_movement
		and not player.is_on_floor()
	)


# Wird von player.gd abgefragt: läuft ein in der Luft gestarteter
# Attack up, steht man jetzt am Boden und ist ein Lande-Abbruch
# überhaupt eingeschaltet? Die Eingabe (Laufen/Springen) prüft player.gd.
func can_land_cancel_attack_up() -> bool:
	return (
		attacking
		and _in_attack_up
		and _attack_up_started_in_air
		and player.is_on_floor()
		and (attack_up_land_cancel_on_move or attack_up_land_cancel_on_jump)
	)


# Bricht den Attack up sofort ab: Hitbox sicher aus, Angriff beendet.
# Die noch wartende _attack_up()-Coroutine merkt über _attack_up_run_id,
# dass sie veraltet ist, und schaltet die Hitbox nicht mehr ein.
func land_cancel_attack_up() -> void:
	_attack_up_run_id += 1

	if attack_up_hitbox != null:
		attack_up_hitbox.monitoring = false
		attack_up_hitbox.set_meta("active", false)

	_end_attack()


func _attack_up() -> void:
	attacking = true
	_in_attack_up = true
	_attack_up_started_in_air = not player.is_on_floor()
	_attack_up_run_id += 1
	var run_id: int = _attack_up_run_id
	combo_requested = false
	cancel_requested = false

	# Nicht Teil der Combo: Treffer-Merker zurücksetzen, damit danach
	# wieder ganz normal mit attack 1 begonnen wird.
	_attack_1_landed = false
	_attack_2_landed = false

	second_hit_cancel_window_open = attack_up_cancelable

	sprite.play(attack_up_name)
	_play_sound(attack_up_sound)

	if attack_up_use_hit_frame:
		# Auf den letzten Frame begrenzen - ein zu großer Wert würde
		# sonst ewig warten (Animation bleibt auf dem letzten Frame
		# stehen) und der Spieler könnte nie wieder angreifen.
		var last_frame: int = sprite.sprite_frames.get_frame_count(attack_up_name) - 1
		await _wait_for_sprite_frame(attack_up_name, clampi(attack_up_hit_frame, 0, max(last_frame, 0)))
	else:
		await get_tree().create_timer(attack_up_hit_delay).timeout

	# Inzwischen per Lande-Abbruch beendet -> nichts mehr anfassen.
	if run_id != _attack_up_run_id:
		return

	second_hit_cancel_window_open = false

	# Abgebrochen, gestorben oder Animation von außen überschrieben ->
	# Hitbox gar nicht erst einschalten.
	if (
		cancel_requested
		or bool(player.get("dead"))
		or sprite.animation != attack_up_name
	):
		_end_attack()
		return

	# _activate_hitbox() spiegelt die Hitbox in Blickrichtung, macht die
	# gleiche Echter-Schaden-Erkennung wie die anderen Schläge und
	# schaltet sie nach hitbox_active_time sicher wieder aus.
	await _activate_hitbox(attack_up_damage, attack_up_hitbox)

	if run_id != _attack_up_run_id:
		return

	await _wait_for_animation_end(attack_up_name)

	if run_id != _attack_up_run_id:
		return

	_end_attack()


# ============================================================
# AIR ATTACK (SCHLAG IN DER LUFT)
# ============================================================

func _wants_air_attack() -> bool:
	if not use_air_attack or air_attack_hitbox == null:
		return false

	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(air_attack_name):
		return false

	# Nutzer-Wunsch: nur in der Luft möglich.
	return not player.is_on_floor()


# Wird von player.gd jeden Physik-Frame während eines Angriffs
# abgefragt: true = Air Attack läuft in der Luft und die normale
# Luftsteuerung soll aktiv bleiben (siehe air_attack_keep_movement).
func is_air_attack_air_movement() -> bool:
	return (
		attacking
		and _in_air_attack
		and air_attack_keep_movement
		and not player.is_on_floor()
	)


# Wie can_land_cancel_attack_up(): läuft eine Air Attack, steht man
# jetzt am Boden und ist ein Lande-Abbruch eingeschaltet? Die Eingabe
# (Laufen/Springen) prüft player.gd. Die Air Attack startet immer in der
# Luft, deshalb braucht es hier keinen "in der Luft gestartet"-Merker.
func can_land_cancel_air_attack() -> bool:
	return (
		attacking
		and _in_air_attack
		and player.is_on_floor()
		and (air_attack_land_cancel_on_move or air_attack_land_cancel_on_jump)
	)


# Bricht die Air Attack sofort ab: Hitbox sicher aus, Angriff beendet.
# Die noch wartende _air_attack()-Coroutine merkt über
# _air_attack_run_id, dass sie veraltet ist.
func land_cancel_air_attack() -> void:
	_air_attack_run_id += 1

	if air_attack_hitbox != null:
		air_attack_hitbox.monitoring = false
		air_attack_hitbox.set_meta("active", false)

	_end_attack()


func _air_attack() -> void:
	attacking = true
	_in_air_attack = true
	_air_attack_run_id += 1
	var run_id: int = _air_attack_run_id
	combo_requested = false
	cancel_requested = false

	# Nicht Teil der Combo: Treffer-Merker zurücksetzen, damit am Boden
	# wieder ganz normal mit attack 1 begonnen wird.
	_attack_1_landed = false
	_attack_2_landed = false

	second_hit_cancel_window_open = air_attack_cancelable

	sprite.play(air_attack_name)
	_play_sound(air_attack_sound)

	# Auf gültige Frames begrenzen - ein zu großer Wert würde sonst ewig
	# warten (Animation bleibt auf dem letzten Frame stehen).
	var last_frame: int = max(sprite.sprite_frames.get_frame_count(air_attack_name) - 1, 0)
	var start_frame: int = clampi(air_attack_hit_start_frame, 0, last_frame)
	var end_frame: int = clampi(air_attack_hit_end_frame, start_frame, last_frame)

	await _wait_for_sprite_frame(air_attack_name, start_frame)

	# Inzwischen per Lande-Abbruch beendet -> nichts mehr anfassen.
	if run_id != _air_attack_run_id:
		return

	second_hit_cancel_window_open = false

	# Abgebrochen, gestorben oder Animation von außen überschrieben ->
	# Hitbox gar nicht erst einschalten.
	if (
		cancel_requested
		or bool(player.get("dead"))
		or sprite.animation != air_attack_name
	):
		_end_attack()
		return

	await _activate_air_attack_hitbox(run_id, end_frame)

	if run_id != _air_attack_run_id:
		return

	await _wait_for_animation_end(air_attack_name)

	if run_id != _air_attack_run_id:
		return

	_end_attack()


# Wie _activate_hitbox(), aber die Hitbox bleibt nicht hitbox_active_time
# lang an, sondern so lange, bis die Animation über end_frame hinaus ist
# (Frame-Fenster, Nutzer-Wunsch). Gleiche Echter-Schaden-Erkennung.
#
# Pro Schlag höchstens ein Treffer je Gegner: die Gegner sperren sich
# selbst nur kurz (damage_hit_locked bzw. hit_lock, meist 0.12 s), das
# Fenster aus 2 Frames bei 11 FPS ist aber ~0.18 s lang. Deshalb wird die
# Treffer-Sperre eines schon getroffenen Gegners bis zum Fensterende
# gehalten und danach wieder freigegeben (nur wenn wir sie gesetzt haben).
func _activate_air_attack_hitbox(run_id: int, end_frame: int) -> void:
	var hitbox: Area2D = air_attack_hitbox

	hit_targets.clear()
	_last_hitbox_landed = false

	_alive_at_activation.clear()
	_hp_at_activation.clear()

	for enemy: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not bool(enemy.get("dead")):
			_alive_at_activation[enemy.get_instance_id()] = true

		var enemy_hp: Variant = enemy.get("hp")

		if enemy_hp is int or enemy_hp is float:
			_hp_at_activation[enemy.get_instance_id()] = float(enemy_hp)

	_update_hitbox_side(hitbox)

	hitbox.set_meta("active", true)
	hitbox.set_meta("damage", air_attack_damage)
	hitbox.monitoring = true

	var hit_enemies: Dictionary = {}
	# Instanz-ID -> Liste der Sperr-Properties, die WIR gesetzt haben.
	var held_locks: Dictionary = {}

	# Robustheit: Zeitgrenze aus Frameanzahl/FPS, falls die Animation
	# hängt oder speed_scale 0 ist.
	var fps: float = sprite.sprite_frames.get_animation_speed(air_attack_name) * absf(sprite.speed_scale)
	var max_time: float = (float(end_frame + 2) / fps if fps > 0.0 else 1.0) + 0.2
	var elapsed: float = 0.0

	await get_tree().physics_frame

	while true:
		if (
			run_id != _air_attack_run_id
			or cancel_requested
			or not is_inside_tree()
			or bool(player.get("dead"))
			or not is_instance_valid(sprite)
			or sprite.animation != air_attack_name
			or sprite.frame > end_frame
			or elapsed >= max_time
		):
			break

		if air_attack_can_turn:
			_update_hitbox_side(hitbox)

		# Gegner ohne eigene Hurtbox bekommen den Schaden über ihren
		# Körper - aber nicht nochmal, wenn sie schon über ihre Hurtbox
		# getroffen wurden.
		for body: Node in hitbox.get_overlapping_bodies():
			if not hit_enemies.has(body.get_instance_id()):
				_damage_body(body, air_attack_damage)

		_collect_damaged_enemies(hitbox, hit_enemies)
		_hold_hit_locks(hit_enemies, held_locks)

		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	_last_hitbox_landed = not hit_enemies.is_empty()

	hitbox.monitoring = false
	hitbox.set_meta("active", false)

	_release_held_hit_locks(held_locks)


const _HIT_LOCK_PROPERTIES: Array[StringName] = [&"damage_hit_locked", &"hit_lock"]


func _hold_hit_locks(hit_enemies: Dictionary, held_locks: Dictionary) -> void:
	for id: int in hit_enemies.keys():
		var obj: Variant = hit_enemies[id]

		if not is_instance_valid(obj) or bool(obj.get("dead")):
			continue

		var node: Node = obj

		for prop: StringName in _HIT_LOCK_PROPERTIES:
			# Nur sperren, wenn der Gegner die Property hat und seine
			# eigene Sperre schon wieder frei ist.
			if node.get(prop) is bool and node.get(prop) == false:
				node.set(prop, true)

				if not held_locks.has(id):
					held_locks[id] = {"node": node, "props": []}

				if not held_locks[id]["props"].has(prop):
					held_locks[id]["props"].append(prop)


func _release_held_hit_locks(held_locks: Dictionary) -> void:
	for id: int in held_locks.keys():
		var obj: Variant = held_locks[id]["node"]

		# Tote Gegner sperren sich in _die() selbst dauerhaft - so lassen.
		if not is_instance_valid(obj) or bool(obj.get("dead")):
			continue

		var node: Node = obj

		for prop: StringName in held_locks[id]["props"]:
			node.set(prop, false)


# Robustheit (siehe CLAUDE.md): nicht nur auf animation_finished
# warten, sondern zusätzlich mit einer Zeitgrenze aus Frameanzahl/FPS
# absichern, sonst kann "attacking" für immer hängen bleiben (z.B. wenn
# Tod/Treffer die Animation überschreibt).
func _wait_for_animation_end(anim: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	var frames: SpriteFrames = sprite.sprite_frames
	var fps: float = frames.get_animation_speed(anim) * absf(sprite.speed_scale)
	var total: float = 0.0

	for i in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, i)

	var max_time: float = (total / fps if fps > 0.0 else 1.0) + 0.2
	var elapsed: float = 0.0

	while (
		is_instance_valid(sprite)
		and sprite.animation == anim
		and sprite.is_playing()
		and elapsed < max_time
		and not bool(player.get("dead"))
	):
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _can_do_attack_3() -> bool:
	return (
		use_attack_3
		and attack_3_hitbox != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(attack_3_name)
	)


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

	if attack_3_hitbox != null:
		attack_3_hitbox.monitoring = false
		attack_3_hitbox.set_meta("active", false)

	if attack_up_hitbox != null:
		attack_up_hitbox.monitoring = false
		attack_up_hitbox.set_meta("active", false)

	if air_attack_hitbox != null:
		air_attack_hitbox.monitoring = false
		air_attack_hitbox.set_meta("active", false)


# Läuft gerade Attack 2 oder 3 und darf (Nutzer-Wunsch) nicht
# abgebrochen werden? Wird von player.gd abgefragt, z.B. damit der
# Bogen den Schlag nicht überschreibt.
func is_uncancelable_attack() -> bool:
	if not attacking:
		return false

	if _in_attack_2 and not attack_2_cancelable:
		return true

	if _in_attack_up and not attack_up_cancelable:
		return true

	if _in_air_attack and not air_attack_cancelable:
		return true

	return _in_attack_3 and not attack_3_cancelable


func _end_attack() -> void:
	_in_attack_2 = false
	_in_attack_3 = false
	_in_attack_up = false
	_attack_up_started_in_air = false
	_in_air_attack = false
	_attack_3_dash_left = 0.0
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
	_last_hitbox_landed = false

	# Nutzer-Wunsch: ein Gegner, den DIESER Schlag tötet, zählt als
	# Treffer (Hit-Effekt kommt auch beim Todesschlag). Dafür merken wir
	# uns, wer beim Aktivieren noch lebte - Leichen, die schon vorher
	# tot waren, zählen weiterhin nicht.
	_alive_at_activation.clear()

	for enemy: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not bool(enemy.get("dead")):
			_alive_at_activation[enemy.get_instance_id()] = true

	_update_hitbox_side(hitbox)

	hitbox.set_meta("active", true)
	hitbox.set_meta("damage", applied_damage)
	hitbox.monitoring = true

	# Nutzer-Korrektur: als Treffer zählt nur, wenn der Gegner durch
	# DIESEN Schlag wirklich Schaden bekommen hat (Leben gesunken oder
	# gestorben) - nur "in Reichweite"/in der Hitbox stehen reicht
	# nicht (z.B. Gegner gerade unverwundbar, schläft noch, Treffer-
	# Sperre). Dafür das Leben aller Gegner vor dem Schlag merken.
	_hp_at_activation.clear()

	for enemy: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy_hp: Variant = enemy.get("hp")

		if enemy_hp is int or enemy_hp is float:
			_hp_at_activation[enemy.get_instance_id()] = float(enemy_hp)

	await get_tree().physics_frame

	for body in hitbox.get_overlapping_bodies():
		_damage_body(body, applied_damage, execution_mode)

	# Alle getroffenen Gegner dieses Schlags (Instanz-ID -> Node).
	var hit_enemies: Dictionary = {}
	# Gegner, für die der Attack-3-Hit-Effekt schon kam.
	var effect_shown: Dictionary = {}

	# Jeden Physik-Frame der aktiven Zeit prüfen, wer Schaden bekommen
	# hat - Gebiet-2-Mobs nehmen den Schaden selbst über ihre Hurtbox,
	# das passiert in ihrem eigenen Physik-Frame.
	var elapsed: float = 0.0

	while true:
		_collect_damaged_enemies(hitbox, hit_enemies)

		# Nutzer-Wunsch: Attack-3-Hit-Effekt sofort beim Treffer, in der
		# Mitte des getroffenen Gegners (siehe Player
		# spawn_attack_3_hit_effect()). Pro Gegner höchstens einmal.
		if hitbox == attack_3_hitbox:
			_show_attack_3_hit_effects(hit_enemies, effect_shown)

		if elapsed >= hitbox_active_time or not is_inside_tree():
			break

		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	_last_hitbox_landed = not hit_enemies.is_empty()

	hitbox.monitoring = false
	hitbox.set_meta("active", false)


# Sammelt alle Gegner, die (über ihren Körper oder ihre Hurtbox) in
# der Hitbox stecken bzw. von _damage_body() getroffen wurden UND
# seit dem Aktivieren wirklich Schaden bekommen haben.
func _collect_damaged_enemies(hitbox: Area2D, hit_enemies: Dictionary) -> void:
	var candidates: Array[Node] = []

	for body: Node in hitbox.get_overlapping_bodies():
		candidates.append(body)

	for area: Area2D in hitbox.get_overlapping_areas():
		candidates.append(area)
		candidates.append(area.get_parent())

	for id: int in hit_targets.keys():
		var node: Object = instance_from_id(id)

		if node is Node and is_instance_valid(node):
			candidates.append(node as Node)

	for node: Node in candidates:
		if node == null or not is_instance_valid(node):
			continue

		if hit_enemies.has(node.get_instance_id()):
			continue

		if _was_damaged_by_this_hit(node):
			hit_enemies[node.get_instance_id()] = node


func _was_damaged_by_this_hit(node: Node) -> bool:
	if node == player or not node.is_in_group(&"enemy"):
		return false

	var id: int = node.get_instance_id()

	# Durch diesen Schlag gestorben (vorher noch am Leben).
	if bool(node.get("dead")) and _alive_at_activation.has(id):
		return true

	# Leben gesunken.
	if _hp_at_activation.has(id):
		var current_hp: Variant = node.get("hp")

		if (current_hp is int or current_hp is float) and float(current_hp) < _hp_at_activation[id]:
			return true

		return false

	# Gegner ohne "hp"-Variable: dann zählt, dass _damage_body() ihm
	# Schaden gegeben hat.
	return hit_targets.has(id)


# Spawnt den Attack-3-Hit-Effekt für alle (noch nicht gezeigten)
# getroffenen Gegner - oder nur für einen, wenn
# attack_3_hit_effect_per_enemy (am Player) aus ist.
func _show_attack_3_hit_effects(hit_enemies: Dictionary, effect_shown: Dictionary) -> void:
	if player == null or not player.has_method("spawn_attack_3_hit_effect"):
		return

	var per_enemy: bool = bool(player.get("attack_3_hit_effect_per_enemy"))

	for id: int in hit_enemies.keys():
		if not per_enemy and not effect_shown.is_empty():
			return

		if effect_shown.has(id):
			continue

		effect_shown[id] = true
		player.spawn_attack_3_hit_effect(hit_enemies[id])



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
