extends Node2D
class_name PlayerThoughtBubble


# Pixel-Schrift (Pixelify Sans, SIL Open Font License) statt der
# Godot-Standardschrift - siehe Fonts/pixelify_sans_LICENSE.txt.
#
# HINWEIS: bewusst NICHT "Press Start 2P" (die erste Version) - die
# ist auf ein SEHR grobes Raster gebaut (für große Überschriften
# gedacht, nicht kleinen UI-Text) und wurde bei der nötigen kleinen
# Größe zu groben, unlesbaren Klötzen statt einzelner Buchstaben.
# Pixelify Sans hat ein deutlich feineres Pixel-Raster (mehr, aber
# kleinere "Pixel" pro Buchstabe) UND echte Kleinbuchstaben (Press
# Start 2P/Silkscreen haben nur Großbuchstaben) - bleibt dadurch bei
# den kleinen Größen hier klar lesbar, siehe _resolve_bounds().
#
# HINWEIS 2: bewusst "static var" statt "const" - bei einer const
# darf man in GDScript keine Property direkt zuweisen (PIXEL_FONT.
# antialiasing = ... unten in _ready() gilt sonst als "Konstante
# verändert" und wird vom Parser abgelehnt). Als static var bleibt
# es weiterhin EINE geteilte Font-Ressource für alle Instanzen.
static var PIXEL_FONT: FontFile = preload("res://Fonts/pixelify_sans.woff2")


# Name eines OPTIONALEN Kindknotens beim Spieler, der Position und
# maximale Fläche für den Text vorgibt - so kann man das bequem mit
# der Maus im Editor einstellen statt Zahlen zu raten (siehe unten
# bei @export_group("Automatische Größe") und _resolve_bounds()).
#
# Aufbau in player.tscn: ein CollisionShape2D als Kind vom Spieler,
# GENAU so benannt, mit einer RectangleShape2D drin. WICHTIG:
# "Disabled" bei diesem CollisionShape2D auf true setzen, sonst
# wirkt es als echter Kollider am Spieler-Körper! Position = die
# UNTERKANTE der Box, direkt über dem Kopf - die Box wächst bei
# mehr Zeilen nach OBEN weg vom Kopf (nie nach unten Richtung
# Spieler). Rechteck-Breite = maximale Textbreite zum Umbrechen,
# Rechteck-Höhe nur ein Richtwert für die automatische Schriftgröße
# (siehe @export_group("Automatische Größe")) - reicht die Höhe bei
# der kleinsten erlaubten Schriftgröße immer noch nicht, wächst die
# Box trotzdem sauber weiter nach oben statt den Text abzuschneiden
# oder über den Spieler zu schieben.
#
# Wird der Knoten nicht gefunden, greifen stattdessen die festen
# Export-Werte vertical_offset/max_text_width/font_size weiter oben.
const BOUNDS_NODE_NAME: StringName = &"ThoughtBubbleBounds"


# ============================================================
# HINWEIS
# ============================================================

# Schwebender "Gedanke" über dem Spieler, z.B. wenn er zum ersten
# Mal einen besonderen Raum betritt (siehe Levels/room_manager.gd
# -> _maybe_show_room_thought_bubble(), ausgelöst über die Exports
# thought_bubble_id/thought_bubble_lines).
#
# Zeigt jede Zeile Buchstabe für Buchstabe an - GENAU derselbe
# Tipp-Effekt-Mechanismus wie Player/interaction_prompt.gd: EIN
# Tween treibt einen "reveal_value" von 0 bis Buchstabenanzahl,
# jeder Buchstabe blendet anhand seines Index ein/aus. Hält kurz,
# blendet genauso wieder Buchstabe für Buchstabe aus, wartet kurz,
# macht mit der nächsten Zeile weiter.
#
# Sperrt NICHT die Spielersteuerung - anders als Game/void_
# narration.gd kann sich der Spieler währenddessen frei bewegen.
# Übersetzt über SettingsManager.t() (Schlüssel, kein roher Text),
# reagiert also automatisch auf einen Sprachwechsel.
#
# Wird als Kind des Spieler-Node hinzugefügt und bleibt dadurch
# automatisch über ihm (siehe vertical_offset) - kein eigenes
# _process() zum Nachführen der Position nötig.


# ============================================================
# EINSTELLUNGEN (Inspector)
# ============================================================

@export_group("Tipp-Effekt")

# Zeit pro Buchstabe beim Rein- und beim Rausgehen - bewusst
# deutlich langsamer als beim Händler-Tipp (Player/interaction_
# prompt.gd), damit man die Zeile noch in Ruhe mitlesen kann.
@export var seconds_per_letter: float = 0.12


@export_group("Farbe")

@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)

# Klein gehalten, damit der Text bei der Pixel-Art-Auflösung des
# Spiels nicht überdimensioniert wirkt.
@export var font_size: int = 10


@export_group("Textbox")

# Feste, schmale Breite zum Umbrechen - die Box soll nur leicht
# links/rechts am Spieler-Kopf vorbeigehen statt über die ganze
# Zeile zu reichen. Der Text wird automatisch an Wortgrenzen in
# mehrere Zeilen umgebrochen (siehe _wrap_text()). Passt notfalls
# hier den Wert an, falls es an der Spielfigur nicht exakt passt.
@export var max_text_width: float = 28.0

# Abstand zwischen den umgebrochenen Zeilen.
@export var line_spacing: float = 2.0

# Dunkler, halbtransparenter Kasten hinter dem Text (wie eine
# kleine Sprechblase ohne Schwänzchen) - Größe passt sich pro
# Zeile automatisch an die Textbreite an (siehe _rebuild_letters()).
@export var box_color: Color = Color(0.06, 0.06, 0.09, 0.8)
@export var box_border_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var box_border_width: float = 1.0
@export var box_padding_horizontal: float = 4.0
@export var box_padding_vertical: float = 3.0
@export var box_fade_time: float = 0.15


@export_group("Position")

# NUR Fallback, falls kein ThoughtBubbleBounds-Knoten gefunden wird
# (siehe BOUNDS_NODE_NAME oben) - Abstand nach oben vom Spieler-
# Ursprung weg (negativ = nach oben). Markiert die UNTERKANTE der
# Box direkt über dem Kopf, die Box wächst von hier aus nach oben.
@export var vertical_offset: float = -34.0

# Rendert immer oben, unabhängig vom z_index des Spielers.
@export var always_on_top: bool = true


@export_group("Automatische Größe")

# Nur wirksam, wenn beim Spieler ein ThoughtBubbleBounds-Knoten
# existiert. Es wird automatisch die GRÖSSTE Schriftgröße in diesem
# Bereich gewählt, bei der der umgebrochene Text noch in die Fläche
# des Bounds-Rechtecks passt - "größer und kleiner machen, damit
# es immer reinpasst".
@export var min_font_size: int = 8
@export var max_font_size: int = 14


@export_group("Timing")

# Wie lange eine fertig eingeblendete Zeile stehen bleibt, bevor
# sie wieder ausgeblendet wird.
@export var line_hold_time: float = 1.3

# Kurze Pause zwischen zwei Zeilen (Zeile 1 ausgeblendet -> Pause
# -> Zeile 2 blendet ein).
@export var line_gap_time: float = 0.5


# ============================================================
# STATUS
# ============================================================

var _letters: Array[Label] = []

var _reveal_tween: Tween
var _reveal_value: float = 0.0

var _box: Panel
var _box_style: StyleBoxFlat
var _box_tween: Tween

# Werden von _resolve_bounds() befüllt, falls ThoughtBubbleBounds
# existiert - sonst bleiben die Fallback-Werte (vertical_offset,
# _bounds_size bleibt ZERO als Signal "kein Bounds-Knoten da").
var _bounds_position: Vector2 = Vector2(0.0, vertical_offset)
var _bounds_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	_resolve_bounds()

	position = _bounds_position

	if always_on_top:
		z_as_relative = false
		z_index = 100

	# Anders als bei der ersten Version (Press Start 2P, harte
	# Blöcke) braucht Pixelify Sans normale Kantenglättung, sonst
	# werden ihre feineren Details bei kleiner Größe unlesbar.
	PIXEL_FONT.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	PIXEL_FONT.hinting = TextServer.HINTING_LIGHT

	# WICHTIG: "0.0" (automatisch) reicht hier NICHT - Godot rastert
	# die Schrift dann nur für die normale Fenstergröße, die Kamera
	# vergrößert das Ergebnis aber zusätzlich (Zoom), wodurch die an
	# sich scharfe Schrift nachträglich verwischt/unscharf wird. Mit
	# einem fest hohen Wert wird von vornherein in höherer Auflösung
	# gerastert, damit es auch nach dem Kamera-Zoom noch scharf ist.
	PIXEL_FONT.oversampling = 6.0

	_build_box()


# Sucht das optionale CollisionShape2D "ThoughtBubbleBounds" beim
# Spieler (siehe BOUNDS_NODE_NAME oben). Falls vorhanden, ersetzen
# dessen Position und Rechteck-Größe die festen vertical_offset/
# max_text_width-Werte - so lässt sich das bequem im Editor per
# Maus einstellen statt Zahlen zu raten.
func _resolve_bounds() -> void:
	var parent := get_parent()

	if parent == null:
		return

	var bounds_node := parent.get_node_or_null(NodePath(BOUNDS_NODE_NAME))

	if bounds_node == null or not (bounds_node is CollisionShape2D):
		return

	var collision_shape := bounds_node as CollisionShape2D
	var rect_shape := collision_shape.shape as RectangleShape2D

	if rect_shape == null:
		push_warning(
			"PlayerThoughtBubble: " + String(BOUNDS_NODE_NAME)
			+ " braucht eine RectangleShape2D."
		)
		return

	_bounds_position = collision_shape.position
	_bounds_size = rect_shape.size


# ============================================================
# TEXTBOX (HINTERGRUND)
# ============================================================

func _build_box() -> void:
	_box_style = StyleBoxFlat.new()
	_box_style.bg_color = box_color
	_box_style.border_color = box_border_color
	_box_style.set_border_width_all(box_border_width)
	_box_style.set_corner_radius_all(0)

	_box = Panel.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_stylebox_override("panel", _box_style)
	_box.modulate.a = 0.0

	if always_on_top:
		_box.z_as_relative = false
		_box.z_index = 99

	add_child(_box)
	move_child(_box, 0)


# ============================================================
# ÖFFENTLICHE FUNKTION
# ============================================================

# translation_keys: Array[String] - jeder Eintrag ein Schlüssel in
# SettingsManager.TRANSLATIONS (z.B. "thought.skill_tree_line_1").
# Zeigt sie nacheinander an (rein -> halten -> raus -> kurze Pause
# -> nächste Zeile) - await-bar, kehrt zurück wenn alle Zeilen
# durch sind.
func play_lines(translation_keys: Array) -> void:
	for key in translation_keys:
		var line_text: String = String(key)

		if get_node_or_null("/root/SettingsManager") != null:
			line_text = SettingsManager.t(String(key))

		await _play_line(line_text)

		if not is_instance_valid(self):
			return

		await get_tree().create_timer(line_gap_time).timeout

		if not is_instance_valid(self):
			return


func _play_line(text: String) -> void:
	_rebuild_letters(text)

	await _start_reveal_tween(float(_letters.size()))

	if not is_instance_valid(self):
		return

	await get_tree().create_timer(line_hold_time).timeout

	if not is_instance_valid(self):
		return

	await _start_reveal_tween(0.0)


# ============================================================
# TIPP-EFFEKT (BUCHSTABENWEISE REIN/RAUS) - wie InteractionPrompt
# ============================================================

func _start_reveal_tween(target: float) -> void:
	# Beim Reingehen erscheint die Box sofort (ist längst fertig,
	# bevor der letzte Buchstabe durch ist) - beim Rausgehen bleibt
	# sie stehen, bis WIRKLICH alle Buchstaben weg sind, und
	# verschwindet erst danach (siehe unten).
	var revealing: bool = target > _reveal_value

	if revealing:
		_fade_box(1.0)

	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()

	var distance: float = abs(target - _reveal_value)
	var duration: float = max(distance * seconds_per_letter, 0.01)

	_reveal_tween = create_tween()
	_reveal_tween.tween_method(
		_set_reveal_value, _reveal_value, target, duration
	)

	await _reveal_tween.finished

	if not revealing:
		await _fade_box(0.0)


func _fade_box(target_alpha: float) -> void:
	if _box == null:
		return

	if _box_tween != null and _box_tween.is_valid():
		_box_tween.kill()

	_box_tween = create_tween()
	_box_tween.tween_property(
		_box, "modulate:a", target_alpha, box_fade_time
	)

	await _box_tween.finished


func _set_reveal_value(value: float) -> void:
	_reveal_value = value

	for i in _letters.size():
		_letters[i].modulate.a = clamp(value - i, 0.0, 1.0)


# ============================================================
# BUCHSTABEN-AUFBAU
# ============================================================

# Baut für jeden Buchstaben ein eigenes Label (wie InteractionPrompt.
# _rebuild_letters()), zentriert über dem Spieler-Ursprung. Bricht
# lange Zeilen an Wortgrenzen um (siehe _wrap_text()), damit die Box
# schmal bleibt statt über die ganze Zeile zu reichen - jede Zeile
# wird für sich horizontal zentriert, die LETZTE Zeile sitzt auf
# Höhe der Node-Position, frühere Zeilen stapeln sich nach OBEN
# (weg vom Spielerkopf) statt nach unten - so wächst die Box bei
# mehr Text nie in Richtung Spieler, egal wie viele Zeilen es sind.
#
# Gibt es einen ThoughtBubbleBounds-Knoten (siehe _resolve_bounds),
# wird zusätzlich die größte Schriftgröße zwischen min_font_size und
# max_font_size gesucht, bei der der Text noch in dessen Höhe passt.
func _rebuild_letters(text: String) -> void:
	for letter in _letters:
		letter.queue_free()

	_letters.clear()
	_reveal_value = 0.0

	var reference_font: Font = PIXEL_FONT
	var has_bounds: bool = _bounds_size != Vector2.ZERO
	var wrap_width: float = _bounds_size.x if has_bounds else max_text_width

	var chosen_font_size: int = font_size
	var lines: Array[String] = []
	var line_height: float = 0.0

	if has_bounds:
		for candidate_size in range(max_font_size, min_font_size - 1, -1):
			var candidate_lines: Array[String] = _wrap_text(
				text, reference_font, candidate_size, wrap_width
			)
			var candidate_line_height: float = (
				reference_font.get_height(candidate_size) + line_spacing
			)
			var candidate_height: float = (
				float(candidate_lines.size()) * candidate_line_height
			)

			if candidate_height <= _bounds_size.y or candidate_size == min_font_size:
				chosen_font_size = candidate_size
				lines = candidate_lines
				line_height = candidate_line_height
				break
	else:
		lines = _wrap_text(text, reference_font, font_size, wrap_width)
		line_height = reference_font.get_height(font_size) + line_spacing

	for row_index in lines.size():
		var line_text: String = lines[row_index]
		var row_width: float = _measure_text_width(
			line_text, reference_font, chosen_font_size
		)
		var running_x: float = -row_width / 2.0

		# Label positioniert sich an seiner OBEREN linken Ecke, der
		# Buchstabe reicht von dort aus line_height nach UNTEN - darum
		# hier -line_height * (Zeilen bis zum Ende) statt bis 0, sonst
		# würde die letzte Zeile noch eine ganze Zeilenhöhe UNTER die
		# Node-Position (und damit unten aus der Box) herausragen.
		# Ergebnis: die letzte Zeile endet exakt bei y=0, alle davor
		# liegenden Zeilen stapeln sich sauber darüber (negativ).
		var row_y: float = float(row_index - lines.size()) * line_height

		for character in line_text:
			var char_width: float = reference_font.get_string_size(
				character, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen_font_size
			).x

			var letter := Label.new()
			letter.text = character
			letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
			letter.add_theme_font_override("font", PIXEL_FONT)
			letter.add_theme_font_size_override("font_size", chosen_font_size)
			letter.add_theme_color_override("font_color", text_color)
			letter.modulate.a = 0.0
			add_child(letter)

			letter.position = Vector2(running_x, row_y)
			running_x += char_width

			_letters.append(letter)

	_resize_box(wrap_width, float(lines.size()) * line_height)


# Bricht text an Wortgrenzen in mehrere Zeilen um, sodass keine
# Zeile breiter als width_limit wird. Ein einzelnes Wort, das schon
# für sich allein zu breit ist, darf ausnahmsweise überstehen statt
# mitten im Wort zerrissen zu werden.
func _wrap_text(
	text: String, font: Font, size: int, width_limit: float
) -> Array[String]:
	var words: PackedStringArray = text.split(" ")
	var lines: Array[String] = []
	var current_line: String = ""

	for word in words:
		var candidate: String = (
			word if current_line.is_empty() else current_line + " " + word
		)

		if (
			current_line.is_empty()
			or _measure_text_width(candidate, font, size) <= width_limit
		):
			current_line = candidate
		else:
			lines.append(current_line)
			current_line = word

	if not current_line.is_empty():
		lines.append(current_line)

	return lines


func _measure_text_width(line: String, font: Font, size: int) -> float:
	var width: float = 0.0

	for character in line:
		width += font.get_string_size(
			character, HORIZONTAL_ALIGNMENT_LEFT, -1, size
		).x

	return width


# Passt die Textbox-Größe/-Position an die aktuelle Zeile an -
# bleibt dabei unsichtbar (modulate.a wird separat über _fade_box()
# gesteuert), damit ein Zeilenwechsel mitten in der Anzeige nicht
# als Sprung in der Boxgröße auffällt.
#
# Ankerpunkt ist die UNTERKANTE der Box (Node-Position, y=0) - die
# Box wächst nach oben (negatives y), passend zu den Buchstaben in
# _rebuild_letters(). So reicht die Box bei mehr Zeilen automatisch
# weiter nach oben statt Richtung Spieler zu wachsen.
func _resize_box(text_width: float, text_height: float) -> void:
	if _box == null:
		return

	_box.position = Vector2(
		-text_width / 2.0 - box_padding_horizontal,
		-text_height - box_padding_vertical
	)

	_box.size = Vector2(
		text_width + box_padding_horizontal * 2.0,
		text_height + box_padding_vertical * 2.0
	)
