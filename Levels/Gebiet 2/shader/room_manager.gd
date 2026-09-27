class_name RoomManager
extends Node


static var return_to_spawn_name: String = ""
static var show_death_screen_after_restart: bool = false

# Wird nach dem Sieg über Phase 2 gesetzt.
# Beim erneuten Laden des Phase-1-Raums werden Boss und Bossleiste entfernt.
static var boss_defeated_in_current_run: bool = false


@export_group("Run System")

@export_file("*.tscn")
var run_start_scene_path: String = "res://Game/game.tscn"

@export var death_restart_delay: float = 1.0


@export_group("Boss Room")

# Diesen Pfad im Inspector mit dem Ordner-Symbol auswählen.
# Raum 9 lädt diesen Raum direkt als Raum 10.
@export_file("*.tscn")
var boss_room_path: String = ""


@export_group("Boss Phase Transition")

@export_file("*.tscn")
var phase_2_room_path: String = ""


@export_group("Phase 2 Return")

@export_file("*.tscn")
var phase_1_return_room_path: String = ""

@export var return_spawn_name: String = "ReturnSpawn"


@export_group("Boss Return Cleanup")

# Diese Pfade passen zu deinem Bossraum-Szenenbaum:
#
# Gebiet_1_Boss_Room
# ├── RoomManager
# ├── Boss_Bar
# └── FireKnightP1

@export var phase_1_boss_path: NodePath = ^"../FireKnightP1"
@export var phase_1_boss_bar_path: NodePath = ^"../Boss_Bar"


@export_group("Phase Transition Flash")

@export var use_phase_flash: bool = true
@export var flash_fade_in_time: float = 0.12
@export var flash_hold_time: float = 0.15
@export var flash_fade_out_time: float = 0.35

@export var flash_color: Color = Color(
	1.0,
	0.55,
	0.15,
	1.0
)


@export_group("Void Erzählung")

# Eindeutiger Schlüssel für RunState.shown_narrations - jeder Raum
# mit eigener Void-Sequenz braucht seinen eigenen Wert, sonst
# teilen sich mehrere Räume denselben "schon gezeigt"-Status.
# Leer lassen (Standard), wenn dieser Raum keine Void-Sequenz hat.
@export var void_intro_id: StringName = &""

# Übersetzungsschlüssel (siehe SettingsManager.TRANSLATIONS,
# Präfix "void.") - werden der Reihe nach von Game/void_
# narration.gd abgespielt, sobald der Raum normal betreten wird
# (siehe _maybe_play_void_narration() unten).
@export var void_intro_lines: Array[String] = []


@export_group("Spieler-Gedanke")

# Eindeutiger Schlüssel für RunState.shown_narrations - wird mit
# den Void-Erzählungen geteilt (beides sind "einmal pro Lauf"-
# Story-Momente, siehe RunState.has_shown_narration()/
# mark_narration_shown()). Jeder Raum mit eigener Gedanken-
# Sprechblase braucht seinen eigenen Wert. Leer lassen (Standard),
# wenn dieser Raum keine hat.
@export var thought_bubble_id: StringName = &""

# Übersetzungsschlüssel (siehe SettingsManager.TRANSLATIONS,
# Präfix "thought.") - werden der Reihe nach über dem Spieler
# angezeigt, 2 Sekunden nach dem normalen Betreten des Raums.
# Sperrt NICHT die Spielersteuerung (siehe _maybe_show_room_
# thought_bubble() unten und Player/player_thought_bubble.gd).
@export var thought_bubble_lines: Array[String] = []


@export_group("Raum-Musik")

# Schlüssel für MusicManager.ROOM_MUSIC_PATHS (siehe Game/music_
# manager.gd) - wird beim normalen Betreten dieses Raums per
# Crossfade eingeblendet (die Gebiets-Musik wird dabei nur leiser,
# NICHT gestoppt) und beim Verlassen des Raums wieder umgekehrt
# ausgeblendet (siehe _maybe_start_room_music()/_maybe_stop_room_
# music() unten). Leer lassen (Standard), wenn dieser Raum keine
# eigene Musik hat.
@export var room_music_id: StringName = &""


@onready var player: CharacterBody2D = (
	get_tree().get_first_node_in_group("player")
	as CharacterBody2D
)

@onready var spawn_door: Node = get_node_or_null(
	"../SpawnDoor"
)

@onready var exit_door: Node = get_node_or_null(
	"../ExitDoor"
)

@onready var player_spawn: Marker2D = (
	get_node_or_null("../PlayerSpawn")
	as Marker2D
)


var busy: bool = false
var death_restart_started: bool = false
var room_change_started: bool = false


func _ready() -> void:
	add_to_group("room_manager")

	print(
		"ROOM MANAGER LÄUFT: ",
		get_path()
	)

	if player == null:
		push_warning(
			"RoomManager: Kein Player gefunden."
		)
		return

	# Steuerung SOFORT sperren, synchron, noch vor jedem await -
	# sonst kann der Spieler für ein paar Frames noch laufen, bevor
	# enter_room() weiter unten (nach Tür-Animation/Gebiets-Titel/
	# Erzählung der Leere) regulär sperrt. Das ist besonders bei
	# frisch geladenen Räumen (z.B. Bosskampf-Übergang per
	# change_scene_to_file) spürbar, wo der neue Player-Node ohne
	# diese Zeile ein paar Frames lang ungesperrt wäre.
	if player.has_method("lock_control"):
		player.lock_control()

	# Wenn wir nach dem Sieg über Phase 2 in den
	# Phase-1-Bossraum zurückkehren, werden Boss und Leiste entfernt.
	_remove_defeated_phase_1_boss()

	_connect_player_signals()

	await get_tree().process_frame

	_connect_boss_signals()

	await enter_room()


# ============================================================
# FRIENDLY SUMMONS BETWEEN ROOMS
# ============================================================

func _get_player_summons_manager() -> Node:
	if player == null or not is_instance_valid(player):
		return null

	return player.get_node_or_null(
		"Scripts/PlayerSummons"
	)


func _save_summons_before_room_change() -> void:
	var summons_manager: Node = (
		_get_player_summons_manager()
	)

	if (
		summons_manager != null
		and summons_manager.has_method("save_to_run_state")
	):
		summons_manager.save_to_run_state()


func _restore_summons_after_room_change() -> void:
	var summons_manager: Node = (
		_get_player_summons_manager()
	)

	if (
		summons_manager != null
		and summons_manager.has_method(
			"restore_from_run_state"
		)
	):
		summons_manager.restore_from_run_state()


# ============================================================
# PHASE-1-BOSS NACH PHASE 2 ENTFERNEN
# ============================================================

func _remove_defeated_phase_1_boss() -> void:
	if not boss_defeated_in_current_run:
		return

	var phase_1_boss: Node = get_node_or_null(
		phase_1_boss_path
	)

	var boss_bar: Node = get_node_or_null(
		phase_1_boss_bar_path
	)

	if phase_1_boss != null:
		phase_1_boss.queue_free()

		print(
			"RoomManager: FireKnightP1 nach Phase 2 entfernt."
		)

	if boss_bar != null:
		boss_bar.queue_free()

		print(
			"RoomManager: Boss_Bar nach Phase 2 entfernt."
		)


func _connect_player_signals() -> void:
	if player == null:
		return

	var health: Node = player.get_node_or_null(
		"Scripts/PlayerHealth"
	)

	if health == null:
		push_warning(
			"RoomManager: PlayerHealth fehlt."
		)
		return

	if health.has_signal("died"):
		if not health.died.is_connected(
			_on_player_died
		):
			health.died.connect(
				_on_player_died
			)


func _connect_boss_signals() -> void:
	# Nach Phase 2 wurde der Boss bereits entfernt.
	if boss_defeated_in_current_run:
		return

	var boss: Node = get_tree().get_first_node_in_group(
		"boss"
	)

	if boss == null:
		return

	if boss.has_signal("phase_1_finished"):
		if not boss.phase_1_finished.is_connected(
			_on_phase_1_finished
		):
			boss.phase_1_finished.connect(
				_on_phase_1_finished
			)

	if boss.has_signal("phase_2_finished"):
		if not boss.phase_2_finished.is_connected(
			_on_phase_2_finished
		):
			boss.phase_2_finished.connect(
				_on_phase_2_finished
			)


func enter_room() -> void:
	# DEBUG (Shop-Checkpoint / SpawnDoor-Suche): zeigt bei JEDEM Raum-
	# Betreten sofort, ob player/spawn_door/player_spawn gefunden wurden
	# und über welchen der beiden Wege (return_to_spawn_name gesetzt vs.
	# normaler Spawn) der Spieler gleich positioniert wird.
	print(
		"enter_room() | Raum=",
		(get_tree().current_scene.name if get_tree() != null and get_tree().current_scene != null else "?"),
		" | player=",
		player,
		" | spawn_door=",
		spawn_door,
		" | player_spawn=",
		player_spawn,
		" | return_to_spawn_name='",
		RoomManager.return_to_spawn_name,
		"'"
	)

	if player == null:
		push_warning(
			"RoomManager: enter_room() abgebrochen - kein Player gefunden."
		)
		return

	busy = true
	room_change_started = false

	if player.has_method("lock_control"):
		player.lock_control()

	if player.has_method("revive_for_room"):
		player.revive_for_room()

	if RoomManager.return_to_spawn_name != "":
		await _enter_at_return_spawn()
		return

	await _enter_at_normal_spawn()


func _enter_at_return_spawn() -> void:
	var return_spawn := get_tree().current_scene.find_child(
		RoomManager.return_to_spawn_name,
		true,
		false
	) as Marker2D

	if return_spawn != null:
		player.global_position = (
			return_spawn.global_position
		)
	else:
		push_warning(
			"RoomManager: ReturnSpawn fehlt: "
			+ RoomManager.return_to_spawn_name
		)

	RoomManager.return_to_spawn_name = ""

	_reset_player_camera()

	player.visible = true

	_restore_summons_after_room_change()

	var echo_to_reveal: StringName = _consume_pending_echo_reveal()

	if echo_to_reveal != &"":
		await _play_echo_reveal_sequence(echo_to_reveal)

	if player.has_method("unlock_control"):
		player.unlock_control()

	busy = false


# Gibt das Echo zurück, das gerade frisch enthüllt werden soll
# (siehe RunState.pending_echo_reveal), und verbraucht es dabei
# sofort (auf &""), damit die Enthüllungs-Sequenz garantiert nur
# einmal abläuft. Leerer StringName (&"") = gerade nichts enthüllen.
func _consume_pending_echo_reveal() -> StringName:
	if get_node_or_null("/root/RunState") == null:
		return &""

	var echo_id: StringName = RunState.pending_echo_reveal
	RunState.pending_echo_reveal = &""

	return echo_id


# Ablauf: Spieler-Animation (einmalig, dabei control_locked -
# siehe play_echo_reveal_animation() in player.gd) -> Kontrolle
# wird SOFORT DANACH wieder freigegeben, damit man sich schon
# während der Banner-Einblende ("... ERHALTEN", übersetzt) frei
# bewegen kann -> dauerhaftes HUD-Icon einblenden.
func _play_echo_reveal_sequence(echo_id: StringName) -> void:
	var definition: Dictionary = RunState.ECHO_DEFINITIONS.get(
		echo_id, {}
	)

	if definition.is_empty():
		return

	if player == null:
		return

	if player.has_method("play_echo_reveal_animation"):
		await player.play_echo_reveal_animation(
			definition.get("anim_name", &"")
		)

	# Ab hier läuft nur noch die Banner-Einblende (reines Overlay,
	# kein Grund mehr, den Spieler stillzuhalten) - Kontrolle schon
	# jetzt freigeben statt erst am Ende von _enter_at_return_spawn().
	if player.has_method("unlock_control"):
		player.unlock_control()

	var banner := EchoBanner.new()

	if get_node_or_null("/root/SettingsManager") != null:
		banner.banner_text = SettingsManager.t(
			definition.get("translation_key", "")
		)

	get_tree().current_scene.add_child(banner)

	await banner.play_banner()

	var hud: Node = get_tree().get_first_node_in_group(&"hud")

	if hud != null and hud.has_method("reveal_echo"):
		hud.reveal_echo(echo_id)


func _enter_at_normal_spawn() -> void:
	if (
		spawn_door != null
		and spawn_door.has_method(
			"get_spawn_position"
		)
	):
		player.global_position = (
			spawn_door.get_spawn_position()
		)

		print(
			"_enter_at_normal_spawn() | über spawn_door (",
			spawn_door.name,
			") positioniert bei ",
			player.global_position
		)

	elif player_spawn != null:
		player.global_position = (
			player_spawn.global_position
		)

		print(
			"_enter_at_normal_spawn() | über player_spawn positioniert bei ",
			player.global_position
		)

	else:
		push_warning(
			"RoomManager: Kein Spawnpunkt gefunden."
		)

		print(
			"_enter_at_normal_spawn() | WARNUNG: weder spawn_door noch player_spawn gefunden - Spieler bleibt an Position ",
			player.global_position
		)

	_reset_player_camera()

	player.visible = false

	if (
		spawn_door != null
		and spawn_door.has_method(
			"play_entry_animation"
		)
	):
		await spawn_door.play_entry_animation()

	player.visible = true

	_restore_summons_after_room_change()

	_maybe_start_room_music()

	if _should_show_area_title_card():
		await _play_area_title_card()
		# _play_area_title_card() kehrt zurück, sobald der Text
		# anfängt zu Rauch aufzulösen - genau dann (nicht erst,
		# wenn der Rauch komplett verklungen ist) soll der Spieler
		# seine Kontrolle zurückbekommen.

	await _maybe_play_void_narration()

	if player.has_method("unlock_control"):
		player.unlock_control()

	busy = false

	_print_current_room_information()

	# Bewusst NICHT awaited - die Gedanken-Sprechblase wartet selbst
	# 2 Sekunden und läuft dann im Hintergrund weiter, ohne dass der
	# Spieler dafür stillstehen oder die Steuerung gesperrt werden
	# müsste (anders als die Void-Erzählung oben).
	_maybe_show_room_thought_bubble()


# Zeigt (falls für diesen Raum konfiguriert, siehe thought_bubble_id/
# thought_bubble_lines oben) 2 Sekunden nach dem normalen Betreten
# des Raums einmal pro Lauf eine kurze Gedanken-Sprechblase über
# dem Spieler - OHNE die Steuerung zu sperren. Wird bewusst nicht
# awaited aufgerufen (siehe _enter_at_normal_spawn() oben).
func _maybe_show_room_thought_bubble() -> void:
	if thought_bubble_id == &"" or thought_bubble_lines.is_empty():
		return

	if get_node_or_null("/root/RunState") == null:
		return

	if RunState.has_shown_narration(thought_bubble_id):
		return

	await get_tree().create_timer(2.0).timeout

	if player == null or not is_instance_valid(player):
		return

	var bubble := PlayerThoughtBubble.new()
	player.add_child(bubble)

	await bubble.play_lines(thought_bubble_lines)

	if is_instance_valid(bubble):
		bubble.queue_free()

	RunState.mark_narration_shown(thought_bubble_id)


# Startet (falls für diesen Raum konfiguriert, siehe room_music_id
# oben) den Crossfade zur Raum-Musik - siehe MusicManager.play_room_
# music() für den eigentlichen Fade (Gebiets-Musik wird dabei nur
# leiser gedreht, nicht gestoppt). Bewusst nicht awaited, der Fade
# läuft im Hintergrund weiter, während der Spieler sich schon frei
# bewegen kann.
func _maybe_start_room_music() -> void:
	if room_music_id == &"":
		return

	if get_node_or_null("/root/MusicManager") == null:
		return

	MusicManager.play_room_music(room_music_id)


# Kehrt _maybe_start_room_music() um - wird beim Verlassen des Raums
# aufgerufen (siehe leave_room() unten), egal in welchen Raum es als
# Nächstes geht.
func _maybe_stop_room_music() -> void:
	if room_music_id == &"":
		return

	if get_node_or_null("/root/MusicManager") == null:
		return

	MusicManager.stop_room_music()


# Spielt (falls für diesen Raum konfiguriert, siehe void_intro_id/
# void_intro_lines oben) einmal pro Run "Die Leere" ab, wenn der
# Raum normal betreten wird - z.B. beim Betreten des Bossraums.
# VoidNarration.play_lines() sperrt/entsperrt die Spielersteuerung
# selbst, deshalb ist hier kein zusätzliches lock_control() nötig.
func _maybe_play_void_narration() -> void:
	if void_intro_id == &"" or void_intro_lines.is_empty():
		return

	if get_node_or_null("/root/RunState") == null:
		return

	if RunState.has_shown_narration(void_intro_id):
		return

	var narration := VoidNarration.new()
	get_tree().current_scene.add_child(narration)

	await narration.play_lines(void_intro_lines)

	RunState.mark_narration_shown(void_intro_id)


# Zeigt den Gebiets-Titel ("GEBIET 1 - DIE EINGANGSHALLEN") NUR,
# wenn man gerade frisch über einen Spielstand im Hauptmenü
# eingestiegen ist (RunState.show_area_intro_pending, wird dort
# von main_menu.gd gesetzt) UND das der allererste Raum ist
# (Raum 1 von 10 - egal welcher der zufällig gemischten Räume das
# gerade ist, siehe RunState.NORMAL_ROOM_PATHS).
#
# Bewusst NICHT einfach nur "Raum 1", weil ein Tod mitten im Lauf
# den Lauf ebenfalls auf Raum 1 zurücksetzt (RoomManager.
# reset_run() -> RunState.reset_run()) - dort wird das Flag aber
# nie gesetzt, deswegen kommt das Intro nach einem Tod nicht
# nochmal, sondern wirklich nur beim Einstieg über einen
# Spielstand im Hauptmenü.
#
# Das Flag wird hier sofort verbraucht (auf false gesetzt), damit
# es garantiert nur einmal auslöst.
func _should_show_area_title_card() -> bool:
	if get_node_or_null("/root/RunState") == null:
		return false

	if not RunState.show_area_intro_pending:
		return false

	if RunState.get_current_room_number() != 1:
		return false

	RunState.show_area_intro_pending = false
	return true


func _play_area_title_card() -> void:
	var title_card := AreaTitleCard.new()

	if get_node_or_null("/root/SettingsManager") != null:
		title_card.title_text = SettingsManager.t(
			"area_intro.gebiet_1_title"
		)
		title_card.subtitle_text = SettingsManager.t(
			"area_intro.gebiet_1_subtitle"
		)

	get_tree().current_scene.add_child(title_card)

	await title_card.play_intro()


func _reset_player_camera() -> void:
	if player == null:
		return

	var camera := player.get_node_or_null(
		"Camera2D"
	) as Camera2D

	if camera == null:
		return

	camera.enabled = true
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()


func _print_current_room_information() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	print(
		"Aktueller Raum: ",
		RunState.get_current_room_number(),
		" / ",
		RunState.get_total_room_count()
	)

	print(
		"Raumpfad laut RunState: ",
		RunState.get_current_room_path()
	)

	print(
		"Tatsächlich geladene Szene: ",
		get_tree().current_scene.scene_file_path
	)

	print(
		"Aktuelle Leben: ",
		RunState.current_health
	)


func request_room_exit() -> void:
	if busy:
		return

	if room_change_started:
		return

	room_change_started = true
	busy = true

	print(
		"RoomManager erhält Ausgang in Raum ",
		RunState.get_current_room_number()
	)

	await leave_room()


func leave_room() -> void:
	if player == null:
		_restore_after_failed_room_change()
		return

	if get_node_or_null("/root/RunState") == null:
		push_error(
			"RoomManager: RunState fehlt."
		)

		_restore_after_failed_room_change()
		return

	if player.has_method("lock_control"):
		player.lock_control()

	player.velocity = Vector2.ZERO

	_maybe_stop_room_music()

	_save_summons_before_room_change()

	player.visible = false

	if (
		exit_door != null
		and exit_door.has_method(
			"play_exit_animation"
		)
	):
		await exit_door.play_exit_animation()

	# ========================================================
	# RAUM 9 -> RAUM 10: DIREKTER BOSSRAUM
	# ========================================================

	if RunState.get_current_room_number() == 9:
		await _change_to_boss_room()
		return

	# ========================================================
	# ALLE ANDEREN RÄUME
	# ========================================================

	await _change_to_next_run_room()


func _change_to_boss_room() -> void:
	if boss_room_path.is_empty():
		push_error(
			"RoomManager: Boss Room Path ist leer. "
			+ "Bitte im Inspector den Bossraum auswählen."
		)

		_restore_after_failed_room_change()
		return

	if not ResourceLoader.exists(boss_room_path):
		push_error(
			"RoomManager: Bossraum wurde nicht gefunden: "
			+ boss_room_path
		)

		_restore_after_failed_room_change()
		return

	# Beim ersten Betreten von Raum 10 lebt der Boss.
	boss_defeated_in_current_run = false

	# Raum 10 besitzt Index 9.
	RunState.current_room_index = 9
	RunState.rooms_finished += 1

	print(
		"RAUM 9 -> BOSSRAUM 10: ",
		boss_room_path
	)

	var tree := get_tree()

	if tree == null:
		push_error(
			"RoomManager: SceneTree fehlt beim Bosswechsel."
		)

		_restore_after_failed_room_change()
		return

	var error: Error = tree.change_scene_to_file(
		boss_room_path
	)

	if error != OK:
		push_error(
			"RoomManager: Bossraum konnte nicht geladen werden. "
			+ "Fehlercode: "
			+ str(error)
		)

		RunState.current_room_index = 8

		RunState.rooms_finished = max(
			RunState.rooms_finished - 1,
			0
		)

		_restore_after_failed_room_change()


func _change_to_next_run_room() -> void:
	if not RunState.has_next_room():
		push_warning(
			"RoomManager: Kein weiterer Raum vorhanden."
		)

		_restore_after_failed_room_change()
		return

	var previous_index: int = (
		RunState.current_room_index
	)

	var previous_number: int = (
		RunState.get_current_room_number()
	)

	var next_room_path: String = (
		RunState.advance_to_next_room()
	)

	if next_room_path.is_empty():
		push_error(
			"RoomManager: Nächster Raumpfad ist leer."
		)

		RunState.current_room_index = previous_index

		RunState.rooms_finished = max(
			RunState.rooms_finished - 1,
			0
		)

		_restore_after_failed_room_change()
		return

	if not ResourceLoader.exists(next_room_path):
		push_error(
			"RoomManager: Raumdatei fehlt: "
			+ next_room_path
		)

		RunState.current_room_index = previous_index

		RunState.rooms_finished = max(
			RunState.rooms_finished - 1,
			0
		)

		_restore_after_failed_room_change()
		return

	print(
		"WECHSEL VON RAUM ",
		previous_number,
		" ZU RAUM ",
		RunState.get_current_room_number(),
		": ",
		next_room_path
	)

	var tree := get_tree()

	if tree == null:
		RunState.current_room_index = previous_index

		RunState.rooms_finished = max(
			RunState.rooms_finished - 1,
			0
		)

		_restore_after_failed_room_change()
		return

	var error: Error = tree.change_scene_to_file(
		next_room_path
	)

	if error != OK:
		push_error(
			"RoomManager: Raumwechsel fehlgeschlagen. "
			+ "Fehlercode: "
			+ str(error)
		)

		RunState.current_room_index = previous_index

		RunState.rooms_finished = max(
			RunState.rooms_finished - 1,
			0
		)

		_restore_after_failed_room_change()


func _restore_after_failed_room_change() -> void:
	if player != null:
		player.visible = true

		if player.has_method("unlock_control"):
			player.unlock_control()

	if (
		exit_door != null
		and exit_door.has_method("restore_door")
	):
		exit_door.restore_door()

	busy = false
	room_change_started = false


func _on_phase_1_finished() -> void:
	if busy:
		return

	if player == null:
		return

	busy = true

	if player.has_method("lock_control"):
		player.lock_control()

	player.velocity = Vector2.ZERO
	_save_summons_before_room_change()
	player.visible = false

	if phase_2_room_path.is_empty():
		push_warning(
			"RoomManager: Phase-2-Pfad ist leer."
		)

		_restore_after_failed_room_change()
		return

	if not ResourceLoader.exists(phase_2_room_path):
		push_error(
			"RoomManager: Phase 2 fehlt: "
			+ phase_2_room_path
		)

		_restore_after_failed_room_change()
		return

	await _play_phase_flash()

	var tree := get_tree()

	if tree == null:
		_restore_after_failed_room_change()
		return

	var error: Error = tree.change_scene_to_file(
		phase_2_room_path
	)

	if error != OK:
		push_error(
			"RoomManager: Phase 2 konnte nicht geladen werden. "
			+ "Fehlercode: "
			+ str(error)
		)

		_restore_after_failed_room_change()


func _on_phase_2_finished() -> void:
	if busy:
		return

	busy = true

	if phase_1_return_room_path.is_empty():
		push_warning(
			"RoomManager: Rückkehrpfad ist leer."
		)

		busy = false
		return

	if not ResourceLoader.exists(
		phase_1_return_room_path
	):
		push_error(
			"RoomManager: Rückkehrraum fehlt: "
			+ phase_1_return_room_path
		)

		busy = false
		return

	# Phase 2 wurde besiegt.
	# Beim Zurückladen von Phase 1 werden Boss und Bossleiste entfernt.
	boss_defeated_in_current_run = true

	if get_node_or_null("/root/RunState") != null:
		RunState.add_boss_kill(1)

		# Feuerritter (Gebiet-1-Boss) schaltet sein Echo frei -
		# unlock_echo() liefert nur beim ERSTEN Mal true, danach
		# bleibt pending_echo_reveal leer und die Enthüllungs-
		# Sequenz unten in _enter_at_return_spawn() läuft nicht
		# nochmal an.
		if RunState.unlock_echo(&"echo_der_flamme"):
			RunState.pending_echo_reveal = &"echo_der_flamme"

	RoomManager.return_to_spawn_name = (
		return_spawn_name
	)

	_save_summons_before_room_change()

	var tree := get_tree()

	if tree == null:
		busy = false
		return

	tree.call_deferred(
		"change_scene_to_file",
		phase_1_return_room_path
	)


func _play_phase_flash() -> void:
	if not use_phase_flash:
		return

	var layer := CanvasLayer.new()
	layer.layer = 999

	var rect := ColorRect.new()

	rect.color = flash_color
	rect.modulate.a = 0.0

	rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	rect.set_anchors_preset(
		Control.PRESET_FULL_RECT
	)

	layer.add_child(rect)
	get_tree().current_scene.add_child(layer)

	var tween := create_tween()

	tween.tween_property(
		rect,
		"modulate:a",
		1.0,
		flash_fade_in_time
	)

	tween.tween_interval(
		flash_hold_time
	)

	tween.tween_property(
		rect,
		"modulate:a",
		0.0,
		flash_fade_out_time
	)

	await tween.finished

	if is_instance_valid(layer):
		layer.queue_free()


func _on_player_died() -> void:
	if death_restart_started:
		return

	death_restart_started = true
	busy = true
	room_change_started = true

	if player != null:
		if player.has_method("lock_control"):
			player.lock_control()

		player.velocity = Vector2.ZERO

	if get_node_or_null("/root/RunState") != null:
		RunState.finish_run()

	RoomManager.show_death_screen_after_restart = true

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		death_restart_delay
	).timeout

	# Neuer Run: Der Boss darf wieder erscheinen.
	boss_defeated_in_current_run = false

	if get_node_or_null("/root/RunState") != null:
		RunState.reset_run()

		# Debug-Log für den Shop-Checkpoint: zeigt bei jedem Tod-Neustart
		# im Ausgabe-Fenster sofort, ob ein Checkpoint benutzt wurde und
		# in welchem Raum der nächste Run startet.
		print(
			"Tod-Neustart | has_shop_checkpoint=",
			RunState.has_shop_checkpoint,
			" | current_room_index=",
			RunState.current_room_index
		)

	# BUGFIX (Shop-Checkpoint): GoldSystem.reset_gold() hat bisher IMMER
	# das Gold auf 0 gesetzt und das auch zurück nach RunState.current_
	# gold geschrieben (siehe Player/gold_system.gd -> reset_gold()) -
	# das hat den gerade von RunState.reset_run() wiederhergestellten
	# Shop-Checkpoint-Goldstand sofort wieder auf 0 überschrieben. Nach
	# einem Checkpoint-Neustart synct GoldSystem sich jetzt stattdessen
	# nur mit dem (schon korrekt wiederhergestellten) RunState.current_
	# gold - nur ein kompletter Reset ohne Checkpoint setzt Gold auf 0.
	if get_node_or_null("/root/GoldSystem") != null:
		var restarted_at_checkpoint: bool = (
			get_node_or_null("/root/RunState") != null
			and RunState.has_shop_checkpoint
		)

		if restarted_at_checkpoint:
			GoldSystem.sync_from_run_state()
		else:
			GoldSystem.reset_gold()

	RoomManager.return_to_spawn_name = ""

	if run_start_scene_path.is_empty():
		push_error(
			"RoomManager: Run-Startpfad ist leer."
		)
		return

	if not ResourceLoader.exists(run_start_scene_path):
		push_error(
			"RoomManager: Run-Startszene fehlt: "
			+ run_start_scene_path
		)
		return

	var error: Error = tree.change_scene_to_file(
		run_start_scene_path
	)

	if error != OK:
		push_error(
			"RoomManager: Run-Neustart fehlgeschlagen. "
			+ "Fehlercode: "
			+ str(error)
		)
