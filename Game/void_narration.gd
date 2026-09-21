class_name VoidNarration
extends CanvasLayer


# ============================================================
# HINWEIS
# ============================================================

# "Die Leere" - der Gefangene ganz oben im Turm, der mit dem
# Spieler redet und ihm hilft (z.B. beim Betreten eines Bossraums).
# Wenn sie spricht:
#
#   Spielersteuerung sperren -> Kamera leicht reinzoomen -> Bild-
#   ränder dunkel/violett verdunkeln (Mitte bleibt sichtbar) ->
#   Musik kurz dämpfen -> ganz leichtes Kamera-Zittern -> Zeile für
#   Zeile Text OHNE Textbox (Buchstabe für Buchstabe erscheint aus
#   einer kleinen Rauchwolke, schwebt danach sanft wie eine Welle,
#   löst sich am Ende wieder in Rauch auf - GENAU wie beim
#   Gebiets-Titel in area_title_card.gd, nur diesmal auch beim
#   ERSCHEINEN, nicht nur beim Verschwinden) -> alles zieht sich
#   wieder zurück -> Kontrolle zurück.
#
# Übersetzt: play_lines() bekommt TRANSLATIONS-Schlüssel (siehe
# Game/settings_manager.gd), keinen rohen Text - ändert sich die
# Sprache in den Einstellungen, spricht die Leere beim nächsten
# Mal automatisch in der neuen Sprache.
#
# Wird rein per Code gebaut und instanziert, braucht keine eigene
# .tscn-Datei. Verwendung (siehe auch Levels/room_manager.gd):
#
#   var void_narration := VoidNarration.new()
#   get_tree().current_scene.add_child(void_narration)
#   await void_narration.play_lines([
#       "void.fire_knight_line_1",
#       "void.fire_knight_line_2",
#       "void.fire_knight_line_3",
#   ])
#   # Node räumt sich danach von selbst auf (queue_free).


# ============================================================
# EINSTELLUNGEN - VIGNETTE
# ============================================================

@export var vignette_color: Color = Color(0.09, 0.0, 0.16, 1.0)
@export var vignette_inner_radius: float = 0.5
@export var vignette_outer_radius: float = 1.05
@export var vignette_fade_time: float = 1.1


# ============================================================
# EINSTELLUNGEN - KAMERA
# ============================================================

# < 1.0 = leicht reinzoomen (Godot: kleinerer Camera2D.zoom-Wert
# zeigt WENIGER von der Szene = wirkt näher dran). 0.93 ~ 7% rein.
@export var camera_zoom_factor: float = 0.93
@export var camera_zoom_time: float = 1.1

@export var shake_amplitude_px: float = 1.4
@export var shake_retarget_time: float = 0.07


# ============================================================
# EINSTELLUNGEN - MUSIK/AMBIENTE DÄMPFEN
# ============================================================

@export var music_duck_db: float = -9.0
@export var music_duck_time: float = 1.1


# ============================================================
# EINSTELLUNGEN - TEXT
# ============================================================

@export var font_size: int = 30
@export var text_color: Color = Color(0.86, 0.78, 1.0, 1.0)

@export var vertical_position_ratio: float = 0.62

# Zeitversatz zwischen Buchstabe 1, 2, 3, ... beim Erscheinen bzw.
# beim Verschwinden - erzeugt den "Buchstabe für Buchstabe"-Sweep,
# genau wie dissolve_stagger in area_title_card.gd.
@export var letter_reveal_stagger: float = 0.09
@export var letter_hide_stagger: float = 0.07

@export var letter_fade_time: float = 0.35

@export var smoke_lifetime: float = 1.1
@export var smoke_particle_amount: int = 12
@export var smoke_color: Color = Color(0.55, 0.42, 0.75, 0.55)

# Sanftes Auf-und-Ab je Buchstabe, solange er sichtbar ist -
# jeder Buchstabe bekommt über wave_phase_per_letter eine eigene
# Phase, dadurch läuft die Welle sichtbar über die ganze Zeile.
@export var wave_amplitude_px: float = 3.5
@export var wave_speed: float = 2.6
@export var wave_phase_per_letter: float = 0.4

@export var line_hold_time: float = 1.1
@export var line_gap_time: float = 0.0


# ============================================================
# NODES / STATUS
# ============================================================

var _root_control: Control
var _vignette_rect: ColorRect
var _vignette_material: ShaderMaterial

var _player: Node = null
var _camera: Camera2D = null
var _camera_original_zoom: Vector2 = Vector2.ONE

# WICHTIG: der Spieler-Kamera kann schon vor der Erzählung ein
# eigener Offset gesetzt sein (z.B. ein "Blick nach oben/unten"-
# Versatz aus einem anderen System). Das Zittern darf diesen
# Offset nicht einfach überschreiben/auf Null ziehen, sonst bleibt
# die Kamera nach der Erzählung sichtbar verschoben ("nach unten
# geschoben"-Bug). Deshalb wird der Ausgangs-Offset hier gemerkt
# und das Zittern schwingt nur UM diesen Wert herum, statt um
# Vector2.ZERO - und am Ende wird exakt dieser Wert wiederhergestellt.
var _camera_original_offset: Vector2 = Vector2.ZERO

var _camera_shake_active: bool = false
var _shake_timer: float = 0.0
var _shake_target: Vector2 = Vector2.ZERO

var _music_bus_index: int = -1
var _music_original_db: float = 0.0

var _time: float = 0.0

# Jeder aktuell sichtbare (oder gerade erscheinende) Buchstabe:
# {"label": Label, "base_y": float, "index": int}
var _bobbing_letters: Array = []


const VIGNETTE_SHADER_CODE: String = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.09, 0.0, 0.16, 1.0);
uniform float inner_radius : hint_range(0.0, 1.5) = 0.5;
uniform float outer_radius : hint_range(0.0, 2.0) = 1.05;
uniform float aspect_ratio : hint_range(0.1, 4.0) = 1.7778;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(aspect_ratio, 1.0);
	float dist = length(centered);
	float vig = smoothstep(inner_radius, outer_radius, dist);
	COLOR = vec4(vignette_color.rgb, vig * intensity);
}
"""


func _ready() -> void:
	# Deutlich über HUD/Pause-Menü/Shop-Overlay etc., wie EchoBanner.
	layer = 65

	_build_vignette()


func _process(delta: float) -> void:
	_time += delta

	if _camera_shake_active and _camera != null:
		_shake_timer -= delta

		if _shake_timer <= 0.0:
			_shake_timer = shake_retarget_time
			_shake_target = Vector2(
				randf_range(-shake_amplitude_px, shake_amplitude_px),
				randf_range(-shake_amplitude_px, shake_amplitude_px)
			)

		_camera.offset = _camera.offset.lerp(
			_camera_original_offset + _shake_target, 0.25
		)

	for entry in _bobbing_letters:
		var label: Label = entry.get("label")

		if label == null or not is_instance_valid(label):
			continue

		var wave: float = sin(
			_time * wave_speed + float(entry["index"]) * wave_phase_per_letter
		) * wave_amplitude_px

		label.position.y = float(entry["base_y"]) + wave


# ============================================================
# AUFBAU DER VIGNETTE (VOLLBILD-SHADER)
# ============================================================

func _build_vignette() -> void:
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
	add_child(_root_control)

	_vignette_rect = ColorRect.new()
	_vignette_rect.anchor_left = 0.0
	_vignette_rect.anchor_top = 0.0
	_vignette_rect.anchor_right = 1.0
	_vignette_rect.anchor_bottom = 1.0
	_vignette_rect.offset_left = 0.0
	_vignette_rect.offset_top = 0.0
	_vignette_rect.offset_right = 0.0
	_vignette_rect.offset_bottom = 0.0
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.color = Color.WHITE

	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER_CODE

	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.set_shader_parameter("intensity", 0.0)
	_vignette_material.set_shader_parameter("vignette_color", vignette_color)
	_vignette_material.set_shader_parameter(
		"inner_radius", vignette_inner_radius
	)
	_vignette_material.set_shader_parameter(
		"outer_radius", vignette_outer_radius
	)

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	_vignette_material.set_shader_parameter(
		"aspect_ratio", screen_size.x / max(screen_size.y, 1.0)
	)

	_vignette_rect.material = _vignette_material
	_root_control.add_child(_vignette_rect)


# ============================================================
# ABLAUF
# ============================================================

# translation_keys: Array[String] - jeder Eintrag ist ein Schlüssel
# in SettingsManager.TRANSLATIONS (z.B. "void.fire_knight_line_1"),
# KEIN roher Text - so bleibt die Leere bei Sprachumschaltung
# automatisch übersetzt.
func play_lines(translation_keys: Array) -> void:
	if not is_inside_tree():
		await ready

	_player = get_tree().get_first_node_in_group("player")

	if _player != null and _player.has_method("lock_control"):
		_player.lock_control()

		# Nutzer-Wunsch: der Spieler soll während die Leere spricht
		# immer im Idle-Frame stehen bleiben - egal, ob er gerade
		# lief, sprang oder mitten in einer Animation war, als die
		# Narration ausgelöst wurde. lock_control() lässt
		# _physics_process() ab jetzt vorzeitig zurückkehren (kein
		# eigenes sprite.play(...) mehr), daher reicht dieser eine
		# Aufruf für die komplette Dauer der Narration.
		if _player.has_method("force_idle"):
			_player.force_idle()

	if _player != null:
		_camera = _player.get_node_or_null("Camera2D") as Camera2D

	if _camera != null:
		_camera_original_offset = _camera.offset

	_duck_music()
	_zoom_camera_in()
	_camera_shake_active = true

	var vignette_in: Tween = create_tween()
	vignette_in.tween_property(
		_vignette_material, "shader_parameter/intensity", 1.0, vignette_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await vignette_in.finished

	if not is_instance_valid(self):
		return

	for key in translation_keys:
		var line_text: String = String(key)

		if get_node_or_null("/root/SettingsManager") != null:
			line_text = SettingsManager.t(String(key))

		await _play_line(line_text)

		if not is_instance_valid(self):
			return

		await get_tree().create_timer(line_gap_time).timeout

	_camera_shake_active = false

	if _camera != null:
		_camera.offset = _camera_original_offset

	_zoom_camera_out()
	_restore_music()

	var vignette_out: Tween = create_tween()
	vignette_out.tween_property(
		_vignette_material, "shader_parameter/intensity", 0.0, vignette_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await vignette_out.finished

	if _player != null and _player.has_method("unlock_control"):
		_player.unlock_control()

	if is_instance_valid(self):
		queue_free()


# ============================================================
# EINE ZEILE: ERSCHEINEN (RAUCH) -> SCHWEBEN -> VERSCHWINDEN (RAUCH)
# ============================================================

func _play_line(text: String) -> void:
	# Erstmal als HBoxContainer bauen (wie area_title_card.gd's
	# _build_letter_row) - das übernimmt die korrekte Breite/
	# Abstände pro Buchstabe anhand der echten Schriftart. Danach
	# werden die Labels in einen normalen Control umgehängt, damit
	# sie sich einzeln in der Höhe bewegen können (in einem
	# HBoxContainer würde dessen eigenes Layout die Y-Position
	# jeden Frame wieder zurücksetzen).
	var temp_row := HBoxContainer.new()
	temp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	temp_row.add_theme_constant_override("separation", 0)
	temp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for character in text:
		var letter := Label.new()
		letter.text = character
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.add_theme_font_size_override("font_size", font_size)
		letter.add_theme_color_override("font_color", text_color)
		letter.modulate.a = 0.0
		temp_row.add_child(letter)

	_root_control.add_child(temp_row)

	# Einen Frame warten, damit das HBoxContainer-Layout einmal
	# durchläuft und jedes Label seine echte Position/Breite hat.
	await get_tree().process_frame

	if not is_instance_valid(self):
		return

	var free_container := Control.new()
	free_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var letters: Array = temp_row.get_children()
	var line_width: float = temp_row.size.x
	var entries: Array = []

	for i in range(letters.size()):
		var letter: Label = letters[i] as Label
		var local_pos: Vector2 = letter.position

		temp_row.remove_child(letter)
		free_container.add_child(letter)
		letter.position = local_pos

		entries.append({
			"label": letter,
			"base_y": local_pos.y,
			"index": i,
		})

	temp_row.queue_free()

	var screen_size: Vector2 = get_viewport().get_visible_rect().size

	free_container.position = Vector2(
		(screen_size.x - line_width) * 0.5,
		screen_size.y * vertical_position_ratio
	)

	_root_control.add_child(free_container)

	_bobbing_letters.append_array(entries)

	# ERSCHEINEN: Buchstabe für Buchstabe aus einer Rauchwolke.
	for entry in entries:
		_reveal_letter(entry)
		await get_tree().create_timer(letter_reveal_stagger).timeout

		if not is_instance_valid(self):
			return

	await get_tree().create_timer(letter_fade_time + line_hold_time).timeout

	if not is_instance_valid(self):
		return

	# VERSCHWINDEN: genauso Buchstabe für Buchstabe, wieder zu Rauch.
	for entry in entries:
		_hide_letter(entry)
		await get_tree().create_timer(letter_hide_stagger).timeout

		if not is_instance_valid(self):
			return

	var total_hide_time: float = (
		float(entries.size()) * letter_hide_stagger
		+ letter_fade_time
		+ smoke_lifetime
		+ 0.2
	)

	await get_tree().create_timer(total_hide_time).timeout

	for entry in entries:
		_bobbing_letters.erase(entry)

	if is_instance_valid(free_container):
		free_container.queue_free()


func _reveal_letter(entry: Dictionary) -> void:
	var label: Label = entry.get("label")

	if label == null or not is_instance_valid(label):
		return

	if label.text.strip_edges() != "":
		_spawn_letter_smoke(label)

	var tween: Tween = create_tween()
	tween.tween_property(
		label, "modulate:a", 1.0, letter_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_letter(entry: Dictionary) -> void:
	var label: Label = entry.get("label")

	if label == null or not is_instance_valid(label):
		return

	if label.text.strip_edges() != "":
		_spawn_letter_smoke(label)

	var tween: Tween = create_tween()
	tween.tween_property(
		label, "modulate:a", 0.0, letter_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# Fast identisch zu area_title_card.gd -> _spawn_letter_smoke(), nur
# mit eigener (violetter) Farbe - passend zur Leere. Wird als
# Geschwister-Node unter _root_control erzeugt (NICHT als Kind vom
# Buchstaben), damit das Ein-/Ausblenden des Buchstabens (modulate)
# nicht automatisch auch den Rauch mit beeinflusst.
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
	smoke.initial_velocity_min = 8.0
	smoke.initial_velocity_max = 22.0
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


# ============================================================
# KAMERA (ZOOM + ZITTERN)
# ============================================================

func _zoom_camera_in() -> void:
	if _camera == null:
		return

	_camera_original_zoom = _camera.zoom

	var tween: Tween = create_tween()
	tween.tween_property(
		_camera,
		"zoom",
		_camera_original_zoom * camera_zoom_factor,
		camera_zoom_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _zoom_camera_out() -> void:
	if _camera == null:
		return

	var tween: Tween = create_tween()
	tween.tween_property(
		_camera, "zoom", _camera_original_zoom, camera_zoom_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# ============================================================
# MUSIK DÄMPFEN
# ============================================================

func _duck_music() -> void:
	if get_node_or_null("/root/MusicManager") == null:
		return

	_music_bus_index = AudioServer.get_bus_index(
		MusicManager.MUSIC_BUS_NAME
	)

	if _music_bus_index == -1:
		return

	_music_original_db = AudioServer.get_bus_volume_db(_music_bus_index)

	var target_db: float = _music_original_db + music_duck_db
	var bus_index: int = _music_bus_index

	var tween: Tween = create_tween()
	tween.tween_method(
		func(db: float) -> void:
			AudioServer.set_bus_volume_db(bus_index, db),
		_music_original_db,
		target_db,
		music_duck_time
	)


func _restore_music() -> void:
	if _music_bus_index == -1:
		return

	var bus_index: int = _music_bus_index
	var start_db: float = AudioServer.get_bus_volume_db(bus_index)
	var end_db: float = _music_original_db

	var tween: Tween = create_tween()
	tween.tween_method(
		func(db: float) -> void:
			AudioServer.set_bus_volume_db(bus_index, db),
		start_db,
		end_db,
		music_duck_time
	)
