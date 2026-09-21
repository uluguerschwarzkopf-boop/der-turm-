extends Node


# ============================================================
# NUR ZUM TESTEN!
# ============================================================

# Füllt die Zauber-Slots des Spielers automatisch immer wieder
# mit den unten eingestellten Test-Zaubern auf, damit man ohne
# Loot-Sammeln alle Effekte durchtesten kann.
#
# ENTFERNEN NACH DEM TESTEN:
# 1. Diesen Node ("DEBUG_SpellFiller") im Player/Scripts-Ordner
#    in Godot löschen.
# 2. Diese Datei (debug_spell_filler.gd) löschen.
# playerspells.gd selbst wird dafür nirgends verändert.


@export var enabled: bool = true

@export_group("Test-Zauber")

@export var slot_1_spell: String = "ice"
@export var slot_2_spell: String = "roots"
@export var slot_3_spell: String = "lightorb"


# ============================================================
# NODES
# ============================================================

@onready var player_spells: Node = get_node_or_null(
	"../PlayerSpells"
)


# ============================================================
# START
# ============================================================

func _ready() -> void:
	if player_spells == null:
		push_warning(
			"DebugSpellFiller: PlayerSpells wurde nicht gefunden."
		)
		return

	if not player_spells.spells_changed.is_connected(
		_on_spells_changed
	):
		player_spells.spells_changed.connect(
			_on_spells_changed
		)

	_fill_slots()


# ============================================================
# AUFFÜLLEN
# ============================================================

var _filling: bool = false


func _on_spells_changed(_spell_slots: Array[String]) -> void:
	_fill_slots()


func _fill_slots() -> void:
	if _filling:
		return

	if not enabled or player_spells == null:
		return

	_filling = true

	var wanted_spells: Array[String] = [
		slot_1_spell,
		slot_2_spell,
		slot_3_spell
	]

	var current_slots: Array[String] = (
		player_spells.get_spell_slots()
	)

	for spell_id in wanted_spells:
		if spell_id.is_empty():
			continue

		if current_slots.has(spell_id):
			continue

		if not player_spells.can_add_spell():
			break

		player_spells.add_spell(spell_id)

	_filling = false
