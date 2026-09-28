extends Node


# ============================================================
# HINWEIS
# ============================================================

# Cut-Scene fürs Aufwachen des Miniboss: sobald der Spieler in die
# WakeArea kommt und der Boss seine Aufwach-Animation startet (siehe
# skeleton_tank.gd -> Signal "wake_up_started"), wird die
# Spielersteuerung gesperrt, das HUD ausgeblendet und oben/unten ein
# schwarzer Balken eingeblendet (klassischer Cutscene-Look).
# Zusätzlich ruckelt die Kamera kurz auf den unten konfigurierten
# Animations-Frames der Aufwach-Animation (z.B. wenn der Boss auf
# Frame 10/16/22 seine Ketten rausreißt).
#
# Sobald die Aufwach-Animation fertig ist (Signal "boss_started",
# wird von skeleton_tank.gd in _on_animation_finished() ausgelöst),
# werden Balken, HUD und Spielersteuerung wieder aufgehoben.
#
# Node liegt als Kind direkt am SkeletonTank-Root (siehe
# skeleton_tank.tscn) - so holt sich dieses Script seinen Boss
# einfach über get_parent(), ohne selbst irgendwelche exportierten
# Pfade zu brauchen.


# ============================================================
# EINSTELLUNGEN - BALKEN
# ============================================================

@export_group("Balken")

# Höhe je Balken, als Anteil der Bildschirmhöhe (0.12 = 12%).
@export var bar_height_ratio: float = 0.12
@export var bar_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var bar_fade_time: float = 0.35


# ============================================================
# EINSTELLUNGEN - HUD
# ============================================================

@export_group("HUD")

# Blendet während der Cut-Scene das komplette HUD aus (über den
# schon vorhandenen CutsceneManager-Autoload, siehe Game/
# cutscene_manager.gd - genau das gleiche Muster wie bei
# fire_knight_p_2.gd).
@export var hide_hud: bool = true


# ============================================================
# EINSTELLUNGEN - KAMERA-RUCKLER
# ============================================================

@export_group("Kamera-Ruckler")

# Auf welchen Frames der Aufwach-Animation die Kamera ruckeln soll
# (z.B. wenn der Boss auf Frame 10/16/22 seine Ketten rausreißt).
@export var camera_shake_frames: Array[int] = [10, 16, 22]

# Wie stark die Kamera pro Ruckler ausschlägt, in Pixeln.
@export var camera_shake_amplitude_px: float = 4.0

# Wie lange ein einzelner Ruckler nachschwingt.
@export var camera_shake_duration: float = 0.25

# Wie schnell die Wackel-Richtung während eines Rucklers wechselt -
# kleinerer Wert = zittriger.
@export var camera_shake_retarget_time: float = 0.05


# ============================================================
# EINSTELLUNGEN - KETTEN-SOUND
# ============================================================

@export_group("Ketten-Sound")

# Spielt auf denselben Frames wie der Kamera-Ruckler oben
# (camera_shake_frames) einen Sound ab - über den AudioStreamPlayer2D
# direkt am SkeletonTank-Root (Geschwister-Node von "Cut Scene",
# siehe skeleton_tank.tscn). Dort liegt auch die chain_shatter.mp3
# als Stream drauf und der Bus ist auf "SFX" gestellt, reagiert also
# automatisch mit auf den Soundeffekte-Regler in den Einstellungen.
#
# Lautstärke stellst du direkt am AudioStreamPlayer2D-Node im
# Inspector ein ("Volume Db") - genau der Node, den du selbst
# hinzugefügt hast.
@export var play_chain_sound: bool = true


# ============================================================
# EINSTELLUNGEN - TEST: BOSS-TALK SOUND (nur testweise!)
# ============================================================

@export_group("TEST - Boss-Talk Sound")

# NUR TESTWEISE: spielt beim Start der Cut-Scene (Aufwachen) einmal
# bosstalk1.mp3 ab, über den neuen AudioStreamPlayer2D-Node
# "BossTalkPlayer_TEST" (Geschwister-Node von "Cut Scene", siehe
# skeleton_tank.tscn).
#
# Wieder entfernen, falls das nicht übernommen wird - dann reicht:
#   1. dieser @export (play_boss_talk_test)
#   2. die Variable _boss_talk_player_TEST weiter unten
#   3. die Zeile mit _play_boss_talk_sound_TEST() in
#      _on_boss_wake_up_started()
#   4. die Funktion _play_boss_talk_sound_TEST() ganz unten
#   5. der Node "BossTalkPlayer_TEST" + die bosstalk1.mp3 in
#      skeleton_tank.tscn
# löschen - hängt sonst nirgendwo dran.
@export var play_boss_talk_test: bool = true


# ============================================================
# EINSTELLUNGEN - TOD: KAMERA-WACKLER
# ============================================================

@export_group("Tod - Kamera-Wackler")

# Kurzer Kamera-Ruckler beim Aufprall in der Todes-Animation - selbe
# Stärke/Dauer wie oben bei "Kamera-Ruckler" (camera_shake_amplitude_px /
# camera_shake_duration / camera_shake_retarget_time), nur eben auf
# der Death-Animation statt der Aufwach-Animation, und unabhängig
# davon, ob gerade eine Cut-Scene läuft.
@export var play_death_shake: bool = true

# Auf welchem Frame der Death-Animation der Boss auf dem Boden
# aufschlägt.
@export var death_shake_frame: int = 10


# ============================================================
# NODES / STATUS
# ============================================================

var _boss: Node = null
var _player: Node = null
var _sprite: AnimatedSprite2D = null
var _chain_sound_player: AudioStreamPlayer2D = null
var _boss_talk_player_TEST: AudioStreamPlayer2D = null

var _cutscene_active: bool = false

var _canvas_layer: CanvasLayer = null
var _top_bar: ColorRect = null
var _bottom_bar: ColorRect = null

var _camera: Camera2D = null
var _camera_original_offset: Vector2 = Vector2.ZERO

var _shake_active: bool = false
var _shake_time_left: float = 0.0
var _shake_retarget_timer: float = 0.0
var _shake_target: Vector2 = Vector2.ZERO


func _ready() -> void:
	_boss = get_parent()

	if _boss == null:
		return

	if _boss.has_signal("wake_up_started"):
		_boss.wake_up_started.connect(_on_boss_wake_up_started)

	if _boss.has_signal("boss_started"):
		_boss.boss_started.connect(_on_boss_started)

	_sprite = _boss.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	if _sprite != null:
		_sprite.frame_changed.connect(_on_sprite_frame_changed)

	_chain_sound_player = (
		_boss.get_node_or_null("AudioStreamPlayer2D") as AudioStreamPlayer2D
	)

	_boss_talk_player_TEST = (
		_boss.get_node_or_null("BossTalkPlayer_TEST") as AudioStreamPlayer2D
	)

	_build_bars()


func _process(delta: float) -> void:
	if not _shake_active:
		return

	if _camera == null or not is_instance_valid(_camera):
		_shake_active = false
		return

	_shake_time_left -= delta
	_shake_retarget_timer -= delta

	if _shake_retarget_timer <= 0.0:
		_shake_retarget_timer = camera_shake_retarget_time

		_shake_target = Vector2(
			randf_range(-camera_shake_amplitude_px, camera_shake_amplitude_px),
			randf_range(-camera_shake_amplitude_px, camera_shake_amplitude_px)
		)

	_camera.offset = _camera.offset.lerp(
		_camera_original_offset + _shake_target, 0.35
	)

	if _shake_time_left <= 0.0:
		_shake_active = false
		_camera.offset = _camera_original_offset


# ============================================================
# AUFBAU DER SCHWARZEN BALKEN
# ============================================================

func _build_bars() -> void:
	_canvas_layer = CanvasLayer.new()

	# Deutlich über dem HUD, genau wie EchoBanner/VoidNarration
	# (siehe Game/void_narration.gd, layer = 65).
	_canvas_layer.layer = 65
	add_child(_canvas_layer)

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var bar_height_px: float = screen_size.y * bar_height_ratio

	_top_bar = _make_bar()
	_top_bar.anchor_left = 0.0
	_top_bar.anchor_right = 1.0
	_top_bar.anchor_top = 0.0
	_top_bar.anchor_bottom = 0.0
	_top_bar.offset_left = 0.0
	_top_bar.offset_right = 0.0
	_top_bar.offset_top = 0.0
	_top_bar.offset_bottom = bar_height_px
	_canvas_layer.add_child(_top_bar)

	_bottom_bar = _make_bar()
	_bottom_bar.anchor_left = 0.0
	_bottom_bar.anchor_right = 1.0
	_bottom_bar.anchor_top = 1.0
	_bottom_bar.anchor_bottom = 1.0
	_bottom_bar.offset_left = 0.0
	_bottom_bar.offset_right = 0.0
	_bottom_bar.offset_top = -bar_height_px
	_bottom_bar.offset_bottom = 0.0
	_canvas_layer.add_child(_bottom_bar)


func _make_bar() -> ColorRect:
	var bar := ColorRect.new()

	bar.color = bar_color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Unsichtbar bis zum ersten Aufwachen - wird per Tween eingeblendet.
	bar.modulate.a = 0.0

	return bar


# ============================================================
# START (AUFWACH-ANIMATION BEGINNT)
# ============================================================

func _on_boss_wake_up_started() -> void:
	_cutscene_active = true

	_play_boss_talk_sound_TEST()

	_player = get_tree().get_first_node_in_group("player")

	if _player != null and _player.has_method("lock_control"):
		_player.lock_control()

		# Spieler bleibt während der ganzen Cut-Scene sichtbar im
		# Idle-Frame stehen, genau wie bei der Leere-Narration
		# (siehe void_narration.gd -> play_lines()).
		if _player.has_method("force_idle"):
			_player.force_idle()

	if _player != null:
		_camera = _player.get_node_or_null("Camera2D") as Camera2D

	if _camera != null:
		_camera_original_offset = _camera.offset

	_shake_active = false

	if hide_hud:
		if get_node_or_null("/root/CutsceneManager") != null:
			CutsceneManager.begin_cutscene()
		else:
			push_warning(
				"Mini-Boss Cut Scene: CutsceneManager wurde nicht als Autoload gefunden."
			)

	_show_bars()


# ============================================================
# ENDE (AUFWACH-ANIMATION FERTIG)
# ============================================================

func _on_boss_started() -> void:
	_cutscene_active = false

	_hide_bars()

	if hide_hud:
		if get_node_or_null("/root/CutsceneManager") != null:
			CutsceneManager.end_cutscene()

	_shake_active = false

	if _camera != null and is_instance_valid(_camera):
		_camera.offset = _camera_original_offset

	_camera = null

	if _player != null and _player.has_method("unlock_control"):
		_player.unlock_control()

	_player = null


# ============================================================
# EIN-/AUSBLENDEN DER BALKEN
# ============================================================

func _show_bars() -> void:
	if _top_bar == null or _bottom_bar == null:
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		_top_bar, "modulate:a", 1.0, bar_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		_bottom_bar, "modulate:a", 1.0, bar_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_bars() -> void:
	if _top_bar == null or _bottom_bar == null:
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		_top_bar, "modulate:a", 0.0, bar_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.tween_property(
		_bottom_bar, "modulate:a", 0.0, bar_fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# ============================================================
# KAMERA-RUCKLER + KETTEN-SOUND AUF BESTIMMTEN AUFWACH-FRAMES
# ============================================================

func _on_sprite_frame_changed() -> void:
	if _boss == null or _sprite == null:
		return

	if _cutscene_active:
		# Dynamischer Zugriff über get(), da _boss nur als Node
		# typisiert ist (anim_awake ist ein Export auf
		# skeleton_tank.gd selbst).
		var awake_anim: StringName = _boss.get("anim_awake")

		if (
			_sprite.animation == awake_anim
			and camera_shake_frames.has(_sprite.frame)
		):
			_trigger_camera_shake()
			_play_chain_shatter_sound()

	_maybe_shake_for_death_frame()


# Läuft unabhängig von der Aufwach-Cut-Scene (_cutscene_active) -
# der Tod kann jederzeit passieren, nicht nur während einer Cut-Scene.
func _maybe_shake_for_death_frame() -> void:
	if not play_death_shake:
		return

	var death_anim: StringName = _boss.get("anim_death")

	if _sprite.animation != death_anim:
		return

	if _sprite.frame != death_shake_frame:
		return

	_ensure_camera_for_death_shake()
	_trigger_camera_shake()


# Holt sich bei Bedarf eine eigene Referenz auf die Spieler-Kamera -
# _camera ist sonst nur während der Aufwach-Cut-Scene gesetzt
# (siehe _on_boss_wake_up_started() / _on_boss_started()), beim Tod
# ist davon aber meistens längst nichts mehr aktiv.
func _ensure_camera_for_death_shake() -> void:
	if _camera != null and is_instance_valid(_camera):
		return

	var target_player: Node = get_tree().get_first_node_in_group("player")

	if target_player == null:
		return

	_camera = target_player.get_node_or_null("Camera2D") as Camera2D

	if _camera != null:
		_camera_original_offset = _camera.offset


func _play_chain_shatter_sound() -> void:
	if not play_chain_sound:
		return

	if _chain_sound_player == null:
		return

	if _chain_sound_player.stream == null:
		return

	_chain_sound_player.play()


# NUR TESTWEISE - siehe Hinweis bei play_boss_talk_test oben.
func _play_boss_talk_sound_TEST() -> void:
	if not play_boss_talk_test:
		return

	if _boss_talk_player_TEST == null:
		return

	if _boss_talk_player_TEST.stream == null:
		return

	_boss_talk_player_TEST.play()


func _trigger_camera_shake() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	_shake_time_left = camera_shake_duration
	_shake_retarget_timer = 0.0
	_shake_active = true
