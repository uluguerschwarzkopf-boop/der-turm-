extends Node2D
class_name InteractionPrompt


# ============================================================
# HINWEIS
# ============================================================

# Wiederverwendbare schwebende Interaktions-Anzeige (z.B. beim
# Händler): zeigt einen Text Buchstabe für Buchstabe an, wobei
# jeder Buchstabe einzeln wie eine Welle auf und ab schwebt
# (Zeitversatz zwischen Nachbarbuchstaben). Beim Verschwinden
# läuft derselbe Effekt mit derselben Geschwindigkeit rückwärts.
# Alles (Tempo, Farbe, Welle, Position) ist über den Inspector
# einstellbar - pro Node individuell, z.B. für unterschiedliche
# Händler/Truhen/Türen.
#
# Wird als Kind der jeweiligen InteractionArea gehängt und
# positioniert sich automatisch oberhalb davon (vertical_offset).
# Rendert immer über allem anderen (eigener z_index, unabhängig
# vom z_index des Elternobjekts) - sonst kann der Text hinter
# Boden-Tiles verschwinden, falls der Träger selbst einen
# negativen z_index hat (wie beim Händler).
#
# Benutzung: show_prompt(action, text_key) / show_text(text_key) /
# show_key_only(action) / hide_prompt() rufen. Die Taste im Text
# kommt live aus SettingsManager und aktualisiert sich automatisch
# bei Rebind/Sprachwechsel.


# ============================================================
# EINSTELLUNGEN (Inspector)
# ============================================================

@export_group("Tipp-Effekt")

# Zeit pro Buchstabe beim Rein- und beim Rausgehen (gleiche
# Geschwindigkeit in beide Richtungen).
@export var seconds_per_letter: float = 0.04


@export_group("Farbe")

@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var font_size: int = 16


@export_group("Schweben")

# Wie schnell ein einzelner Buchstabe hoch und runter geht.
@export var wave_speed: float = 4.0

# Wie weit ein einzelner Buchstabe hoch und runter geht.
@export var wave_height: float = 3.0

# Zeitversatz zwischen benachbarten Buchstaben, damit es wie
# eine durchlaufende Welle aussieht statt einem gleichzeitigen
# Wippen des ganzen Texts.
@export var wave_letter_delay: float = 0.08


@export_group("Position")

# Abstand nach oben von diesem Node weg (negativ = nach oben).
# Bei einem Kind der InteractionArea also der Abstand über
# deren Ursprung.
@export var vertical_offset: float = -72.0

# Rendert immer oben, unabhängig vom z_index des Elternobjekts.
@export var always_on_top: bool = true


# ============================================================
# STATUS
# ============================================================

var _action_name: StringName = &""
var _text_key: String = ""
var _show_key_suffix: bool = true
var _key_only: bool = false

var _letters: Array[Label] = []
var _elapsed_time: float = 0.0
var _floating: bool = false

var _reveal_tween: Tween
var _reveal_value: float = 0.0


# ============================================================
# START
# ============================================================

func _ready() -> void:
	position = Vector2(0.0, vertical_offset)

	if always_on_top:
		z_as_relative = false
		z_index = 100

	visible = false

	if get_node_or_null("/root/SettingsManager") != null:
		if not SettingsManager.controls_changed.is_connected(
			_on_controls_changed
		):
			SettingsManager.controls_changed.connect(
				_on_controls_changed
			)

		if not SettingsManager.language_changed.is_connected(
			_on_language_changed
		):
			SettingsManager.language_changed.connect(
				_on_language_changed
			)


func _process(delta: float) -> void:
	if not _floating:
		return

	_elapsed_time += delta

	for i in _letters.size():
		var letter: Label = _letters[i]
		var phase: float = wave_speed * (
			_elapsed_time - i * wave_letter_delay
		)

		# Auf ganze Pixel runden (siehe auch _rebuild_letters() für die
		# X-Position) - eine krumme Kommazahl-Position lässt die
		# Pixel-Schrift beim Rendern seitlich "verschmieren"/ungleich
		# breite Kanten bekommen, siehe Nutzer-Feedback zum Händler-
		# Kaufen-Text.
		letter.position.y = round(sin(phase) * wave_height)


# ============================================================
# ÖFFENTLICHE FUNKTIONEN
# ============================================================

# action_name: die Input-Action, deren aktuelle Taste angezeigt
# werden soll (z.B. &"interact").
# text_key: SettingsManager-Übersetzungsschlüssel für das Verb
# vor der Taste (z.B. "shop.prompt_prefix" -> "Kaufen [V]").
func show_prompt(
	action_name: StringName,
	text_key: String
) -> void:
	_action_name = action_name
	_text_key = text_key
	_show_key_suffix = true
	_key_only = false

	_refresh_text()

	visible = true
	_elapsed_time = 0.0
	_floating = true

	_start_reveal_tween(float(_letters.size()))


# Wie show_prompt(), aber OHNE angehängte Taste - für reinen Info-
# Text statt einer Handlungsaufforderung (z.B. die Pfad-Namen bei
# den Skill-Baum-Staturen, siehe Objects/Staturen/skill_statue.gd).
func show_text(text_key: String) -> void:
	_action_name = &""
	_text_key = text_key
	_show_key_suffix = false
	_key_only = false

	_refresh_text()

	visible = true
	_elapsed_time = 0.0
	_floating = true

	_start_reveal_tween(float(_letters.size()))


# Wie show_prompt(), aber OHNE jeden Verb-Text/Klammern davor -
# zeigt NUR die Taste selbst (z.B. nur "V"). Für Fälle, wo aus dem
# Kontext (z.B. der Händler selbst) schon klar ist, WAS die Taste
# tut, und nur noch WELCHE Taste gezeigt werden soll.
func show_key_only(action_name: StringName) -> void:
	_action_name = action_name
	_text_key = ""
	_show_key_suffix = false
	_key_only = true

	_refresh_text()

	visible = true
	_elapsed_time = 0.0
	_floating = true

	_start_reveal_tween(float(_letters.size()))


func hide_prompt() -> void:
	if not visible:
		return

	_start_reveal_tween(0.0)


func is_prompt_visible() -> bool:
	return visible and _reveal_value > 0.0


# ============================================================
# TIPP-EFFEKT (BUCHSTABENWEISE REIN/RAUS)
# ============================================================

func _start_reveal_tween(target: float) -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()

	var distance: float = abs(target - _reveal_value)
	var duration: float = max(
		distance * seconds_per_letter,
		0.01
	)

	_reveal_tween = create_tween()
	_reveal_tween.tween_method(
		_set_reveal_value,
		_reveal_value,
		target,
		duration
	)

	if target <= 0.0:
		_reveal_tween.finished.connect(
			_on_hide_finished,
			CONNECT_ONE_SHOT
		)


func _on_hide_finished() -> void:
	visible = false
	_floating = false


func _set_reveal_value(value: float) -> void:
	_reveal_value = value

	for i in _letters.size():
		_letters[i].modulate.a = clamp(value - i, 0.0, 1.0)


# ============================================================
# TEXT, TASTE UND BUCHSTABEN-AUFBAU
# ============================================================

func _refresh_text() -> void:
	if _key_only:
		var key_only_text: String = "?"

		if get_node_or_null("/root/SettingsManager") != null:
			key_only_text = SettingsManager.get_binding_text(
				_action_name
			)

		_rebuild_letters(key_only_text)
		return

	if _text_key == "":
		return

	if _show_key_suffix and _action_name == &"":
		return

	var text: String = _text_key

	if get_node_or_null("/root/SettingsManager") != null:
		text = SettingsManager.t(_text_key)

	if _show_key_suffix:
		var key_text: String = "?"

		if get_node_or_null("/root/SettingsManager") != null:
			key_text = SettingsManager.get_binding_text(_action_name)

		text = text + " [" + key_text + "]"

	_rebuild_letters(text)


# ============================================================
# SCHRIFT: LAUFZEIT-FEINABSTIMMUNG (KEIN Godot-Reimport nötig)
# ============================================================

# Der Reimport der Schriftart im Godot-Editor (Antialiasing aus)
# klappte auf dem Ziel-Rechner nicht zuverlässig - darum wird die
# Schrift hier stattdessen direkt per Code justiert. Das greift
# GARANTIERT bei jedem Spielstart, unabhängig davon, ob Godot die
# .import-Einstellungen im Editor neu eingelesen hat, weil die
# Eigenschaften direkt zur Laufzeit auf der geladenen FontFile
# gesetzt werden (Antialiasing/Hinting/Subpixel AUS) - und zusätzlich
# über eine FontVariation mit negativem variation_embolden dünnere
# Striche erzwingt (Nutzer-Wunsch: "Schrift dünner machen"), OHNE
# die restliche Spiel-Schrift (Menüs/Titel) anzufassen - die bleibt
# unverändert, nur dieser schwebende Text wird angepasst.
const _PIXEL_FONT_EMBOLDEN: float = -0.4

static var _pixel_font_cache: FontVariation = null


static func _get_pixel_font() -> Font:
	if _pixel_font_cache != null:
		return _pixel_font_cache

	var base_font: FontFile = (
		load("res://Fonts/pixelify_sans.woff2") as FontFile
	)

	if base_font == null:
		return ThemeDB.fallback_font

	base_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	base_font.hinting = TextServer.HINTING_NONE
	base_font.subpixel_positioning = (
		TextServer.SUBPIXEL_POSITIONING_DISABLED
	)

	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.variation_embolden = _PIXEL_FONT_EMBOLDEN

	_pixel_font_cache = variation
	return _pixel_font_cache


# Baut für jeden Buchstaben ein eigenes Label, damit jeder
# einzeln wellenförmig schweben kann (statt eines Labels mit
# visible_ratio, das den ganzen Text nur am Stück zeigt).
func _rebuild_letters(text: String) -> void:
	var was_visible: bool = _floating and visible

	for letter in _letters:
		letter.queue_free()

	_letters.clear()

	# Vorher stand hier ThemeDB.fallback_font (der generische Engine-
	# Font) - das passte NICHT zur tatsächlich gerenderten Schrift und
	# konnte die Breiten-Berechnung leicht verfälschen. Jetzt wird für
	# Messung UND Rendering dieselbe (justierte) Schrift benutzt.
	var reference_font: Font = _get_pixel_font()
	var cumulative_x: float = 0.0
	var widths: Array[float] = []

	for character in text:
		var char_width: float = reference_font.get_string_size(
			character,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size
		).x

		widths.append(char_width)
		cumulative_x += char_width

	var start_x: float = -cumulative_x / 2.0
	var running_x: float = start_x

	for i in text.length():
		var letter := Label.new()
		letter.text = text[i]
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.add_theme_font_override("font", reference_font)
		letter.add_theme_font_size_override("font_size", font_size)
		letter.add_theme_color_override("font_color", text_color)
		letter.modulate.a = 1.0 if was_visible else 0.0
		add_child(letter)

		# Nutzer-Wunsch: Pixel-Schrift wirkte "fett"/mit ungleich
		# breiten Kanten (z.B. beim "K" 2 Pixel auf der einen, 1 Pixel
		# auf der anderen Seite) - Ursache war eine krumme Kommazahl-
		# Position (z.B. x=23.65). Jedes Zeichen bekommt hier jetzt
		# eine GANZZAHLIGE Pixel-Position, damit der Nearest-Filter
		# jeden Buchstaben sauber auf ein Pixelraster setzt, statt ihn
		# zwischen zwei Pixeln zu "verwischen".
		letter.position.x = round(running_x)
		running_x += widths[i]

		_letters.append(letter)

	if was_visible:
		_reveal_value = float(_letters.size())


func _on_controls_changed(_changed_action: StringName) -> void:
	if not visible:
		return

	_refresh_text()


func _on_language_changed(_language: String) -> void:
	if not visible:
		return

	_refresh_text()
