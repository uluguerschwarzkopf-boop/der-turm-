extends Node

signal gold_changed(new_amount: int, added_amount: int)

@export var start_gold: int = 0

var gold: int = 0


func _ready() -> void:
	if get_node_or_null("/root/RunState") != null:
		gold = max(RunState.current_gold, 0)
	else:
		gold = max(start_gold, 0)

	gold_changed.emit(gold, 0)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	gold += amount

	if get_node_or_null("/root/RunState") != null:
		RunState.set_gold(gold)

	gold_changed.emit(gold, amount)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return false

	if gold < amount:
		return false

	gold -= amount

	if get_node_or_null("/root/RunState") != null:
		RunState.set_gold(gold)

	gold_changed.emit(gold, -amount)

	return true


func set_gold(amount: int) -> void:
	var old_gold := gold

	gold = max(amount, 0)

	if get_node_or_null("/root/RunState") != null:
		RunState.set_gold(gold)

	gold_changed.emit(gold, gold - old_gold)


func get_gold() -> int:
	return gold


func reset_gold() -> void:
	var old_gold := gold

	gold = max(start_gold, 0)

	if get_node_or_null("/root/RunState") != null:
		RunState.set_gold(gold)

	gold_changed.emit(gold, gold - old_gold)


func sync_from_run_state() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	var old_gold := gold

	gold = max(RunState.current_gold, 0)

	gold_changed.emit(gold, gold - old_gold)
