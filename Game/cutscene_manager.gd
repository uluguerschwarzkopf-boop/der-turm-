extends Node


# ============================================================
# SIGNALE
# ============================================================

signal cutscene_started
signal cutscene_finished


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export_group("Gruppen")

# Alle HUD-Nodes, die ausgeblendet werden sollen,
# kommen in diese Gruppe.
@export var hud_group: StringName = &"hud"

# Optional:
# Nodes wie GoldUI, BossHealthBar oder andere Oberflächen
# können ebenfalls in diese Gruppe gelegt werden.
@export var additional_ui_group: StringName = &"cutscene_ui"


# ============================================================
# STATUS
# ============================================================

var cutscene_active: bool = false

# Falls mehrere Systeme gleichzeitig eine Cutscene beginnen,
# bleibt das HUD verborgen, bis alle Cutscenes beendet wurden.
var cutscene_lock_count: int = 0


# ============================================================
# CUTSCENE STARTEN
# ============================================================

func begin_cutscene() -> void:
	cutscene_lock_count += 1

	if cutscene_active:
		return

	cutscene_active = true

	_hide_all_cutscene_ui()

	cutscene_started.emit()


# ============================================================
# CUTSCENE BEENDEN
# ============================================================

func end_cutscene() -> void:
	if cutscene_lock_count > 0:
		cutscene_lock_count -= 1

	# Eine andere Cutscene ist noch aktiv.
	if cutscene_lock_count > 0:
		return

	cutscene_lock_count = 0

	if not cutscene_active:
		return

	cutscene_active = false

	_show_all_cutscene_ui()

	cutscene_finished.emit()


# ============================================================
# SOFORT ALLES ZURÜCKSETZEN
# ============================================================

# Nützlich bei Tod, Szenenwechsel oder falls eine Cutscene
# durch einen Fehler unterbrochen wurde.
func force_end_cutscene() -> void:
	cutscene_lock_count = 0
	cutscene_active = false

	_show_all_cutscene_ui()

	cutscene_finished.emit()


# ============================================================
# HUD AUSBLENDEN
# ============================================================

func _hide_all_cutscene_ui() -> void:
	var tree := get_tree()

	if tree == null:
		return

	for hud_node: Node in tree.get_nodes_in_group(
		hud_group
	):
		_hide_ui_node(hud_node)

	for ui_node: Node in tree.get_nodes_in_group(
		additional_ui_group
	):
		_hide_ui_node(ui_node)


func _hide_ui_node(ui_node: Node) -> void:
	if ui_node == null:
		return

	if not is_instance_valid(ui_node):
		return

	# Bevorzugt deine bereits vorhandene HUD-Funktion.
	if ui_node.has_method("hide_for_cutscene"):
		ui_node.hide_for_cutscene()
		return

	if ui_node is CanvasItem:
		(ui_node as CanvasItem).visible = false


# ============================================================
# HUD EINBLENDEN
# ============================================================

func _show_all_cutscene_ui() -> void:
	var tree := get_tree()

	if tree == null:
		return

	for hud_node: Node in tree.get_nodes_in_group(
		hud_group
	):
		_show_ui_node(hud_node)

	for ui_node: Node in tree.get_nodes_in_group(
		additional_ui_group
	):
		_show_ui_node(ui_node)


func _show_ui_node(ui_node: Node) -> void:
	if ui_node == null:
		return

	if not is_instance_valid(ui_node):
		return

	if ui_node.has_method("show_after_cutscene"):
		ui_node.show_after_cutscene()
		return

	if ui_node is CanvasItem:
		(ui_node as CanvasItem).visible = true


# ============================================================
# ABFRAGE
# ============================================================

func is_cutscene_active() -> bool:
	return cutscene_active
