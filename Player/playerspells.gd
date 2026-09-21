extends Node


# ============================================================
# SIGNALE
# ============================================================

signal spells_changed(spell_slots: Array[String])
signal spell_used(slot_index: int, spell_id: String)
signal spell_failed(message: String)


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export_group("Spell Slots")

@export_range(1, 10, 1)
var max_spell_slots: int = 3


# ============================================================
# ERLAUBTE ZAUBER
# ============================================================

const VALID_SPELL_IDS: Array[String] = [
	"fireball",
	"lightning",
	"ice",
	"roots",
	"necromancy",
	"lightorb"
]


# ============================================================
# NODES UND DATEN
# ============================================================

@onready var spell_manager: Node = get_node_or_null(
	"../SpellManager"
)

var spell_slots: Array[String] = []


# ============================================================
# START
# ============================================================

func _ready() -> void:
	_create_empty_slots()
	_load_slots_from_run_state()

	if spell_manager == null:
		push_warning(
			"PlayerSpells: SpellManager wurde nicht gefunden."
		)

	await get_tree().process_frame

	spells_changed.emit(
		spell_slots.duplicate()
	)


# ============================================================
# LADEN UND SPEICHERN
# ============================================================

func _create_empty_slots() -> void:
	spell_slots.clear()

	for i in range(max_spell_slots):
		spell_slots.append("")


func _load_slots_from_run_state() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	var saved_slots: Array = RunState.spell_slots

	for i in range(
		min(saved_slots.size(), spell_slots.size())
	):
		spell_slots[i] = str(saved_slots[i])


func _save_slots_to_run_state() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	RunState.set_spell_slots(
		spell_slots.duplicate()
	)


# ============================================================
# ZAUBER HINZUFÜGEN
# ============================================================

func add_spell(spell_id: String) -> bool:
	var normalized_spell_id: String = (
		spell_id.strip_edges().to_lower()
	)

	if not is_valid_spell(normalized_spell_id):
		spell_failed.emit(
			"Unbekannter Zauber: "
			+ normalized_spell_id
		)
		return false

	var free_slot: int = get_first_free_slot()

	if free_slot == -1:
		spell_failed.emit(
			"Alle Zauberplätze belegt."
		)
		return false

	spell_slots[free_slot] = normalized_spell_id

	_save_slots_to_run_state()

	spells_changed.emit(
		spell_slots.duplicate()
	)

	print(
		"PlayerSpells: ",
		normalized_spell_id,
		" wurde in Slot ",
		free_slot + 1,
		" gelegt."
	)

	return true


# ============================================================
# ZAUBER BENUTZEN
# ============================================================

func use_spell(slot_index: int) -> bool:
	if not is_valid_slot_index(slot_index):
		spell_failed.emit(
			"Ungültiger Zauberslot."
		)
		return false

	var spell_id: String = spell_slots[slot_index]

	if spell_id.is_empty():
		spell_failed.emit(
			"Kein Zauber in diesem Slot."
		)
		return false

	if spell_manager == null:
		spell_manager = get_node_or_null(
			"../SpellManager"
		)

	if spell_manager == null:
		spell_failed.emit(
			"SpellManager wurde nicht gefunden."
		)
		return false

	if not spell_manager.has_method("cast_spell"):
		spell_failed.emit(
			"SpellManager besitzt keine cast_spell()-Funktion."
		)
		return false

	var cast_started: bool = spell_manager.cast_spell(
		spell_id
	)

	if not cast_started:
		spell_failed.emit(
			"Der Zauber konnte nicht gestartet werden."
		)
		return false

	# Der Slot wird nur geleert, nachdem der SpellManager
	# den Cast erfolgreich gestartet hat.
	spell_slots[slot_index] = ""

	_save_slots_to_run_state()

	spells_changed.emit(
		spell_slots.duplicate()
	)

	spell_used.emit(
		slot_index,
		spell_id
	)

	print(
		"PlayerSpells: ",
		spell_id,
		" wurde aus Slot ",
		slot_index + 1,
		" verwendet."
	)

	return true


# ============================================================
# SLOTS LEEREN
# ============================================================

func clear_slot(slot_index: int) -> bool:
	if not is_valid_slot_index(slot_index):
		return false

	if spell_slots[slot_index].is_empty():
		return false

	spell_slots[slot_index] = ""

	_save_slots_to_run_state()

	spells_changed.emit(
		spell_slots.duplicate()
	)

	return true


func clear_all_spells() -> void:
	for i in range(spell_slots.size()):
		spell_slots[i] = ""

	_save_slots_to_run_state()

	spells_changed.emit(
		spell_slots.duplicate()
	)


# ============================================================
# SLOT-INFORMATIONEN
# ============================================================

func get_first_free_slot() -> int:
	for i in range(spell_slots.size()):
		if spell_slots[i].is_empty():
			return i

	return -1


func can_add_spell() -> bool:
	return get_first_free_slot() != -1


func are_all_slots_full() -> bool:
	return get_first_free_slot() == -1


func get_spell_in_slot(slot_index: int) -> String:
	if not is_valid_slot_index(slot_index):
		return ""

	return spell_slots[slot_index]


func get_spell_slots() -> Array[String]:
	return spell_slots.duplicate()


func get_free_slot_count() -> int:
	var free_slots: int = 0

	for spell_id in spell_slots:
		if spell_id.is_empty():
			free_slots += 1

	return free_slots


func get_filled_slot_count() -> int:
	return (
		spell_slots.size()
		- get_free_slot_count()
	)


# ============================================================
# PRÜFUNGEN
# ============================================================

func is_valid_slot_index(slot_index: int) -> bool:
	return (
		slot_index >= 0
		and slot_index < spell_slots.size()
	)


func is_valid_spell(spell_id: String) -> bool:
	return VALID_SPELL_IDS.has(spell_id)
