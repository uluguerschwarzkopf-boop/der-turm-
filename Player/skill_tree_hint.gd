extends Node2D
class_name SkillTreeHint


# ============================================================
# HINWEIS
# ============================================================

# Einfacher Hinweistext über dem Spieler (z.B. "T - Skill-Baum
# öffnen", siehe Objects/Staturen/skill_statue.gd -> _maybe_show_
# skill_tree_open_hint()) - anders als PlayerThoughtBubble (Player/
# player_thought_bubble.gd, für die Raum-Gedankenblasen) BEWUSST:
#   - OHNE Box/Hintergrund, nur reiner Text (Nutzer-Wunsch: "soll
#     ohne Box kommen, einfach über dem Spieler normal stehen")
#   - OHNE automatisches Verschwinden nach einer festen Zeit - bleibt
#     stehen, bis dismiss_action tatsächlich gedrückt wird (siehe
#     _process() unten, Nutzer-Wunsch: "geht erst weg, wenn man dann
#     T gedrückt hat")
#   - AKTUALISIERT sich live, wenn dismiss_action in den Einstellungen
#     umbelegt wird (siehe _on_controls_changed()), statt weiter die
#     alte Taste anzuzeigen
#
# WICHTIG: Buchstaben werden EINZELN als eigene Labels aufgebaut -
# GENAU wie PlayerThoughtBubble._rebuild_letters() - bewusst NICHT
# ein einzelnes Label mit dem kompletten String: Letzteres hat den
# ersten Buchstaben ("T") verzerrt/wie einen Pfeil aussehen lassen
# (Ursache unklar, evtl. Label-Eigenlayout vs. eigene text_width-
# Berechnung nicht exakt deckungsgleich) - die pro-Buchstabe-Methode
# ist an den Raum-Gedankenblasen bereits erprobt und fehlerfrei.
#
# process_mode = PROCESS_MODE_ALWAYS ist hier PFLICHT (nicht nur
# Komfort): Game/skill_tree_menu.gd pausiert den Spielbaum beim
# Öffnen (get_tree().paused = true) GENAU in dem Frame, in dem T
# gedrückt wird - ohne ALWAYS würde _process() unten (das genau
# diesen Tastendruck erkennen soll) in exakt diesem Moment einfach
# nicht laufen, und der Hinweis bliebe für immer stehen.
#
# Wird (wie PlayerThoughtBubble) als Kind des Spieler-Node
# hinzugefügt und bleibt dadurch automatisch über ihm - kein eigenes
# Nachführen der Position nötig.

static var PIXEL_FONT: FontFile = preload("res://Fonts/pixelify_sans.woff2")


@export var vertical_offset: float = -34.0
@export var font_size: int = 10
@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var fade_time: float = 0.25


# Übersetzungsschlüssel MIT "%s" für die Taste (siehe Game/settings_
# manager.gd -> "hint.skill_tree_open") - wird in _refresh_text()
# über SettingsManager.get_binding_text(dismiss_action) aufgefüllt.
var translation_key: String = "hint.skill_tree_open"

# Aktion, bei deren erstem Drücken der Hinweis verschwindet UND deren
# aktuell gebundene Taste im Text steht (siehe _refresh_text()).
var dismiss_action: StringName = &"open_skill_tree"

signal dismissed

var _letters: Array[Label] = []
var _dismissed: bool = false


func _ready() -> void:
	# Siehe HINWEIS oben - Pflicht, kein reiner Komfort-Fix.
	process_mode = Node.PROCESS_MODE_ALWAYS

	position = Vector2(0.0, vertical_offset)

	# Rendert immer oben, unabhängig vom z_index des Spielers - genau
	# wie bei PlayerThoughtBubble.
	z_as_relative = false
	z_index = 100

	# Siehe PlayerThoughtBubble für die Begründung (schärfer nach dem
	# Kamera-Zoom, echte Kleinbuchstaben statt grober Blöcke).
	PIXEL_FONT.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	PIXEL_FONT.hinting = TextServer.HINTING_LIGHT
	PIXEL_FONT.oversampling = 6.0

	if get_node_or_null("/root/SettingsManager") != null:
		if not SettingsManager.controls_changed.is_connected(
			_on_controls_changed
		):
			SettingsManager.controls_changed.connect(
				_on_controls_changed
			)

	_refresh_text()

	for letter in _letters:
		letter.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_method(_set_reveal_alpha, 0.0, 1.0, fade_time)


func _on_controls_changed(action_name: StringName) -> void:
	if action_name != dismiss_action:
		return

	_refresh_text()


# ============================================================
# TEXT AUFBAUEN (PRO BUCHSTABE EIN LABEL, siehe HINWEIS oben)
# ============================================================

func _refresh_text() -> void:
	var key_text: String = "?"
	var full_text: String

	if get_node_or_null("/root/SettingsManager") != null:
		key_text = SettingsManager.get_binding_text(dismiss_action)
		full_text = SettingsManager.t(translation_key) % key_text
	else:
		full_text = key_text

	_rebuild_letters(full_text)


func _rebuild_letters(text: String) -> void:
	for letter in _letters:
		letter.queue_free()

	_letters.clear()

	var row_width: float = 0.0

	for character in text:
		row_width += PIXEL_FONT.get_string_size(
			character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x

	var running_x: float = -row_width / 2.0

	for character in text:
		var char_width: float = PIXEL_FONT.get_string_size(
			character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x

		var letter := Label.new()
		letter.text = character
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.add_theme_font_override("font", PIXEL_FONT)
		letter.add_theme_font_size_override("font_size", font_size)
		letter.add_theme_color_override("font_color", text_color)
		add_child(letter)

		letter.position = Vector2(running_x, -float(font_size))
		running_x += char_width

		_letters.append(letter)


func _set_reveal_alpha(alpha: float) -> void:
	for letter in _letters:
		if is_instance_valid(letter):
			letter.modulate.a = alpha


# ============================================================
# VERSCHWINDEN BEI TASTENDRUCK
# ============================================================

func _process(_delta: float) -> void:
	if _dismissed:
		return

	if not Input.is_action_just_pressed(dismiss_action):
		return

	_dismiss()


func _dismiss() -> void:
	if _dismissed:
		return

	_dismissed = true
	dismissed.emit()

	if _letters.is_empty():
		queue_free()
		return

	var tween := create_tween()
	tween.tween_method(_set_reveal_alpha, 1.0, 0.0, fade_time)

	await tween.finished

	queue_free()
