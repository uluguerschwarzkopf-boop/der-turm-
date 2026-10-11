extends Node2D

# Nutzer-Wunsch: Cutscene "Käfig fällt von der Decke".
# Läuft der Spieler unter den Käfig, bleibt er stehen und schaut hoch, die
# Kamera zoomt leicht zum Käfig (Kino-Balken blenden ein). Der Käfig wackelt
# immer stärker (Bildschirm wackelt mit), drin bewegt sich der Schatten
# Mutant. Dann fällt der Käfig, der Spieler setzt sich hin und krabbelt
# rückwärts. Beim Aufprall: Ruckler, Staubwelle nach beiden Seiten, dichte
# Staubwolke. Die Wolke löst sich auf, der Käfig liegt zerbrochen da, der
# Spieler steht auf, der Mutant bricht aus und greift an. Danach normale
# Steuerung.
#
# Vorlage für Balken/HUD/Sperre: mini bosse/Skelleton Tank/
# mini_boss_wake_cutscene.gd (gleiches Muster: CutsceneManager +
# lock_control()).
#
# Position dieses Nodes = Punkt auf dem Boden genau unter dem Käfig.
# Der Auslöser ist das Kind "Auslöser" (Form im Editor anpassbar).

# ============================================================
# KÄFIG
# ============================================================

@export_group("Käfig")
@export var cage_texture: Texture2D
## Ausschnitt des Käfigs in der Grafik (mit Kette oben und Anhänger unten).
@export var cage_region: Rect2 = Rect2(172, 8, 33, 116)
## Wo in diesem Ausschnitt der Käfigkorb sitzt (y oben / y unten, Pixel).
@export var cage_body_top: float = 36.0
@export var cage_body_bottom: float = 92.0
@export var cage_scale: Vector2 = Vector2(1.72, 1.39)
## Aufhängepunkt (Kettenanfang) relativ zu diesem Node.
@export var hang_offset: Vector2 = Vector2(0, -240)
@export var cage_z_index: int = 10

@export_group("Wackeln")
## Leichtes Pendeln, solange nichts passiert (Grad).
@export var idle_swing_deg: float = 1.5
@export var idle_swing_period: float = 4.0
## Stärkstes Wackeln kurz vor dem Fall (Grad) und wie schnell.
@export var shake_swing_deg: float = 11.0
@export var shake_swing_period: float = 0.32
## So lange wackelt der Käfig, bevor er fällt (Sekunden).
@export var shake_time: float = 3.2

@export_group("Fall und Aufprall")
@export var fall_gravity: float = 600.0
## Wie weit die Bruchstücke seitlich fliegen (Pixel).
@export var debris_spread: float = 18.0
@export var debris_settle_time: float = 0.45

# ============================================================
# SCHATTEN MUTANT
# ============================================================

@export_group("Mutant")
## Szene des Gegners, der aus dem Käfig ausbricht.
@export var mob_scene: PackedScene
## Animationen des Gegners, solange er im Käfig sitzt.
@export var mob_anim_calm: StringName = &"laufen"
@export var mob_anim_restless: StringName = &"laufen"
@export var mob_in_cage_scale: float = 1.0
@export var mob_in_cage_modulate: Color = Color(1, 1, 1)
## Tempo seiner Animation im Käfig: ruhig bzw. kurz vor dem Fall.
@export var mob_calm_speed: float = 0.45
@export var mob_restless_speed: float = 1.8
## Pause nach dem Auflösen der Staubwolke, bis der Mutant aufwacht.
@export var mob_wake_delay: float = 0.15

# ============================================================
# SPIELER
# ============================================================

@export_group("Spieler-Animationen")
## Platzhalter, bis es eigene Animationen gibt. Später hier einfach die
## neuen Animationsnamen aus dem Spieler-SpriteFrames eintragen.
@export var anim_look_up: StringName = &"idle"
@export var anim_sit_down: StringName = &"idle"
@export var anim_crawl_back: StringName = &"backstep"
@export var anim_stand_up: StringName = &"idle"
## Wie oft und wie weit er rückwärts rutscht.
@export var crawl_steps: int = 3
@export var crawl_step_distance: float = 10.0
@export var crawl_step_time: float = 0.5
@export var crawl_step_pause: float = 0.35
## Zeit für die Aufsteh-Animation, bevor die Steuerung zurückkommt.
@export var stand_up_time: float = 0.9

# ============================================================
# KINO-MODUS
# ============================================================

@export_group("Kino-Balken")
@export var bar_height_ratio: float = 0.12
@export var bar_color: Color = Color(0, 0, 0, 1)
@export var bar_fade_time: float = 1.0
@export var hide_hud: bool = true

@export_group("Kamera")
## Zoom während der Szene, relativ zum normalen Zoom (1.12 = 12 % näher).
@export var camera_zoom_factor: float = 1.18
## Wie weit die Kamera Richtung Käfig rückt (0 = bleibt beim Spieler, 1 = ganz zum Käfig).
@export_range(0.0, 1.0) var camera_pan_to_cage: float = 0.9
## Kamera zusätzlich hoch/runter schieben (Pixel, negativ = hoch). Leicht
## nach unten, damit der Spieler nicht hinter dem unteren Balken verschwindet.
@export var camera_look_up: float = -42.0
@export var camera_move_time: float = 2.2
## So lange fährt die Kamera vor dem Fall langsam wieder zurück.
@export var camera_return_time: float = 1.8
## Dauerwackeln der Kamera, während der Käfig wackelt (Pixel).
@export var camera_shake_px: float = 1.2
## Ruckler beim Aufprall.
@export var impact_shake_px: float = 6.0
@export var impact_shake_time: float = 0.35

# ============================================================
# STAUB
# ============================================================

@export_group("Staub")
## Staubfarbe. Werte über 1 sind Absicht: "Darkness" dunkelt alles ab,
## sonst wäre der Staub fast unsichtbar.
@export var dust_color: Color = Color(2.0, 2.1, 2.4, 0.6)
## So lange verdeckt die Wolke den Käfig, bis sie sich auflöst.
@export var dust_cloud_time: float = 2.4
## Halbe Breite/Höhe der Wolke in Pixeln (muss den ganzen Käfig abdecken).
@export var dust_cloud_size: Vector2 = Vector2(48, 60)
@export var dust_cloud_amount: int = 170
@export var dust_wave_amount: int = 20
@export var dust_wave_speed: float = 95.0

# ============================================================
# STATUS
# ============================================================

var _triggered: bool = false
var _player: Node2D = null
var _camera: Camera2D = null
var _cam_zoom_orig: Vector2 = Vector2.ONE
var _cam_offset_orig: Vector2 = Vector2.ZERO
var _cam_offset_base: Vector2 = Vector2.ZERO
var _shake_px: float = 0.0
var _shake_time_left: float = 0.0
var _shake_target: Vector2 = Vector2.ZERO
var _shake_now: Vector2 = Vector2.ZERO
var _shake_retarget: float = 0.0
var _cam_controlled: bool = false

var _hang: Node2D = null
var _cage_sprite: Sprite2D = null
var _mob_sprite: AnimatedSprite2D = null
var _swing_deg: float = 0.0
var _swing_period: float = 4.0
var _swing_t: float = 0.0
var _swinging: bool = true

var _canvas_layer: CanvasLayer = null
var _top_bar: ColorRect = null
var _bottom_bar: ColorRect = null
var _dust_texture: Texture2D = null

@onready var trigger: Area2D = $"Auslöser"


func _ready() -> void:
	_swing_deg = idle_swing_deg
	_swing_period = idle_swing_period
	_build_cage()
	_build_bars()
	_dust_texture = _make_dust_texture()
	trigger.body_entered.connect(_on_trigger_body_entered)


func _process(delta: float) -> void:
	if _swinging and _hang != null:
		_swing_t += delta
		_hang.rotation = deg_to_rad(_swing_deg) * sin(_swing_t * TAU / maxf(_swing_period, 0.05))

	if _cam_controlled and _camera != null and is_instance_valid(_camera):
		# Nutzer-Korrektur: Wackeln weich nachziehen (neues Ziel nur alle
		# 0.07 s), sonst wirkt die Kamera ruckig, als würde sie zurückspringen.
		if _shake_time_left > 0.0:
			_shake_time_left -= delta
			_shake_retarget -= delta
			if _shake_retarget <= 0.0:
				_shake_retarget = 0.07
				_shake_target = Vector2(randf_range(-_shake_px, _shake_px), randf_range(-_shake_px, _shake_px))
		else:
			_shake_target = Vector2.ZERO
		_shake_now = _shake_now.lerp(_shake_target, clampf(delta * 18.0, 0.0, 1.0))
		_camera.offset = _cam_offset_base + _shake_now


# ============================================================
# AUFBAU
# ============================================================

func _build_cage() -> void:
	_hang = Node2D.new()
	_hang.name = "Aufhängung"
	_hang.position = hang_offset
	_hang.z_index = cage_z_index
	add_child(_hang)

	# Mutant hinter den Gitterstäben (nur Anzeige, der echte Gegner
	# wird erst beim Ausbrechen erzeugt).
	_mob_sprite = AnimatedSprite2D.new()
	_mob_sprite.name = "Mutant im Käfig"
	var frames: SpriteFrames = _get_mob_frames()
	if frames != null:
		_mob_sprite.sprite_frames = frames
		if frames.has_animation(mob_anim_calm):
			_mob_sprite.play(mob_anim_calm)
			_mob_sprite.speed_scale = mob_calm_speed
	_mob_sprite.scale = Vector2(mob_in_cage_scale, mob_in_cage_scale)
	_mob_sprite.modulate = mob_in_cage_modulate
	# Füße auf dem Käfigboden, Grafik des Mobs hat die Füße 18 px unter der Mitte.
	_mob_sprite.position = Vector2(1.0, cage_body_bottom * cage_scale.y - 18.0 * mob_in_cage_scale)
	_hang.add_child(_mob_sprite)

	_cage_sprite = Sprite2D.new()
	_cage_sprite.name = "Käfig"
	_cage_sprite.texture = cage_texture
	_cage_sprite.region_enabled = true
	_cage_sprite.region_rect = cage_region
	_cage_sprite.scale = cage_scale
	_cage_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Oberkante (Kettenanfang) am Drehpunkt.
	_cage_sprite.offset = Vector2(0.0, cage_region.size.y * 0.5)
	_hang.add_child(_cage_sprite)


func _get_mob_frames() -> SpriteFrames:
	if mob_scene == null:
		return null
	var temp: Node = mob_scene.instantiate()
	var spr: AnimatedSprite2D = temp.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = spr.sprite_frames if spr != null else null
	temp.free()
	return frames


func _build_bars() -> void:
	_canvas_layer = CanvasLayer.new()
	# Über dem HUD, wie bei der Mini-Boss-Cutscene (layer 65).
	_canvas_layer.layer = 65
	add_child(_canvas_layer)
	var bar_h: float = get_viewport().get_visible_rect().size.y * bar_height_ratio
	_top_bar = _make_bar()
	_top_bar.anchor_right = 1.0
	_top_bar.offset_bottom = bar_h
	_canvas_layer.add_child(_top_bar)
	_bottom_bar = _make_bar()
	_bottom_bar.anchor_right = 1.0
	_bottom_bar.anchor_top = 1.0
	_bottom_bar.anchor_bottom = 1.0
	_bottom_bar.offset_top = -bar_h
	_canvas_layer.add_child(_bottom_bar)


func _make_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = bar_color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.modulate.a = 0.0
	return bar


func _make_dust_texture() -> Texture2D:
	# Weicher runder Staubpunkt (nie eckig/pixelig).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


# ============================================================
# AUSLÖSER
# ============================================================

func _on_trigger_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	_triggered = true
	trigger.set_deferred("monitoring", false)
	_player = body as Node2D
	_run_cutscene()


# ============================================================
# ABLAUF
# ============================================================

func _run_cutscene() -> void:
	# --- 1) Sperren, Balken, Kamera zum Käfig ---
	if _player.has_method("lock_control"):
		_player.lock_control()
	if _player.has_method("force_idle"):
		_player.force_idle()
	_face_player_to_cage()
	_play_player_anim(anim_look_up)

	if hide_hud and get_node_or_null("/root/CutsceneManager") != null:
		CutsceneManager.begin_cutscene()

	_fade_bars(1.0)
	_camera = _player.get_node_or_null("Camera2D") as Camera2D
	if _camera != null:
		_cam_zoom_orig = _camera.zoom
		_cam_offset_orig = _camera.offset
		_cam_offset_base = _cam_offset_orig
		_cam_controlled = true

	# --- 2) Käfig wackelt immer stärker, Mutant wird unruhig.
	#        Dabei fährt die Kamera EINMAL langsam auf den Käfig ...
	if _mob_sprite.sprite_frames != null and _mob_sprite.sprite_frames.has_animation(mob_anim_restless):
		_mob_sprite.play(mob_anim_restless)
		_mob_sprite.speed_scale = mob_restless_speed
	var swing_tween: Tween = create_tween().set_parallel(true)
	swing_tween.tween_property(self, "_swing_deg", shake_swing_deg, shake_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	swing_tween.tween_property(self, "_swing_period", shake_swing_period, shake_time * 0.6)
	_start_shake(camera_shake_px, shake_time + camera_return_time)
	if _camera != null:
		var target_offset: Vector2 = _cam_offset_orig + Vector2(
			(global_position.x - _player.global_position.x) * camera_pan_to_cage,
			camera_look_up
		)
		var cam_in: Tween = create_tween().set_parallel(true)
		cam_in.tween_property(_camera, "zoom", _cam_zoom_orig * camera_zoom_factor, camera_move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		cam_in.tween_property(self, "_cam_offset_base", target_offset, camera_move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not await _wait(maxf(shake_time, camera_move_time)):
		return

	#        ... und danach EINMAL langsam wieder zurück, der Käfig wackelt weiter.
	if _camera != null and is_instance_valid(_camera):
		var cam_out: Tween = create_tween().set_parallel(true)
		cam_out.tween_property(_camera, "zoom", _cam_zoom_orig, camera_return_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		cam_out.tween_property(self, "_cam_offset_base", _cam_offset_orig, camera_return_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not await _wait(camera_return_time):
		return

	# --- 3) Käfig fällt, Spieler setzt sich und krabbelt zurück ---
	_swinging = false
	var body_bottom_y: float = cage_body_bottom * cage_scale.y
	var fall_distance: float = maxf(-hang_offset.y - body_bottom_y, 1.0)
	var fall_time: float = sqrt(2.0 * fall_distance / maxf(fall_gravity, 1.0))
	var fall_tween: Tween = create_tween().set_parallel(true)
	fall_tween.tween_property(_hang, "position:y", hang_offset.y + fall_distance, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall_tween.tween_property(_hang, "rotation", 0.0, fall_time * 0.6)
	_crawl_back()
	if not await _wait(fall_time):
		return

	# --- 4) Aufprall: Ruckler, Staubwelle, Staubwolke, Käfig zerbricht ---
	_start_shake(impact_shake_px, impact_shake_time)
	_spawn_dust()
	_break_cage()
	if not await _wait(dust_cloud_time):
		return

	# --- 5) Wolke weg: Spieler steht auf, Mutant bricht aus ---
	_play_player_anim(anim_stand_up)
	var mob: Node2D = _spawn_mob()
	if not await _wait(maxf(stand_up_time, mob_wake_delay)):
		return
	if mob != null and is_instance_valid(mob) and mob.has_method("_wake_up_for_target"):
		mob._wake_up_for_target(_player)

	# --- 6) Kino-Modus aus, Steuerung zurück ---
	_end_cutscene()


func _end_cutscene() -> void:
	_fade_bars(0.0)
	if _camera != null and is_instance_valid(_camera):
		var cam_tween: Tween = create_tween().set_parallel(true)
		cam_tween.tween_property(_camera, "zoom", _cam_zoom_orig, bar_fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		cam_tween.tween_property(self, "_cam_offset_base", _cam_offset_orig, bar_fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		cam_tween.chain().tween_callback(_release_camera)
	if hide_hud and get_node_or_null("/root/CutsceneManager") != null:
		CutsceneManager.end_cutscene()
	if _player != null and is_instance_valid(_player):
		if _player.has_method("force_idle"):
			_player.force_idle()
		if _player.has_method("unlock_control"):
			_player.unlock_control()


func _release_camera() -> void:
	_cam_controlled = false
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = _cam_offset_orig


# Wartet und meldet false, wenn Spieler/Szene inzwischen weg sind
# (z. B. Tod oder Raumwechsel) - dann wird sauber aufgeräumt.
func _wait(seconds: float) -> bool:
	await get_tree().create_timer(maxf(seconds, 0.01)).timeout
	if not is_inside_tree() or _player == null or not is_instance_valid(_player):
		_end_cutscene()
		return false
	return true


# ============================================================
# SPIELER
# ============================================================

func _face_player_to_cage() -> void:
	var right: bool = global_position.x >= _player.global_position.x
	if "facing_right" in _player:
		_player.facing_right = right
	var spr: AnimatedSprite2D = _player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr != null:
		spr.flip_h = not right


func _play_player_anim(anim: StringName) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var spr: AnimatedSprite2D = _player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null or spr.sprite_frames == null:
		return
	if spr.sprite_frames.has_animation(anim):
		spr.play(anim)


# Stück für Stück rückwärts weg vom Käfig (läuft parallel zum Fall/Staub).
func _crawl_back() -> void:
	_play_player_anim(anim_sit_down)
	var away: float = -1.0 if global_position.x >= _player.global_position.x else 1.0
	for i in crawl_steps:
		if _player == null or not is_instance_valid(_player) or not is_inside_tree():
			return
		_play_player_anim(anim_crawl_back)
		var t: Tween = create_tween()
		t.tween_property(_player, "global_position:x", _player.global_position.x + away * crawl_step_distance, crawl_step_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(crawl_step_time + crawl_step_pause).timeout


# ============================================================
# KAMERA / BALKEN
# ============================================================

func _start_shake(px: float, seconds: float) -> void:
	_shake_px = px
	_shake_time_left = seconds


func _fade_bars(alpha: float) -> void:
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(_top_bar, "modulate:a", alpha, bar_fade_time)
	t.tween_property(_bottom_bar, "modulate:a", alpha, bar_fade_time)


# ============================================================
# AUFPRALL
# ============================================================

func _spawn_dust() -> void:
	# Staubwelle nach links und rechts über den Boden.
	for dir in [-1.0, 1.0]:
		var wave := CPUParticles2D.new()
		_setup_dust(wave, dust_wave_amount, 0.9)
		wave.position = Vector2(dir * 6.0, -3.0)
		wave.direction = Vector2(dir, -0.12)
		wave.spread = 10.0
		wave.initial_velocity_min = dust_wave_speed * 0.5
		wave.initial_velocity_max = dust_wave_speed
		wave.damping_min = 70.0
		wave.damping_max = 110.0
		wave.gravity = Vector2(0, -12)
		wave.scale_amount_min = 0.25
		wave.scale_amount_max = 0.55
		add_child(wave)
		wave.restart()

	# Dichte Wolke, die den Käfig zuerst komplett verdeckt.
	var cloud := CPUParticles2D.new()
	_setup_dust(cloud, dust_cloud_amount, dust_cloud_time)
	cloud.position = Vector2(0, -dust_cloud_size.y * 0.8)
	cloud.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	cloud.emission_rect_extents = dust_cloud_size
	cloud.direction = Vector2(0, -1)
	cloud.spread = 180.0
	cloud.initial_velocity_min = 4.0
	cloud.initial_velocity_max = 16.0
	cloud.gravity = Vector2(0, -6)
	cloud.scale_amount_min = 0.7
	cloud.scale_amount_max = 1.5
	add_child(cloud)
	cloud.restart()


func _setup_dust(p: CPUParticles2D, amount: int, life: float) -> void:
	p.z_index = cage_z_index + 1
	p.texture = _dust_texture
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.color = dust_color
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	p.color_ramp = ramp


# Zerlegt das Käfigbild in Bruchstücke, die auseinanderfallen und liegen bleiben.
func _break_cage() -> void:
	_cage_sprite.visible = false
	# Nutzer-Korrektur: Der Mutant bleibt die ganze Zeit sichtbar, bis der
	# echte Gegner an seiner Stelle ausbricht (siehe _spawn_mob()).
	var r: Rect2 = cage_region
	var mid_x: float = r.size.x * 0.5
	var mid_y: float = (cage_body_top + cage_body_bottom) * 0.5
	# Ausschnitte relativ zum Käfig-Ausschnitt: Kette, 4 Korbteile, Anhänger.
	var parts: Array[Rect2] = [
		Rect2(0, 0, r.size.x, cage_body_top),
		Rect2(0, cage_body_top, mid_x, mid_y - cage_body_top),
		Rect2(mid_x, cage_body_top, r.size.x - mid_x, mid_y - cage_body_top),
		Rect2(0, mid_y, mid_x, cage_body_bottom - mid_y),
		Rect2(mid_x, mid_y, r.size.x - mid_x, cage_body_bottom - mid_y),
		Rect2(0, cage_body_bottom, r.size.x, r.size.y - cage_body_bottom),
	]
	for part in parts:
		var piece := Sprite2D.new()
		piece.texture = cage_texture
		piece.region_enabled = true
		piece.region_rect = Rect2(r.position + part.position, part.size)
		piece.scale = cage_scale
		# Hinter dem Spieler, damit die Trümmer ihn nicht verdecken.
		piece.z_index = -1
		# Startposition: dort, wo das Teil im gefallenen Käfig gerade ist.
		var local_center: Vector2 = Vector2(
			(part.position.x + part.size.x * 0.5 - r.size.x * 0.5) * cage_scale.x,
			(part.position.y + part.size.y * 0.5) * cage_scale.y
		)
		piece.position = _hang.position + local_center
		add_child(piece)
		# Ruhelage: seitlich verstreut, flach auf dem Boden.
		var side: float = signf(local_center.x) if absf(local_center.x) > 0.5 else (1.0 if randf() > 0.5 else -1.0)
		var rest: Vector2 = Vector2(
			local_center.x + side * randf_range(debris_spread * 0.3, debris_spread),
			-part.size.x * cage_scale.x * 0.5 * randf_range(0.35, 0.6)
		)
		var rot: float = side * randf_range(0.9, 1.6)
		var t: Tween = create_tween().set_parallel(true)
		t.tween_property(piece, "position:x", rest.x, debris_settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(piece, "position:y", rest.y, debris_settle_time).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.tween_property(piece, "rotation", rot, debris_settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _spawn_mob() -> Node2D:
	if mob_scene == null:
		return null
	var mob: Node2D = mob_scene.instantiate() as Node2D
	if mob == null:
		return null
	# Zu den anderen Gegnern hängen, falls es den Node gibt.
	var holder: Node = get_tree().current_scene.get_node_or_null("Enemies") if get_tree().current_scene != null else null
	if holder == null:
		holder = get_parent()
	holder.add_child(mob)
	mob.global_position = global_position
	_mob_sprite.visible = false
	return mob
