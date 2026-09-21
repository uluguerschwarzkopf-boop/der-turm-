class_name EchoBanner
extends CanvasLayer


# ============================================================
# HINWEIS
# ============================================================

# Kurze Dark-Souls-artige Einblende ("ECHO DER FLAMME ERHALTEN")
# nach einem besonderen Ereignis (aktuell: Feuerritter-Sieg):
#
#   sanft einblenden -> kurz stehenlassen -> wieder ausblenden.
#
# Wird rein per Code gebaut und instanziert (siehe
# Levels/room_manager.gd -> _play_echo_reveal_sequence()), braucht
# keine eigene .tscn-Datei.
#
# Anders als bei AreaTitleCard kehrt play_banner() erst zurück,
# wenn die komplette Sequenz (auch das Ausblenden) fertig ist -
# danach soll direkt das dauerhafte HUD-Icon erscheinen, es gibt
# hier keinen Grund, dem Aufrufer schon früher die Kontrolle
# zurückzugeben.
#
# Verwendung:
#   var banner := EchoBanner.new()
#   banner.banner_text = "ECHO DER FLAMME ERHALTEN"
#   get_tree().current_scene.add_child(banner)
#   await banner.play_banner()
#   # Node räumt sich danach von selbst auf (queue_free).


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export var banner_text: String = ""

@export var font_size: int = 56
@export var text_color: Color = Color(1.0, 0.93, 0.78, 1.0)

@export var fade_in_time: float = 0.8
@export var hold_time: float = 1.8
@export var fade_out_time: float = 1.0

# Höhe von oben, als Anteil der Bildschirmhöhe (0.0 = ganz oben,
# 1.0 = ganz unten) - klassische Dark-Souls-Banner sitzen etwas
# über der Bildschirmmitte.
@export var vertical_position_ratio: float = 0.38


# ============================================================
# NODES (per Code gebaut)
# ============================================================

var _root_control: Control
var _label: Label


func _ready() -> void:
	# Deutlich über HUD/Pause-Menü/Shop-Overlay etc.
	layer = 60

	_root_control = Control.new()

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

	_label = Label.new()
	_label.text = banner_text
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)

	# WICHTIG: set_anchors_preset() zieht sich in der Standard-
	# Einstellung auf die Mindestgröße des Inhalts zusammen statt
	# wirklich über die volle Bildschirmbreite zu gehen (derselbe
	# Anker-Bug wie schon beim Hauptmenü und beim Gebiets-Titel) -
	# ohne echte Breite hat horizontal_alignment=CENTER nichts, in
	# dessen Rahmen es zentrieren könnte, und der Text landet am
	# linken Bildschirmrand statt in der Mitte. Deshalb Anker UND
	# Ränder hier direkt und eindeutig setzen.
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 0.0
	_label.offset_left = 0.0
	_label.offset_right = 0.0
	_label.offset_top = 0.0
	_label.offset_bottom = float(font_size) * 1.6

	_root_control.add_child(_label)

	_position_label()

	if not get_tree().root.size_changed.is_connected(
		_on_root_size_changed
	):
		get_tree().root.size_changed.connect(
			_on_root_size_changed
		)


func _position_label() -> void:
	# CanvasLayer hat kein get_viewport_rect() (das gibt es nur auf
	# Control) - deshalb hier über den Viewport selbst gehen.
	var screen_size: Vector2 = get_viewport().get_visible_rect().size

	_label.position.y = screen_size.y * vertical_position_ratio


func _on_root_size_changed() -> void:
	if _label != null:
		_position_label()


# ============================================================
# ABLAUF
# ============================================================

func play_banner() -> void:
	if not is_inside_tree():
		await ready

	var tween: Tween = create_tween()

	tween.tween_property(
		_root_control, "modulate:a", 1.0, fade_in_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_interval(hold_time)

	tween.tween_property(
		_root_control, "modulate:a", 0.0, fade_out_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished

	if is_instance_valid(self):
		queue_free()
