extends Node


# ============================================================
# HINWEIS
# ============================================================

# Speichert/lädt den Spielstand auf Raum-Neustart-Genauigkeit,
# in einem von drei Slots (1-3): Beim Laden wird der zuletzt
# gespeicherte Raum komplett neu betreten (alle Gegner wieder
# da), aber Gold, Items, HP und der Fortschritt im Run
# (Statistiken, Shop-Angebot, Zauber-Slots, Begleiter, Spielzeit)
# bleiben erhalten. RunState.get_current_run_data() liefert dafür
# bereits das komplette Schema - dieses Script schreibt es nur
# noch als JSON nach user:// und wieder zurück.


const SLOT_COUNT: int = 3


# ============================================================
# ABFRAGE
# ============================================================

func has_save_file(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


# Leichtgewichtige Vorschau für die Slot-Auswahl im Hauptmenü,
# ohne den Spielstand direkt in RunState zu laden.
func peek_save_summary(slot: int) -> Dictionary:
	var data: Dictionary = _read_save_file(slot)

	if data.is_empty():
		return {}

	return {
		"area": int(data.get("area", 1)),
		"room_number": int(data.get("room_number", 1)),
		"gold": int(data.get("gold", 0)),
		"rooms_finished": int(data.get("rooms_finished", 0)),
		"playtime_seconds": float(data.get("playtime_seconds", 0.0))
	}


# ============================================================
# SPEICHERN
# ============================================================

# slot: 1-3. Ohne Angabe wird in den zuletzt aktiven Slot
# geschrieben (RunState.current_save_slot) - das ist der
# normale Fall beim "Speichern"-Button im Pause-Menü.
func save_game(slot: int = -1) -> bool:
	if get_node_or_null("/root/RunState") == null:
		push_error(
			"SaveManager: RunState wurde nicht als Autoload gefunden."
		)
		return false

	var target_slot: int = slot

	if target_slot == -1:
		target_slot = RunState.current_save_slot

	if not _is_valid_slot(target_slot):
		push_error(
			"SaveManager: Kein gültiger Spielstand-Slot zum Speichern."
		)
		return false

	var data: Dictionary = RunState.get_current_run_data()

	var file := FileAccess.open(
		_slot_path(target_slot),
		FileAccess.WRITE
	)

	if file == null:
		push_error(
			"SaveManager: Speichern fehlgeschlagen (Datei konnte nicht geöffnet werden)."
		)
		return false

	file.store_string(
		JSON.stringify(data, "\t")
	)

	file.close()

	print(
		"SaveManager: Spielstand in Slot ",
		target_slot,
		" gespeichert."
	)

	return true


# ============================================================
# LADEN
# ============================================================

# Lädt den Spielstand nur in RunState (und die davon abhängigen
# Autoloads), wechselt aber NICHT selbst die Szene. Für den
# üblichen Fall bitte load_and_enter_saved_room() benutzen.
func load_game(slot: int) -> bool:
	if get_node_or_null("/root/RunState") == null:
		push_error(
			"SaveManager: RunState wurde nicht als Autoload gefunden."
		)
		return false

	var data: Dictionary = _read_save_file(slot)

	if data.is_empty():
		return false

	_apply_run_data(data)

	RunState.set_active_save_slot(slot)
	RunState.start_time_tracking()

	return true


# Lädt den Spielstand UND wechselt direkt in den gespeicherten
# Raum - das ist der normale Weg, den das Hauptmenü benutzt.
func load_and_enter_saved_room(slot: int) -> bool:
	if not load_game(slot):
		return false

	var room_path: String = RunState.get_current_room_path()

	if room_path.is_empty():
		push_error(
			"SaveManager: Kein gültiger Raum im Spielstand gefunden."
		)
		return false

	if not ResourceLoader.exists(room_path):
		push_error(
			"SaveManager: Der gespeicherte Raum wurde nicht gefunden: "
			+ room_path
		)
		return false

	var error: Error = get_tree().change_scene_to_file(room_path)

	if error != OK:
		push_error(
			"SaveManager: Raum konnte nicht geladen werden: "
			+ room_path
			+ " | Fehlercode: "
			+ str(error)
		)
		return false

	return true


func delete_save(slot: int) -> void:
	if not has_save_file(slot):
		return

	DirAccess.remove_absolute(_slot_path(slot))


# ============================================================
# INTERNES: SLOTS
# ============================================================

func _slot_path(slot: int) -> String:
	return "user://savegame_slot_%d.json" % slot


func _is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


# ============================================================
# INTERNES: DATEI LESEN
# ============================================================

func _read_save_file(slot: int) -> Dictionary:
	if not has_save_file(slot):
		return {}

	var file := FileAccess.open(
		_slot_path(slot),
		FileAccess.READ
	)

	if file == null:
		push_error(
			"SaveManager: Laden fehlgeschlagen (Datei konnte nicht geöffnet werden)."
		)
		return {}

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)

	if parsed == null or not (parsed is Dictionary):
		push_error(
			"SaveManager: Speicherdatei ist beschädigt oder leer."
		)
		return {}

	return parsed as Dictionary


# ============================================================
# INTERNES: DATEN IN RUNSTATE ÜBERNEHMEN
# ============================================================

# Öffentlicher Wrapper um _apply_run_data() unten - wird zusätzlich
# zum normalen "Laden aus Datei"-Ablauf jetzt auch von RunState.
# _restore_shop_checkpoint() benutzt (siehe Game/run_state.gd), um
# einen im Speicher gehaltenen Shop-Checkpoint-Snapshot anzuwenden,
# ganz ohne den Umweg über eine JSON-Datei.
func apply_run_data(data: Dictionary) -> void:
	_apply_run_data(data)


func _apply_run_data(data: Dictionary) -> void:
	# Ein geladener Spielstand hat nichts mit einem eventuell noch im
	# Speicher liegenden Shop-Checkpoint aus einem ANDEREN Lauf zu tun -
	# sonst könnte ein Tod nach dem Laden fälschlich zu diesem alten
	# Checkpoint zurückspringen, statt normal neu zu starten. Ein
	# frischer Checkpoint entsteht ohnehin automatisch wieder, sobald
	# im geladenen Lauf erneut der Shop betreten wird.
	RunState.has_shop_checkpoint = false

	RunState.current_area = int(
		data.get("area", RunState.START_AREA)
	)

	RunState.current_playtime_seconds = float(
		data.get("playtime_seconds", 0.0)
	)

	RunState.current_health = int(
		data.get("health", RunState.START_HEALTH)
	)

	RunState.current_gold = int(
		data.get("gold", RunState.START_GOLD)
	)

	RunState.current_potions = int(
		data.get("potions", RunState.START_POTIONS)
	)

	RunState.current_armor = int(
		data.get("armor", RunState.START_ARMOR)
	)

	RunState.set_armor_types(
		_to_string_array(
			data.get("armor_types", [])
		)
	)

	RunState.current_arrows = int(
		data.get("arrows", RunState.START_ARROWS)
	)

	RunState.bow_unlocked = bool(
		data.get("bow_unlocked", RunState.START_BOW_UNLOCKED)
	)

	RunState.set_spell_slots(
		_to_string_array(
			data.get("spell_slots", [])
		)
	)

	RunState.bosses_killed = int(data.get("bosses_killed", 0))
	RunState.minibosses_killed = int(data.get("minibosses_killed", 0))
	RunState.rooms_finished = int(data.get("rooms_finished", 0))
	RunState.enemies_killed = int(data.get("enemies_killed", 0))

	RunState.current_run_seed = int(data.get("run_seed", 0))

	var loaded_room_order: Array[String] = _to_string_array(
		data.get("room_order", [])
	)

	if not loaded_room_order.is_empty():
		RunState.room_order = loaded_room_order
	else:
		RunState.generate_room_order()

	RunState.current_room_index = int(
		data.get("room_index", RunState.START_ROOM_INDEX)
	)

	RunState.set_shop_offer(
		_to_string_array(
			data.get("shop_item_ids", [])
		)
	)

	var loaded_bought: Variant = data.get(
		"bought_unique_shop_items",
		{}
	)

	if loaded_bought is Dictionary:
		RunState.bought_unique_shop_items = (
			(loaded_bought as Dictionary).duplicate()
		)
	else:
		RunState.bought_unique_shop_items = {}

	RunState.summon_active = bool(data.get("summon_active", false))
	RunState.summon_health = int(data.get("summon_health", 0))

	RunState.unlocked_echoes = _to_string_name_array(
		data.get("unlocked_echoes", [])
	)

	RunState.used_doors = _to_string_name_array(
		data.get("used_doors", [])
	)

	RunState.shown_narrations = _to_string_name_array(
		data.get("shown_narrations", [])
	)

	RunState.chosen_skill_path = StringName(
		data.get("chosen_skill_path", "")
	)

	RunState.skill_path_xp = float(data.get("skill_path_xp", 0.0))
	RunState.skill_points = int(data.get("skill_points", 0))
	RunState.skill_ring_revealed = bool(
		data.get("skill_ring_revealed", false)
	)
	RunState.unlocked_skills = _to_string_name_array(
		data.get("unlocked_skills", [])
	)

	RunState.current_vigor = clamp(
		int(data.get("vigor", 0)),
		0,
		RunState.VIGOR_MAX
	)

	RunState.equipped_active_skill = StringName(
		data.get("equipped_active_skill", "")
	)

	# GoldSystem ist selbst ein Autoload (kein Raum-Node) und
	# bekommt beim Szenenwechsel deshalb KEIN eigenes _ready()
	# mehr - muss also manuell mit dem geladenen Gold-Wert
	# synchronisiert werden.
	if get_node_or_null("/root/GoldSystem") != null:
		GoldSystem.sync_from_run_state()


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in (value as Array):
			result.append(str(entry))

	return result


func _to_string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []

	if value is Array:
		for entry in (value as Array):
			result.append(StringName(str(entry)))

	return result
