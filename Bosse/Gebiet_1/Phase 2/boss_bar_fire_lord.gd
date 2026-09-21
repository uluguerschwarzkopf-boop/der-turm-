extends CanvasLayer

@export var boss_group: StringName = &"boss"
@export var boss_name: String = "The Ashen Core"

# ============================================================
# PHASE-NAME-INTRO (NUTZER-WUNSCH)
# ============================================================

# Sobald boss_started feuert (also NACHDEM die Phase-2-Spawn-
# Animation fertig ist und die Boss-Leiste erscheint), taucht der
# Bossname groß in der Bildschirmmitte auf, schrumpft dann und
# wandert an seine Position über der Boss-Leiste. Der echte
# Leisten-Name (label) bleibt so lange unsichtbar (siehe
# _hide_bar_name()) und erscheint erst GENAU dann, wenn der große
# Name dort "ankommt" (siehe _play_name_intro()) - so wie vom Nutzer
# beschrieben, kein separates Verschwinden, sondern ein nahtloser
# Übergang groß -> klein an die Leisten-Position.
@export_group("Phase-Name-Intro")
@export var show_name_intro: bool = true

# Nutzer-Wunsch: zwei verschiedene Varianten, wie der große Name
# wieder verschwindet, EINSTELLBAR per Häkchen (siehe _play_name_
# intro() unten für beide Abläufe):
#
# AN (Standard): Name schrumpft und wandert von der Bildschirmmitte
# zur Leisten-Position, "kommt" dort an und wird nahtlos vom echten
# Leisten-Namen abgelöst (bisheriges Verhalten).
#
# AUS: Name bleibt einfach in der Bildschirmmitte stehen, hält dort
# (intro_hold_time) und löst sich dann an Ort und Stelle in Luft auf
# (Ausblenden über intro_move_time) - der echte Leisten-Name wird
# GENAU dann sichtbar, wandert aber selbst nirgendwo hin.
@export var intro_move_to_bar_position: bool = true

@export var intro_start_font_size: int = 96
@export var intro_fade_in_time: float = 0.25
@export var intro_hold_time: float = 2.0
@export var intro_move_time: float = 0.5
@export var intro_box_size: Vector2 = Vector2(900.0, 160.0)

# Automatisch berechnete Ziel-Position: die Y-Koordinate kommt von der
# Mitte des echten Leisten-Labels, die X-Koordinate wird aber IMMER auf
# die horizontale Bildschirmmitte gezwungen (siehe _play_name_intro()) -
# die Leiste selbst (VBoxContainer) ist symmetrisch um die Bildschirm-
# mitte zentriert, ein aus label.global_position gelesener X-Wert konnte
# durch Container-Reflow-Timing leicht daneben liegen ("oben rechts"
# statt "mittig"). Für Sonderfälle trotzdem per Hand nachjustierbar.
@export var use_manual_target_position: bool = false
@export var manual_target_position: Vector2 = Vector2(640.0, 70.0)

var _name_intro_label: Label = null

@export_group("Fire Particles")
@export var use_fire_particles: bool = true
@export var particle_y_offset: float = -8.0
@export var particle_width_multiplier: float = 0.5
@export var particle_height: float = 2.0

var boss = null
var label: Label = null
var bar: ProgressBar = null
var border: AnimatedSprite2D = null
var fire_particles: CPUParticles2D = null


func _ready() -> void:
	visible = false

	label = find_child("Label", true, false) as Label
	bar = find_child("ProgressBar", true, false) as ProgressBar
	border = find_child("Border", true, false) as AnimatedSprite2D
	fire_particles = find_child("FireParticles", true, false) as CPUParticles2D

	if label == null or bar == null or border == null:
		push_warning("BossBar: Label, ProgressBar oder Border fehlt.")
		return

	if fire_particles != null:
		fire_particles.emitting = false
		fire_particles.visible = true
		fire_particles.z_index = 100

	if not border.animation_finished.is_connected(_on_border_animation_finished):
		border.animation_finished.connect(_on_border_animation_finished)

	await get_tree().process_frame

	boss = get_tree().get_first_node_in_group(boss_group)

	if boss == null:
		push_warning("Boss nicht gefunden.")
		return

	if boss.has_signal("boss_started"):
		boss.boss_started.connect(_on_boss_started)

	if boss.has_signal("phase_1_finished"):
		boss.phase_1_finished.connect(_on_boss_finished)

	if boss.has_signal("phase_2_finished"):
		boss.phase_2_finished.connect(_on_boss_finished)

	if boss.has_signal("summon_started"):
		boss.summon_started.connect(_on_summon_started)

	if boss.has_signal("summon_ended"):
		boss.summon_ended.connect(_on_summon_ended)

	if boss.has_signal("cutscene_started"):
		boss.cutscene_started.connect(_on_cutscene_started)

	label.text = boss_name
	bar.max_value = boss.max_health
	bar.value = boss.hp

	border.play("Normal")
	_update_fire_particles()

	# Name erst beim Intro (siehe _play_name_intro()) sichtbar machen -
	# NUR den Text leeren (nicht z.B. label.modulate.a = 0), damit die
	# Kind-Nodes von "label" (ProgressBar, Border - siehe .tscn) davon
	# unberührt bleiben. Ein einzelnes Leerzeichen statt "" hält die
	# Zeilenzahl/Zeilenhöhe identisch zum echten Namen, damit sich
	# Größe/Position des Labels (und damit die Ziel-Position des
	# Intros, siehe _play_name_intro()) durchs Leeren nicht verschiebt.
	if show_name_intro:
		label.text = " "


func _process(_delta: float) -> void:
	if boss == null:
		return

	if not visible:
		return

	bar.value = boss.hp
	_update_fire_particles()


func _on_boss_started() -> void:
	visible = true

	if fire_particles != null and use_fire_particles:
		fire_particles.emitting = true

	_update_fire_particles()

	if show_name_intro:
		_play_name_intro()
	elif label != null:
		label.text = boss_name


func _on_boss_finished() -> void:
	queue_free()


func _on_cutscene_started() -> void:
	visible = false

	if fire_particles != null:
		fire_particles.emitting = false


func _on_summon_started() -> void:
	border.play("Fire_Start")

	if fire_particles != null and use_fire_particles and visible:
		fire_particles.emitting = true


func _on_summon_ended() -> void:
	border.play("Fire_End")


func _on_border_animation_finished() -> void:
	if border.animation == "Fire_Start":
		border.play("Fire_Loop")
	elif border.animation == "Fire_End":
		border.play("Normal")


# ============================================================
# PHASE-NAME-INTRO
# ============================================================

# Baut das große Intro-Label komplett per Code (genau wie z.B.
# Player/hud.gd das schon für Skill-Slot/Vigor-Leiste macht) und
# übernimmt Schriftart/Farbe/Umriss 1:1 vom echten Leisten-Label,
# damit beide exakt gleich aussehen - taucht groß in der Bildschirm-
# mitte auf, hält kurz, schrumpft dann und wandert an die Position
# des echten Labels. GENAU wenn es dort "ankommt", wird das Intro-
# Label entfernt und der echte Leisten-Name gleichzeitig sichtbar -
# kein separates Verschwinden dazwischen (Nutzer-Wunsch).
func _play_name_intro() -> void:
	if label == null:
		return

	# Ziel-Position VOR dem Wiedereinblenden des echten Namens
	# berechnen (label.text ist zu diesem Zeitpunkt noch der
	# Platzhalter " ", siehe _ready()) - dieselbe Zeilenzahl wie der
	# echte Name sorgt dafür, dass sich Größe/Position dadurch nicht
	# mehr nennenswert verschiebt, wenn der Name später zurückkommt.
	# X wird IMMER auf die Bildschirmmitte gezwungen (siehe Kommentar
	# bei manual_target_position oben) - nur Y kommt aus der echten
	# Label-Position, damit die Höhe weiterhin exakt über der Leiste
	# landet.
	var auto_target_center: Vector2 = label.global_position + label.size / 2.0
	auto_target_center.x = get_viewport().get_visible_rect().size.x / 2.0

	var target_center: Vector2 = (
		manual_target_position if use_manual_target_position
		else auto_target_center
	)

	var target_font_size: int = label.get_theme_font_size("font_size")

	_name_intro_label = Label.new()
	_name_intro_label.text = boss_name
	_name_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_intro_label.clip_text = false
	_name_intro_label.z_index = 100

	_name_intro_label.add_theme_color_override(
		"font_color",
		label.get_theme_color("font_color")
	)

	_name_intro_label.add_theme_color_override(
		"font_outline_color",
		label.get_theme_color("font_outline_color")
	)

	_name_intro_label.add_theme_constant_override(
		"outline_size",
		label.get_theme_constant("outline_size")
	)

	var target_font: Font = label.get_theme_font("font")

	if target_font != null:
		_name_intro_label.add_theme_font_override("font", target_font)

	_name_intro_label.add_theme_font_size_override(
		"font_size",
		intro_start_font_size
	)

	add_child(_name_intro_label)

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var start_center: Vector2 = screen_size / 2.0

	_name_intro_label.size = intro_box_size
	_name_intro_label.pivot_offset = intro_box_size / 2.0
	_name_intro_label.global_position = start_center - intro_box_size / 2.0
	_name_intro_label.modulate.a = 0.0

	var fade_in_tween := create_tween()

	fade_in_tween.tween_property(
		_name_intro_label,
		"modulate:a",
		1.0,
		intro_fade_in_time
	)

	await fade_in_tween.finished

	if not is_instance_valid(_name_intro_label):
		return

	await get_tree().create_timer(intro_hold_time).timeout

	if not is_instance_valid(_name_intro_label):
		return

	if intro_move_to_bar_position:
		var end_pos: Vector2 = target_center - intro_box_size / 2.0

		var move_tween := create_tween()
		move_tween.set_parallel(true)

		move_tween.tween_property(
			_name_intro_label,
			"global_position",
			end_pos,
			intro_move_time
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

		move_tween.tween_method(
			_set_intro_font_size,
			intro_start_font_size,
			target_font_size,
			intro_move_time
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

		await move_tween.finished

		# Genau JETZT übernimmt der echte Leisten-Name nahtlos - kein
		# separates Verschwinden/Ausblenden des Intro-Labels davor.
		if is_instance_valid(label):
			label.text = boss_name

		if is_instance_valid(_name_intro_label):
			_name_intro_label.queue_free()

		_name_intro_label = null

		return

	# intro_move_to_bar_position = AUS (Nutzer-Wunsch): der Name bleibt
	# an Ort und Stelle in der Bildschirmmitte und löst sich dort in
	# Luft auf, statt zur Leisten-Position zu wandern. Der echte
	# Leisten-Name wird GENAU dann sichtbar, wenn das Ausblenden
	# beginnt - so bleibt es weiterhin ein nahtloser Übergang, nur
	# eben ohne Bewegung.
	if is_instance_valid(label):
		label.text = boss_name

	var fade_out_tween := create_tween()

	fade_out_tween.tween_property(
		_name_intro_label,
		"modulate:a",
		0.0,
		intro_move_time
	)

	await fade_out_tween.finished

	if is_instance_valid(_name_intro_label):
		_name_intro_label.queue_free()

	_name_intro_label = null


func _set_intro_font_size(value: float) -> void:
	if _name_intro_label == null or not is_instance_valid(_name_intro_label):
		return

	_name_intro_label.add_theme_font_size_override(
		"font_size",
		int(round(value))
	)


func _update_fire_particles() -> void:
	if fire_particles == null or bar == null or boss == null:
		return

	var percent: float = 0.0

	if boss.max_health > 0:
		percent = float(boss.hp) / float(boss.max_health)

	percent = clamp(percent, 0.0, 1.0)

	if percent <= 0.0:
		fire_particles.emitting = false
		return

	var bar_width: float = bar.size.x
	var current_width: float = bar_width * percent

	fire_particles.global_position.x = bar.global_position.x + current_width * 0.5
	fire_particles.global_position.y = bar.global_position.y + particle_y_offset

	fire_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fire_particles.emission_rect_extents = Vector2(
		max(1.0, current_width * particle_width_multiplier),
		particle_height
	)

	if use_fire_particles and visible:
		fire_particles.emitting = true
