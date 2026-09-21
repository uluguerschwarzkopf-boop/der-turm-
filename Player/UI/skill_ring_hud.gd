extends Control


# ============================================================
# SKILL-BAUM: XP-RING (OBEN RECHTS IM HUD)
# ============================================================
#
# Zeigt, sobald eine Skill-Statur gewählt wurde (siehe Objects/
# Staturen/skill_statue.gd -> RunState.choose_skill_path()), einen
# Kreis mit Rand oben rechts im HUD. Direkt am Rand dieses Kreises
# liegt ein zweiter, dünnerer Ring - der XP-Ring - der sich mit
# jedem besiegten Monster ein Stück füllt (siehe RunState.
# add_skill_path_xp()). Die Füllfarbe entspricht dem gewählten Pfad
# (RunState.get_skill_path_color()).
#
# Ist der XP-Ring einmal komplett voll, schließt er sich, die Zahl
# in der Mitte des Hauptkreises geht um 1 hoch (kein "+1"-Aufblitzen
# - die Zahl selbst steigt einfach, wie bei Ori), und der XP-Ring
# beginnt wieder bei 0.
#
# WICHTIG (nach mehreren fehlgeschlagenen Anläufen über HUD-Signale/
# Gruppen-Suche bewusst so gebaut): Dieses Script liest RunState
# JEDEN FRAME komplett SELBST aus (siehe _process() unten), kein
# "hud"-Gruppen-Lookup, kein has_method() von außen. Dadurch kann
# nichts mehr an einer stillen Verbindungs-/Timing-Lücke zwischen HUD
# und Statur scheitern.
#
# EINE Ausnahme: RunState.enemy_killed_for_xp (Signal) - der Ring
# wird bei jedem Gegner-Kill NICHT sofort weitergezogen, sondern
# erst, wenn ein kleiner Pixel von der Todesposition des Gegners aus
# beim Ring "angekommen" ist (siehe KILL-PIXEL-Abschnitt unten,
# Nutzer-Wunsch). Deshalb spiegelt _process() unten RunState.
# skill_path_xp/skill_points NICHT mehr live 1:1, sondern nur noch
# als Sicherheitsnetz für Änderungen OHNE Pixel (z.B. den Debug-
# Button im Pause-Menü) - der Ring zeigt am Ende trotzdem IMMER genau
# das, was in RunState steht, nur mit einer kleinen, gewollten
# Verzögerung für den Kill-Pixel-Effekt.
#
# RunState.skill_ring_revealed (siehe run_state.gd) steuert dabei
# GENAU den Zeitpunkt des ersten Sichtbarwerdens: bleibt false bis
# skill_statue.gd es am ENDE der "Aufnehmen"-Animation auf true
# setzt (reine Property-Zuweisung, kann nicht still fehlschlagen -
# im Gegensatz zu einer Gruppen-Suche mit has_method()-Guard).

@export var ring_radius: float = 26.0
@export var main_border_width: float = 3.0
@export var xp_ring_width: float = 7.0

@export var track_color: Color = Color(1.0, 1.0, 1.0, 0.16)
@export var main_fill_color: Color = Color(0.05, 0.05, 0.08, 0.82)
@export var main_border_color: Color = Color(0.86, 0.78, 0.55, 0.95)

@export_group("Kill-Pixel (fliegt zum Ring)")

# Wie lange ein einzelner Pixel von der Todesposition des Gegners bis
# zum Ring braucht (siehe spawn_xp_orb()).
@export var xp_orb_flight_duration: float = 0.45

# Größe des quadratischen Pixels - bewusst klein/hartkantig gehalten
# (Pixel-Art-Look, kein weicher Kreis wie bei den Zauber-Partikeln).
@export var xp_orb_size: float = 4.0

# Wie lange EIN Warteschlangen-Schritt braucht, wenn nach Ankunft
# eines Pixels der Ring ein Stück weitergefüllt wird (siehe
# _try_start_catchup()) - "langsam" laut Nutzer-Wunsch, deshalb
# bewusst nicht sofort/instant.
@export var xp_catchup_step_duration: float = 0.35

@export_group("Effekt bei neuem Punkt")

# Wie lange der auslaufende Blitzring nach außen wächst und
# ausblendet (siehe _play_point_gain_effect()) - "wie in Ori" beim
# Einsammeln von Erfahrung/Fähigkeitspunkten.
@export var point_gain_burst_duration: float = 0.6

# Um wie viel Pixel der Blitzring über den XP-Ring hinaus nach
# außen wächst, bevor er komplett verblasst ist.
@export var point_gain_burst_extra_radius: float = 34.0

@onready var _point_label: Label = $PointLabel

# 0.0 (leer) bis <1.0 (kurz vor voll) - siehe RunState.
# skill_path_xp.
var _xp_progress: float = 0.0

# Aktuelle Füllfarbe des XP-Rings, kommt über set_path_color() von
# RunState.get_skill_path_color().
var _xp_color: Color = Color(0.8, 0.8, 0.8, 1.0)

var _skill_points: int = 0

# false, solange set_skill_points() noch nie aufgerufen wurde -
# verhindert, dass beim allerersten Einblenden des Rings (oder beim
# Wiederbetreten des Raums mit bereits vorhandenen Punkten aus
# einem Spielstand) sofort der Punkt-Effekt abgefeuert wird, obwohl
# gerade gar kein NEUER Punkt dazugekommen ist.
var _skill_points_initialized: bool = false

# 1.0 = kein aktiver Effekt gerade. Läuft beim Punktgewinn von 0.0
# auf 1.0 hoch (siehe _play_point_gain_effect()/_set_burst_
# progress()) und steuert in _draw() den auslaufenden Blitzring.
var _burst_progress: float = 1.0
var _burst_tween: Tween = null
var _label_tween: Tween = null

# ============================================================
# KILL-PIXEL -> RING (siehe RunState.enemy_killed_for_xp)
# ============================================================
#
# _xp_progress/_skill_points oben werden NICHT mehr jeden Frame 1:1
# von RunState gespiegelt (das würde den ganzen Warte-auf-den-Pixel-
# Effekt sofort überspringen) - stattdessen bleiben sie auf ihrem
# zuletzt ANGEZEIGTEN Stand, bis ein Kill-Pixel hier ankommt UND
# dadurch _try_start_catchup() den Ring ein Stück weiterzieht.
#
# Wie viele angekommene Pixel noch auf ihren Füll-Schritt warten -
# wird bei jeder Pixel-Ankunft (_on_xp_orb_arrived()) hochgezählt und
# von _try_start_catchup() nacheinander abgearbeitet (ein Schritt
# nach dem anderen, nicht alle gleichzeitig).
var _pending_orbs: int = 0

var _catchup_tween: Tween = null


func _ready() -> void:
	# Der Skill-Baum (Game/skill_tree_menu.gd) UND das Pause-Menü
	# (Game/pause_menu.gd, siehe dessen Debug-Button "+1 Skillpunkt")
	# pausieren beim Öffnen den kompletten Baum (get_tree().paused =
	# true). Ohne PROCESS_MODE_ALWAYS würde _process() unten dann
	# einfach mit aussetzen - RunState.skill_points ändert sich zwar
	# sofort, aber der Ring hier würde erst beim Schließen/Entpausieren
	# nachziehen, statt live mitzuzählen (genau der Bug, den der
	# Nutzer gemeldet hat).
	process_mode = Node.PROCESS_MODE_ALWAYS

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	if get_node_or_null("/root/RunState") != null:
		if not RunState.enemy_killed_for_xp.is_connected(
			_on_enemy_killed_for_xp
		):
			RunState.enemy_killed_for_xp.connect(
				_on_enemy_killed_for_xp
			)

	if _point_label != null:
		_point_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_point_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_point_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_point_label.add_theme_font_size_override("font_size", 22)
		_point_label.add_theme_color_override(
			"font_color",
			Color(0.97, 0.94, 0.85, 1.0)
		)

	_refresh_label()


func _process(_delta: float) -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	var should_show: bool = (
		RunState.has_chosen_skill_path()
		and RunState.skill_ring_revealed
	)

	if should_show != visible:
		visible = should_show

		if should_show:
			set_path_color(RunState.get_skill_path_color())
			# Erstes Sichtbarwerden (frisch gewählt ODER Raum mit
			# bereits vorhandenen Punkten aus einem Spielstand wieder
			# betreten) - hier bewusst SOFORT/ohne Animation auf den
			# echten Stand bringen, kein Pixel dafür nötig/vorhanden.
			_sync_displayed_progress_instantly()

	if not should_show:
		return

	# Sicherheitsnetz für Änderungen OHNE zugehörigen Kill-Pixel (z.B.
	# der Debug-Button "+1 Skillpunkt" im Pause-Menü, siehe RunState.
	# debug_add_skill_point()) - normale Gegner-Kills laufen komplett
	# über die Pixel-Warteschlange (_pending_orbs) unten und werden
	# hier deshalb NICHT nochmal angefasst, solange noch etwas davon
	# aussteht/läuft.
	var catchup_active: bool = (
		_pending_orbs > 0
		or (_catchup_tween != null and _catchup_tween.is_valid())
	)

	if not catchup_active:
		var out_of_sync: bool = (
			not is_equal_approx(_xp_progress, RunState.skill_path_xp)
			or _skill_points != RunState.skill_points
		)

		if out_of_sync:
			_sync_displayed_progress_instantly()


func set_path_color(color: Color) -> void:
	_xp_color = color
	queue_redraw()


func set_xp_progress(progress: float) -> void:
	_xp_progress = clamp(progress, 0.0, 1.0)
	queue_redraw()


func set_skill_points(points: int) -> void:
	var new_points: int = max(points, 0)

	if not _skill_points_initialized:
		_skill_points_initialized = true
		_skill_points = new_points
		_refresh_label()
		return

	if new_points > _skill_points:
		_play_point_gain_effect()

	_skill_points = new_points
	_refresh_label()


# Bringt die ANGEZEIGTEN Werte OHNE Animation sofort auf den echten
# RunState-Stand - für den ersten Sichtbarwerden des Rings und als
# Sicherheitsnetz (siehe _process() oben), NICHT für normale Kills
# (die laufen über den Kill-Pixel-Effekt unten).
func _sync_displayed_progress_instantly() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	set_xp_progress(RunState.skill_path_xp)
	set_skill_points(RunState.skill_points)


# ============================================================
# KILL-PIXEL: FLIEGT VON DER TODESPOSITION ZUM RING
# ============================================================

func _on_enemy_killed_for_xp(death_position: Vector2) -> void:
	spawn_xp_orb(death_position)


# Lässt einen kleinen, hartkantigen Pixel (in der aktuellen Ring-/
# Pfadfarbe, siehe _xp_color) von der Weltposition des gestorbenen
# Gegners zur Ringmitte fliegen. Der Ring-Füllstand wird dabei NOCH
# NICHT verändert - das passiert erst bei Ankunft, siehe
# _on_xp_orb_arrived()/_try_start_catchup() unten.
func spawn_xp_orb(from_world_position: Vector2) -> void:
	if not visible:
		# Ring gerade gar nicht sichtbar - nichts zu sehen, der
		# nächste Sicherheitsnetz-Sync in _process() holt den echten
		# RunState-Stand trotzdem nach, sobald der Ring wieder
		# eingeblendet wird (siehe dort).
		return

	var viewport: Viewport = get_viewport()

	if viewport == null:
		return

	# Weltposition -> Bildschirm-/Viewport-Pixel (berücksichtigt
	# Kameraposition/-zoom), dann relativ zu diesem Control - genau
	# dieselbe Pixel-Koordinaten-Annahme wie beim restlichen HUD
	# (siehe Player/hud.gd): eine CanvasLayer ohne eigene Verschiebung/
	# Skalierung deckt sich 1:1 mit Viewport-Pixeln.
	var screen_position: Vector2 = (
		viewport.get_canvas_transform() * from_world_position
	)
	var local_start: Vector2 = screen_position - global_position

	var orb := ColorRect.new()
	orb.color = _xp_color
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.size = Vector2(xp_orb_size, xp_orb_size)
	orb.position = local_start - orb.size * 0.5
	orb.pivot_offset = orb.size * 0.5
	orb.scale = Vector2(0.4, 0.4)

	add_child(orb)

	var target_local: Vector2 = size * 0.5 - orb.size * 0.5

	var flight_tween := create_tween()
	flight_tween.set_parallel(true)
	flight_tween.tween_property(
		orb, "scale", Vector2.ONE, 0.08
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flight_tween.tween_property(
		orb,
		"position",
		target_local,
		xp_orb_flight_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	flight_tween.set_parallel(false)
	flight_tween.tween_callback(orb.queue_free)
	flight_tween.tween_callback(_on_xp_orb_arrived)


func _on_xp_orb_arrived() -> void:
	_pending_orbs += 1
	_try_start_catchup()


# Arbeitet die Warteschlange angekommener Pixel EINEN nach dem
# anderen ab (siehe _pending_orbs oben) - erst wenn ein Füll-Schritt
# fertig ist (_on_catchup_step_filled_ring()), wird der nächste
# gestartet, damit mehrere Kills kurz hintereinander nicht alle auf
# einmal, sondern sichtbar nacheinander im Ring ankommen.
func _try_start_catchup() -> void:
	if _catchup_tween != null and _catchup_tween.is_valid():
		return

	if _pending_orbs <= 0:
		return

	if get_node_or_null("/root/RunState") == null:
		return

	_pending_orbs -= 1

	var per_kill_xp: float = RunState.SKILL_XP_PER_ENEMY_KILL
	var start_progress: float = _xp_progress

	_catchup_tween = create_tween()

	if start_progress + per_kill_xp >= 1.0:
		# Dieser Kill macht den Ring voll - erst ganz auffüllen,
		# danach (siehe _on_catchup_step_filled_ring()) schließt er
		# sich, die Zahl geht hoch und er beginnt wieder bei 0.
		_catchup_tween.tween_method(
			set_xp_progress,
			start_progress,
			1.0,
			xp_catchup_step_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_catchup_tween.tween_callback(_on_catchup_step_filled_ring)
	else:
		_catchup_tween.tween_method(
			set_xp_progress,
			start_progress,
			start_progress + per_kill_xp,
			xp_catchup_step_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_catchup_tween.tween_callback(_try_start_catchup)


func _on_catchup_step_filled_ring() -> void:
	set_skill_points(_skill_points + 1)
	set_xp_progress(0.0)
	_try_start_catchup()


# "Wie in Ori" beim Erreichen eines neuen Punktes: ein heller Blitz
# in der Mitte, der sofort wieder verschwindet, plus ein Ring in der
# Pfadfarbe, der kurz nach außen wächst und dabei ausblendet (siehe
# _draw()), dazu ein kleiner Bounce der Zahl in der Mitte.
func _play_point_gain_effect() -> void:
	if _burst_tween != null and _burst_tween.is_valid():
		_burst_tween.kill()

	_burst_progress = 0.0

	_burst_tween = create_tween()
	_burst_tween.tween_method(
		_set_burst_progress,
		0.0,
		1.0,
		point_gain_burst_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_play_label_pop()


func _set_burst_progress(value: float) -> void:
	_burst_progress = value
	queue_redraw()


func _play_label_pop() -> void:
	if _point_label == null:
		return

	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()

	_point_label.pivot_offset = _point_label.size * 0.5
	_point_label.scale = Vector2(1.65, 1.65)

	_label_tween = create_tween()
	_label_tween.tween_property(
		_point_label,
		"scale",
		Vector2.ONE,
		0.4
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Zeigt bewusst noch NICHTS an, solange skill_points 0 ist (der
# Nutzer-Wunsch war: "es geht einfach auf 1" - die Zahl erscheint
# erst, wenn wirklich ein erster Punkt verdient wurde, statt schon
# vorher eine "0" im Ring stehen zu haben).
func _refresh_label() -> void:
	if _point_label == null:
		return

	_point_label.text = (
		str(_skill_points) if _skill_points > 0 else ""
	)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var xp_radius: float = ring_radius + xp_ring_width * 0.5 + 1.0

	draw_circle(center, ring_radius, main_fill_color)

	draw_arc(
		center,
		xp_radius,
		0.0,
		TAU,
		48,
		track_color,
		xp_ring_width,
		true
	)

	if _xp_progress > 0.001:
		var start_angle: float = -PI * 0.5
		var end_angle: float = start_angle + TAU * _xp_progress

		var point_count: int = max(
			2,
			int(64.0 * _xp_progress) + 1
		)

		draw_arc(
			center,
			xp_radius,
			start_angle,
			end_angle,
			point_count,
			_xp_color,
			xp_ring_width,
			true
		)

	draw_arc(
		center,
		ring_radius,
		0.0,
		TAU,
		48,
		main_border_color,
		main_border_width,
		true
	)

	# Punkt-Effekt (siehe _play_point_gain_effect()): läuft nur kurz
	# nach einem neuen Punkt, sonst ist _burst_progress >= 1.0 und
	# hier ist nichts zu zeichnen.
	if _burst_progress < 1.0:
		var burst_radius: float = lerp(
			xp_radius,
			xp_radius + point_gain_burst_extra_radius,
			_burst_progress
		)

		var burst_alpha: float = 1.0 - _burst_progress

		draw_arc(
			center,
			burst_radius,
			0.0,
			TAU,
			48,
			Color(_xp_color.r, _xp_color.g, _xp_color.b, burst_alpha * 0.9),
			max(1.0, 5.0 * burst_alpha),
			true
		)

		# Kurzer heller Blitz genau in der Mitte, klingt sehr schnell
		# ab (schon nach einem Sechstel der Burst-Dauer komplett weg) -
		# das eigentliche "Pop"-Gefühl kommt von diesem Blitz plus dem
		# Zahlen-Bounce (siehe _play_label_pop()), nicht vom Ring
		# selbst, der länger und dezenter ausklingt.
		var flash_alpha: float = clamp(1.0 - _burst_progress * 6.0, 0.0, 1.0)

		if flash_alpha > 0.0:
			var flash_color: Color = Color(
				lerp(_xp_color.r, 1.0, 0.5),
				lerp(_xp_color.g, 1.0, 0.5),
				lerp(_xp_color.b, 1.0, 0.5),
				flash_alpha * 0.85
			)

			draw_circle(center, ring_radius + 2.0, flash_color)
