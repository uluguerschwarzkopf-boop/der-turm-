extends Node2D

# Nutzer-Wunsch: alle Werte fürs Kampfgefühl an einer Stelle im Inspektor des
# Spielers (Node "CombatSettings" unter dem Player), jede Funktion mit einem
# Haken ein-/ausschaltbar. PlayerCombat und Player melden hier nur, was
# passiert ist. Was daraus wird, steht hier.


@export_group("Zeitlupe bei Treffer")

@export var zeitlupe_an: bool = true
## Spieltempo während der Zeitlupe (0.05 = 5 % = fast Stillstand).
@export_range(0.01, 1.0, 0.01) var zeitlupe_tempo: float = 0.05
## Dauer in echten Sekunden (nicht verlangsamt).
@export var zeitlupe_dauer: float = 0.06
## Eigene, etwas längere Dauer für den dritten Kombo-Schlag.
@export var zeitlupe_dauer_schlag_3: float = 0.09


@export_group("Kamera-Ruckler Schlag 3")

@export var ruckler_an: bool = true
## Stärke in Welt-Pixeln (bei Zoom 4.5 ist 1 Pixel schon gut sichtbar).
@export var ruckler_staerke: float = 1.5
@export var ruckler_dauer: float = 0.14
## An = nur wenn der dritte Schlag wirklich trifft, aus = bei jedem dritten Schlag.
@export var ruckler_nur_bei_treffer: bool = false


@export_group("Rückstoß Gegner")

@export var gegner_rueckstoss_an: bool = true
## So viele Pixel wird ein getroffener Gegner weggeschoben.
@export var gegner_rueckstoss_px: float = 4.0
@export var gegner_rueckstoss_px_schlag_3: float = 9.0
@export var gegner_rueckstoss_dauer: float = 0.1
## Aus = Bosse und Mini-Bosse bleiben stehen.
@export var gegner_rueckstoss_bei_bossen: bool = false
## An = nicht über Plattform-Kanten schieben.
@export var gegner_rueckstoss_kanten_schutz: bool = true


@export_group("Eingabe-Puffer")

@export var puffer_an: bool = true
## So lange (Sekunden) wird ein zu früher Schlag-Klick gemerkt und nachgeholt.
@export var puffer_zeit: float = 0.2


@export_group("Rolle")

@export var rolle_unverwundbar_an: bool = true
## Unverwundbar auf den ersten so vielen Frames der Roll-Animation.
@export var rolle_unverwundbar_frames: int = 2
## An = Rollen bricht die Boden-Combo ab (auch mitten im Schlag).
@export var rolle_bricht_schlag_ab: bool = true


@export_group("Rückstoß Spieler")

@export var spieler_rueckstoss_an: bool = true
## So viele Pixel rutscht der Spieler beim Treffer zurück.
@export var spieler_rueckstoss_px: float = 1.5
## Aus = beim dritten Schlag kein Rückstoß, weil er dort nach vorne dasht.
@export var spieler_rueckstoss_bei_schlag_3: bool = false


@export_group("Abprallen (Air Attack)")

@export var abprall_an: bool = true
## Sprungkraft nach oben (zum Vergleich: normaler Sprung ist 270).
@export var abprall_kraft: float = 190.0
## An = nur solange die Taste abprall_taste gehalten wird.
@export var abprall_nur_mit_taste: bool = false
@export var abprall_taste: StringName = &"drop_through"


@export_group("Treffer-Sound Schlag 3")

@export var schlag_3_sound_an: bool = true
## Sound aus der Sound-Bank des SoundManagers.
@export var schlag_3_sound_id: StringName = &"sword_hit_2"
## Unter 1 = tiefer und schwerer.
@export var schlag_3_sound_tonhoehe: float = 0.7


@export_group("Warnung vor Gegner-Angriffen")

@export var warnung_an: bool = true
@export var warnung_farbe: Color = Color(1.6, 1.25, 0.8)
@export var warnung_dauer: float = 0.28
@export var warnung_groesse: float = 1.0
## Pixel über der Gegner-Mitte.
@export var warnung_hoehe: float = 20.0
## Enthält der Animationsname eines Gegners eines dieser Wörter, gilt das als
## Angriff (Groß-/Kleinschreibung egal).
@export var warnung_woerter: Array[String] = ["attack", "angriff", "biss", "stich", "spuck", "nahkampf", "ranziehen"]


@export_group("Eigener Treffer")

@export var eigener_treffer_an: bool = true
@export_range(0.01, 1.0, 0.01) var eigener_treffer_tempo: float = 0.15
@export var eigener_treffer_dauer: float = 0.1
@export var eigener_treffer_ruckler_staerke: float = 2.5
@export var eigener_treffer_ruckler_dauer: float = 0.22


# Eine neuere Zeitlupe verlängert die laufende, die alte darf dann nicht
# vorzeitig zurücksetzen.
var _zeitlupe_nummer: int = 0
var _zeitlupe_aktiv: bool = false

# Letzte Animation je Gegner, um den Wechsel in einen Angriff zu erkennen.
var _letzte_anim: Dictionary = {}
var _warn_textur: Texture2D = null


func _ready() -> void:
	# Die Kamera-Ruckler laufen auf dem Player, der ist Eltern-Node. Dessen
	# Health-Referenz steht erst nach seinem _ready().
	await get_tree().process_frame

	var spieler: Node = get_parent()

	if spieler == null or not is_instance_valid(spieler):
		return

	var health: Variant = spieler.get("health")

	if health != null and health.has_signal("hurt"):
		health.hurt.connect(_on_spieler_getroffen)


func _exit_tree() -> void:
	# Sicherheitsnetz: Raumwechsel/Tod mitten in der Zeitlupe darf das Spiel
	# nicht dauerhaft verlangsamt lassen. Engine.time_scale überlebt Szenen.
	if _zeitlupe_aktiv:
		_zeitlupe_aktiv = false
		Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	if warnung_an:
		_pruefe_gegner_angriffe()


# ------------------------------------------------------------
# Meldungen von PlayerCombat / Player
# ------------------------------------------------------------

# Der dritte Kombo-Schlag wird ausgeführt (Treffer-Frame erreicht).
func on_schlag_3() -> void:
	if ruckler_an and not ruckler_nur_bei_treffer:
		_ruckler(ruckler_staerke, ruckler_dauer)


# Der Schlag hat mindestens einen Gegner wirklich getroffen. Wird pro Schlag
# nur einmal aufgerufen, auch wenn er mehrere Gegner erwischt.
func on_treffer(ist_schlag_3: bool, ist_air_attack: bool = false) -> void:
	if ist_schlag_3:
		if ruckler_an and ruckler_nur_bei_treffer:
			_ruckler(ruckler_staerke, ruckler_dauer)

		_spiele_schlag_3_sound()

	if zeitlupe_an:
		_zeitlupe(
			zeitlupe_tempo,
			zeitlupe_dauer_schlag_3 if ist_schlag_3 else zeitlupe_dauer
		)

	if ist_air_attack:
		_abprallen()
	elif spieler_rueckstoss_an and (spieler_rueckstoss_bei_schlag_3 or not ist_schlag_3):
		_spieler_rueckstoss()


# Einzeln für jeden getroffenen Gegner.
func on_gegner_getroffen(gegner: Node, ist_schlag_3: bool) -> void:
	if not gegner_rueckstoss_an or not (gegner is CharacterBody2D):
		return

	if not gegner_rueckstoss_bei_bossen and _ist_boss(gegner):
		return

	var px: float = gegner_rueckstoss_px_schlag_3 if ist_schlag_3 else gegner_rueckstoss_px

	_gegner_rueckstoss(gegner as CharacterBody2D, px)


# Schützt die Rolle gerade vor Schaden? (Player.take_damage() u.a. fragen das)
func rolle_schuetzt(spieler: Node) -> bool:
	if not rolle_unverwundbar_an or not bool(spieler.get("is_rolling")):
		return false

	var sprite: AnimatedSprite2D = spieler.get("sprite")

	return (
		sprite != null
		and sprite.animation == &"roll"
		and sprite.frame < rolle_unverwundbar_frames
	)


# ------------------------------------------------------------
# Umsetzung
# ------------------------------------------------------------

func _ruckler(staerke: float, dauer: float) -> void:
	var spieler: Node = get_parent()

	if spieler != null and spieler.has_method("_shake_camera"):
		spieler._shake_camera(staerke, dauer)


func _zeitlupe(tempo: float, dauer: float) -> void:
	var tree := get_tree()

	if tree == null or dauer <= 0.0:
		return

	_zeitlupe_nummer += 1
	var nummer: int = _zeitlupe_nummer

	_zeitlupe_aktiv = true
	Engine.time_scale = clampf(tempo, 0.01, 1.0)

	# ignore_time_scale: sonst dauert der Timer selbst 20x so lang.
	# process_always: läuft auch weiter, falls genau jetzt pausiert wird.
	await tree.create_timer(dauer, true, false, true).timeout

	if not is_instance_valid(self) or nummer != _zeitlupe_nummer:
		return

	_zeitlupe_aktiv = false
	Engine.time_scale = 1.0


func _on_spieler_getroffen() -> void:
	if not eigener_treffer_an:
		return

	_ruckler(eigener_treffer_ruckler_staerke, eigener_treffer_ruckler_dauer)
	_zeitlupe(eigener_treffer_tempo, eigener_treffer_dauer)


func _ist_boss(gegner: Node) -> bool:
	var skript: Script = gegner.get_script()

	if skript == null:
		return false

	var pfad: String = skript.resource_path

	return pfad.contains("/Bosse/") or pfad.contains("res://Bosse") or pfad.contains("mini bosse")


# Schiebt direkt über move_and_collide, statt an velocity zu drehen: die
# Gegner setzen velocity.x jeden Frame selbst und würden den Stoß überschreiben.
func _gegner_rueckstoss(gegner: CharacterBody2D, px: float) -> void:
	var spieler := get_parent() as Node2D

	if spieler == null or px <= 0.0:
		return

	var richtung: float = signf(gegner.global_position.x - spieler.global_position.x)

	if richtung == 0.0:
		richtung = 1.0 if bool(spieler.get("facing_right")) else -1.0

	var tree := get_tree()
	var dauer: float = maxf(gegner_rueckstoss_dauer, 0.01)
	var vergangen: float = 0.0
	var geschoben: float = 0.0

	while vergangen < dauer and is_instance_valid(gegner) and is_inside_tree():
		await tree.physics_frame

		if not is_instance_valid(gegner) or bool(gegner.get("dead")):
			return

		vergangen += get_physics_process_delta_time()

		# Abbremsend: der Stoß ist am Anfang am stärksten.
		var t: float = clampf(vergangen / dauer, 0.0, 1.0)
		var soll: float = px * (1.0 - (1.0 - t) * (1.0 - t))
		var schritt: float = (soll - geschoben) * richtung

		geschoben = soll

		if gegner_rueckstoss_kanten_schutz and gegner.is_on_floor():
			if not _boden_vorhanden(gegner, schritt):
				return

		gegner.move_and_collide(Vector2(schritt, 0.0))


func _boden_vorhanden(koerper: CharacterBody2D, schritt: float) -> bool:
	var abfrage := PhysicsPointQueryParameters2D.new()
	abfrage.position = koerper.global_position + Vector2(schritt + signf(schritt) * 4.0, 4.0)
	abfrage.collision_mask = koerper.collision_mask
	abfrage.exclude = [koerper.get_rid()]

	return not get_world_2d().direct_space_state.intersect_point(abfrage, 1).is_empty()


func _spieler_rueckstoss() -> void:
	var spieler := get_parent() as CharacterBody2D

	if spieler == null or spieler_rueckstoss_px <= 0.0:
		return

	var richtung: float = -1.0 if bool(spieler.get("facing_right")) else 1.0
	var schritte: int = 3
	var tree := get_tree()

	for i in schritte:
		await tree.physics_frame

		if not is_instance_valid(spieler):
			return

		spieler.move_and_collide(Vector2(richtung * spieler_rueckstoss_px / schritte, 0.0))


func _abprallen() -> void:
	if not abprall_an:
		return

	if abprall_nur_mit_taste and not Input.is_action_pressed(abprall_taste):
		return

	var spieler := get_parent() as CharacterBody2D

	if spieler != null:
		spieler.velocity.y = -abprall_kraft


func _spiele_schlag_3_sound() -> void:
	if not schlag_3_sound_an:
		return

	var sound: Node = get_parent().get_node_or_null("Scripts/SoundManager")

	if sound != null and sound.has_method("play"):
		sound.play(schlag_3_sound_id, schlag_3_sound_tonhoehe)


# Bewusst ein eigenes Zeichen über dem Gegner statt den Gegner einzufärben:
# die Gegner-Sprites haben eigene Shader, die modulate ignorieren.
func _pruefe_gegner_angriffe() -> void:
	for gegner: Node in get_tree().get_nodes_in_group(&"enemy"):
		var sprite: AnimatedSprite2D = null

		for kind: Node in gegner.get_children():
			if kind is AnimatedSprite2D:
				sprite = kind
				break

		if sprite == null:
			continue

		var id: int = gegner.get_instance_id()
		var anim: StringName = sprite.animation

		if _letzte_anim.get(id, &"") != anim:
			_letzte_anim[id] = anim

			if not bool(gegner.get("dead")) and _ist_angriff(String(anim)):
				_zeige_warnung(gegner)


func _ist_angriff(anim_name: String) -> bool:
	var klein: String = anim_name.to_lower()

	for wort: String in warnung_woerter:
		if klein.contains(wort.to_lower()):
			return true

	return false


func _zeige_warnung(gegner: Node) -> void:
	var spieler: Node = get_parent()

	if spieler == null or not spieler.has_method("get_enemy_center"):
		return

	var mitte: Vector2 = spieler.get_enemy_center(gegner)
	var zeichen := Sprite2D.new()

	zeichen.texture = _warn_form()
	zeichen.top_level = true
	zeichen.z_index = 20
	zeichen.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	zeichen.modulate = warnung_farbe
	zeichen.scale = Vector2.ONE * 0.2 * warnung_groesse
	add_child(zeichen)
	zeichen.global_position = mitte + Vector2(0.0, -warnung_hoehe)

	var dauer: float = maxf(warnung_dauer, 0.05)
	var t := create_tween()

	t.tween_property(zeichen, "scale", Vector2.ONE * warnung_groesse, dauer * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(zeichen, "modulate:a", 0.0, dauer * 0.65)
	t.tween_callback(zeichen.queue_free)


# Vierzackiger Lichtblitz in Pixel-Optik.
func _warn_form() -> Texture2D:
	if _warn_textur != null:
		return _warn_textur

	var groesse: int = 13
	var mitte: int = groesse / 2
	var bild := Image.create(groesse, groesse, false, Image.FORMAT_RGBA8)

	for i in groesse:
		var abstand: int = absi(i - mitte)
		var a: float = 1.0 - float(abstand) / float(mitte + 1)

		bild.set_pixel(i, mitte, Color(1, 1, 1, a))
		bild.set_pixel(mitte, i, Color(1, 1, 1, a))

	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			bild.set_pixel(mitte + dx, mitte + dy, Color(1, 1, 1, 1))

	_warn_textur = ImageTexture.create_from_image(bild)

	return _warn_textur
