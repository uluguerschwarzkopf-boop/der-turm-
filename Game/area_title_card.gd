class_name AreaTitleCard
extends CanvasLayer


# ============================================================
# HINWEIS
# ============================================================

# Großer Gebiets-Titel oben am Bildschirmrand beim Betreten eines
# neuen Gebiets (z.B. "GEBIET 1" / "DIE EINGANGSHALLEN"):
#
#   sanft einblenden -> kurz stehenlassen -> Buchstabe für
#   Buchstabe zu Rauch auflösen (jeder Buchstabe verschwindet und
#   hinterlässt eine kleine Rauchwolke, die langsam schwächer
#   wird, bis nichts mehr zu sehen ist).
#
# Wird rein per Code gebaut und instanziert (siehe
# Levels/room_manager.gd -> _play_area_title_card()), braucht
# keine eigene .tscn-Datei.
#
# Verwendung:
#   var card := AreaTitleCard.new()
#   card.title_text = "GEBIET 1"
#   card.subtitle_text = "DIE EINGANGSHALLEN"
#   get_tree().current_scene.add_child(card)
#   await card.play_intro()
#   # play_intro() kehrt zurück, SOBALD das Auflösen beginnt -
#   # der Aufrufer kann direkt danach die Spielerkontrolle
#   # freigeben, während die Buchstaben im Hintergrund noch zu
#   # Rauch zerfallen. Das Node räumt sich danach von selbst auf
#   # (queue_free), es muss nirgends manuell entfernt werden.


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export var title_text: String = "GEBIET 1"
@export var subtitle_text: String = "DIE EINGANGSHALLEN"

@export var title_font_size: int = 64
@export var subtitle_font_size: int = 30

@export var title_color: Color = Color(0.92, 0.87, 0.78, 1.0)
@export var subtitle_color: Color = Color(0.82, 0.4, 0.28, 1.0)

@export var top_margin: float = 70.0

@export var fade_in_time: float = 1.1
@export var hold_time: float = 2.0

# Zeitversatz zwischen dem Start von Buchstabe 1, 2, 3, ... beim
# Auflösen - erzeugt den "Buchstabe für Buchstabe"-Sweep.
@export var dissolve_stagger: float = 0.05

# Wie schnell der Buchstabe selbst verschwindet, sobald er dran
# ist (die Rauchwolke lebt danach noch deutlich länger weiter,
# siehe smoke_lifetime).
@export var dissolve_fade_time: float = 0.25

@export var smoke_lifetime: float = 1.3
@export var smoke_particle_amount: int = 14
@export var smoke_color: Color = Color(0.75, 0.72, 0.7, 0.55)


# ============================================================
# NODES (per Code gebaut)
# ============================================================

var _root_control: Control
var _vbox: VBoxContainer
var _title_row: HBoxContainer
var _subtitle_row: HBoxContainer


func _ready() -> void:
	# Deutlich über HUD/Pause-Menü/Shop-Overlay etc.
	layer = 60

	_root_control = Control.new()

	# WICHTIG: set_anchors_preset(PRESET_FULL_RECT) zieht sich in
	# der Standard-Einstellung auf die Mindestgröße des Inhalts
	# zusammen statt wirklich den ganzen Bildschirm einzunehmen
	# (derselbe Bug, der schon mal das Hauptmenü nur oben links
	# klein gezeigt hat - siehe main_menu.gd -> _fill_parent_rect).
	# Deshalb hier Anker UND Ränder direkt und eindeutig setzen.
	_root_control.anchor_left = 0.0
	_root_control.anchor_top = 0.0
	_root_control.anchor_right = 1.0
	_root_control.anchor_bottom = 1.0
	_root_control.offset_left = 0.0
	_root_control.offset_top = 0.0
	_root_control.offset_right = 0.0
	_root_control.offset_bottom = 0.0

	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.modulate.a = 0.0
	add_child(_root_control)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_vbox.position.y = top_margin
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_vbox)

	_title_row = _build_letter_row(
		title_text, title_font_size, title_color
	)
	_vbox.add_child(_title_row)

	_subtitle_row = _build_letter_row(
		subtitle_text, subtitle_font_size, subtitle_color
	)
	_vbox.add_child(_subtitle_row)


# Baut eine Zeile Text als HBoxContainer mit EINEM Label pro
# Buchstabe (Abstand 0) statt einem einzelnen Label. Sieht optisch
# identisch zu normalem Text aus (Godot reiht die Labels nahtlos
# aneinander), macht es aber möglich, später jeden Buchstaben
# einzeln ein- und ausblenden zu lassen (siehe _dissolve_into_smoke).
func _build_letter_row(
	text: String, font_size: int, color: Color
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for character in text:
		var letter := Label.new()
		letter.text = character
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.add_theme_font_size_override("font_size", font_size)
		letter.add_theme_color_override("font_color", color)
		row.add_child(letter)

	return row


# ============================================================
# ABLAUF
# ============================================================

func play_intro() -> void:
	if not is_inside_tree():
		await ready

	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(
		_root_control, "modulate:a", 1.0, fade_in_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await fade_tween.finished

	if not is_instance_valid(self):
		return

	await get_tree().create_timer(hold_time).timeout

	if not is_instance_valid(self):
		return

	_dissolve_into_smoke()
	# Kehrt HIER zurück, NICHT erst wenn der Rauch komplett
	# verklungen ist - _dissolve_into_smoke() läuft eigenständig
	# im Hintergrund weiter (inkl. Selbst-Aufräumen am Ende).


# Löst beide Zeilen (Titel + Untertitel) GLEICHZEITIG auf, jede
# für sich von links nach rechts, Buchstabe für Buchstabe.
func _dissolve_into_smoke() -> void:
	var title_letters: Array = _title_row.get_children()
	var subtitle_letters: Array = _subtitle_row.get_children()

	for i in range(title_letters.size()):
		_dissolve_single_letter(
			title_letters[i] as Label, i * dissolve_stagger
		)

	for j in range(subtitle_letters.size()):
		_dissolve_single_letter(
			subtitle_letters[j] as Label, j * dissolve_stagger
		)

	var longest_row_size: int = max(
		title_letters.size(), subtitle_letters.size()
	)

	var total_lifetime: float = (
		float(longest_row_size) * dissolve_stagger
		+ dissolve_fade_time
		+ smoke_lifetime
		+ 0.2
	)

	await get_tree().create_timer(total_lifetime).timeout

	if is_instance_valid(self):
		queue_free()


# Ein einzelner Buchstabe: nach "delay" Sekunden warten, dann eine
# kleine Rauchwolke an seiner Stelle erzeugen und den Buchstaben
# selbst schnell ausblenden ("er verwandelt sich in den Rauch").
func _dissolve_single_letter(letter: Label, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	if not is_instance_valid(letter):
		return

	# Leerzeichen brauchen keine Rauchwolke - da ist nichts zu sehen.
	if letter.text.strip_edges() == "":
		return

	_spawn_letter_smoke(letter)

	var letter_tween: Tween = create_tween()
	letter_tween.tween_property(
		letter, "modulate:a", 0.0, dissolve_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# Rauchwolke wird als Geschwister-Node unter _root_control erzeugt
# (NICHT als Kind vom Buchstaben-Label!) - sonst würde das Aus-
# blenden des Buchstabens (modulate) automatisch auch den Rauch
# mit ausblenden, obwohl der ja gerade erst noch länger sichtbar
# bleiben und selbstständig verklingen soll.
func _spawn_letter_smoke(letter: Label) -> void:
	var smoke := CPUParticles2D.new()
	_root_control.add_child(smoke)

	smoke.global_position = (
		letter.global_position + letter.size * 0.5
	)

	smoke.amount = smoke_particle_amount
	smoke.lifetime = smoke_lifetime
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.emitting = true

	smoke.direction = Vector2(0.0, -1.0)
	smoke.spread = 35.0
	smoke.gravity = Vector2(0.0, -14.0)
	smoke.initial_velocity_min = 10.0
	smoke.initial_velocity_max = 26.0
	smoke.damping_min = 6.0
	smoke.damping_max = 10.0
	smoke.angular_velocity_min = -40.0
	smoke.angular_velocity_max = 40.0

	smoke.scale_amount_min = 0.4
	smoke.scale_amount_max = 0.8

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(1.0, 1.6))
	smoke.scale_amount_curve = scale_curve

	var smoke_gradient := Gradient.new()
	smoke_gradient.set_color(
		0, Color(smoke_color.r, smoke_color.g, smoke_color.b, smoke_color.a)
	)
	smoke_gradient.set_color(
		1, Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0)
	)
	smoke.color_ramp = smoke_gradient
